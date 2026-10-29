import { assert, assertEquals, assertMatch, assertThrows } from "@std/assert";
import { createLocalJWKSet, exportJWK, generateKeyPair, SignJWT } from "jose";
import { z } from "zod";

import {
  createPomodoistMcpHandler,
  type PomodoistMcpDependencies,
  toolError,
  toolSuccess,
} from "./pomodoist_mcp.ts";

const issuer = "https://issuer.test/auth/v1";
const resource = "https://issuer.test/functions/v1/pomodoist-mcp";
const metadataUrl =
  "https://issuer.test/.well-known/oauth-protected-resource/functions/v1/pomodoist-mcp";
const serviceKey = "service-role-secret-value";
const subject = "11111111-1111-4111-8111-111111111111";
const sessionId = "22222222-2222-4222-8222-222222222222";
const clientId = "33333333-3333-4333-8333-333333333333";
const realUserId = "44444444-4444-4444-8444-444444444444";
const { privateKey, publicKey } = await generateKeyPair("RS256");
const { privateKey: otherPrivateKey } = await generateKeyPair("RS256");
const publicJwk = {
  ...await exportJWK(publicKey),
  alg: "RS256",
  kid: "test-rsa-key",
  use: "sig",
};
const localJwks = createLocalJWKSet({ keys: [publicJwk] });
let cachedToken = "";
cachedToken = await validToken();

Deno.test("ships the import map required by the production bundler", async () => {
  const config = JSON.parse(
    await Deno.readTextFile(
      new URL("./deno.json", import.meta.url),
    ),
  );

  for (
    const dependency of [
      "@modelcontextprotocol/sdk/server/mcp.js",
      "@modelcontextprotocol/sdk/server/webStandardStreamableHttp.js",
      "@modelcontextprotocol/sdk/types.js",
      "@supabase/functions-js/edge-runtime.d.ts",
      "jose",
      "zod",
    ]
  ) {
    assert(typeof config.imports?.[dependency] === "string");
  }
});

Deno.test("serves exact nested protected-resource metadata", async () => {
  const response = await handler()(
    new Request(metadataUrl, { headers: { "x-request-id": "metadata-1" } }),
  );

  assertEquals(response.status, 200);
  assertEquals(response.headers.get("x-request-id"), "metadata-1");
  assertEquals(await response.json(), {
    resource,
    authorization_servers: [issuer],
    scopes_supported: [],
    bearer_methods_supported: ["header"],
  });
});

Deno.test("challenges unauthenticated MCP requests with exact metadata URL", async () => {
  const response = await handler()(
    mcpRequest(initializeMessage(), { token: null }),
  );

  assertEquals(response.status, 401);
  assertEquals(
    response.headers.get("www-authenticate"),
    `Bearer resource_metadata="${metadataUrl}"`,
  );
});

Deno.test("verifies a signed JWT then resolves only pseudonymous claims", async () => {
  const calls: FetchCall[] = [];
  const response = await handler({ calls })(
    mcpRequest(initializeMessage()),
  );
  const payload = await response.json();

  assertEquals(response.status, 200);
  assertEquals(payload.result.protocolVersion, "2025-11-25");
  assertEquals(calls.length, 1);
  assertEquals(
    calls[0].url,
    "https://supabase.test/rest/v1/rpc/resolve_pomodoist_mcp_session",
  );
  assertEquals(calls[0].body, {
    p_subject: subject,
    p_session_id: sessionId,
    p_client_id: clientId,
  });
  assertServiceRoleHeaders(calls[0].headers);
  assert(!JSON.stringify(calls[0]).includes(await validToken()));
});

Deno.test("negotiates the sole supported protocol version 2025-11-25", async () => {
  const message = initializeMessage();
  message.params.protocolVersion = "2025-06-18";
  const response = await handler()(mcpRequest(message));

  assertEquals(response.status, 200);
  assertEquals(
    (await response.json()).result.protocolVersion,
    "2025-11-25",
  );
});

Deno.test("rejects initialize before negotiation when protocolVersion is missing or not a string", async () => {
  for (
    const params of [
      {
        capabilities: {},
        clientInfo: { name: "test-client", version: "1.0.0" },
      },
      {
        protocolVersion: 7,
        capabilities: {},
        clientInfo: { name: "test-client", version: "1.0.0" },
      },
    ]
  ) {
    const response = await handler()(mcpRequest({
      jsonrpc: "2.0",
      id: 7,
      method: "initialize",
      params,
    }));

    assertEquals(response.status, 400);
  }
});

Deno.test("rejects older protocol headers after initialization", async () => {
  const response = await handler()(mcpRequest({
    jsonrpc: "2.0",
    id: 7,
    method: "tools/list",
    params: {},
  }, { protocolVersion: "2025-06-18" }));

  assertEquals(response.status, 400);
});

Deno.test("requires the exact protocol header after initialization", async () => {
  const response = await handler()(mcpRequest({
    jsonrpc: "2.0",
    id: 8,
    method: "tools/list",
    params: {},
  }, { protocolVersion: null }));

  assertEquals(response.status, 400);
});

Deno.test("rejects a JWT with a bad signature", async () => {
  const token = await validToken({}, otherPrivateKey);
  const response = await handler()(mcpRequest(initializeMessage(), { token }));

  assertEquals(response.status, 401);
});

Deno.test("rejects symmetric JWT algorithms before consulting JWKS", async () => {
  const secret = new TextEncoder().encode(
    "a-test-secret-at-least-32-bytes-long",
  );
  const token = await new SignJWT(validClaims())
    .setProtectedHeader({ alg: "HS256", kid: "symmetric" })
    .sign(secret);
  let jwksCreations = 0;
  const response = await handler({
    createJwks: () => {
      jwksCreations++;
      return localJwks;
    },
  })(mcpRequest(initializeMessage(), { token }));

  assertEquals(response.status, 401);
  assertEquals(jwksCreations, 0);
});

Deno.test("rejects an unexpected issuer before creating or fetching JWKS", async () => {
  const token = await validToken({ iss: "https://attacker.test/auth/v1" });
  let jwksCreations = 0;
  const response = await handler({
    createJwks: () => {
      jwksCreations++;
      return localJwks;
    },
  })(mcpRequest(initializeMessage(), { token }));

  assertEquals(response.status, 401);
  assertEquals(jwksCreations, 0);
});

for (
  const [name, claims] of [
    ["audience", { aud: `${resource}/other` }],
    ["expiry", { exp: Math.floor(Date.now() / 1000) - 60 }],
    ["role", { role: "authenticated" }],
    ["subject UUID", { sub: "not-a-uuid" }],
    ["session UUID", { session_id: "not-a-uuid" }],
    ["client UUID", { client_id: "not-a-uuid" }],
  ] as const
) {
  Deno.test(`rejects an invalid JWT ${name}`, async () => {
    const response = await handler()(
      mcpRequest(initializeMessage(), { token: await validToken(claims) }),
    );

    assertEquals(response.status, 401);
  });
}

Deno.test("rejects revoked or mismatched resolver results", async () => {
  for (const resolverBody of [null, [realUserId], { user_id: realUserId }]) {
    const response = await handler({ resolverBody })(
      mcpRequest(initializeMessage()),
    );
    assertEquals(response.status, 401);
  }
});

Deno.test("handles initialize, initialized notification, and request-scoped empty tools/list", async () => {
  const serve = handler();
  const initialized = await serve(
    mcpRequest({
      jsonrpc: "2.0",
      method: "notifications/initialized",
      params: {},
    }),
  );
  const listed = await serve(
    mcpRequest({
      jsonrpc: "2.0",
      id: 2,
      method: "tools/list",
      params: {},
    }),
  );

  assertEquals(initialized.status, 202);
  assertEquals(await initialized.text(), "");
  assertEquals(listed.status, 200);
  assertEquals(await listed.json(), {
    jsonrpc: "2.0",
    id: 2,
    result: { tools: [] },
  });
  assertEquals(listed.headers.get("mcp-session-id"), null);
});

Deno.test("allows missing and exact allowlisted Origins", async () => {
  const serve = handler();
  const missing = await serve(mcpRequest(initializeMessage()));
  const allowed = await serve(
    mcpRequest(initializeMessage(), {
      origin: "https://inspector.example",
    }),
  );

  assertEquals(missing.status, 200);
  assertEquals(allowed.status, 200);
  assertEquals(
    allowed.headers.get("access-control-allow-origin"),
    "https://inspector.example",
  );
});

Deno.test("rejects a disallowed Origin before reading the body", async () => {
  let reads = 0;
  class TrackingRequest extends Request {
    override get body() {
      reads++;
      return super.body;
    }
  }
  const response = await handler()(
    new TrackingRequest(resource, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${await validToken()}`,
        Origin: "https://evil.example",
      },
      body: "{}",
    }),
  );

  assertEquals(response.status, 403);
  assertEquals(reads, 0);
});

Deno.test("rejects oversized Content-Length without reading the body", async () => {
  let reads = 0;
  class TrackingRequest extends Request {
    override get body() {
      reads++;
      return super.body;
    }
  }
  const response = await handler()(
    new TrackingRequest(resource, {
      method: "POST",
      headers: {
        Accept: "application/json, text/event-stream",
        Authorization: `Bearer ${await validToken()}`,
        "Content-Length": `${256 * 1024 + 1}`,
        "Content-Type": "application/json",
      },
      body: "{}",
    }),
  );

  assertEquals(response.status, 413);
  assertEquals(reads, 0);
});

Deno.test("rejects streamed body overflow at 256 KiB", async () => {
  const chunk = new Uint8Array(150 * 1024);
  let sent = 0;
  const body = new ReadableStream<Uint8Array>({
    pull(controller) {
      if (sent++ < 2) {
        controller.enqueue(chunk);
      } else {
        controller.close();
      }
    },
  });
  const response = await handler()(
    new Request(resource, {
      method: "POST",
      headers: mcpHeaders(await validToken()),
      body,
    }),
  );

  assertEquals(response.status, 413);
});

Deno.test("consumes rate limit only for tools/call", async () => {
  const calls: FetchCall[] = [];
  let executions = 0;
  const serve = handler({
    calls,
    registerTools(server) {
      server.registerTool(
        "test_echo",
        {
          inputSchema: { value: z.string() },
          outputSchema: { ok: z.literal(true), data: z.unknown() },
        },
        ({ value }) => {
          executions++;
          return toolSuccess({ value });
        },
      );
    },
  });
  await serve(mcpRequest(initializeMessage()));
  await serve(mcpRequest({
    jsonrpc: "2.0",
    id: 3,
    method: "tools/list",
    params: {},
  }));
  const called = await serve(mcpRequest({
    jsonrpc: "2.0",
    id: 4,
    method: "tools/call",
    params: { name: "test_echo", arguments: { value: "hello" } },
  }));

  assertEquals(called.status, 200);
  assertEquals(executions, 1);
  assertEquals(
    calls.filter((call) =>
      call.url.endsWith("/rpc/consume_pomodoist_mcp_rate_limit")
    ).length,
    1,
  );
});

Deno.test("returns structured retry error without invoking a rate-limited tool", async () => {
  let executions = 0;
  const response = await handler({
    rateLimitBody: [{ allowed: false, retry_after_seconds: 7 }],
    registerTools(server) {
      server.registerTool("test_echo", { inputSchema: {} }, () => {
        executions++;
        return toolSuccess({});
      });
    },
  })(mcpRequest({
    jsonrpc: "2.0",
    id: 5,
    method: "tools/call",
    params: { name: "test_echo", arguments: {} },
  }));

  assertEquals(executions, 0);
  assertEquals(await response.json(), {
    jsonrpc: "2.0",
    id: 5,
    result: {
      content: [{
        type: "text",
        text:
          '{"ok":false,"error":{"code":"rate_limited","message":"Rate limit exceeded.","retry_after_seconds":7}}',
      }],
      structuredContent: {
        ok: false,
        error: {
          code: "rate_limited",
          message: "Rate limit exceeded.",
          retry_after_seconds: 7,
        },
      },
      isError: true,
    },
  });
});

Deno.test("logs a JSON-RPC method error as an error outcome", async () => {
  const logs: unknown[] = [];
  const response = await handler({ log: (entry) => logs.push(entry) })(
    mcpRequest({
      jsonrpc: "2.0",
      id: 9,
      method: "tools/call",
      params: { name: "missing_tool", arguments: {} },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals((await response.json()).error.code, -32601);
  assertEquals(
    (logs[0] as Record<string, unknown>).outcome,
    "error",
  );
});

Deno.test("logs an isError tool result without logging its response content", async () => {
  const logs: unknown[] = [];
  const response = await handler({
    log: (entry) => logs.push(entry),
    registerTools(server) {
      server.registerTool(
        "test_failure",
        { inputSchema: {} },
        () => toolError("internal", "private response content"),
      );
    },
  })(mcpRequest({
    jsonrpc: "2.0",
    id: 10,
    method: "tools/call",
    params: { name: "test_failure", arguments: {} },
  }));

  assertEquals(response.status, 200);
  assertEquals((await response.json()).result.isError, true);
  assertEquals(
    (logs[0] as Record<string, unknown>).outcome,
    "error",
  );
  assert(!JSON.stringify(logs).includes("private response content"));
});

Deno.test("builds equivalent success and accepted-code error envelopes", () => {
  assertEquals(toolSuccess({ count: 2 }), {
    content: [{
      type: "text",
      text: '{"ok":true,"data":{"count":2}}',
    }],
    structuredContent: { ok: true, data: { count: 2 } },
  });
  assertEquals(toolError("not_found", "Task not found."), {
    content: [{
      type: "text",
      text:
        '{"ok":false,"error":{"code":"not_found","message":"Task not found."}}',
    }],
    structuredContent: {
      ok: false,
      error: { code: "not_found", message: "Task not found." },
    },
    isError: true,
  });
});

Deno.test("structured logs exclude credentials, arguments, content, and real user UUID", async () => {
  const logs: unknown[] = [];
  const token = await validToken();
  const response = await handler({
    log: (entry) => logs.push(entry),
    registerTools(server) {
      server.registerTool(
        "test_echo",
        {
          inputSchema: { task: z.string() },
          outputSchema: { ok: z.literal(true), data: z.unknown() },
        },
        () => toolSuccess({ accepted: true }),
      );
    },
  })(mcpRequest({
    jsonrpc: "2.0",
    id: 6,
    method: "tools/call",
    params: {
      name: "test_echo",
      arguments: { task: "private task content" },
    },
  }, { token }));

  assertEquals(response.status, 200);
  assertEquals(logs.length, 1);
  assertEquals(Object.keys(logs[0] as Record<string, unknown>).sort(), [
    "client_id",
    "latency_ms",
    "outcome",
    "request_id",
    "subject",
    "tool_name",
  ]);
  const captured = JSON.stringify(logs);
  for (
    const secret of [
      token,
      "private task content",
      serviceKey,
      realUserId,
      '"arguments"',
    ]
  ) {
    assert(!captured.includes(secret), `log leaked ${secret}`);
  }
});

Deno.test("local config disables platform JWT verification for pomodoist-mcp", async () => {
  const config = await Deno.readTextFile(
    new URL("../../config.toml", import.meta.url),
  );
  assertMatch(
    config,
    /\[functions\.pomodoist-mcp\]\s+verify_jwt = false/,
  );
});

Deno.test("rejects invalid dependency configuration", () => {
  assertThrows(
    () =>
      createPomodoistMcpHandler({
        ...dependencies(),
        config: { ...dependencies().config, issuer: `${issuer}/` },
      }),
    Error,
  );
});

Deno.test("accepts only the reviewed production gateway origin", () => {
  const productionConfig = {
    ...dependencies().config,
    issuer: "https://ewauihswbwduvklrozke.supabase.co/auth/v1",
    resourceUrl: "https://mcp.pomodoist.com/functions/v1/pomodoist-mcp",
  };

  createPomodoistMcpHandler({
    ...dependencies(),
    config: productionConfig,
  });
  assertThrows(
    () =>
      createPomodoistMcpHandler({
        ...dependencies(),
        config: {
          ...productionConfig,
          resourceUrl: "https://evil.example/functions/v1/pomodoist-mcp",
        },
      }),
    Error,
  );
});

Deno.test("accepts the path Supabase passes to a deployed function", async () => {
  const response = await handler()(
    new Request("https://issuer.test/pomodoist-mcp", {
      method: "POST",
    }),
  );

  assertEquals(response.status, 401);
  assertEquals(
    response.headers.get("www-authenticate"),
    `Bearer resource_metadata="${metadataUrl}"`,
  );
});

type FetchCall = {
  url: string;
  headers: Headers;
  body: unknown;
};

function handler(
  options: {
    calls?: FetchCall[];
    resolverBody?: unknown;
    rateLimitBody?: unknown;
    createJwks?: PomodoistMcpDependencies["createJwks"];
    registerTools?: PomodoistMcpDependencies["registerTools"];
    log?: PomodoistMcpDependencies["log"];
  } = {},
) {
  return createPomodoistMcpHandler(dependencies(options));
}

function dependencies(
  options: {
    calls?: FetchCall[];
    resolverBody?: unknown;
    rateLimitBody?: unknown;
    createJwks?: PomodoistMcpDependencies["createJwks"];
    registerTools?: PomodoistMcpDependencies["registerTools"];
    log?: PomodoistMcpDependencies["log"];
  } = {},
): PomodoistMcpDependencies {
  return {
    config: {
      issuer,
      resourceUrl: resource,
      allowedOrigins: ["https://inspector.example"],
      supabaseUrl: "https://supabase.test",
      serviceRoleKey: serviceKey,
    },
    createJwks: options.createJwks ?? (() => localJwks),
    fetch: (input, init) => {
      const url = String(input);
      const headers = new Headers(init?.headers);
      const body = init?.body ? JSON.parse(String(init.body)) : undefined;
      options.calls?.push({ url, headers, body });
      if (url.endsWith("/rpc/resolve_pomodoist_mcp_session")) {
        return Promise.resolve(Response.json(
          options.resolverBody === undefined
            ? realUserId
            : options.resolverBody,
        ));
      }
      if (url.endsWith("/rpc/consume_pomodoist_mcp_rate_limit")) {
        return Promise.resolve(Response.json(
          options.rateLimitBody ?? [{
            allowed: true,
            retry_after_seconds: null,
          }],
        ));
      }
      throw new Error(`Unexpected fetch: ${url}`);
    },
    log: options.log ?? (() => {}),
    requestId: () => "generated-request-id",
    registerTools: options.registerTools,
  };
}

function initializeMessage() {
  return {
    jsonrpc: "2.0",
    id: 1,
    method: "initialize",
    params: {
      protocolVersion: "2025-11-25",
      capabilities: {},
      clientInfo: { name: "test-client", version: "1.0.0" },
    },
  };
}

function mcpRequest(
  message: unknown,
  options: {
    token?: string | null;
    origin?: string;
    protocolVersion?: string | null;
  } = {},
) {
  return new Request(resource, {
    method: "POST",
    headers: {
      ...mcpHeaders(
        options.token === null ? null : options.token,
        options.protocolVersion,
      ),
      ...(options.origin ? { Origin: options.origin } : {}),
    },
    body: JSON.stringify(message),
  });
}

function mcpHeaders(
  token?: string | null,
  protocol: string | null = "2025-11-25",
) {
  return {
    Accept: "application/json, text/event-stream",
    ...(token === null
      ? {}
      : { Authorization: `Bearer ${token ?? cachedToken}` }),
    "Content-Type": "application/json",
    ...(protocol === null ? {} : { "MCP-Protocol-Version": protocol }),
  };
}

async function validToken(
  overrides: Record<string, unknown> = {},
  key: CryptoKey = privateKey,
) {
  const claims = { ...validClaims(), ...overrides };
  const token = await new SignJWT(claims)
    .setProtectedHeader({ alg: "RS256", kid: "test-rsa-key", typ: "JWT" })
    .sign(key);
  return token;
}

function validClaims() {
  return {
    iss: issuer,
    aud: resource,
    exp: Math.floor(Date.now() / 1000) + 3600,
    role: "pomodoist_mcp",
    sub: subject,
    session_id: sessionId,
    client_id: clientId,
  };
}

function assertServiceRoleHeaders(headers: Headers) {
  assertEquals(headers.get("apikey"), serviceKey);
  assertEquals(headers.get("authorization"), `Bearer ${serviceKey}`);
}

Deno.test("self-hosted MCP permits loopback HTTP and rejects insecure remote URLs", () => {
  for (
    const origin of [
      "http://localhost:55421",
      "http://127.0.0.1:55421",
      "http://[::1]:55421",
    ]
  ) {
    createPomodoistMcpHandler({
      ...dependencies(),
      config: {
        ...dependencies().config,
        issuer: `${origin}/auth/v1`,
        resourceUrl: `${origin}/functions/v1/pomodoist-mcp`,
      },
    });
  }
  for (
    const origin of [
      "http://remote.example",
      "http://localhost.evil.example",
      "https://user:password@example.com",
    ]
  ) {
    assertThrows(() =>
      createPomodoistMcpHandler({
        ...dependencies(),
        config: {
          ...dependencies().config,
          issuer: `${origin}/auth/v1`,
          resourceUrl: `${origin}/functions/v1/pomodoist-mcp`,
        },
      })
    );
  }
});

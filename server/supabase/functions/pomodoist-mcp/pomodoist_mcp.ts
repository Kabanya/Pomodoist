import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { WebStandardStreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/webStandardStreamableHttp.js";
import {
  InitializeRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import {
  createRemoteJWKSet,
  decodeJwt,
  decodeProtectedHeader,
  jwtVerify,
  type JWTVerifyGetKey,
} from "jose";
import { z } from "zod";

const maxBodyBytes = 256 * 1024;
const protocolVersion = "2025-11-25";
const allowedAlgorithms = ["RS256", "ES256"] as const;
const uuid = z.string().uuid();
const claimsSchema = z.object({
  iss: z.string(),
  aud: z.string(),
  exp: z.number(),
  role: z.literal("pomodoist_mcp"),
  sub: uuid,
  session_id: uuid,
  client_id: uuid,
});
const rateLimitRowSchema = z.object({
  allowed: z.boolean(),
  retry_after_seconds: z.number().int().positive().nullable(),
});

export type ToolErrorCode =
  | "invalid_argument"
  | "not_found"
  | "conflict"
  | "forbidden"
  | "rate_limited"
  | "internal";

export type PomodoistMcpConfig = {
  issuer: string;
  resourceUrl: string;
  allowedOrigins: string[];
  supabaseUrl: string;
  serviceRoleKey: string;
};

export type PomodoistMcpAuth = {
  subject: string;
  sessionId: string;
  clientId: string;
  userId: string;
};

export type PomodoistMcpLog = {
  request_id: string;
  subject: string;
  client_id: string;
  tool_name: string;
  outcome: string;
  latency_ms: number;
};

export type PomodoistMcpFetch = (
  input: string | URL | Request,
  init?: globalThis.RequestInit,
) => Promise<Response>;

export type PomodoistMcpDependencies = {
  config: PomodoistMcpConfig;
  createJwks?: (issuer: string) => JWTVerifyGetKey;
  fetch?: PomodoistMcpFetch;
  log?: (entry: PomodoistMcpLog) => void;
  requestId?: () => string;
  registerTools?: (server: McpServer, auth: PomodoistMcpAuth) => void;
};

export function toolSuccess(data: unknown) {
  const structuredContent = { ok: true as const, data };
  return {
    content: [{
      type: "text" as const,
      text: JSON.stringify(structuredContent),
    }],
    structuredContent,
  };
}

export function toolError(
  code: ToolErrorCode,
  message: string,
  retryAfterSeconds?: number,
) {
  const error = {
    code,
    message,
    ...(retryAfterSeconds === undefined
      ? {}
      : { retry_after_seconds: retryAfterSeconds }),
  };
  const structuredContent = { ok: false as const, error };
  return {
    content: [{
      type: "text" as const,
      text: JSON.stringify(structuredContent),
    }],
    structuredContent,
    isError: true,
  };
}

export function configFromEnv(): PomodoistMcpConfig {
  return {
    issuer: requiredEnv("POMODOIST_MCP_ISSUER"),
    resourceUrl: requiredEnv("POMODOIST_MCP_RESOURCE_URL"),
    allowedOrigins: (Deno.env.get("POMODOIST_MCP_ALLOWED_ORIGINS") ?? "")
      .split(",")
      .map((origin) => origin.trim())
      .filter(Boolean),
    supabaseUrl: requiredEnv("SUPABASE_URL"),
    serviceRoleKey: requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
  };
}

export function createPomodoistMcpHandler(
  dependencies: PomodoistMcpDependencies,
) {
  const config = validateConfig(dependencies.config);
  const fetcher = dependencies.fetch ?? fetch;
  const logger = dependencies.log ??
    ((entry) => console.log(JSON.stringify(entry)));
  const createJwks = dependencies.createJwks ??
    (() =>
      createRemoteJWKSet(
        // The public issuer can be loopback on the host; use the configured API
        // inside Docker while still verifying the token's exact public issuer.
        new URL(`${config.supabaseUrl}/auth/v1/.well-known/jwks.json`),
      ));
  const metadataUrl = protectedResourceMetadataUrl(config.resourceUrl);
  const metadataPath = new URL(metadataUrl).pathname;
  const resourcePath = new URL(config.resourceUrl).pathname;
  let jwks: JWTVerifyGetKey | undefined;

  return async (request: Request): Promise<Response> => {
    const startedAt = performance.now();
    const requestId = request.headers.get("x-request-id") ||
      dependencies.requestId?.() || crypto.randomUUID();
    const origin = request.headers.get("origin");
    let auth: PomodoistMcpAuth | undefined;
    let toolName = "";
    let outcome = "internal";

    try {
      if (origin && !config.allowedOrigins.includes(origin)) {
        outcome = "forbidden";
        return withResponseHeaders(
          Response.json({ error: "Forbidden." }, { status: 403 }),
          requestId,
        );
      }

      const pathname = new URL(request.url).pathname;
      if (pathname === metadataPath) {
        outcome = "ok";
        return withResponseHeaders(
          Response.json({
            resource: config.resourceUrl,
            authorization_servers: [config.issuer],
            scopes_supported: [],
            bearer_methods_supported: ["header"],
          }),
          requestId,
          origin,
        );
      }
      if (pathname !== resourcePath && pathname !== "/pomodoist-mcp") {
        outcome = "not_found";
        return withResponseHeaders(
          Response.json({ error: "Not found." }, { status: 404 }),
          requestId,
          origin,
        );
      }
      if (request.method === "OPTIONS") {
        outcome = "ok";
        return withResponseHeaders(
          new Response(null, {
            status: 204,
            headers: {
              "Access-Control-Allow-Headers":
                "authorization, content-type, mcp-protocol-version, x-request-id",
              "Access-Control-Allow-Methods": "POST, OPTIONS",
            },
          }),
          requestId,
          origin,
        );
      }

      const token = bearerToken(request);
      if (!token) {
        outcome = "unauthorized";
        return unauthorized(requestId, metadataUrl, origin);
      }

      const claims = await verifyBearer(token);
      const userId = await resolveSession(fetcher, config, claims);
      if (!userId) {
        outcome = "unauthorized";
        return unauthorized(requestId, metadataUrl, origin);
      }
      auth = {
        subject: claims.sub,
        sessionId: claims.session_id,
        clientId: claims.client_id,
        userId,
      };

      if (request.method !== "POST") {
        outcome = "method_not_allowed";
        return withResponseHeaders(
          Response.json({ error: "Method not allowed." }, { status: 405 }),
          requestId,
          origin,
        );
      }

      const originalBody = await readBoundedJson(request);
      if (
        getMethod(originalBody) === "initialize" &&
        !InitializeRequestSchema.safeParse(originalBody).success
      ) {
        throw new BadRequestError();
      }
      const parsedBody = negotiateProtocolVersion(originalBody);
      const requestedProtocol = request.headers.get("mcp-protocol-version");
      if (
        getMethod(parsedBody) !== "initialize" &&
        requestedProtocol !== protocolVersion
      ) {
        throw new BadRequestError();
      }
      toolName = getToolName(parsedBody);
      if (getMethod(parsedBody) === "tools/call") {
        const rateLimit = await consumeRateLimit(fetcher, config, auth);
        if (!rateLimit.allowed) {
          outcome = "rate_limited";
          return withResponseHeaders(
            Response.json({
              jsonrpc: "2.0",
              id: getRequestId(parsedBody),
              result: toolError(
                "rate_limited",
                "Rate limit exceeded.",
                rateLimit.retry_after_seconds ?? 1,
              ),
            }),
            requestId,
            origin,
          );
        }
      }

      const server = new McpServer({
        name: "pomodoist-mcp",
        version: "1.0.0",
      });
      if (dependencies.registerTools) {
        dependencies.registerTools(server, auth);
      } else {
        server.server.registerCapabilities({ tools: { listChanged: false } });
        server.server.setRequestHandler(
          ListToolsRequestSchema,
          () => ({ tools: [] }),
        );
      }
      const transport = new WebStandardStreamableHTTPServerTransport({
        sessionIdGenerator: undefined,
        enableJsonResponse: true,
      });
      try {
        await server.connect(transport);
        const response = await transport.handleRequest(request, { parsedBody });
        outcome = await responseOutcome(response);
        return withResponseHeaders(response, requestId, origin);
      } finally {
        await server.close();
      }
    } catch (error) {
      if (error instanceof PayloadTooLargeError) {
        outcome = "payload_too_large";
        return withResponseHeaders(
          Response.json({ error: "Payload too large." }, { status: 413 }),
          requestId,
          origin,
        );
      }
      if (error instanceof BadRequestError) {
        outcome = "invalid_request";
        return withResponseHeaders(
          Response.json({ error: "Invalid request." }, { status: 400 }),
          requestId,
          origin,
        );
      }
      if (error instanceof UnauthorizedError) {
        outcome = "unauthorized";
        return unauthorized(requestId, metadataUrl, origin);
      }
      outcome = "internal";
      return withResponseHeaders(
        Response.json({ error: "Internal server error." }, { status: 500 }),
        requestId,
        origin,
      );
    } finally {
      logger({
        request_id: requestId,
        subject: auth?.subject ?? "",
        client_id: auth?.clientId ?? "",
        tool_name: toolName,
        outcome,
        latency_ms: Math.max(0, Math.round(performance.now() - startedAt)),
      });
    }
  };

  async function verifyBearer(token: string) {
    try {
      const unverifiedPayload = decodeJwt(token);
      if (unverifiedPayload.iss !== config.issuer) {
        throw new UnauthorizedError();
      }
      const header = decodeProtectedHeader(token);
      if (
        typeof header.alg !== "string" ||
        !allowedAlgorithms.includes(
          header.alg as typeof allowedAlgorithms[number],
        )
      ) {
        throw new UnauthorizedError();
      }
      jwks ??= createJwks(config.issuer);
      const { payload } = await jwtVerify(token, jwks, {
        algorithms: [...allowedAlgorithms],
        audience: config.resourceUrl,
        issuer: config.issuer,
        requiredClaims: [
          "aud",
          "client_id",
          "exp",
          "iss",
          "role",
          "session_id",
          "sub",
        ],
      });
      const parsed = claimsSchema.safeParse(payload);
      if (!parsed.success || parsed.data.aud !== config.resourceUrl) {
        throw new UnauthorizedError();
      }
      return parsed.data;
    } catch (error) {
      if (error instanceof UnauthorizedError) {
        throw error;
      }
      throw new UnauthorizedError();
    }
  }
}

function secureEndpoint(url: URL) {
  return !url.username && !url.password && (url.protocol === "https:" ||
    (url.protocol === "http:" &&
      ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname)));
}

function validateConfig(config: PomodoistMcpConfig) {
  const issuer = new URL(config.issuer);
  const resource = new URL(config.resourceUrl);
  const productionGateway = config.issuer ===
      "https://ewauihswbwduvklrozke.supabase.co/auth/v1" &&
    config.resourceUrl ===
      "https://mcp.pomodoist.com/functions/v1/pomodoist-mcp";
  if (
    !secureEndpoint(issuer) ||
    issuer.pathname !== "/auth/v1" ||
    issuer.search || issuer.hash ||
    !secureEndpoint(resource) ||
    resource.pathname !== "/functions/v1/pomodoist-mcp" ||
    resource.search || resource.hash ||
    (resource.origin !== issuer.origin && !productionGateway) ||
    !config.supabaseUrl ||
    !config.serviceRoleKey
  ) {
    throw new Error("Invalid Pomodoist MCP configuration.");
  }
  for (const origin of config.allowedOrigins) {
    const parsed = new URL(origin);
    if (parsed.origin !== origin) {
      throw new Error("Allowed Origins must be exact origins.");
    }
  }
  return {
    ...config,
    supabaseUrl: config.supabaseUrl.replace(/\/+$/, ""),
  };
}

function protectedResourceMetadataUrl(resourceUrl: string) {
  const resource = new URL(resourceUrl);
  return `${resource.origin}/.well-known/oauth-protected-resource${resource.pathname}`;
}

async function resolveSession(
  fetcher: PomodoistMcpFetch,
  config: PomodoistMcpConfig,
  claims: z.infer<typeof claimsSchema>,
) {
  const response = await postgrestRpc(
    fetcher,
    config,
    "resolve_pomodoist_mcp_session",
    {
      p_subject: claims.sub,
      p_session_id: claims.session_id,
      p_client_id: claims.client_id,
    },
  );
  if (!response.ok) {
    throw new Error("Session resolver failed.");
  }
  const parsed = uuid.safeParse(await response.json());
  return parsed.success ? parsed.data : null;
}

async function consumeRateLimit(
  fetcher: PomodoistMcpFetch,
  config: PomodoistMcpConfig,
  auth: PomodoistMcpAuth,
) {
  const response = await postgrestRpc(
    fetcher,
    config,
    "consume_pomodoist_mcp_rate_limit",
    {
      p_user_id: auth.userId,
      p_client_id: auth.clientId,
    },
  );
  if (!response.ok) {
    throw new Error("Rate limiter failed.");
  }
  const body = await response.json();
  const parsed = z.array(rateLimitRowSchema).length(1).safeParse(body);
  if (!parsed.success) {
    throw new Error("Invalid rate limiter response.");
  }
  return parsed.data[0];
}

function postgrestRpc(
  fetcher: PomodoistMcpFetch,
  config: PomodoistMcpConfig,
  rpc: string,
  body: Record<string, string>,
) {
  return fetcher(`${config.supabaseUrl}/rest/v1/rpc/${rpc}`, {
    method: "POST",
    headers: {
      apikey: config.serviceRoleKey,
      Authorization: `Bearer ${config.serviceRoleKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
}

function bearerToken(request: Request) {
  return request.headers.get("authorization")?.match(/^Bearer ([^\s]+)$/)?.[1];
}

async function readBoundedJson(request: Request) {
  const declaredLength = request.headers.get("content-length");
  if (
    declaredLength !== null &&
    /^\d+$/.test(declaredLength) &&
    Number(declaredLength) > maxBodyBytes
  ) {
    throw new PayloadTooLargeError();
  }
  if (!request.body) {
    throw new BadRequestError();
  }
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      length += value.byteLength;
      if (length > maxBodyBytes) {
        await reader.cancel();
        throw new PayloadTooLargeError();
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  try {
    return JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    throw new BadRequestError();
  }
}

function getMethod(body: unknown) {
  return isRecord(body) && typeof body.method === "string" ? body.method : "";
}

function negotiateProtocolVersion(body: unknown) {
  if (getMethod(body) !== "initialize" || !isRecord(body)) return body;
  return {
    ...body,
    params: {
      ...(isRecord(body.params) ? body.params : {}),
      protocolVersion,
    },
  };
}

function getToolName(body: unknown) {
  if (getMethod(body) !== "tools/call" || !isRecord(body)) return "";
  const params = body.params;
  return isRecord(params) && typeof params.name === "string" ? params.name : "";
}

function getRequestId(body: unknown) {
  if (!isRecord(body)) return null;
  return typeof body.id === "string" || typeof body.id === "number"
    ? body.id
    : null;
}

async function responseOutcome(response: Response) {
  if (!response.ok) return "error";
  try {
    const body = await response.clone().json();
    const messages = Array.isArray(body) ? body : [body];
    return messages.some((message) =>
        isRecord(message) &&
        (isRecord(message.error) ||
          (isRecord(message.result) && message.result.isError === true))
      )
      ? "error"
      : "ok";
  } catch {
    return "ok";
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function unauthorized(
  requestId: string,
  metadataUrl: string,
  origin: string | null,
) {
  return withResponseHeaders(
    Response.json({ error: "Unauthorized." }, {
      status: 401,
      headers: {
        "WWW-Authenticate": `Bearer resource_metadata="${metadataUrl}"`,
      },
    }),
    requestId,
    origin,
  );
}

function withResponseHeaders(
  response: Response,
  requestId: string,
  origin?: string | null,
) {
  const headers = new Headers(response.headers);
  headers.set("x-request-id", requestId);
  if (origin) {
    headers.set("access-control-allow-origin", origin);
    headers.set("vary", "Origin");
  }
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is required.`);
  return value;
}

class UnauthorizedError extends Error {}
class BadRequestError extends Error {}
class PayloadTooLargeError extends Error {}

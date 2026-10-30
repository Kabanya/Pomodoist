import { assertEquals } from "jsr:@std/assert";
import { handlePomodoistAi } from "./pomodoist_ai.ts";
import type { PomodoistWatchDeps } from "../_shared/task_decomposition_http.ts";

const resource = { kind: "domain", id: "youtube.com" };
const provider = {
  usage: { server_tool_use: { web_search_requests: 1 } },
  choices: [{
    message: {
      content: JSON.stringify({
        category: "video",
        sources: [{ title: "YouTube", url: "https://www.youtube.com/about/" }],
      }),
      annotations: [{
        type: "url_citation",
        url_citation: {
          title: "YouTube",
          url: "https://www.youtube.com/about/",
        },
      }],
    },
  }],
};
function fixture(
  options: {
    pro?: boolean;
    cached?: boolean;
    response?: unknown;
    status?: number;
    fail?: boolean;
    cacheFail?: boolean;
    exhausted?: boolean;
  } = {},
) {
  const quota: string[] = [];
  const cacheCalls: RequestInit[] = [];
  const calls: Record<string, unknown>[] = [];
  const assignment = {
    ...resource,
    name: "youtube.com",
    source: "automatic",
    category: "video",
    sources: [{ title: "YouTube", url: "https://www.youtube.com/about/" }],
    updatedAt: "2026-10-26T00:00:00Z",
  };
  const deps: PomodoistWatchDeps = {
    env: {
      get: (key) =>
        key === "POMODOIST_OPENROUTER_API_KEY"
          ? "secret"
          : key === "SUPABASE_URL"
          ? "https://database.test"
          : key === "SUPABASE_SERVICE_ROLE_KEY"
          ? "service-secret"
          : undefined,
    },
    now: () => new Date("2026-10-26T00:00:00Z"),
    uuid: () => "a0000000-0000-4000-8000-000000000001",
    quota: async (action) => {
      quota.push(action);
      return { allowed: !options.exhausted };
    },
    createClient: () => ({
      auth: { getUser: async () => ({ data: { user: { id: "user" } } }) },
      rpc: async (name) => ({
        data: name === "pomodoist_resource_classification"
          ? {
            isPro: options.pro !== false,
            assignment: options.cached ? assignment : null,
          }
          : null,
        error: null,
      }),
    }),
    fetch: (async (_url, init) => {
      if (String(_url).startsWith("https://database.test/")) {
        {
          cacheCalls.push(init!);
          return Response.json({}, { status: options.cacheFail ? 503 : 200 });
        }
      }
      calls.push(JSON.parse(init!.body as string));
      if (options.fail) throw new DOMException("timeout", "TimeoutError");
      return Response.json(options.response ?? provider, {
        status: options.status ?? 200,
      });
    }) as typeof fetch,
  };
  return { deps, quota, calls, cacheCalls };
}
async function call(
  deps: PomodoistWatchDeps,
  value: unknown = resource,
  authorization = true,
) {
  return await handlePomodoistAi(
    new Request("https://test.local", {
      method: "POST",
      headers: authorization ? { Authorization: "Bearer user" } : {},
      body: JSON.stringify({
        command: { type: "resource.classify", resource: value },
      }),
    }),
    deps,
  );
}
Deno.test("classification checks authenticated Pro before cache and does not spend cache quota", async () => {
  const free = fixture({ pro: false, cached: true });
  assertEquals((await call(free.deps)).status, 403);
  assertEquals(free.calls.length, 0);
  assertEquals(free.quota, []);
  const cached = fixture({ cached: true });
  const response = await call(cached.deps);
  assertEquals(response.status, 200);
  assertEquals((await response.json()).cached, true);
  assertEquals(cached.quota, []);
  assertEquals((await call(cached.deps, resource, false)).status, 401);
});
Deno.test("classification uses bounded real search and shared reserve/complete quota", async () => {
  const f = fixture();
  const result = await call(f.deps);
  assertEquals(result.status, 200);
  assertEquals((await result.json()).assignment.category, "video");
  assertEquals(f.quota, ["reserve", "complete"]);
  assertEquals(f.calls[0].model, "openai/gpt-oss-120b");
  assertEquals(f.calls[0].tools, [{
    type: "openrouter:web_search",
    parameters: {
      max_uses: 1,
      max_results: 3,
      max_total_results: 3,
      engine: "parallel",
      mode: "fast",
    },
  }]);
});
Deno.test("classification rejects private identities and invented provenance without charging", async () => {
  for (
    const id of [
      "localhost",
      "192.168.1.1",
      "127.0.0.1",
      "10.0.0.1",
      "internal.local",
      "example.com/path",
      "example.com?q=secret",
      "https://example.com",
      "2130706433",
      "foo.internal",
      "foo.home.arpa",
    ]
  ) {
    const f = fixture();
    assertEquals((await call(f.deps, { kind: "domain", id })).status, 400, id);
    assertEquals(f.calls.length, 0);
  }
  const f = fixture({ response: { ...provider, usage: {} } });
  assertEquals((await call(f.deps)).status, 502);
  assertEquals(f.quota, ["reserve", "release"]);
  const bad = fixture({
    response: {
      ...provider,
      choices: [{
        message: {
          ...provider.choices[0].message,
          content: JSON.stringify({
            category: "video",
            sources: [{ title: "Invented", url: "https://invented.example" }],
          }),
        },
      }],
    },
  });
  assertEquals((await call(bad.deps)).status, 502);
  assertEquals(bad.quota, ["reserve", "release"]);
});
Deno.test("classification timeout and upstream 429 release quota and allow manual fallback", async () => {
  for (const options of [{ fail: true }, { status: 429 }]) {
    const f = fixture(options);
    const result = await call(f.deps);
    assertEquals(result.status, options.fail ? 504 : 429);
    assertEquals((await result.json()).manualAvailable, true);
    assertEquals(f.quota, ["reserve", "release"]);
  }
});

Deno.test("classification cache persists with server credentials and failed persistence releases quota", async () => {
  const f = fixture();
  const result = await call(f.deps, {
    ...resource,
    name: "Private window title must never reach search",
  });
  assertEquals(result.status, 200);
  assertEquals(JSON.stringify(f.calls).includes("Private window"), false);
  assertEquals(
    (f.cacheCalls[0].headers as Record<string, string>).Authorization,
    "Bearer service-secret",
  );
  assertEquals(
    JSON.parse(f.cacheCalls[0].body as string).p_assignment.id,
    "youtube.com",
  );
  const failed = fixture({ cacheFail: true });
  assertEquals((await call(failed.deps)).status, 503);
  assertEquals(failed.quota, ["reserve", "release"]);
  const exhausted = fixture({ exhausted: true });
  assertEquals((await call(exhausted.deps)).status, 429);
  assertEquals(exhausted.calls.length, 0);
  assertEquals(exhausted.quota, ["reserve"]);
});

Deno.test("classification accepts native Windows stable IDs and rejects paths and arbitrary namespaces", async () => {
  for (
    const id of [
      "windows:win32:chrome.exe",
      "windows:win32:Visual Studio Code.exe",
      "windows:aumid:Microsoft.WindowsCalculator_8wekyb3d8bbwe!App",
    ]
  ) {
    const f = fixture();
    const result = await call(f.deps, { kind: "app", id });
    assertEquals(result.status, 200, id);
    assertEquals((await result.json()).assignment.id, id);
    assertEquals(f.quota, ["reserve", "complete"]);
    assertEquals(
      JSON.parse(f.cacheCalls[0].body as string).p_assignment.id,
      id,
    );
  }
  for (
    const id of [
      "windows:chrome.exe",
      "windows:other:chrome.exe",
      "windows:win32:C:\\Users\\Private\\chrome.exe",
      "windows:win32:folder/chrome.exe",
      "windows:win32:chrome.exe:private",
      "windows:aumid:Microsoft.App!App:private",
      "windows:aumid:folder/App",
      "windows:win32:..exe",
    ]
  ) {
    const f = fixture();
    assertEquals((await call(f.deps, { kind: "app", id })).status, 400, id);
    assertEquals(f.calls.length, 0);
    assertEquals(f.quota, []);
  }
});

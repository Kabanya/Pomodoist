import { assertEquals, assertMatch, assertRejects } from "jsr:@std/assert";
import { createLlmQuota, type LlmQuotaSubject } from "../_shared/llm_quota.ts";
import { handlePomodoistAi } from "./pomodoist_ai.ts";
import { handlePomodoistWatch } from "../pomodoist-watch/pomodoist_watch.ts";
import type { PomodoistWatchDeps } from "../_shared/task_decomposition_http.ts";

Deno.test("AI and Watch share signed-in and StoreKit-only decomposition contracts", async () => {
  for (const signedIn of [true, false]) {
    let paidCalls = 0;
    const dependencies: PomodoistWatchDeps = {
      quota: async () => ({ allowed: true }),
      env: {
        get: (key) => key === "CEREBRAS_API_KEY" ? "test-key" : undefined,
      },
      now: () => new Date("2026-09-13T10:00:00Z"),
      uuid: () => "request-id",
      createClient: () => ({
        auth: { getUser: async () => ({ data: { user: { id: "user" } } }) },
        rpc: () => {
          throw new Error("Decomposition must not persist product state");
        },
      }),
      verifyStoreTransaction: async () => ({
        bundleId: "com.finchforge.pomodoist",
        productId: "pomodoist.pro.lifetime",
        purchaseId: "purchase",
        claims: {},
        transactionId: "transaction",
        originalTransactionId: "transaction",
        environment: "Production",
      }),
      fetch: (() => {
        paidCalls++;
        return Promise.resolve(
          Response.json({
            choices: [{
              message: { content: '{"tasks":[{"quickAdd":"Buy milk"}]}' },
            }],
          }),
        );
      }) as typeof fetch,
    };
    // Reuse the signed StoreKit fixture product from the shared purchase policy.
    const request = () =>
      new Request("https://example.test", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...(signedIn ? { Authorization: "Bearer test" } : {}),
        },
        body: JSON.stringify({
          storeTransactions: ["signed-transaction"],
          command: {
            type: "task.decomposeTranscript",
            transcript: "Buy milk",
            locale: "en",
            currentLocalTime: "2026-09-13T10:00:00Z",
          },
        }),
      });
    const watch = await handlePomodoistWatch(request(), dependencies);
    const ai = await handlePomodoistAi(request(), dependencies);
    assertEquals(ai.status, watch.status);
    assertEquals(await ai.json(), await watch.json());
    assertEquals(paidCalls, 2);
  }
});

Deno.test("AI keeps gateway JWT disabled and rejects unverified purchase", async () => {
  assertMatch(
    await Deno.readTextFile(new URL("../../config.toml", import.meta.url)),
    /\[functions\.pomodoist-ai\]\s+verify_jwt = false/,
  );
  const response = await handlePomodoistAi(
    new Request("https://example.test", {
      method: "POST",
      body: JSON.stringify({ command: { type: "task.decomposeTranscript" } }),
    }),
    {
      env: { get: () => undefined },
      fetch,
      createClient: () => {
        throw new Error("No bearer token");
      },
    },
  );
  assertEquals(response.status, 403);
  assertEquals((await response.json()).code, "purchase_verification_failed");
});

Deno.test("both AI routes gate normal and Smart calls and settle only successful analyses", async () => {
  for (const handler of [handlePomodoistAi, handlePomodoistWatch]) {
    for (const smart of [false, true]) {
      for (
        const outcome of [
          "success",
          "exhausted",
          "quota_error",
          "provider_error",
          "settlement_error",
          "invalid",
        ] as const
      ) {
        const events: string[] = [];
        const response = await handler(
          new Request("https://example.test", {
            method: "POST",
            headers: { Authorization: "Bearer verified" },
            body: JSON.stringify({
              userId: "spoofed",
              purchaseSubject: "spoofed",
              command: {
                type: "task.decomposeTranscript",
                transcript: outcome === "invalid" ? "" : "Buy milk",
                locale: "en",
                smart,
              },
            }),
          }),
          {
            env: {
              get: (key) =>
                key === "DEEPSEEK_API_KEY" ? "provider-key" : undefined,
            },
            uuid: () => "server-request",
            createClient: () => ({
              auth: {
                getUser: async () => ({
                  data: { user: { id: "verified-user" } },
                }),
              },
              rpc: () => {
                throw Error("Unexpected user RPC");
              },
            }),
            quota: async (action, subject, id) => {
              events.push(action);
              assertEquals(subject, { userId: "verified-user" });
              assertEquals(id, "server-request");
              if (
                outcome === "quota_error" ||
                (outcome === "settlement_error" && action === "complete")
              ) throw Error("Unavailable");
              return {
                allowed: outcome !== "exhausted",
                resetsAt: "2026-10-01T00:00:00Z",
              };
            },
            fetch: (() => {
              events.push("provider");
              return Promise.resolve(
                outcome === "provider_error"
                  ? new Response(null, { status: 503 })
                  : Response.json({
                    choices: [{
                      message: {
                        content: '{"tasks":[{"quickAdd":"Buy milk"}]}',
                      },
                    }],
                  }),
              );
            }) as typeof fetch,
          },
        );
        const expected = {
          success: [200, ["reserve", "provider", "complete"]],
          exhausted: [429, ["reserve"]],
          quota_error: [503, ["reserve"]],
          provider_error: [502, ["reserve", "provider", "release"]],
          settlement_error: [503, ["reserve", "provider", "complete"]],
          invalid: [400, ["reserve", "release"]],
        }[outcome];
        assertEquals([response.status, events], expected);
        if (outcome === "exhausted") {
          const body = await response.json();
          assertEquals([body.code, body.retryable, body.resetsAt], [
            "llm_quota_exceeded",
            false,
            "2026-10-01T00:00:00Z",
          ]);
        }
      }
    }
  }
});

Deno.test("StoreKit renewals use a verified stable purchase identity and retries consume one slot", async () => {
  const subjects: LlmQuotaSubject[] = [];
  const events: string[] = [];
  for (const transactionId of ["renewal-one", "renewal-two"]) {
    let attempts = 0;
    const response = await handlePomodoistAi(
      new Request("https://example.test", {
        method: "POST",
        body: JSON.stringify({
          storeTransactions: [transactionId],
          purchaseSubject: "spoofed",
          command: {
            type: "task.decomposeTranscript",
            transcript: "Buy milk",
            locale: "en",
            smart: true,
          },
        }),
      }),
      {
        env: {
          get: (key) => key === "DEEPSEEK_API_KEY" ? "test-key" : undefined,
        },
        createClient: () => {
          throw Error("No bearer token");
        },
        verifyStoreTransaction: async () => ({
          originalTransactionId: "original",
          transactionId,
          purchaseId: "original",
          environment: "Production",
          bundleId: "com.finchforge.pomodoist",
          productId: "pomodoist.pro.lifetime",
          claims: {},
        }),
        quota: async (action, subject) => {
          events.push(action);
          subjects.push(subject);
          return { allowed: true };
        },
        fetch: (() => {
          attempts++;
          return Promise.resolve(Response.json({
            choices: attempts === 1 ? [] : [{
              message: { content: '{"tasks":[{"quickAdd":"Buy milk"}]}' },
            }],
          }));
        }) as typeof fetch,
      },
    );
    assertEquals(response.status, 200);
    assertEquals(attempts, 2);
  }
  assertEquals(events, ["reserve", "complete", "reserve", "complete"]);
  assertEquals(
    subjects,
    Array(4).fill({ purchaseSubject: "apple:Production:original" }),
  );
});

Deno.test("quota RPC retries preserve identity, use server credentials and sanitize failures", async () => {
  const bodies: unknown[] = [];
  const env = {
    get: (key: string) =>
      ({
        SUPABASE_URL: "https://database.test",
        SUPABASE_SERVICE_ROLE_KEY: "server-only",
      })[key],
  };
  const quota = createLlmQuota(
    env,
    (async (input: string | URL | Request, init?: RequestInit) => {
      assertEquals(
        input,
        "https://database.test/rest/v1/rpc/pomodoist_llm_quota",
      );
      assertEquals(
        new Headers(init?.headers).get("Authorization"),
        "Bearer server-only",
      );
      bodies.push(JSON.parse(String(init?.body)));
      if (bodies.length === 1) throw Error("Lost response");
      return Response.json({ allowed: true });
    }) as typeof fetch,
  );
  assertEquals(await quota("complete", { userId: "user" }, "request"), {
    allowed: true,
    resetsAt: undefined,
  });
  assertEquals(bodies[0], bodies[1]);
  assertEquals(bodies[0], {
    p_action: "complete",
    p_user_id: "user",
    p_purchase_subject: null,
    p_request_id: "request",
  });
  await assertRejects(
    () =>
      createLlmQuota(
        env,
        (() =>
          Promise.resolve(
            Response.json({ error: "private details" }, { status: 500 }),
          )) as typeof fetch,
      )("reserve", { userId: "user" }, "id"),
    Error,
    "Quota unavailable",
  );
});

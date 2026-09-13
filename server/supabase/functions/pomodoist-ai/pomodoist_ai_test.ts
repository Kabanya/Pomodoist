import { assertEquals, assertMatch } from "jsr:@std/assert";
import { handlePomodoistAi } from "./pomodoist_ai.ts";
import { handlePomodoistWatch } from "../pomodoist-watch/pomodoist_watch.ts";
import type { PomodoistWatchDeps } from "../_shared/task_decomposition_http.ts";

Deno.test("AI and Watch share signed-in and StoreKit-only decomposition contracts", async () => {
  for (const signedIn of [true, false]) {
    let paidCalls = 0;
    const dependencies: PomodoistWatchDeps = {
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

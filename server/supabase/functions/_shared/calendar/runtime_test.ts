import { strict as assert } from "node:assert";
import { calendarHandler, type RuntimeDeps } from "./runtime.ts";
const deps = (): RuntimeDeps => ({
  provider: "outlook",
  workerSecret: "worker-secret",
  actions: {
    provider: "outlook",
    clientId: "id",
    configured: true,
    redirectUri: "https://api.test/outlook",
    appRedirectUri: "pomodoist://outlook-calendar-connected",
    authenticate: async () => "user",
    storeState: async () => {},
    consumeState: async () => null,
    exchange: async () => {
      throw new Error("unused");
    },
    connect: async () => {},
    sync: async () => {},
    disconnect: async () => {},
  },
  notifications: { lookup: async () => null, enqueue: async () => {} },
  googleWebhook: async () => false,
  runWorker: async () => ({ claimed: 1, succeeded: 1, failed: 0 }),
});
Deno.test("worker requests require exact nonempty secret", async () => {
  const d = deps();
  const r = await calendarHandler(
    new Request("https://api.test/outlook", {
      method: "POST",
      headers: { "X-Pomodoist-Worker-Secret": "wrong" },
    }),
    d,
  );
  assert.equal(r.status, 401);
});
Deno.test("worker endpoint executes the actual worker dependency", async () => {
  let runs = 0;
  const d = deps();
  d.runWorker = async () => {
    runs++;
    return { claimed: 1, succeeded: 1, failed: 0 };
  };
  const r = await calendarHandler(
    new Request("https://api.test/outlook", {
      method: "POST",
      headers: { "X-Pomodoist-Worker-Secret": "worker-secret" },
    }),
    d,
  );
  assert.equal(runs, 1);
  assert.equal(r.status, 200);
});
Deno.test("Graph validation routes before application authentication", async () => {
  const d = deps();
  d.actions.authenticate = async () => {
    throw new Error("must not authenticate notification");
  };
  const r = await calendarHandler(
    new Request(
      "https://api.test/outlook/notifications?validationToken=challenge",
      { method: "POST" },
    ),
    d,
  );
  assert.equal(await r.text(), "challenge");
});

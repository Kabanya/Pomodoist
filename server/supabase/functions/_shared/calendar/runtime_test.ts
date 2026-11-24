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

Deno.test("calendar OAuth returns to the F-Droid app that started it", async () => {
  for (const provider of ["google", "outlook"] as const) {
    const d = deps();
    d.provider = provider;
    d.actions.provider = provider;
    d.actions.appRedirectUri = `pomodoist://${provider}-calendar-connected`;
    const pending = new Map<string, { userId: string; verifier: string }>();
    d.actions.storeState = async (input) => {
      pending.set(String(input.stateHash), {
        userId: String(input.userId),
        verifier: String(input.verifier),
      });
    };
    d.actions.consumeState = async (key) => {
      const value = pending.get(key);
      pending.delete(key);
      return value ?? null;
    };
    d.actions.exchange = async () => ({
      accessToken: "access",
      refreshToken: "refresh",
      accountId: "account",
      accountEmail: null,
    });
    const endpoint = `https://api.test/${provider}`;
    for (const channel of ["fdroid", undefined]) {
      const start = await calendarHandler(
        new Request(endpoint, {
          method: "POST",
          body: JSON.stringify({ action: "start", channel }),
        }),
        d,
      );
      assert.equal(start.status, 200);
      const url = new URL((await start.json()).authorizationUrl);
      const state = url.searchParams.get("state");
      assert.ok(state);
      const callback = (value: string) =>
        calendarHandler(new Request(`${endpoint}?code=code&state=${value}`), d);
      assert.equal((await callback(`fdroid.${state}`)).status, 400);
      const result = await callback(state);
      assert.equal(result.status, 302);
      assert.equal(
        result.headers.get("location"),
        `${
          channel ? "pomodoist-fdroid" : "pomodoist"
        }://${provider}-calendar-connected`,
      );
      assert.equal((await callback(state)).status, 400);
    }
  }
});

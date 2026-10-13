import { strict as assert } from "node:assert";
import {
  maintainSubscription,
  type SubscriptionState,
} from "./outlook_subscriptions.ts";
const now = new Date("2026-10-11T00:00:00Z");
const state: SubscriptionState = {
  id: "sub",
  expiresAt: "2026-10-13T00:00:00Z",
  notificationUrl: "https://api.test/notifications?registration=one",
  lifecycleUrl: "https://api.test/lifecycle",
  clientState: "secret",
  resource: "me/events",
};
Deno.test("healthy subscription makes no provider request", async () => {
  let calls = 0;
  const result = await maintainSubscription(state, async () => {
    calls++;
    return {};
  }, now);
  assert.equal(calls, 0);
  assert.equal(result.replaced, false);
});
Deno.test("subscription renewal follows returned expiration", async () => {
  const calls: string[] = [];
  const result = await maintainSubscription({
    ...state,
    expiresAt: now.toISOString(),
  }, async (path, options) => {
    calls.push(`${options?.method} ${path}`);
    return { id: "sub", expirationDateTime: "2026-10-12T18:00:00Z" };
  }, now);
  assert.deepEqual(calls, ["PATCH /subscriptions/sub"]);
  assert.equal(result.state.expiresAt, "2026-10-12T18:00:00Z");
});
Deno.test("ambiguous creation recovers existing subscription before creating", async () => {
  const calls: string[] = [];
  const result = await maintainSubscription(
    { ...state, id: null },
    async (path) => {
      calls.push(path);
      return {
        value: [{
          id: "recovered",
          resource: "me/events",
          notificationUrl: state.notificationUrl,
          expirationDateTime: state.expiresAt,
        }],
      };
    },
    now,
  );
  assert.deepEqual(calls, ["/subscriptions"]);
  assert.equal(result.state.id, "recovered");
  assert.equal(result.replaced, true);
});
Deno.test("new subscriptions use basic notifications and immutable IDs via transport", async () => {
  const bodies: unknown[] = [];
  const result = await maintainSubscription(
    { ...state, id: null },
    async (_path, options) => {
      if (!options) return { value: [] };
      bodies.push(options.body);
      return { id: "new", expirationDateTime: state.expiresAt };
    },
    now,
  );
  assert.equal(
    (bodies[0] as Record<string, unknown>).includeResourceData,
    false,
  );
  assert.equal(
    (bodies[0] as Record<string, unknown>).changeType,
    "created,updated,deleted",
  );
  assert.equal(result.replaced, true);
});

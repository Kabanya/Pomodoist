import { strict as assert } from "node:assert";
import {
  handleOutlookNotifications,
  type NotificationDeps,
} from "./outlook_notifications.ts";
function deps(overrides: Partial<NotificationDeps> = {}): NotificationDeps {
  return {
    lookup: async () => ({
      connectionId: "outlook",
      generation: 1,
      clientStateHash: await hash("secret"),
      resource: "me/events",
    }),
    enqueue: async () => {},
    ...overrides,
  };
}
async function hash(s: string) {
  return Array.from(
    new Uint8Array(
      await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)),
    ),
  ).map((b) => b.toString(16).padStart(2, "0")).join("");
}
function request(value: unknown) {
  return new Request("https://api.test/notifications", {
    method: "POST",
    body: JSON.stringify(value),
  });
}
const item = {
  subscriptionId: "sub",
  clientState: "secret",
  changeType: "updated",
  resource: "Users('u')/Events('e')",
  resourceData: { id: "e", "@odata.type": "#Microsoft.Graph.Event" },
};
Deno.test("Graph validation returns decoded plain text without queue access", async () => {
  const response = await handleOutlookNotifications(
    new Request("https://api.test/notifications?validationToken=a%2Bb", {
      method: "POST",
    }),
    deps({
      lookup: () => {
        throw new Error("must not access storage");
      },
    }),
  );
  assert.equal(response.status, 200);
  assert.equal(await response.text(), "a+b");
  assert.match(response.headers.get("Content-Type")!, /text\/plain/);
});
Deno.test("valid duplicate hints coalesce within a notification batch", async () => {
  const queued: unknown[] = [];
  const response = await handleOutlookNotifications(
    request({ value: [item, item] }),
    deps({
      enqueue: async (...args) => {
        queued.push(args);
      },
    }),
  );
  assert.equal(response.status, 202);
  assert.equal(queued.length, 1);
});
Deno.test("forged clientState and unknown subscription do not enqueue", async () => {
  let calls = 0;
  await handleOutlookNotifications(
    request({ value: [{ ...item, clientState: "wrong" }] }),
    deps({
      enqueue: async () => {
        calls++;
      },
    }),
  );
  await handleOutlookNotifications(
    request({ value: [item] }),
    deps({
      lookup: async () => null,
      enqueue: async () => {
        calls++;
      },
    }),
  );
  assert.equal(calls, 0);
});
Deno.test("queue failure is retriable and is never acknowledged as success", async () => {
  const response = await handleOutlookNotifications(
    request({ value: [item] }),
    deps({
      enqueue: async () => {
        throw new Error("database unavailable");
      },
    }),
  );
  assert.equal(response.status, 503);
});
Deno.test("missed lifecycle signal queues recovery and renewal", async () => {
  const queued: unknown[][] = [];
  await handleOutlookNotifications(
    request({ value: [{ ...item, lifecycleEvent: "missed" }] }),
    deps({
      enqueue: async (...args) => {
        queued.push(args);
      },
    }),
  );
  assert.equal((queued[0][2] as Record<string, unknown>).recovery, true);
});
Deno.test("oversized batches are rejected without storage calls", async () => {
  const response = await handleOutlookNotifications(
    request({ value: Array(1001).fill(item) }),
    deps({
      lookup: () => {
        throw new Error("no access");
      },
    }),
  );
  assert.equal(response.status, 413);
});

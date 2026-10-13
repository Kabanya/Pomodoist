import { strict as assert } from "node:assert";
import { OutlookAdapter } from "./outlook_adapter.ts";
import { GraphCalendarApi, graphEventBody } from "./graph_adapter.ts";
const fields = {
  content: "Task",
  description: null,
  status: "open",
  schedule: { type: "allDay" as const, date: "2026-10-11" },
};
Deno.test("moved Outlook event is unsupported rather than deleted", async () => {
  const graph = new GraphCalendarApi(
    "token",
    async (url) =>
      Response.json(
        String(url).endsWith("/calendar") ? { id: "foreign" } : {
          ...graphEventBody("task", 1, fields),
          id: "event",
          lastModifiedDateTime: "2026-10-11T00:00:00Z",
        },
      ),
  );
  const adapter = new OutlookAdapter(graph, "connection", "calendar");
  assert.equal((await adapter.lookup("event", fields))?.state, "unsupported");
});
Deno.test("foreign mailbox hints never initiate a full calendar read", async () => {
  const graph = new GraphCalendarApi("token", async (url) => {
    assert.ok(!String(url).includes("/calendars/"));
    return Response.json(
      String(url).endsWith("/calendar") ? { id: "foreign" } : { id: "event" },
    );
  });
  assert.equal(
    await new OutlookAdapter(graph, "connection", "calendar").classifyHint({
      eventId: "event",
      version: null,
      kind: "updated",
    }),
    false,
  );
});
Deno.test("lifecycle reauthorization renews a healthy subscription without reading events", async () => {
  const calls: string[] = [];
  const graph = new GraphCalendarApi("token", async (url, init) => {
    calls.push(`${init?.method} ${new URL(String(url)).pathname}`);
    return Response.json({
      id: "subscription",
      expirationDateTime: "2030-01-03T00:00:00Z",
    });
  });
  const adapter = new OutlookAdapter(graph, "connection", "calendar");
  await adapter.maintain({
    subscriptionId: "subscription",
    subscriptionExpiresAt: "2030-01-02T00:00:00Z",
    clientState: "secret",
    notificationUrl: "https://example.test/notifications",
    lifecycleUrl: "https://example.test/lifecycle",
  }, true);
  assert.deepEqual(calls, ["PATCH /v1.0/subscriptions/subscription"]);
});
Deno.test("calendar removal during a read cannot be mistaken for event deletion", async () => {
  const graph = new GraphCalendarApi(
    "token",
    async () => new Response(null, { status: 404 }),
  );
  const adapter = new OutlookAdapter(graph, "connection", "calendar");
  await assert.rejects(() => adapter.lookup("event", fields));
});

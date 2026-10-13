import { strict as assert } from "node:assert";
import {
  GraphCalendarApi,
  GraphError,
  graphEventBody,
  graphEventFields,
} from "./graph_adapter.ts";
const fields = {
  content: "Task",
  description: "Note",
  status: "open",
  schedule: { type: "allDay" as const, date: "2026-10-11" },
};
Deno.test("Graph pagination reads all pages and consistently requests immutable IDs", async () => {
  const calls: string[] = [];
  const api = new GraphCalendarApi("access", async (url, init) => {
    calls.push(String(url));
    assert.match(new Headers(init?.headers).get("Prefer")!, /ImmutableId/);
    return Response.json(
      calls.length === 1
        ? {
          value: [{ id: "one" }],
          "@odata.nextLink":
            "https://graph.microsoft.com/v1.0/me/calendars/c/events?$skip=1",
        }
        : { value: [{ id: "two" }] },
    );
  });
  assert.deepEqual((await api.listEvents("c")).map((e) => e.id), [
    "one",
    "two",
  ]);
});
Deno.test("Graph refuses a foreign paging destination before sending credentials", async () => {
  let calls = 0;
  const api = new GraphCalendarApi("access", async () => {
    calls++;
    return Response.json({
      value: [],
      "@odata.nextLink": "https://evil.test/steal",
    });
  });
  await assert.rejects(() => api.listEvents("c"), /paging|destination/);
  assert.equal(calls, 1);
});
Deno.test("all-day event round trip retains date and exclusive next-day end", () => {
  const body = graphEventBody("task", 1, fields);
  assert.equal(
    (body.end as Record<string, unknown>).dateTime,
    "2026-10-12T00:00:00",
  );
  assert.deepEqual(graphEventFields({ ...body, id: "e" }), fields);
});
Deno.test("timed UTC event round trip and completion marker are stable", () => {
  const value = {
    ...fields,
    status: "completed",
    schedule: {
      type: "timed" as const,
      start: "2026-10-11T10:00:00.000Z",
      end: "2026-10-11T11:00:00.000Z",
      timeZone: "UTC",
    },
  };
  const body = graphEventBody("task", 2, value);
  assert.equal(body.subject, "✓ Task");
  assert.deepEqual(graphEventFields(body), value);
});
Deno.test("recurrence is rejected without interpreting it as deletion", () => {
  assert.throws(
    () =>
      graphEventFields({
        ...graphEventBody("task", 1, fields),
        recurrence: { pattern: {} },
      }),
    /Recurring/,
  );
});
Deno.test("conditional writes retain the expected version and do not follow redirects", async () => {
  const api = new GraphCalendarApi("access", async (_url, init) => {
    assert.equal(new Headers(init?.headers).get("If-Match"), "version-1");
    assert.equal(init?.redirect, "error");
    return new Response(null, { status: 412 });
  });
  await assert.rejects(
    () => api.patchEvent("c", "e", {}, "version-1"),
    (e) => e instanceof GraphError && e.status === 412,
  );
});
Deno.test("delete accepts an already absent event", async () => {
  const api = new GraphCalendarApi(
    "access",
    async () => new Response(null, { status: 404 }),
  );
  await api.deleteEvent("c", "e");
});
Deno.test("Graph throttling exposes Retry-After without leaking response bodies", async () => {
  const api = new GraphCalendarApi(
    "access",
    async () =>
      new Response("private event contents", {
        status: 429,
        headers: { "Retry-After": "45" },
      }),
  );
  await assert.rejects(
    () => api.listEvents("c"),
    (e) =>
      e instanceof GraphError && e.retrySeconds === 45 &&
      !e.message.includes("private"),
  );
});
Deno.test("creation retries use the same transaction identity", async () => {
  const bodies: Record<string, unknown>[] = [];
  const api = new GraphCalendarApi("access", async (_url, init) => {
    bodies.push(JSON.parse(String(init?.body)));
    return Response.json({ id: "same" });
  });
  await api.createEvent("c", "task", 3, fields);
  await api.createEvent("c", "task", 3, fields);
  assert.equal(bodies[0].transactionId, bodies[1].transactionId);
});

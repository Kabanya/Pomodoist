import { strict as assert } from "node:assert";
import { GoogleAdapter } from "./google_calendar_adapter.ts";
const fields = {
  content: "Task",
  description: null,
  status: "open",
  schedule: { type: "allDay" as const, date: "2026-10-11" },
};
Deno.test("Google adapter preserves linked identity and parses cancellation", async () => {
  const api = new GoogleAdapter(
    "token",
    "connection",
    "calendar",
    {},
    "https://api.test/google",
    async () =>
      Response.json({
        items: [{
          id: "e",
          status: "cancelled",
          updated: "2026-10-11T00:00:00Z",
        }],
        nextSyncToken: "next",
      }),
  );
  const events = await api.read();
  assert.equal(events[0].state, "deleted");
  assert.equal(events[0].eventId, "e");
  assert.equal(api.cursorState().syncToken, "next");
});
Deno.test("Google existing calendar access failure never creates a replacement", async () => {
  const requests: string[] = [];
  const api = new GoogleAdapter(
    "token",
    "connection",
    "calendar",
    {},
    "https://api.test/google",
    async (_url, options) => {
      requests.push(options?.method ?? "GET");
      return new Response(null, { status: 404 });
    },
  );
  await assert.rejects(() => api.ensureCalendar("calendar"));
  assert.deepEqual(requests, ["GET"]);
});
Deno.test("Google creation identity is stable across retries", async () => {
  const ids: unknown[] = [];
  const api = new GoogleAdapter(
    "token",
    "connection",
    "calendar",
    {},
    "https://api.test/google",
    async (_url, options) => {
      const body = JSON.parse(String(options?.body));
      ids.push(body.id);
      return Response.json({ ...body, etag: "v1" });
    },
  );
  const task = {
    ...fields,
    id: "task",
    revision: 1,
    incarnation: 2,
    deleted: false,
    stamps: {},
  };
  await api.create(task);
  await api.create(task);
  assert.equal(ids.length, 2);
  assert.equal(typeof ids[0], "string");
  assert.equal(ids[0], ids[1]);
  assert.match(String(ids[0]), /^[a-v0-9]{5,1024}$/);
});
Deno.test("Google quota refusal retries without requiring new authorization", async () => {
  const api = new GoogleAdapter(
    "token",
    "connection",
    "calendar",
    {},
    "https://api.test/google",
    async () =>
      Response.json({
        error: { errors: [{ reason: "userRateLimitExceeded" }] },
      }, { status: 403 }),
  );
  await assert.rejects(
    () => api.ensureCalendar("calendar"),
    (error: unknown) =>
      typeof error === "object" && error !== null && "status" in error &&
      error.status === 429,
  );
});

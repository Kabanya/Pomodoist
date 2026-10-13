import { strict as assert } from "node:assert";
import { decodeConnection, RpcCalendarStore } from "./store.ts";
import { emptyWork } from "./work.ts";
Deno.test("connection mapping retains Google identity and permits another provider", () => {
  const google = decodeConnection({
    id: "g",
    userId: "u",
    provider: "google",
    generation: 1,
    lease: "l",
    calendarId: "old-calendar",
    tasks: [],
    links: [],
    work: emptyWork(),
    state: {},
  });
  const outlook = decodeConnection({ ...google, id: "o", provider: "outlook" });
  assert.equal(google.calendarId, "old-calendar");
  assert.notEqual(google.id, outlook.id);
});
Deno.test("guarded store effects carry user connection generation lease and revision", async () => {
  const calls: unknown[][] = [];
  const store = new RpcCalendarStore(async (...args) => {
    calls.push(args);
    return { accepted: false };
  });
  const connection = decodeConnection({
    id: "g",
    userId: "u",
    provider: "google",
    generation: 5,
    lease: "l",
    tasks: [],
    links: [],
    work: emptyWork(),
    state: {},
  });
  const accepted = await store.prepareEffect(
    connection,
    {
      id: "t",
      content: "T",
      description: null,
      status: "open",
      schedule: null,
      deleted: false,
      revision: 9,
      incarnation: 2,
      stamps: {},
    },
    "delete",
    "e",
  );
  assert.equal(accepted, false);
  assert.equal(calls[0][0], "prepare_effect");
  assert.equal(calls[0][1], "u");
  assert.deepEqual((calls[0][3] as Record<string, unknown>).guard, {
    connectionId: "g",
    generation: 5,
    lease: "l",
  });
  assert.equal((calls[0][3] as Record<string, unknown>).revision, 9);
});
Deno.test("task projection maps all-day schedule and source clocks", () => {
  const c = decodeConnection({
    id: "g",
    userId: "u",
    provider: "google",
    tasks: [{
      id: "t",
      content: "Task",
      description: null,
      status: "open",
      dueJson: '{"type":"allDay","date":"2026-10-11"}',
      _revision: 4,
      _clientUpdatedAt: "2026-10-11T00:00:00Z",
      _metadata: {},
    }],
    links: [],
  });
  assert.deepEqual(c.tasks[0].schedule, { type: "allDay", date: "2026-10-11" });
  assert.equal(c.tasks[0].revision, 4);
  assert.equal(c.tasks[0].stamps.content?.source, "pomodoist");
});

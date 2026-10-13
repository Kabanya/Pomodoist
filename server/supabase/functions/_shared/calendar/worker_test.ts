import { strict as assert } from "node:assert";
import {
  type CalendarAdapter,
  type CalendarStore,
  type ConnectionSnapshot,
  processConnection,
  type StoredTask,
} from "./worker.ts";
import { emptyWork } from "./work.ts";
const fields = {
  content: "Task",
  description: null,
  status: "open",
  schedule: { type: "allDay" as const, date: "2026-10-11" },
};
const task: StoredTask = {
  ...fields,
  id: "task",
  deleted: false,
  revision: 1,
  incarnation: 1,
  stamps: {},
};
function fixture(work = { ...emptyWork(), refresh: true }) {
  const calls: string[] = [];
  const snapshot: ConnectionSnapshot = {
    id: "connection",
    userId: "user",
    provider: "outlook",
    generation: 1,
    lease: "lease",
    calendarId: "calendar",
    tasks: [task],
    links: [],
    work,
    state: {},
  };
  const store: CalendarStore = {
    snapshot: async () => snapshot,
    accept: async (_connection, input) => input.task,
    saveLink: async () => {
      calls.push("saveLink");
    },
    removeLink: async () => {},
    prepareEffect: async () => true,
    complete: async () => {
      calls.push("complete");
    },
    checkpoint: async () => {},
    fail: async () => {},
  };
  const adapter: CalendarAdapter = {
    ensureCalendar: async () => "calendar",
    maintain: async () => ({ state: {}, replaced: false }),
    read: async () => {
      calls.push("read");
      return [];
    },
    lookup: async () => null,
    classifyHint: async () => false,
    create: async () => {
      calls.push("create");
      return { eventId: "event", version: "v1", fields };
    },
    patch: async () => {
      calls.push("patch");
      return { eventId: "event", version: "v2", fields };
    },
    delete: async () => {
      calls.push("delete");
    },
  };
  return { calls, snapshot, store, adapter };
}
Deno.test("worker creates a scheduled event and saves its accepted baseline", async () => {
  const f = fixture();
  await processConnection(f.snapshot, f.store, f.adapter);
  assert.deepEqual(f.calls, ["read", "create", "saveLink", "complete"]);
});
Deno.test("maintenance-only pass does not read or publish events", async () => {
  const f = fixture({ ...emptyWork(), maintenance: true });
  await processConnection(f.snapshot, f.store, f.adapter);
  assert.deepEqual(f.calls, ["complete"]);
});
Deno.test("foreign-only notification pass does not read the calendar", async () => {
  const f = fixture({
    ...emptyWork(),
    hints: [{
      eventId: "foreign",
      version: null,
      kind: "updated",
      generation: 1,
    }],
  });
  await processConnection(f.snapshot, f.store, f.adapter);
  assert.deepEqual(f.calls, ["complete"]);
});
Deno.test("stale prepared effect cannot issue a provider write", async () => {
  const f = fixture();
  f.store.prepareEffect = async () => false;
  await processConnection(f.snapshot, f.store, f.adapter);
  assert.equal(f.calls.includes("create"), false);
});
Deno.test("unmodified linked event generates no provider writes", async () => {
  const f = fixture();
  f.snapshot.links = [{
    taskId: "task",
    connectionId: "connection",
    provider: "outlook",
    eventId: "event",
    incarnation: 1,
    version: "v1",
    baseline: fields,
  }];
  f.adapter.read = async () => [{
    connectionId: "connection",
    eventId: "event",
    version: "v1",
    modifiedAt: "2026-10-11T00:00:00Z",
    state: "active",
    fields,
  }];
  await processConnection(f.snapshot, f.store, f.adapter);
  assert.ok(!f.calls.some((c) => ["create", "patch", "delete"].includes(c)));
});
Deno.test("deletion uses the observed event version to reject intervening edits", async () => {
  const f = fixture();
  f.snapshot.tasks = [{ ...task, deleted: true }];
  f.snapshot.links = [{
    taskId: "task",
    connectionId: "connection",
    provider: "outlook",
    eventId: "event",
    incarnation: 1,
    version: "v1",
    baseline: fields,
  }];
  f.adapter.read = async () => [{
    connectionId: "connection",
    eventId: "event",
    version: "v2",
    modifiedAt: "2026-10-11T00:00:00Z",
    state: "active",
    fields,
  }];
  let observed: string | null | undefined;
  f.adapter.delete = async (_id, version) => {
    observed = version;
  };
  await processConnection(f.snapshot, f.store, f.adapter);
  assert.equal(observed, "v2");
});
Deno.test("pending PATCH acknowledgement cannot overwrite a newer local edit after a crash", async () => {
  const f = fixture();
  f.snapshot.tasks = [{
    ...task,
    content: "New local title",
    revision: 3,
    stamps: {
      content: {
        source: "pomodoist",
        modifiedAt: "2026-10-11T10:00:00Z",
        changeId: "3",
      },
    },
  }];
  f.snapshot.links = [{
    taskId: "task",
    connectionId: "connection",
    provider: "outlook",
    eventId: "event",
    incarnation: 1,
    version: "v1",
    baseline: fields,
  }];
  f.snapshot.pendingEffects = [{
    taskId: "task",
    revision: 2,
    incarnation: 1,
    kind: "patch",
    eventId: "event",
    fields: { ...fields, content: "Previous local title" },
  }];
  f.adapter.read = async () => [{
    connectionId: "connection",
    eventId: "event",
    version: "v2",
    modifiedAt: "2026-10-11T10:01:00Z",
    state: "active",
    fields: { ...fields, content: "Previous local title" },
  }];
  let desired: string | undefined;
  f.store.accept = async (_c, input, result) => result.task;
  f.adapter.patch = async (_id, _version, t) => {
    desired = t.content;
    return {
      eventId: "event",
      version: "v3",
      fields: { ...fields, content: t.content },
    };
  };
  await processConnection(f.snapshot, f.store, f.adapter);
  assert.equal(desired, "New local title");
});
Deno.test("pending CREATE from a prior scheduled incarnation is recovered and deleted", async () => {
  const f = fixture();
  f.snapshot.tasks = [{ ...task, incarnation: 2, revision: 3 }];
  f.snapshot.pendingEffects = [{
    taskId: "task",
    revision: 1,
    incarnation: 1,
    kind: "create",
    fields,
  }];
  f.adapter.read = async () => [{
    connectionId: "connection",
    eventId: "old-event",
    version: "v1",
    modifiedAt: "2026-10-11T10:01:00Z",
    state: "active",
    fields,
    taskId: "task",
    incarnation: 1,
  }];
  f.store.accept = async (_c, _input, result) => result.task;
  await processConnection(f.snapshot, f.store, f.adapter);
  assert.deepEqual(f.calls, ["delete", "create", "saveLink", "complete"]);
});
Deno.test("linked deletion hint cannot be suppressed by an unchanged etag", async () => {
  const f = fixture({
    ...emptyWork(),
    hints: [{
      eventId: "event",
      version: "v1",
      kind: "deleted",
      generation: 1,
    }],
  });
  f.snapshot.links = [{
    taskId: "task",
    connectionId: "connection",
    provider: "outlook",
    eventId: "event",
    incarnation: 1,
    version: "v1",
    baseline: fields,
  }];
  f.adapter.read = async () => {
    f.calls.push("read");
    return [{
      connectionId: "connection",
      eventId: "event",
      version: "v1",
      modifiedAt: "2026-10-11T10:01:00Z",
      state: "deleted",
      fields,
    }];
  };
  let cleared = false;
  f.store.accept = async (_c, _input, result) => {
    cleared = result.task.schedule === null;
    return result.task;
  };
  await processConnection(f.snapshot, f.store, f.adapter);
  assert.equal(cleared, true);
  assert.deepEqual(f.calls, ["read", "complete"]);
});

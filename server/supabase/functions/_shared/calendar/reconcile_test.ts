import { strict as assert } from "node:assert";
import {
  type EventSnapshot,
  type LinkSnapshot,
  reconcile,
  type TaskSnapshot,
} from "./reconcile.ts";

const old = "2026-10-01T10:00:00.000Z";
const newer = "2026-10-01T11:00:00.000Z";
const schedule = {
  type: "timed" as const,
  start: "2026-10-02T10:00:00.000Z",
  end: "2026-10-02T11:00:00.000Z",
  timeZone: "UTC",
};
function task(): TaskSnapshot {
  return {
    id: "task-1",
    content: "Write proposal",
    description: "Details",
    status: "open",
    schedule,
    deleted: false,
    revision: 1,
    incarnation: 1,
    stamps: {},
  };
}
function link(provider: "google" | "outlook"): LinkSnapshot {
  return {
    taskId: "task-1",
    connectionId: provider,
    provider,
    eventId: `${provider}-event`,
    incarnation: 1,
    version: "v1",
    baseline: {
      content: "Write proposal",
      description: "Details",
      status: "open",
      schedule,
    },
  };
}
function event(provider: "google" | "outlook", changes = {}): EventSnapshot {
  return {
    connectionId: provider,
    eventId: `${provider}-event`,
    version: "v2",
    modifiedAt: newer,
    state: "active",
    fields: { ...link(provider).baseline },
    ...changes,
  };
}
Deno.test("remote deletion clears schedule but preserves task and deletes counterpart", () => {
  const result = reconcile({
    task: task(),
    links: [link("google"), link("outlook")],
    remote: [event("google", { state: "deleted" })],
  });
  assert.equal(result.task.deleted, false);
  assert.equal(result.task.content, "Write proposal");
  assert.equal(result.task.schedule, null);
  assert.deepEqual(result.effects.map((e) => [e.connectionId, e.kind]), [[
    "outlook",
    "delete",
  ]]);
  assert.equal(result.task.clearedIncarnation, 1);
});
Deno.test("independent remote fields merge without republishing the unchanged source", () => {
  const result = reconcile({
    task: task(),
    links: [link("google"), link("outlook")],
    remote: [
      event("google", {
        fields: { ...link("google").baseline, content: "New title" },
      }),
      event("outlook", {
        fields: { ...link("outlook").baseline, description: "New details" },
      }),
    ],
  });
  assert.equal(result.task.content, "New title");
  assert.equal(result.task.description, "New details");
  assert.equal(result.effects.length, 2);
});
Deno.test("equal-time conflicts converge regardless of provider delivery order", () => {
  const events = [
    event("google", {
      fields: { ...link("google").baseline, content: "Google title" },
    }),
    event("outlook", {
      fields: { ...link("outlook").baseline, content: "Outlook title" },
    }),
  ];
  for (const remote of [events, [...events].reverse()]) {
    const result = reconcile({
      task: task(),
      links: [link("google"), link("outlook")],
      remote,
    });
    assert.equal(result.task.content, "Google title");
  }
});
Deno.test("a recorded outgoing echo performs no additional write or task revision", () => {
  const t = task();
  const result = reconcile({
    task: t,
    links: [link("google"), link("outlook")],
    remote: [event("outlook")],
  });
  assert.equal(result.task.revision, t.revision);
  assert.deepEqual(result.effects, []);
});
Deno.test("late remote edit cannot restore cleared schedule", () => {
  const t = { ...task(), schedule: null, clearedIncarnation: 1 };
  const result = reconcile({
    task: t,
    links: [link("google"), link("outlook")],
    remote: [
      event("outlook", {
        fields: {
          ...link("outlook").baseline,
          schedule: {
            ...schedule,
            start: "2026-10-02T12:00:00.000Z",
            end: "2026-10-02T13:00:00.000Z",
          },
        },
      }),
    ],
  });
  assert.equal(result.task.schedule, null);
  assert.ok(result.effects.every((e) => e.kind === "delete"));
});
Deno.test("old incarnation deletion cannot clear deliberately rescheduled task", () => {
  const t = { ...task(), incarnation: 2, clearedIncarnation: 1 };
  const result = reconcile({
    task: t,
    links: [link("google")],
    remote: [event("google", { state: "deleted" })],
  });
  assert.deepEqual(result.task.schedule, schedule);
});
Deno.test("unsupported recurrence and unknown events never alter the task", () => {
  const result = reconcile({
    task: task(),
    links: [link("google")],
    remote: [
      event("google", { state: "unsupported" }),
      event("outlook", { eventId: "foreign" }),
    ],
  });
  assert.deepEqual(result.task, task());
  assert.deepEqual(result.effects, []);
});
Deno.test("local edit beats an older remote change", () => {
  const t = {
    ...task(),
    content: "Local title",
    stamps: {
      content: {
        modifiedAt: newer,
        source: "pomodoist" as const,
        changeId: "local-2",
      },
    },
  };
  const result = reconcile({
    task: t,
    links: [link("google")],
    remote: [
      event("google", {
        modifiedAt: old,
        fields: { ...link("google").baseline, content: "Old remote title" },
      }),
    ],
  });
  assert.equal(result.task.content, "Local title");
  assert.equal(result.effects[0].kind, "patch");
});
Deno.test("unsupported linked event warns until it becomes supported again", () => {
  const blocked = reconcile({
    task: task(),
    links: [link("outlook")],
    remote: [event("outlook", { state: "unsupported" })],
  });
  assert.equal(blocked.links[0].unsupportedReason, "unsupported_event");
  const restored = reconcile({
    task: blocked.task,
    links: blocked.links,
    remote: [event("outlook")],
  });
  assert.equal(restored.links[0].unsupportedReason, null);
});
Deno.test("sequential equal-time provider conflicts converge in either order", () => {
  for (const order of [["google", "outlook"], ["outlook", "google"]] as const) {
    let current = task();
    for (const provider of order) {
      const result = reconcile({
        task: current,
        links: [link(provider)],
        remote: [
          event(provider, {
            fields: { ...link(provider).baseline, content: provider },
          }),
        ],
      });
      current = result.task;
    }
    assert.equal(current.content, "google");
  }
});
Deno.test("genuine same-value remote edits advance the winning stamp in either delivery order", () => {
  for (const order of [["outlook", "google"], ["google", "outlook"]] as const) {
    let current = {
      ...task(),
      content: "X",
      stamps: {
        content: {
          source: "pomodoist" as const,
          modifiedAt: "2026-10-01T10:01:00Z",
          changeId: "local",
        },
      },
    };
    for (const provider of order) {
      current = reconcile({
        task: current,
        links: [link(provider)],
        remote: [
          event(provider, {
            modifiedAt: provider === "outlook"
              ? "2026-10-01T10:03:00Z"
              : "2026-10-01T10:02:00Z",
            fields: {
              ...link(provider).baseline,
              content: provider === "outlook" ? "X" : "Y",
            },
          }),
        ],
      }).task as typeof current;
    }
    assert.equal(current.content, "X");
    assert.equal(current.stamps.content.source, "outlook");
  }
});

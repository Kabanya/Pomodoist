import { assertEquals } from "jsr:@std/assert";

import {
  applyOptimisticCommand,
  localeFor,
  remainingSeconds,
  taskPatch,
  telegramEntityId,
  textFor,
} from "./core.js";

Deno.test("all requested Telegram locales resolve with English fallback", () => {
  assertEquals(
    ["ar", "de", "en", "es", "fr", "ru", "zh"].map((locale) =>
      textFor(locale).inbox
    ).every(Boolean),
    true,
  );
  assertEquals(localeFor("ru-RU"), "ru");
  assertEquals(localeFor("zh-Hans"), "zh");
  assertEquals(localeFor("ja-JP"), "en");
  assertEquals(textFor("ar").direction, "rtl");
});

Deno.test("timer restores from server timestamps and freezes while paused", () => {
  const running = {
    interval: {
      status: "running",
      startedAt: "2026-08-03T12:00:00.000Z",
      pausedAt: null,
      pausedTotalSeconds: 60,
      plannedSeconds: 1500,
    },
  };
  const paused = {
    interval: {
      ...running.interval,
      status: "paused",
      pausedAt: "2026-08-03T12:05:00.000Z",
      pausedTotalSeconds: 0,
    },
  };

  assertEquals(
    remainingSeconds(running, Date.parse("2026-08-03T12:10:00.000Z")),
    960,
  );
  assertEquals(
    remainingSeconds(paused, Date.parse("2026-08-03T12:20:00.000Z")),
    1200,
  );
});

Deno.test("standalone Focus retains no task across persistence, pause and resume", () => {
  const now = Date.parse("2026-09-08T12:00:00Z");
  const initial = { inbox: [], tasks: [], focus: null };
  const started = applyOptimisticCommand(initial, {
    type: "focus.start",
    id: "11111111-1111-4111-8111-111111111111",
  }, now);
  const restored = JSON.parse(JSON.stringify(started));
  assertEquals(restored.focus.run.taskId, null);
  assertEquals(restored.focus.interval.taskId, null);
  assertEquals(restored.tasks, []);
  assertEquals(remainingSeconds(restored.focus, now + 60000), 1440);
  const paused = applyOptimisticCommand(
    restored,
    { type: "focus.pause" },
    now + 60000,
  );
  assertEquals(remainingSeconds(paused.focus, now + 120000), 1440);
  const resumed = applyOptimisticCommand(
    paused,
    { type: "focus.resume" },
    now + 120000,
  );
  assertEquals(remainingSeconds(resumed.focus, now + 180000), 1380);
  assertEquals(
    applyOptimisticCommand(resumed, { type: "focus.stop" }).focus,
    null,
  );
});

Deno.test("Telegram commands update the interface before the server replies", () => {
  const now = Date.parse("2026-08-04T12:00:00.000Z");
  const task = { id: "task-1", content: "Ship fast" };
  const initial = {
    account: { linked: false },
    inbox: [task],
    focus: null,
  };

  const created = applyOptimisticCommand(initial, {
    type: "task.create",
    id: "command-1",
    content: "No waiting",
  }, now);
  assertEquals(created.inbox.map((item: { content: string }) => item.content), [
    "Ship fast",
    "No waiting",
  ]);
  assertEquals(
    applyOptimisticCommand(created, {
      type: "task.create",
      id: "command-1",
      content: "No waiting",
    }, now).inbox.length,
    2,
  );

  const completed = applyOptimisticCommand(created, {
    type: "task.complete",
    taskId: task.id,
  }, now);
  assertEquals(completed.inbox.length, 1);

  const restored = applyOptimisticCommand(completed, {
    type: "task.uncomplete",
    taskId: task.id,
    optimisticTask: task,
  }, now);
  assertEquals(restored.inbox.at(-1), task);

  const started = applyOptimisticCommand(restored, {
    type: "focus.start",
    id: "command-2",
    taskId: task.id,
  }, now);
  assertEquals(started.focus.interval.status, "running");
  assertEquals(remainingSeconds(started.focus, now), 1500);

  const paused = applyOptimisticCommand(started, { type: "focus.pause" }, now);
  assertEquals(paused.focus.interval.status, "paused");
  const resumed = applyOptimisticCommand(
    paused,
    { type: "focus.resume" },
    now + 5000,
  );
  assertEquals(resumed.focus.interval.status, "running");
  assertEquals(resumed.focus.interval.pausedTotalSeconds, 5);

  assertEquals(
    applyOptimisticCommand(resumed, { type: "focus.stop" }, now).focus,
    null,
  );
});

Deno.test("optimistic task ID matches the backend deterministic entity ID", () => {
  assertEquals(
    telegramEntityId("11111111-1111-4111-8111-111111111111"),
    "11111111-1111-5111-8111-111111111110",
  );
  const started = applyOptimisticCommand({ inbox: [] }, {
    type: "focus.start",
    id: "11111111-1111-4111-8111-111111111111",
    taskId: "task-1",
  });
  assertEquals(started.focus.run.id, "11111111-1111-5111-8111-111111111110");
  assertEquals(
    started.focus.interval.id,
    "11111111-1111-5111-8111-111111111113",
  );
});

Deno.test("Mini App edits, completion and deletion project into the selected view and detail", () => {
  const task = {
    id: "task-1",
    content: "Before",
    projectId: "inbox",
    status: "open",
    priority: 4,
    day: "2026-09-07",
  };
  const initial = {
    inbox: [task],
    tasks: [task],
    task,
    view: "today",
    timeZone: "UTC",
    total: 1,
    focus: null,
  };
  const now = Date.parse("2026-09-07T12:00:00Z");
  const edited = applyOptimisticCommand(initial, {
    type: "task.update",
    taskId: task.id,
    patch: {
      content: "After",
      description: "Notes",
      priority: 1,
      dueJson: '{"type":"allDay","date":"2026-09-08"}',
    },
  }, now);
  assertEquals(edited.task.content, "After");
  assertEquals(edited.task.description, "Notes");
  assertEquals(edited.task.priority, 1);
  assertEquals(edited.task.day, "2026-09-08");
  assertEquals(edited.tasks, []);
  assertEquals(edited.total, 0);
  assertEquals(initial.task.content, "Before");
  const completed = applyOptimisticCommand(initial, {
    type: "task.complete",
    taskId: task.id,
  }, now);
  assertEquals(completed.tasks, []);
  assertEquals(completed.task.status, "completed");
  const restored = applyOptimisticCommand(
    { ...completed, tasks: [completed.task], view: "completed" },
    { type: "task.uncomplete", taskId: task.id },
    now,
  );
  assertEquals(restored.tasks, []);
  assertEquals(restored.task.status, "open");
  const deleted = applyOptimisticCommand(initial, {
    type: "task.delete",
    taskId: task.id,
  }, now);
  assertEquals(deleted.task, null);
  assertEquals(deleted.tasks, []);
  assertEquals(deleted.inbox, []);
});

Deno.test("creating an Inbox task never adds it to Today or duplicates a replayed task", () => {
  const initial = { inbox: [], tasks: [], view: "today", total: 0 };
  const command = {
    type: "task.create",
    id: "11111111-1111-4111-8111-111111111111",
    content: "New",
  };
  const today = applyOptimisticCommand(initial, command);
  assertEquals(today.tasks, []);
  assertEquals(today.inbox.length, 1);
  const inbox = applyOptimisticCommand({ ...initial, view: "inbox" }, command);
  assertEquals(inbox.tasks.length, 1);
  assertEquals(applyOptimisticCommand(inbox, command).tasks.length, 1);
});

Deno.test("editing notes keeps timed recurrence intact unless the user changes the date", () => {
  const task = {
    content: "Task",
    description: null,
    priority: 4,
    day: "2026-09-07",
    dueJson:
      '{"type":"timed","start":"2026-09-07T12:00:00Z","end":"2026-09-07T13:00:00Z","recurrence":{"frequency":"daily"}}',
  };
  const fields = {
    content: "Task",
    description: "Note",
    priority: 4,
    date: "2026-09-07",
  };
  assertEquals(taskPatch(task, fields), { description: "Note" });
  assertEquals(
    taskPatch(task, { ...fields, date: "2026-09-08", description: "" }),
    { dueJson: '{"type":"allDay","date":"2026-09-08"}' },
  );
  assertEquals(taskPatch(task, { ...fields, date: "", description: "" }), {
    dueJson: null,
  });
});

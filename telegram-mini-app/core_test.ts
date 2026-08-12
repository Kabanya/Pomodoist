import { assertEquals } from "jsr:@std/assert";

import {
  applyOptimisticCommand,
  localeFor,
  remainingSeconds,
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
});

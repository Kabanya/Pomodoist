import assert from "node:assert/strict";
import { parseQuickAdd, taskCreateOps } from "./pomodoist_task_commands.ts";
import { pomodoistState } from "./pomodoist_state.ts";
import { watchTask } from "./pomodoist_snapshots.ts";

const now = new Date("2026-10-20T09:00:00Z");

Deno.test("manual estimates survive creation with a timed block and watch projection", () => {
  const operations = taskCreateOps(
    pomodoistState([]),
    { input: "Report today 10:00 60m 3p" },
    { id: "user" },
    now,
    () => "task",
  );
  const task =
    operations.find((operation) => operation.entityType === "task")!.payload;
  assert.equal(task.estimatedFocusIntervals, 3);
  assert.equal(task.isFocusEstimateManual, true);
  assert.equal(task.durationSeconds, 3600);
  assert.equal(watchTask(task).isFocusEstimateManual, true);
  assert.equal(
    watchTask({ estimatedFocusIntervals: 3 }).isFocusEstimateManual,
    false,
  );
});

Deno.test("the server parser bounds manual estimates without losing task text", () => {
  for (const token of ["0p", "1000p", "999999999999999999999999999p"]) {
    const parsed = parseQuickAdd(`Report ${token}`, now);
    assert.equal(parsed.estimatedFocusIntervals, undefined);
    assert.equal(parsed.content, `Report ${token}`);
  }
  assert.equal(parseQuickAdd("Report 1p", now).estimatedFocusIntervals, 1);
  assert.equal(parseQuickAdd("Report 999п", now).estimatedFocusIntervals, 999);
});

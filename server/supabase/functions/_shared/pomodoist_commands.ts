import {
  activeFocus,
  commandOpId,
  dateValue,
  deterministicCommandUuid,
  type JsonMap,
  mapValue,
  numberValue,
  op,
  type PomodoistOperation,
  type PomodoistState,
  requiredString,
  stringValue,
} from "./pomodoist_state.ts";
import {
  completeTaskOps,
  createParsedTaskOps,
  uncompleteTaskOps,
} from "./pomodoist_task_commands.ts";
import { focusStartOps, focusUpdateOps } from "./pomodoist_focus_commands.ts";

export function telegramCommandOps(
  state: PomodoistState,
  command: JsonMap,
  now: Date,
  uuid?: () => string,
): PomodoistOperation[] {
  const nextUuid = uuid ?? deterministicCommandUuid(command);
  const user = { id: "telegram" };
  const type = requiredString(command, "type");
  if (type === "task.create") {
    return createParsedTaskOps(
      state,
      {
        content: requiredString(command, "content").trim(),
        labels: [],
      },
      now,
      nextUuid,
      command,
    );
  }
  if (type === "task.complete") {
    return completeTaskOps(state, command, user, now, nextUuid);
  }
  if (type === "task.uncomplete") {
    return uncompleteTaskOps(state, command, user, now);
  }

  const active = activeFocus(state);
  if (type === "focus.complete") {
    const interval = active.interval;
    const startedAt = dateValue(interval?.startedAt);
    if (interval == null || startedAt == null) {
      throw new Error("Focus is not active.");
    }
    const pausedAt = interval.status === "paused"
      ? dateValue(interval.pausedAt)
      : null;
    const effectiveNow = pausedAt ?? now;
    const elapsed = Math.max(
      0,
      Math.floor((effectiveNow.getTime() - startedAt.getTime()) / 1000) -
        (numberValue(interval.pausedTotalSeconds) ?? 0),
    );
    if (elapsed < (numberValue(interval.plannedSeconds) ?? 25 * 60)) {
      throw new Error("Focus interval has not elapsed.");
    }
  }
  let operations: PomodoistOperation[];
  if (type === "focus.start") {
    operations = focusStartOps(
      state,
      { ...command, type: "focus.startDefault" },
      user,
      now,
      nextUuid,
      1,
    );
    const workInterval = operations.find((item) =>
      item.entityType === "focus_interval"
    );
    if (workInterval != null) workInterval.payload.plannedSeconds = 25 * 60;
  } else {
    operations = focusUpdateOps(state, command, user, now, nextUuid);
  }

  const run = type === "focus.start"
    ? mapValue(
      operations.find((item) => item.entityType === "focus_run")?.payload,
    )
    : active.run;
  const interval = type === "focus.start"
    ? mapValue(
      operations.find((item) => item.entityType === "focus_interval")?.payload,
    )
    : active.interval;
  if (run == null || interval == null) return operations;
  const eventTypes = type === "focus.start"
    ? ["runStarted", "intervalStarted"]
    : [
      type === "focus.pause"
        ? "intervalPaused"
        : type === "focus.resume"
        ? "intervalResumed"
        : type === "focus.complete"
        ? "intervalCompleted"
        : "runStopped",
    ];
  for (const eventType of eventTypes) {
    const eventId = nextUuid();
    operations.push(op(
      `${commandOpId(command, eventId)}:event:${eventType}`,
      "focus_event",
      eventId,
      {
        id: eventId,
        runId: run.id,
        intervalId: interval.id,
        type: eventType,
        occurredAt: now.toISOString(),
        payloadJson: eventType === "runStarted"
          ? JSON.stringify({
            taskId: run.taskId ?? null,
            projectId: run.projectId ?? null,
          })
          : eventType === "intervalStarted"
          ? JSON.stringify({ type: interval.type })
          : null,
        createdAt: now.toISOString(),
        commandType: `focus.event.${eventType}`,
      },
      now,
    ));
  }
  if (type === "focus.complete") {
    const runCompleted = operations.some((item) =>
      item.entityType === "focus_run" && item.payload.status === "completed"
    );
    if (runCompleted) {
      const eventId = nextUuid();
      operations.push(op(
        `${commandOpId(command, eventId)}:event:runCompleted`,
        "focus_event",
        eventId,
        {
          id: eventId,
          runId: run.id,
          intervalId: interval.id,
          type: "runCompleted",
          occurredAt: now.toISOString(),
          payloadJson: null,
          createdAt: now.toISOString(),
          commandType: "focus.event.runCompleted",
        },
        now,
      ));
    }
    const taskId = stringValue(interval.taskId);
    const task = taskId == null ? null : state.tasks.get(taskId);
    if (taskId != null && task != null && interval.type === "work") {
      operations.push(op(
        `${commandOpId(command, taskId)}:task-focus`,
        "task",
        taskId,
        {
          ...task,
          completedFocusIntervals:
            (numberValue(task.completedFocusIntervals) ?? 0) + 1,
          totalFocusSeconds: (numberValue(task.totalFocusSeconds) ?? 0) +
            (numberValue(interval.plannedSeconds) ?? 0),
          updatedAt: now.toISOString(),
          commandType: "task.focus.complete",
        },
        now,
      ));
    }
  }
  return operations;
}

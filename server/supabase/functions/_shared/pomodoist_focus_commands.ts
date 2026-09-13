import {
  activeFocus,
  commandOpId,
  dateValue,
  inboxProjectId,
  type JsonMap,
  localUserId,
  numberValue,
  op,
  type PomodoistOperation,
  type PomodoistState,
  requiredString,
  selectedPreset,
  stringValue,
  type User,
} from "./pomodoist_state.ts";

export function focusStartOps(
  state: PomodoistState,
  command: JsonMap,
  _user: User,
  now: Date,
  uuid: () => string,
  forcedTargetWorkIntervals?: number,
): PomodoistOperation[] {
  const active = activeFocus(state);
  if (active.run != null && command.replaceActive !== true) {
    throw new Error("Focus already active.");
  }
  const taskId = stringValue(command.taskId);
  const task = taskId == null ? undefined : state.tasks.get(taskId);
  if (taskId != null && task == null) {
    throw new Error("Task not found.");
  }
  if (task?.status === "completed" || task?.isDeleted === true) {
    throw new Error("Completed tasks must be restored before Focus starts.");
  }
  const preset = selectedPreset(state, stringValue(command.presetId));
  const projectId = task == null
    ? undefined
    : stringValue(task.projectId) ?? inboxProjectId;
  const targetWorkIntervals = forcedTargetWorkIntervals ?? Math.max(
    1,
    task == null
      ? numberValue(preset.intervalsBeforeLongBreak) ?? 1
      : numberValue(task.estimatedFocusIntervals) ?? 1,
  );
  const timestamp = now.toISOString();
  const runId = uuid();
  const intervalId = uuid();
  const stopOps = active.run == null ? [] : focusUpdateOps(
    state,
    {
      ...command,
      id: `${commandOpId(command, "focus-replace")}:stop`,
      type: "focus.stop",
    },
    _user,
    now,
    uuid,
  );
  return [
    ...stopOps,
    op(commandOpId(command, `focus-run:${runId}`), "focus_run", runId, {
      id: runId,
      userId: localUserId,
      taskId: taskId ?? null,
      projectId: projectId ?? null,
      presetId: preset.id,
      status: "active",
      startedAt: timestamp,
      endedAt: null,
      targetWorkIntervals,
      completedWorkIntervals: 0,
      note: null,
      createdAt: timestamp,
      updatedAt: timestamp,
      isDeleted: false,
      commandType: "focus.run.start",
    }, now),
    op(
      `${commandOpId(command, runId)}:interval`,
      "focus_interval",
      intervalId,
      {
        id: intervalId,
        runId,
        taskId: taskId ?? null,
        projectId: projectId ?? null,
        type: "work",
        status: "running",
        plannedSeconds: preset.workSeconds,
        startedAt: timestamp,
        pausedAt: null,
        pausedTotalSeconds: 0,
        completedAt: null,
        stoppedAt: null,
        sequenceNumber: 1,
        createdAt: timestamp,
        updatedAt: timestamp,
        isDeleted: false,
        commandType: "focus.interval.start",
      },
      now,
    ),
  ];
}

export function focusUpdateOps(
  state: PomodoistState,
  command: JsonMap,
  _user: User,
  now: Date,
  uuid: () => string,
): PomodoistOperation[] {
  const { run, interval } = activeFocus(state);
  if (run == null || interval == null) throw new Error("Focus is not active.");
  const type = stringValue(command.type) ?? "";
  const timestamp = now.toISOString();
  const runId = requiredString(run, "id");
  const intervalId = requiredString(interval, "id");
  const ops: PomodoistOperation[] = [];

  if (type === "focus.pause") {
    if (interval.status !== "running") {
      throw new Error("Focus interval is not running.");
    }
    ops.push(
      op(
        commandOpId(command, `pause:${intervalId}`),
        "focus_interval",
        intervalId,
        {
          ...interval,
          status: "paused",
          pausedAt: timestamp,
          updatedAt: timestamp,
          commandType: "focus.interval.pause",
        },
        now,
      ),
    );
    ops.push(op(`${commandOpId(command, intervalId)}:run`, "focus_run", runId, {
      ...run,
      status: "paused",
      updatedAt: timestamp,
      commandType: "focus.run.pause",
    }, now));
  } else if (type === "focus.resume") {
    if (interval.status !== "paused") {
      throw new Error("Focus interval is not paused.");
    }
    const pausedAt = dateValue(interval.pausedAt);
    const pausedTotal = numberValue(interval.pausedTotalSeconds) ?? 0;
    ops.push(
      op(
        commandOpId(command, `resume:${intervalId}`),
        "focus_interval",
        intervalId,
        {
          ...interval,
          status: "running",
          pausedAt: null,
          pausedTotalSeconds: pausedAt == null ? pausedTotal : pausedTotal +
            Math.max(
              0,
              Math.floor((now.getTime() - pausedAt.getTime()) / 1000),
            ),
          updatedAt: timestamp,
          commandType: "focus.interval.resume",
        },
        now,
      ),
    );
    ops.push(op(`${commandOpId(command, intervalId)}:run`, "focus_run", runId, {
      ...run,
      status: "active",
      updatedAt: timestamp,
      commandType: "focus.run.resume",
    }, now));
  } else if (type === "focus.restartInterval") {
    ops.push(
      op(
        commandOpId(command, `restart:${intervalId}`),
        "focus_interval",
        intervalId,
        {
          ...interval,
          status: "running",
          startedAt: timestamp,
          pausedAt: null,
          pausedTotalSeconds: 0,
          completedAt: null,
          stoppedAt: null,
          updatedAt: timestamp,
          commandType: "focus.interval.restart",
        },
        now,
      ),
    );
  } else if (type === "focus.complete") {
    const preset = selectedPreset(state, stringValue(run.presetId));
    const completed = (numberValue(run.completedWorkIntervals) ?? 0) +
      (interval.type === "work" ? 1 : 0);
    ops.push(
      op(
        commandOpId(command, `complete:${intervalId}`),
        "focus_interval",
        intervalId,
        {
          ...interval,
          status: "completed",
          completedAt: timestamp,
          updatedAt: timestamp,
          commandType: "focus.interval.complete",
        },
        now,
      ),
    );
    if (completed >= (numberValue(run.targetWorkIntervals) ?? 1)) {
      ops.push(
        op(`${commandOpId(command, intervalId)}:run`, "focus_run", runId, {
          ...run,
          status: "completed",
          completedWorkIntervals: completed,
          endedAt: timestamp,
          updatedAt: timestamp,
          commandType: "focus.run.complete",
        }, now),
      );
    } else {
      const nextType = interval.type === "work" ? "shortBreak" : "work";
      const nextId = uuid();
      ops.push(
        op(
          `${commandOpId(command, intervalId)}:next:${nextId}`,
          "focus_interval",
          nextId,
          {
            id: nextId,
            runId,
            taskId: interval.taskId ?? null,
            projectId: interval.projectId ?? null,
            type: nextType,
            status: "running",
            plannedSeconds: nextType === "work"
              ? preset.workSeconds
              : preset.shortBreakSeconds,
            startedAt: timestamp,
            pausedAt: null,
            pausedTotalSeconds: 0,
            completedAt: null,
            stoppedAt: null,
            sequenceNumber: (numberValue(interval.sequenceNumber) ?? 1) + 1,
            createdAt: timestamp,
            updatedAt: timestamp,
            isDeleted: false,
            commandType: "focus.interval.start",
          },
          now,
        ),
      );
      ops.push(
        op(`${commandOpId(command, intervalId)}:run`, "focus_run", runId, {
          ...run,
          status: "active",
          completedWorkIntervals: completed,
          updatedAt: timestamp,
          commandType: "focus.run.update",
        }, now),
      );
    }
  } else {
    ops.push(
      op(
        commandOpId(command, `stop:${intervalId}`),
        "focus_interval",
        intervalId,
        {
          ...interval,
          status: "stopped",
          stoppedAt: timestamp,
          updatedAt: timestamp,
          commandType: "focus.interval.stop",
        },
        now,
      ),
    );
    ops.push(op(`${commandOpId(command, intervalId)}:run`, "focus_run", runId, {
      ...run,
      status: "stopped",
      endedAt: timestamp,
      updatedAt: timestamp,
      commandType: "focus.run.stop",
    }, now));
  }
  return ops;
}

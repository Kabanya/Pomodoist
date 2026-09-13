import {
  activeFocus,
  dateOnly,
  dateValue,
  inboxProjectId,
  type JsonMap,
  orderKey,
  type PomodoistState,
  scheduleMap,
  selectedPreset,
  stringValue,
  taskCompare,
  taskDate,
} from "./pomodoist_state.ts";

export function telegramSnapshot(state: PomodoistState, now: Date) {
  const snapshot = buildSnapshot(state, now);
  const inbox = [...state.tasks.values()]
    .filter((task) =>
      task.status !== "completed" &&
      task.isDeleted !== true &&
      stringValue(task.projectId) === inboxProjectId
    )
    .sort(taskCompare)
    .slice(0, 100)
    .map(watchTask);
  return {
    generatedAt: now.toISOString(),
    inbox,
    focus: snapshot.focus.active
      ? {
        preset: snapshot.focus.preset,
        run: snapshot.focus.run!,
        interval: snapshot.focus.interval!,
      }
      : null,
  };
}

export function buildSnapshot(state: PomodoistState, now: Date) {
  const today = dateOnly(now);
  const openTasks = [...state.tasks.values()].filter((task) =>
    task.status !== "completed" && task.isDeleted !== true
  );
  const sorted = (tasks: JsonMap[]) =>
    [...tasks].sort(taskCompare).slice(0, 12).map(watchTask);
  const todayTasks = openTasks.filter((task) =>
    taskDate(task) != null && taskDate(task)! <= today
  );
  const upcoming = openTasks.filter((task) => {
    const date = taskDate(task);
    return date != null && date > today;
  });
  const inbox = openTasks.filter((task) =>
    stringValue(task.projectId) === inboxProjectId
  );
  const recentAdded = [...openTasks].sort((a, b) =>
    (dateValue(b.createdAt)?.getTime() ?? 0) -
    (dateValue(a.createdAt)?.getTime() ?? 0)
  );
  const projectCounts = new Map<string, number>();
  for (const task of openTasks) {
    const projectId = stringValue(task.projectId) ?? inboxProjectId;
    projectCounts.set(projectId, (projectCounts.get(projectId) ?? 0) + 1);
  }
  const projects = [...state.projects.values()]
    .filter((project) =>
      project.id !== inboxProjectId &&
      project.isArchived !== true &&
      project.isDeleted !== true
    )
    .sort((a, b) => `${a.orderKey ?? ""}`.localeCompare(`${b.orderKey ?? ""}`));
  const { run, interval } = activeFocus(state);
  const preset = selectedPreset(state, stringValue(run?.presetId));
  return {
    version: 1,
    generatedAt: now.toISOString(),
    focus: {
      active: run != null && interval != null,
      presetId: preset.id,
      presetName: preset.name,
      preset: watchPreset(preset),
      run: run == null ? null : {
        id: run.id,
        status: run.status,
        taskId: run.taskId ?? null,
        projectId: run.projectId ?? null,
        startedAt: run.startedAt,
        completedWorkIntervals: run.completedWorkIntervals ?? 0,
        targetWorkIntervals: run.targetWorkIntervals ?? 1,
      },
      interval: interval == null ? null : {
        id: interval.id,
        type: interval.type,
        status: interval.status,
        plannedSeconds: interval.plannedSeconds,
        startedAt: interval.startedAt,
        pausedAt: interval.pausedAt ?? null,
        pausedTotalSeconds: interval.pausedTotalSeconds ?? 0,
        sequenceNumber: interval.sequenceNumber ?? 1,
      },
    },
    tasks: {
      today: sorted(todayTasks),
      upcoming: sorted(upcoming),
      inbox: sorted(inbox),
      recentAdded: recentAdded.slice(0, 12).map(watchTask),
      byProject: Object.fromEntries(
        projects.map((project) => {
          const projectId = stringValue(project.id) ?? "";
          return [
            projectId,
            sorted(
              openTasks.filter((task) =>
                stringValue(task.projectId) === projectId
              ),
            ),
          ];
        }),
      ),
    },
    projects: projects
      .map((project) => ({
        id: project.id,
        name: project.name,
        color: project.color ?? null,
        openTaskCount: projectCounts.get(stringValue(project.id) ?? "") ?? 0,
      })),
    sync: { appliedCommandIds: [] },
  };
}

export function watchTask(task: JsonMap) {
  return {
    id: task.id,
    content: task.content,
    description: task.description ?? null,
    projectId: task.projectId ?? inboxProjectId,
    priority: task.priority ?? 4,
    completed: task.status === "completed",
    schedule: scheduleMap(stringValue(task.dueJson)),
    estimatedFocusIntervals: task.estimatedFocusIntervals ?? null,
    completedFocusIntervals: task.completedFocusIntervals ?? 0,
    createdAt: task.createdAt ?? null,
  };
}

export function watchPreset(preset: JsonMap) {
  return {
    id: preset.id,
    name: preset.name,
    workSeconds: preset.workSeconds,
    shortBreakSeconds: preset.shortBreakSeconds,
    longBreakSeconds: preset.longBreakSeconds,
    intervalsBeforeLongBreak: preset.intervalsBeforeLongBreak,
    allowPause: preset.allowPause,
    strictMode: preset.strictMode,
  };
}

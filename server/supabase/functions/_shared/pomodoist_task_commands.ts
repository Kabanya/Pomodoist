import {
  addDays,
  arrayValue,
  commandOpId,
  dateOnly,
  deterministicCommandUuid,
  inboxProjectId,
  type JsonMap,
  labelFor,
  localUserId,
  mapValue,
  op,
  orderKey,
  type ParsedQuickAdd,
  type PomodoistOperation,
  type PomodoistState,
  projectIdFor,
  requiredString,
  requiredTaskId,
  stringValue,
  type User,
} from "./pomodoist_state.ts";

export function taskCreateOps(
  state: PomodoistState,
  command: JsonMap,
  user: User,
  now: Date,
  uuid: () => string,
): PomodoistOperation[] {
  return createTaskOps(
    state,
    requiredString(command, "input"),
    user,
    now,
    uuid,
    command,
  );
}

export async function commitDraftOps(
  state: PomodoistState,
  command: JsonMap,
  user: User,
  now: Date,
  uuid: () => string,
): Promise<PomodoistOperation[]> {
  const commandId = stringValue(command.id) ?? uuid();
  const ops: PomodoistOperation[] = [];
  // Entity IDs depend on draft position, never on labels already in the snapshot.
  for (const [index, draft] of arrayValue(command.tasks).entries()) {
    const item = mapValue(draft);
    const quickAdd = stringValue(item?.quickAdd ?? item?.input);
    if (quickAdd == null || quickAdd.trim().length === 0) continue;
    const digest = new Uint8Array(
      await crypto.subtle.digest(
        "SHA-256",
        new TextEncoder().encode(`pomodoist:drafts:${commandId}:${index}`),
      ),
    );
    const hex = Array.from(
      digest.slice(0, 16),
      (byte) => byte.toString(16).padStart(2, "0"),
    ).join("");
    const nextUuid = deterministicCommandUuid({ id: hex });
    const taskOps = createTaskOps(state, quickAdd, user, now, nextUuid, {
      ...command,
      id: `${commandId}:draft:${index}`,
    }, stringValue(item?.description));
    // Preserve the legacy root receipt so accepted pre-upgrade commands cannot
    // be replayed as fresh batches. The RPC checks this before any write.
    if (ops.length === 0) taskOps[0].opId = commandId;
    ops.push(...taskOps);
    for (const operation of taskOps) {
      if (operation.entityType === "label") {
        state.labels.set(operation.entityId, operation.payload);
      }
    }
  }
  return ops;
}

export function createTaskOps(
  state: PomodoistState,
  quickAdd: string,
  _user: User,
  now: Date,
  uuid: () => string,
  command: JsonMap,
  description?: string,
): PomodoistOperation[] {
  const parsed = parseQuickAdd(quickAdd, now);
  return createParsedTaskOps(state, parsed, now, uuid, command, description);
}

export function createParsedTaskOps(
  state: PomodoistState,
  parsed: ParsedQuickAdd,
  now: Date,
  uuid: () => string,
  command: JsonMap,
  description?: string,
): PomodoistOperation[] {
  if (parsed.content.length === 0) {
    throw new Error("Task content is empty.");
  }
  const id = uuid();
  const timestamp = now.toISOString();
  const projectId = projectIdFor(state, parsed.project) ?? inboxProjectId;
  const payload: JsonMap = {
    id,
    userId: localUserId,
    content: parsed.content,
    description: description ?? null,
    projectId,
    sectionId: null,
    parentId: null,
    priority: parsed.priority ?? 4,
    dueJson: parsed.dueJson ?? null,
    deadlineJson: null,
    durationSeconds: parsed.durationSeconds ?? null,
    status: "open",
    estimatedFocusIntervals: parsed.estimatedFocusIntervals ?? null,
    completedFocusIntervals: 0,
    totalFocusSeconds: 0,
    orderKey: orderKey(now),
    dayOrder: null,
    isCollapsed: false,
    isDeleted: false,
    createdAt: timestamp,
    updatedAt: timestamp,
    completedAt: null,
    commandType: "task.create",
  };
  const ops = [
    op(commandOpId(command, `task:${id}`), "task", id, payload, now),
  ];
  const seenLabels = new Set<string>();
  for (const labelName of parsed.labels) {
    const labelKey = labelName.trim().toLowerCase();
    if (seenLabels.has(labelKey)) continue;
    seenLabels.add(labelKey);
    const label = labelFor(state, labelName);
    const labelId = stringValue(label?.id) ?? uuid();
    if (label == null) {
      const labelPayload = {
        id: labelId,
        userId: localUserId,
        name: labelName,
        color: null,
        orderKey: orderKey(now),
        isFavorite: false,
        isDeleted: false,
        createdAt: timestamp,
        updatedAt: timestamp,
        commandType: "label.create",
      };
      ops.push(
        op(
          `${commandOpId(command, id)}:label:${labelId}`,
          "label",
          labelId,
          labelPayload,
          now,
        ),
      );
    }
    ops.push(op(
      `${commandOpId(command, id)}:task_label:${labelId}`,
      "task_label",
      `${id}:${labelId}`,
      {
        taskId: id,
        labelId,
        createdAt: timestamp,
        commandType: "task.label.add",
      },
      now,
    ));
  }
  return ops;
}

export function completeTaskOps(
  state: PomodoistState,
  command: JsonMap,
  _user: User,
  now: Date,
  uuid: () => string,
): PomodoistOperation[] {
  const id = requiredTaskId(command);
  const task = state.tasks.get(id);
  if (task == null) throw new Error("Task not found.");
  if (task.status === "completed") return [];
  const timestamp = now.toISOString();
  const taskPayload = {
    ...task,
    status: "completed",
    completedAt: timestamp,
    updatedAt: timestamp,
    commandType: "task.complete",
  };
  const completionId = uuid();
  return [
    op(commandOpId(command, `complete:${id}`), "task", id, taskPayload, now),
    op(
      `${commandOpId(command, id)}:completion:${completionId}`,
      "task_completion",
      completionId,
      {
        id: completionId,
        taskId: id,
        userId: localUserId,
        completedAt: timestamp,
        snapshotJson: null,
        createdAt: timestamp,
        commandType: "task.complete",
      },
      now,
    ),
  ];
}

export function uncompleteTaskOps(
  state: PomodoistState,
  command: JsonMap,
  _user: User,
  now: Date,
): PomodoistOperation[] {
  const id = requiredTaskId(command);
  const task = state.tasks.get(id);
  if (task == null) throw new Error("Task not found.");
  if (task.status !== "completed") return [];
  return [
    op(commandOpId(command, `uncomplete:${id}`), "task", id, {
      ...task,
      status: "open",
      completedAt: null,
      updatedAt: now.toISOString(),
      commandType: "task.uncomplete",
    }, now),
  ];
}

export function parseQuickAdd(input: string, now: Date): ParsedQuickAdd {
  const today = dateOnly(now);
  const content: string[] = [];
  const labels: string[] = [];
  let project: string | undefined;
  let priority: number | undefined;
  let dueDate: string | undefined;
  let startMinute: number | undefined;
  let durationMinutes: number | undefined;
  let estimatedFocusIntervals: number | undefined;

  for (const token of input.trim().split(/\s+/).filter(Boolean)) {
    const lower = token.toLowerCase();
    if (token.startsWith("#") && token.length > 1) {
      project = token.slice(1);
    } else if (token.startsWith("@") && token.length > 1) {
      labels.push(token.slice(1));
    } else if (/^p[1-4]$/i.test(token)) {
      priority = Number(token.slice(1));
    } else if (/^\d{4}-\d{2}-\d{2}$/.test(token)) {
      dueDate = token;
    } else if (lower === "today" || lower === "сегодня") {
      dueDate = today;
    } else if (lower === "tomorrow" || lower === "завтра") {
      dueDate = addDays(today, 1);
    } else if (/^\d{1,2}:\d{2}$/.test(token)) {
      const [hour, minute] = token.split(":").map(Number);
      if (hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59) {
        startMinute = hour * 60 + minute;
      }
    } else if (/^\d+(m|min|мин|м)$/i.test(token)) {
      durationMinutes = Number(token.match(/^\d+/)?.[0]);
    } else if (/^\d+(h|ч)$/i.test(token)) {
      durationMinutes = Number(token.match(/^\d+/)?.[0]) * 60;
    } else if (/^\d+(p|п)$/i.test(token)) {
      estimatedFocusIntervals = Number(token.match(/^\d+/)?.[0]);
    } else {
      content.push(token);
    }
  }

  const dueJson = dueJsonFrom(dueDate, startMinute, durationMinutes);
  return {
    content: content.join(" ").trim(),
    project,
    labels,
    priority,
    dueJson,
    durationSeconds: durationMinutes == null ? null : durationMinutes * 60,
    estimatedFocusIntervals,
  };
}

export function dueJsonFrom(
  date: string | undefined,
  startMinute?: number,
  durationMinutes?: number,
) {
  if (startMinute == null) {
    return date == null ? null : JSON.stringify({ type: "allDay", date });
  }
  const base = date ?? dateOnly(new Date());
  const start = new Date(`${base}T00:00:00.000Z`);
  start.setUTCMinutes(startMinute);
  const end = new Date(start.getTime() + (durationMinutes ?? 30) * 60 * 1000);
  return JSON.stringify({
    type: "timed",
    start: start.toISOString(),
    end: end.toISOString(),
  });
}

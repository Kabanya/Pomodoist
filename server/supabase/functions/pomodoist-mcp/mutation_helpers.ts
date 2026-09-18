import { z } from "zod";
import { toolSuccess } from "./pomodoist_mcp.ts";
import {
  Context,
  Operation,
  RecordValue,
  RpcFailure,
  ToolFailure,
  backlogId,
  doneId,
  entityId,
  inboxId,
  localUserId,
  maximumOrder,
  nullableString,
  number,
  orderKey,
  outputSchemas,
  projectPalette,
  readRpc,
  record,
  records,
  rpc,
  schedule,
  settingsId,
  string,
  validDate,
  validId,
  validTask,
  validTimeZone,
} from "./tool_core.ts";

export type MutationPlan = { operations: Operation[]; result: RecordValue };
export type MutationDefinition = {
  name: string;
  config: { inputSchema: z.ZodType; outputSchema: z.ZodType; annotations: { openWorldHint: boolean; destructiveHint?: boolean } };
  plan: (arguments_: unknown) => Promise<MutationPlan>;
};

export type DefineMutation = <Schema extends z.ZodType>(
  name: string,
  config: { inputSchema: Schema; outputSchema: z.ZodType; annotations: { openWorldHint: boolean; destructiveHint?: boolean } },
  plan: (arguments_: z.output<Schema>) => Promise<MutationPlan>,
) => void;

export function mutationPlan(operations: Operation[], result: RecordValue): MutationPlan {
  if (!operations.length) throw new ToolFailure("conflict", "Mutation has no effect.");
  return { operations, result: { ...result, server_revision: null } };
}

export function taskAction(
  define: DefineMutation,
  name: string,
  annotations: { openWorldHint: boolean },
  context: Context,
  build: (
    snapshot: Snapshot,
    task: RecordValue,
    now: string,
  ) => Operation[],
) {
  define(
    name,
    {
      inputSchema: z.object({ task_id: entityId }).strict(),
      outputSchema: outputSchemas.mutation,
      annotations,
    },
    async ({ task_id }) => {
      const snapshot = await mutationSnapshot(context);
      const task = requireTask(snapshot, task_id);
      const now = new Date().toISOString();
      return mutationPlan( build(snapshot, task, now), { id: task.id });
    },
  );
}

export function compareProjectOrder(a: RecordValue, b: RecordValue): number {
  const left = string(a.orderKey), right = string(b.orderKey);
  if (left !== right) return left < right ? -1 : 1;
  return string(a.id) < string(b.id)
    ? -1
    : string(a.id) === string(b.id)
    ? 0
    : 1;
}

// Match Flutter's display forest when handling incomplete or cyclic legacy data.
export function projectParents(projects: RecordValue[]): Map<string, string | null> {
  const ids = new Set(projects.map((row) => string(row.id)));
  const parents = new Map(projects.map((row): [string, string | null] => {
    const parentId = nullableString(row.parentId);
    return [
      string(row.id),
      parentId !== inboxId && parentId !== null && ids.has(parentId)
        ? parentId
        : null,
    ];
  }));
  const visited = new Set<string>();
  for (const row of projects) {
    const path = new Set<string>();
    let id: string | null = string(row.id);
    while (id !== null && !visited.has(id)) {
      if (path.has(id)) {
        parents.set(id, null);
        break;
      }
      path.add(id);
      id = parents.get(id) ?? null;
    }
    for (const id of path) visited.add(id);
  }
  return parents;
}

export type Snapshot = {
  tasks: RecordValue[];
  projects: RecordValue[];
  labels: RecordValue[];
  taskLabels: RecordValue[];
  assignments: RecordValue[];
  completions: RecordValue[];
  settings: RecordValue;
};

export async function mutationSnapshot(context: Context): Promise<Snapshot> {
  const value = record(
    await readRpc(context, "mutation_snapshot", {}),
  );
  if (!value) throw new RpcFailure(500);
  const projects = records(value.projects).filter((item) => validId(item.id));
  const labels = records(value.labels).filter((item) => validId(item.id));
  if (!projects.some((item) => item.id === inboxId)) {
    projects.push({
      id: inboxId,
      userId: localUserId,
      name: "Inbox",
      color: null,
      orderKey: "a",
      isFavorite: true,
      isArchived: false,
    });
  }
  if (!labels.some((item) => item.id === backlogId)) {
    labels.push({
      id: backlogId,
      name: "Backlog",
      kind: "kanbanStatus",
      systemKey: "backlog",
      orderKey: "00000000000000000000",
    });
  }
  if (!labels.some((item) => item.id === doneId)) {
    labels.push({
      id: doneId,
      name: "Done",
      kind: "kanbanStatus",
      systemKey: "done",
      orderKey: "00004503599627370496",
    });
  }
  return {
    tasks: records(value.tasks).filter(validTask),
    projects,
    labels,
    taskLabels: records(value.taskLabels).filter((item) =>
      validId(item.entityId) && validId(item.taskId) && validId(item.labelId)
    ),
    assignments: records(value.assignments).filter((item) =>
      validId(item.taskId) && validId(item.labelId)
    ),
    completions: records(value.completions).filter((item) =>
      validId(item.id) && validId(item.taskId)
    ),
    settings: validId(record(value.settings)?.id) ? record(value.settings)! : {
      id: settingsId,
      userId: localUserId,
      selectedProjectIdsJson: '["inbox"]',
      focusStatusLabelId: backlogId,
    },
  };
}

export async function mutate(
  context: Context,
  operations: Operation[],
  result: RecordValue,
) {
  if (operations.length === 0) {
    throw new ToolFailure("conflict", "Mutation has no effect.");
  }
  const pushed = record(
    await rpc(context, "push_pomodoist_mcp_changes", {
      p_user_id: context.auth.userId,
      p_client_id: context.auth.clientId,
      p_operations: operations,
    }),
  );
  if (!pushed) throw new RpcFailure(500);
  try {
    await rpc(context, "send_pomodoist_mcp_sync_hint", {
      p_user_id: context.auth.userId,
      p_client_id: context.auth.clientId,
    });
  } catch {
    context.log({
      request_id: "",
      subject: context.auth.subject,
      client_id: context.auth.clientId,
      tool_name: "",
      outcome: "hint_failed",
      latency_ms: 0,
    });
  }
  return toolSuccess({
    ...result,
    server_revision: pushed.serverRevision ?? null,
  });
}

export function completeOperations(
  snapshot: Snapshot,
  task: RecordValue,
  now: string,
) {
  const operations: Operation[] = [];
  for (const row of descendants(snapshot.tasks, task.id)) {
    if (row.status === "completed") continue;
    const completionId = crypto.randomUUID();
    const previousStatus = currentStatus(snapshot, row.id);
    operations.push(
      upsert(
        "task",
        row.id,
        sanitizeTask({
          ...row,
          commandType: "task.complete",
          status: "completed",
          completedAt: now,
          updatedAt: now,
        }),
        now,
      ),
      upsert("task_completion", completionId, {
        schemaVersion: 1,
        id: completionId,
        taskId: row.id,
        userId: localUserId,
        completedAt: now,
        snapshotJson: JSON.stringify({
          version: 1,
          kanban: { previousStatusLabelId: previousStatus },
        }),
        createdAt: now,
      }, now),
      assignment(row.id, doneId, now),
    );
  }
  return operations;
}

export function restoreOperations(
  snapshot: Snapshot,
  task: RecordValue,
  now: string,
  explicitRootStatus?: string,
) {
  const operations: Operation[] = [];
  for (const row of descendants(snapshot.tasks, task.id)) {
    if (row.status !== "completed") continue;
    const status = row.id === task.id && explicitRootStatus
      ? explicitRootStatus
      : previousStatus(snapshot, string(row.id));
    operations.push(
      upsert(
        "task",
        row.id,
        sanitizeTask({
          ...row,
          commandType: "task.uncomplete",
          status: "open",
          completedAt: null,
          updatedAt: now,
        }),
        now,
      ),
      assignment(row.id, status, now),
    );
  }
  return operations;
}

export async function deleteTaskOperations(
  snapshot: Snapshot,
  task: RecordValue,
  scope: "selected" | "selected_and_following",
  now: string,
) {
  const parsed = parseDue(task.dueJson);
  const seriesId = recurrenceSeriesKey(parsed);
  if (!seriesId) {
    return descendants(snapshot.tasks, task.id).map((row) =>
      remove("task", row.id, {
        commandType: "task.delete",
        id: row.id,
      }, now)
    );
  }
  if (scope === "selected_and_following") {
    const selectedStart = scheduleStart(parsed!);
    const roots = snapshot.tasks.filter((row) => {
      const due = parseDue(row.dueJson);
      return due !== null &&
        recurrenceSeriesKey(due) === seriesId &&
        scheduleStart(due) >= selectedStart;
    });
    const ids = new Set<string>();
    for (const root of roots) {
      for (const row of descendants(snapshot.tasks, root.id)) {
        ids.add(string(row.id));
      }
    }
    return [...ids].map((id) =>
      remove("task", id, { commandType: "task.delete", id }, now)
    );
  }

  if (!record(record(parsed)?.recurrence)) {
    return descendants(snapshot.tasks, task.id).map((row) =>
      remove("task", row.id, {
        commandType: "task.delete",
        id: row.id,
      }, now)
    );
  }
  const next = nextSchedule(parsed!, new Date());
  const sourceRows = descendants(snapshot.tasks, task.id);
  const delta = scheduleStart(next) - scheduleStart(parsed!);
  const ids = new Map<string, string>();
  const nextRootId = await recurringId(
    seriesId,
    scheduleOccurrenceKey(next),
    string(task.id),
  );
  if (snapshot.tasks.some((row) => row.id === nextRootId)) {
    return sourceRows.map((row) =>
      remove("task", row.id, {
        commandType: "task.delete",
        id: row.id,
      }, now)
    );
  }
  for (const row of sourceRows) {
    ids.set(
      string(row.id),
      row.id === task.id ? nextRootId : await recurringId(
        seriesId,
        scheduleOccurrenceKey(next),
        string(row.id),
      ),
    );
  }
  const operations: Operation[] = [];
  for (const row of sourceRows) {
    const isRoot = row.id === task.id;
    const id = ids.get(string(row.id))!;
    const shiftedDue = isRoot
      ? next
      : shiftChildSchedule(parseDue(row.dueJson), delta);
    operations.push(
      upsert(
        "task",
        id,
        sanitizeTask({
          ...row,
          commandType: "task.create",
          id,
          parentId: isRoot
            ? row.parentId
            : ids.get(string(row.parentId)) ?? row.parentId,
          dueJson: shiftedDue ? JSON.stringify(shiftedDue) : null,
          status: "open",
          completedAt: null,
          createdAt: now,
          updatedAt: now,
        }),
        now,
      ),
      assignment(
        id,
        row.status === "completed"
          ? previousStatus(snapshot, string(row.id))
          : currentStatus(snapshot, row.id),
        now,
      ),
    );
    for (
      const relation of snapshot.taskLabels.filter((link) =>
        link.taskId === row.id
      )
    ) {
      operations.push(upsert(
        "task_label",
        `${id}:${relation.labelId}`,
        {
          schemaVersion: 1,
          commandType: "task.label.add",
          taskId: id,
          labelId: relation.labelId,
          kind: "user",
          createdAt: now,
        },
        now,
      ));
    }
  }
  operations.push(
    ...sourceRows.map((row) =>
      remove("task", row.id, {
        commandType: "task.delete",
        id: row.id,
      }, now)
    ),
  );
  return operations;
}

export function labelAdditions(
  snapshot: Snapshot,
  taskId: string,
  labelNames: string[],
  now: string,
) {
  const operations: Operation[] = [];
  const seen = new Set<string>();
  for (const rawName of labelNames) {
    const normalized = rawName.trim();
    const key = normalized.toLowerCase();
    if (!normalized || !seen.add(key)) continue;
    const existing = snapshot.labels.find((label) =>
      label.kind === "user" && string(label.name).toLowerCase() === key
    );
    const labelId = existing ? string(existing.id) : crypto.randomUUID();
    if (!existing) {
      const label = userLabel(labelId, normalized, now);
      snapshot.labels.push(label);
      operations.push(upsert("label", labelId, label, now));
    }
    if (
      !snapshot.taskLabels.some((link) =>
        link.taskId === taskId && link.labelId === labelId
      )
    ) {
      operations.push(upsert("task_label", `${taskId}:${labelId}`, {
        schemaVersion: 1,
        commandType: "task.label.add",
        taskId,
        labelId,
        kind: "user",
        createdAt: now,
      }, now));
    }
  }
  return operations;
}

export function upsert(
  entityType: string,
  entityId: unknown,
  payload: RecordValue,
  now: string,
): Operation {
  return operation(entityType, entityId, "upsert", payload, now);
}

export function remove(
  entityType: string,
  entityId: unknown,
  payload: RecordValue,
  now: string,
): Operation {
  return operation(entityType, entityId, "delete", payload, now);
}

export function operation(
  entityType: string,
  id: unknown,
  kind: "upsert" | "delete",
  payload: RecordValue,
  now: string,
): Operation {
  const entityId = string(id);
  return {
    opId: crypto.randomUUID(),
    entityType,
    entityId,
    operation: kind,
    payload,
    clientUpdatedAt: now,
  };
}

export function assignment(taskId: unknown, labelId: string, now: string) {
  const id = string(taskId);
  return upsert("task_kanban_status", id, {
    schemaVersion: 1,
    commandType: "task.kanbanStatus.set",
    taskId: id,
    labelId,
    changedAt: now,
  }, now);
}

export function settingsOperation(
  _settings: RecordValue,
  patch: RecordValue,
  now: string,
) {
  return upsert("kanban_settings", settingsId, {
    commandType: patch.selectedProjectIdsJson !== undefined
      ? "kanban.settings.projects.set"
      : "kanban.settings.focus.set",
    id: settingsId,
    ...patch,
    changedAt: now,
  }, now);
}

export function userLabel(id: string, labelName: string, now: string) {
  return {
    schemaVersion: 1,
    commandType: "label.create",
    id,
    userId: localUserId,
    name: labelName,
    color: null,
    kind: "user",
    systemKey: null,
    orderKey: orderKey(),
    isFavorite: false,
    isDeleted: false,
    createdAt: now,
    updatedAt: now,
  };
}

export function requireTask(snapshot: Snapshot, id: string) {
  const task = snapshot.tasks.find((item) => item.id === id);
  if (!task) throw new ToolFailure("not_found", "Task not found.");
  return task;
}

export function requireProject(snapshot: Snapshot, id: string) {
  const project = snapshot.projects.find((item) => item.id === id);
  if (!project) throw new ToolFailure("not_found", "Project not found.");
  return project;
}

export function requireLabel(snapshot: Snapshot, id: string, kind: string) {
  const label = snapshot.labels.find((item) =>
    item.id === id && item.kind === kind
  );
  if (!label) {
    throw new ToolFailure(
      "not_found",
      kind === "user" ? "Label not found." : "Kanban status not found.",
    );
  }
  return label;
}

export function descendants(tasks: RecordValue[], rootId: unknown) {
  const id = string(rootId);
  const root = tasks.find((task) => task.id === id);
  if (!root) return [];
  const result: RecordValue[] = [];
  const stack = [root];
  const seen = new Set<string>();
  while (stack.length) {
    const row = stack.pop()!;
    if (!seen.add(string(row.id))) continue;
    result.push(row);
    stack.push(
      ...tasks.filter((task) => task.parentId === row.id).reverse(),
    );
  }
  return result;
}

export function validateParent(
  snapshot: Snapshot,
  taskId: string,
  parentId: string | null,
  projectId: string,
) {
  if (parentId === null) return;
  if (parentId === taskId) {
    throw new ToolFailure("conflict", "A task cannot be its own parent.");
  }
  const parent = requireTask(snapshot, parentId);
  if (parent.projectId !== projectId) {
    throw new ToolFailure(
      "conflict",
      "Parent task belongs to another project.",
    );
  }
  if (descendants(snapshot.tasks, taskId).some((row) => row.id === parentId)) {
    throw new ToolFailure("conflict", "Task parent would create a cycle.");
  }
}

export function currentStatus(snapshot: Snapshot, taskId: unknown) {
  const statusId = snapshot.assignments.find((link) => link.taskId === taskId)
    ?.labelId;
  return activeNonDoneStatus(snapshot, statusId) ? string(statusId) : backlogId;
}

export function previousStatus(snapshot: Snapshot, taskId: string) {
  for (
    const completion of snapshot.completions.filter((row) =>
      row.taskId === taskId
    )
  ) {
    try {
      const value = JSON.parse(string(completion.snapshotJson));
      const status = record(record(value)?.kanban)?.previousStatusLabelId;
      if (activeNonDoneStatus(snapshot, status)) return string(status);
    } catch {
      // Ignore malformed legacy snapshots.
    }
  }
  return backlogId;
}

export function activeNonDoneStatus(snapshot: Snapshot, value: unknown) {
  return typeof value === "string" && value !== doneId &&
    snapshot.labels.some((label) =>
      label.id === value && label.kind === "kanbanStatus"
    );
}

export function kanbanStatuses(snapshot: Snapshot) {
  return snapshot.labels.filter((label) => label.kind === "kanbanStatus")
    .sort((a, b) => {
      const rank = (row: RecordValue) =>
        row.id === backlogId ? 0 : row.id === doneId ? 2 : 1;
      return rank(a) - rank(b) ||
        string(a.orderKey).localeCompare(string(b.orderKey)) ||
        string(a.id).localeCompare(string(b.id));
    });
}

export function reorderStatuses(
  statuses: RecordValue[],
  now: string,
  createdId?: string,
) {
  const step = Math.floor(maximumOrder / (statuses.length - 1));
  return statuses.flatMap((status, index) => {
    const value = index === statuses.length - 1 ? maximumOrder : step * index;
    const nextOrder = String(value).padStart(20, "0");
    if (status.orderKey === nextOrder && status.updatedAt !== now) return [];
    const created = status.id === createdId;
    return [upsert(
      "label",
      status.id,
      created
        ? {
          commandType: "kanban.status.create",
          id: status.id,
          userId: localUserId,
          name: status.name,
          color: status.color ?? null,
          kind: "kanbanStatus",
          systemKey: null,
          orderKey: nextOrder,
          isFavorite: false,
          isDeleted: false,
          createdAt: now,
          updatedAt: now,
        }
        : {
          commandType: "kanban.status.reorder",
          id: status.id,
          orderKey: nextOrder,
          changedAt: now,
        },
      now,
    )];
  });
}

export function ensureUniqueStatusName(
  snapshot: Snapshot,
  statusName: string,
  exceptId?: string,
) {
  if (
    snapshot.labels.some((label) =>
      label.kind === "kanbanStatus" &&
      label.id !== exceptId &&
      string(label.name).toLowerCase() === statusName.toLowerCase()
    )
  ) {
    throw new ToolFailure("conflict", "Kanban status name already exists.");
  }
}

export function fallbackFocusStatus(snapshot: Snapshot, excludedId: string) {
  return string(
    kanbanStatuses(snapshot).find((status) =>
      status.id !== excludedId &&
      status.id !== doneId &&
      status.id !== backlogId
    )?.id ?? backlogId,
  );
}

export function selectedProjectIds(settings: RecordValue) {
  try {
    const value = JSON.parse(string(settings.selectedProjectIdsJson));
    return Array.isArray(value)
      ? [
        ...new Set(
          value.filter((item): item is string => typeof item === "string"),
        ),
      ].sort()
      : [inboxId];
  } catch {
    return [inboxId];
  }
}

export function reorderedTask(
  snapshot: Snapshot,
  task: RecordValue,
  statusId: string,
  targetIndex: number,
  now: string,
) {
  const selected = new Set(selectedProjectIds(snapshot.settings));
  const assigned = new Map(
    snapshot.assignments.map((link) => [link.taskId, link.labelId]),
  );
  const rows = snapshot.tasks.filter((row) =>
    row.id !== task.id &&
    row.parentId == null &&
    row.status === "open" &&
    selected.has(string(row.projectId)) &&
    assigned.get(row.id) === statusId
  ).sort((a, b) =>
    string(a.orderKey).localeCompare(string(b.orderKey)) ||
    string(a.id).localeCompare(string(b.id))
  );
  const index = Math.min(targetIndex, rows.length);
  rows.splice(index, 0, task);
  const left = index === 0 ? 0 : Number(rows[index - 1].orderKey);
  const right = index === rows.length - 1
    ? maximumOrder
    : Number(rows[index + 1].orderKey);
  if (!Number.isSafeInteger(left) || !Number.isSafeInteger(right)) return null;
  const midpoint = left + Math.floor((right - left) / 2);
  if (midpoint <= left || midpoint >= right) return null;
  return {
    id: task.id,
    commandType: "task.reorder",
    orderKey: String(midpoint).padStart(20, "0"),
    changedAt: now,
  };
}

export function sanitizeTask(value: RecordValue) {
  const result = { ...value };
  delete result.deadline;
  delete result.deadlineJson;
  delete result.duration;
  delete result.durationSeconds;
  return result;
}

export function dueJson(value: z.infer<typeof schedule>) {
  const recurrenceValue = value.recurrence
    ? {
      interval: value.recurrence.interval,
      unit: value.recurrence.frequency,
      seriesId: crypto.randomUUID(),
    }
    : undefined;
  return JSON.stringify(
    value.type === "all_day"
      ? {
        type: "allDay",
        date: value.date,
        ...(recurrenceValue ? { recurrence: recurrenceValue } : {}),
      }
      : {
        type: "timed",
        start: new Date(value.start).toISOString(),
        end: new Date(value.end).toISOString(),
        timeZone: value.time_zone,
        ...(recurrenceValue ? { recurrence: recurrenceValue } : {}),
      },
  );
}

export function parseDue(value: unknown) {
  if (typeof value !== "string") return null;
  try {
    const parsed = record(JSON.parse(value));
    if (!parsed) return null;
    const recurrence = parseRecurrence(parsed.recurrence);
    const recurrenceSeriesId = recurrence
      ? null
      : cleanSeriesId(parsed.recurrenceSeriesId);
    if (parsed.type === "timed") {
      if (
        typeof parsed.start !== "string" ||
        typeof parsed.end !== "string"
      ) {
        return null;
      }
      const start = new Date(parsed.start);
      const end = new Date(parsed.end);
      if (
        !Number.isFinite(start.getTime()) ||
        !Number.isFinite(end.getTime()) ||
        end.getTime() <= start.getTime()
      ) {
        return null;
      }
      return {
        type: "timed",
        start: start.toISOString(),
        end: end.toISOString(),
        ...(typeof parsed.timeZone === "string"
          ? { timeZone: parsed.timeZone }
          : {}),
        ...(recurrence
          ? { recurrence }
          : recurrenceSeriesId
          ? { recurrenceSeriesId }
          : {}),
      };
    }
    if (typeof parsed.date !== "string" || !validDate(parsed.date)) return null;
    return {
      type: "allDay",
      date: parsed.date,
      ...(recurrence
        ? { recurrence }
        : recurrenceSeriesId
        ? { recurrenceSeriesId }
        : {}),
    };
  } catch {
    return null;
  }
}

export function parseRecurrence(value: unknown) {
  const recurrence = record(value);
  if (
    !recurrence ||
    !Number.isInteger(recurrence.interval) ||
    number(recurrence.interval) < 1 ||
    number(recurrence.interval) > 999 ||
    !["day", "week", "month"].includes(string(recurrence.unit)) ||
    typeof recurrence.seriesId !== "string" ||
    recurrence.seriesId.trim() === ""
  ) {
    return null;
  }
  return {
    interval: recurrence.interval,
    unit: recurrence.unit,
    seriesId: recurrence.seriesId,
  };
}

export function cleanSeriesId(value: unknown) {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed === "" ? null : trimmed;
}

export function recurrenceSeriesKey(value: RecordValue | null) {
  if (!value) return null;
  const recurrence = record(value.recurrence);
  return cleanSeriesId(recurrence?.seriesId) ??
    cleanSeriesId(value.recurrenceSeriesId);
}

export function scheduleStart(value: RecordValue) {
  return value.type === "allDay"
    ? Date.parse(`${value.date}T00:00:00.000Z`)
    : Date.parse(string(value.start));
}

export function scheduleOccurrenceKey(value: RecordValue) {
  return value.type === "allDay"
    ? string(value.date)
    : new Date(string(value.start)).toISOString();
}

export function nextSchedule(value: RecordValue, now: Date) {
  const repeat = record(value.recurrence)!;
  const interval = number(repeat.interval);
  const unit = string(repeat.unit);
  const start = scheduleStart(value);
  if (unit === "day" || unit === "week") {
    const period = interval * (unit === "day" ? 86400000 : 604800000);
    const steps = Math.max(1, Math.floor((now.getTime() - start) / period) + 1);
    return advanceSchedule(value, unit, interval * steps);
  }
  const startDate = new Date(start);
  const monthDelta = (now.getUTCFullYear() - startDate.getUTCFullYear()) * 12 +
    now.getUTCMonth() - startDate.getUTCMonth();
  const steps = Math.max(1, Math.floor(monthDelta / interval));
  let next = advanceSchedule(value, unit, interval * steps);
  while (scheduleStart(next) <= now.getTime()) {
    next = advanceSchedule(next, unit, interval);
  }
  return next;
}

export function advanceSchedule(
  value: RecordValue,
  unit: string,
  interval: number,
) {
  if (value.type === "allDay") {
    return { ...value, date: addDate(string(value.date), unit, interval) };
  }
  const start = new Date(string(value.start));
  const end = new Date(string(value.end));
  const duration = end.getTime() - start.getTime();
  const nextStart = addZonedInstant(
    start,
    unit,
    interval,
    validTimeZone(string(value.timeZone)) ? string(value.timeZone) : "UTC",
  );
  return {
    ...value,
    start: nextStart.toISOString(),
    end: new Date(nextStart.getTime() + duration).toISOString(),
  };
}

export function shiftChildSchedule(value: RecordValue | null, delta: number) {
  if (!value) return null;
  const next = { ...value };
  delete next.recurrence;
  delete next.recurrenceSeriesId;
  if (next.type === "allDay") {
    next.date = new Date(
      Date.parse(`${next.date}T00:00:00.000Z`) + delta,
    ).toISOString().slice(0, 10);
  } else {
    next.start = new Date(Date.parse(string(next.start)) + delta).toISOString();
    next.end = new Date(Date.parse(string(next.end)) + delta).toISOString();
  }
  return next;
}

export function addDate(value: string, unit: string, interval: number) {
  return addInstant(
    new Date(`${value}T00:00:00.000Z`),
    unit,
    interval,
  ).toISOString().slice(0, 10);
}

export function addInstant(value: Date, unit: string, interval: number) {
  const next = new Date(value);
  if (unit === "day") next.setUTCDate(next.getUTCDate() + interval);
  else if (unit === "week") next.setUTCDate(next.getUTCDate() + 7 * interval);
  else {
    const day = next.getUTCDate();
    next.setUTCDate(1);
    next.setUTCMonth(next.getUTCMonth() + interval);
    const last = new Date(Date.UTC(
      next.getUTCFullYear(),
      next.getUTCMonth() + 1,
      0,
    )).getUTCDate();
    next.setUTCDate(Math.min(day, last));
  }
  return next;
}

export function addZonedInstant(
  value: Date,
  unit: string,
  interval: number,
  zone: string,
) {
  const local = zonedParts(value, zone);
  const localClock = addInstant(
    new Date(Date.UTC(
      local.year,
      local.month - 1,
      local.day,
      local.hour,
      local.minute,
      local.second,
      value.getUTCMilliseconds(),
    )),
    unit,
    interval,
  );
  return instantForZonedParts({
    year: localClock.getUTCFullYear(),
    month: localClock.getUTCMonth() + 1,
    day: localClock.getUTCDate(),
    hour: localClock.getUTCHours(),
    minute: localClock.getUTCMinutes(),
    second: localClock.getUTCSeconds(),
    millisecond: localClock.getUTCMilliseconds(),
  }, zone);
}

export function zonedParts(value: Date, zone: string) {
  const parts = new Intl.DateTimeFormat("en-CA-u-ca-gregory-nu-latn", {
    timeZone: zone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23",
  }).formatToParts(value);
  const result = Object.fromEntries(
    parts.filter((part) => part.type !== "literal")
      .map((part) => [part.type, Number(part.value)]),
  );
  return {
    year: result.year,
    month: result.month,
    day: result.day,
    hour: result.hour,
    minute: result.minute,
    second: result.second,
  };
}

export function instantForZonedParts(
  desired: ReturnType<typeof zonedParts> & { millisecond: number },
  zone: string,
) {
  const desiredClock = Date.UTC(
    desired.year,
    desired.month - 1,
    desired.day,
    desired.hour,
    desired.minute,
    desired.second,
    desired.millisecond,
  );
  let guess = desiredClock;
  for (let attempt = 0; attempt < 4; attempt++) {
    const actual = zonedParts(new Date(guess), zone);
    const actualClock = Date.UTC(
      actual.year,
      actual.month - 1,
      actual.day,
      actual.hour,
      actual.minute,
      actual.second,
      desired.millisecond,
    );
    const correction = desiredClock - actualClock;
    if (correction === 0) return new Date(guess);
    guess += correction;
  }
  return new Date(guess);
}

export async function recurringId(
  seriesId: string,
  occurrenceKey: string,
  sourceId: string,
) {
  const digest = await crypto.subtle.digest(
    "SHA-1",
    new TextEncoder().encode(`${seriesId}|${occurrenceKey}|${sourceId}`),
  );
  return `rec-${
    [...new Uint8Array(digest)].map((byte) =>
      byte.toString(16).padStart(2, "0")
    ).join("")
  }`;
}

export function nextProjectColor(projects: RecordValue[]) {
  const counts = new Map(projectPalette.map((value) => [value, 0]));
  for (const project of projects) {
    if (project.id === inboxId) continue;
    const stored = typeof project.color === "string" &&
        projectPalette.includes(project.color as typeof projectPalette[number])
      ? project.color
      : projectPalette[stableHash(string(project.id)) % projectPalette.length];
    counts.set(
      stored as typeof projectPalette[number],
      (counts.get(stored as typeof projectPalette[number]) ?? 0) + 1,
    );
  }
  return projectPalette.reduce((best, value) =>
    (counts.get(value) ?? 0) < (counts.get(best) ?? 0) ? value : best
  );
}

export function stableHash(value: string) {
  let hash = 0x811c9dc5;
  for (const code of new TextEncoder().encode(value)) {
    hash = Math.imul(hash ^ code, 0x01000193) & 0x7fffffff;
  }
  return hash;
}

export type MutationScope = {
  define: DefineMutation;
  context: Context;
  annotations: {
    closed: { openWorldHint: boolean };
    destructive: { openWorldHint: boolean; destructiveHint: boolean };
  };
};

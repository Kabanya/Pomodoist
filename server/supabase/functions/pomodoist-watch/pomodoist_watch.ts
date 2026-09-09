import {
  type AppleStoreTransaction,
  verifyAppleStoreTransactionJws,
} from "../_shared/apple_app_transaction.ts";
import {
  pomodoistAppleVerificationOptions,
  pomodoistPurchaseState,
} from "../_shared/pomodoist_storekit.ts";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const appId = "pomodoist";
const localUserId = "local-user";
const inboxProjectId = "inbox";
const defaultPreset = {
  id: "classic",
  name: "Pomodoro",
  workSeconds: 25 * 60,
  shortBreakSeconds: 5 * 60,
  longBreakSeconds: 15 * 60,
  intervalsBeforeLongBreak: 4,
  allowPause: true,
  strictMode: false,
  isDefault: true,
};

type User = { id: string; email?: string };
type RpcResult = { data: unknown; error: { message: string } | null };
type SupabaseClient = {
  auth: {
    getUser: () => Promise<{
      data: { user: User | null };
      error?: { message: string } | null;
    }>;
  };
  rpc: (
    functionName: string,
    args: Record<string, unknown>,
  ) => PromiseLike<RpcResult>;
};

export type PomodoistWatchDeps = {
  env: Pick<typeof Deno.env, "get">;
  fetch: typeof fetch;
  createClient: (authorization: string) => SupabaseClient;
  now?: () => Date;
  uuid?: () => string;
  verifyStoreTransaction?: (
    jws: string,
    options: typeof pomodoistAppleVerificationOptions,
  ) => Promise<AppleStoreTransaction>;
};

type JsonMap = Record<string, unknown>;
export type PomodoistSyncEntity = {
  entityType: string;
  entityId: string;
  serverRevision: number;
  deletedAt?: string | null;
  data: JsonMap;
};
export type PomodoistState = {
  entities: PomodoistSyncEntity[];
  tasks: Map<string, JsonMap>;
  projects: Map<string, JsonMap>;
  labels: Map<string, JsonMap>;
  focusPresets: Map<string, JsonMap>;
  focusRuns: Map<string, JsonMap>;
  focusIntervals: Map<string, JsonMap>;
  maxRevision: number;
};
type ParsedQuickAdd = {
  content: string;
  project?: string;
  labels: string[];
  priority?: number;
  dueJson?: string | null;
  durationSeconds?: number | null;
  estimatedFocusIntervals?: number;
};
export type PomodoistOperation = {
  opId: string;
  entityType: string;
  entityId: string;
  operation: "upsert" | "delete";
  payload: JsonMap;
  clientUpdatedAt: string;
};

export async function handlePomodoistWatch(
  req: Request,
  deps: PomodoistWatchDeps,
) {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ ok: false, error: "Method not allowed." }, 405);
  }

  const body = await readJson(req);
  if (body == null) {
    return json({ ok: false, error: "Request body must be valid JSON." }, 400);
  }

  const deviceId = stringValue(body.deviceId) ?? "apple-watch";
  const command = mapValue(body.command) ?? body;
  const type = stringValue(command.type) ?? "snapshot.request";
  const now = deps.now?.() ?? new Date();
  const uuid = deps.uuid ?? (() => crypto.randomUUID());
  const authorization = req.headers.get("Authorization");
  const client = authorization ? deps.createClient(authorization) : null;
  const user = client ? (await client.auth.getUser()).data.user : null;

  if (type === "task.decomposeTranscript") {
    if (!user && !(await hasActivePomodoistStoreTransaction(body, deps, now))) {
      return json({
        ok: false,
        code: "purchase_verification_failed",
        error: "Could not verify Pomodoist Pro purchase.",
      }, 403);
    }
    const requestId = uuid();
    const startedAt = performance.now();
    try {
      const tasks = await decomposeTranscript(command, deps, requestId);
      return json({ ok: true, tasks });
    } catch (error) {
      if (error instanceof TaskDecompositionError) {
        console.error(JSON.stringify({
          requestId,
          smart: command.smart === true,
          stage: error.code.startsWith("invalid_") ? "validation" : "provider",
          durationMs: Math.round(performance.now() - startedAt),
          code: error.code,
        }));
        return json(
          { ok: false, code: error.code, error: error.message },
          error.status,
        );
      }
      return json(
        {
          ok: false,
          code: "task_decomposition_failed",
          error: "Task analysis failed.",
        },
        502,
      );
    }
  }

  if (!client || !user) {
    return json({ ok: false, error: "Unauthorized." }, 401);
  }

  try {
    let state = await loadState(client, deviceId);
    let extra: JsonMap = {};
    let appliedCommandId = stringValue(command.id);
    let includeSnapshot = true;
    let ops: PomodoistOperation[] = [];

    switch (type) {
      case "snapshot.request":
        break;
      case "task.createQuickAdd":
        ops = taskCreateOps(state, command, user, now, uuid);
        break;
      case "task.commitDrafts":
        ops = commitDraftOps(state, command, user, now, uuid);
        break;
      case "task.complete":
        ops = completeTaskOps(state, command, user, now, uuid);
        break;
      case "task.uncomplete":
        ops = uncompleteTaskOps(state, command, user, now);
        break;
      case "focus.startDefault":
        ops = focusStartOps(state, command, user, now, uuid);
        break;
      case "focus.pause":
      case "focus.resume":
      case "focus.restartInterval":
      case "focus.complete":
      case "focus.skip":
      case "focus.stop":
        ops = focusUpdateOps(state, command, user, now, uuid);
        break;
      default:
        return json(
          { ok: false, error: `Unsupported watch command: ${type}` },
          400,
        );
    }

    if (ops.length > 0) {
      await pushChanges(client, deviceId, ops);
      state = await loadState(client, deviceId);
    }

    return json({
      ok: true,
      ...extra,
      ...(appliedCommandId == null ? {} : { appliedCommandId }),
      ...(includeSnapshot ? { snapshot: buildSnapshot(state, now) } : {}),
    });
  } catch (error) {
    return json({ ok: false, error: `${error}` }, 400);
  }
}

async function hasActivePomodoistStoreTransaction(
  body: JsonMap,
  deps: PomodoistWatchDeps,
  now: Date,
) {
  const values = body.storeTransactions;
  if (!Array.isArray(values) || values.length === 0 || values.length > 100) {
    return false;
  }
  const verify = deps.verifyStoreTransaction ?? verifyAppleStoreTransactionJws;
  for (const value of values) {
    if (
      typeof value !== "string" || value.length === 0 || value.length > 32768
    ) {
      continue;
    }
    try {
      const transaction = await verify(
        value,
        pomodoistAppleVerificationOptions,
      );
      if (pomodoistPurchaseState(transaction, now)?.status === "active") {
        return true;
      }
    } catch {
      // A candidate may be stale or unrelated; another signed transaction can
      // still represent the customer's current entitlement.
    }
  }
  return false;
}

async function loadState(
  client: SupabaseClient,
  deviceId: string,
): Promise<PomodoistState> {
  let cursor = 0;
  const entities: PomodoistSyncEntity[] = [];
  // ponytail: full watch snapshot is rebuilt from current sync_entities; add
  // incremental materialized watch state if accounts grow past a few thousand rows.
  while (true) {
    const { data, error } = await client.rpc("pull_changes", {
      p_app_id: appId,
      p_device_id: deviceId,
      p_since_revision: cursor,
      p_limit: 1000,
    });
    if (error) {
      throw new Error(error.message);
    }
    const page = mapValue(data) ?? {};
    for (const item of arrayValue(page.changes)) {
      const entity = mapValue(item);
      if (entity == null) continue;
      const serverRevision =
        numberValue(entity.serverRevision ?? entity.server_revision) ?? 0;
      entities.push({
        entityType: stringValue(entity.entityType ?? entity.entity_type) ?? "",
        entityId: stringValue(entity.entityId ?? entity.entity_id) ?? "",
        serverRevision,
        deletedAt: stringValue(entity.deletedAt ?? entity.deleted_at),
        data: mapValue(entity.data) ?? {},
      });
    }
    const nextCursor = numberValue(page.nextCursor ?? page.next_cursor) ??
      cursor;
    const hasMore = Boolean(page.hasMore ?? page.has_more);
    cursor = nextCursor;
    if (!hasMore) break;
  }

  return pomodoistState(entities);
}

export function pomodoistState(values: unknown[]): PomodoistState {
  const entities = values.map((item) => {
    const entity = mapValue(item) ?? {};
    return {
      entityType: stringValue(entity.entityType ?? entity.entity_type) ?? "",
      entityId: stringValue(entity.entityId ?? entity.entity_id) ?? "",
      serverRevision:
        numberValue(entity.serverRevision ?? entity.server_revision) ?? 0,
      deletedAt: stringValue(entity.deletedAt ?? entity.deleted_at),
      data: mapValue(entity.data) ?? {},
    };
  });
  const state: PomodoistState = {
    entities,
    tasks: new Map(),
    projects: new Map(),
    labels: new Map(),
    focusPresets: new Map(),
    focusRuns: new Map(),
    focusIntervals: new Map(),
    maxRevision: entities.reduce(
      (maximum, entity) => Math.max(maximum, entity.serverRevision),
      0,
    ),
  };
  for (const entity of entities) {
    if (entity.deletedAt != null) continue;
    const data = { ...entity.data };
    switch (entity.entityType) {
      case "task":
        if (data.isDeleted !== true) state.tasks.set(entity.entityId, data);
        break;
      case "project":
        if (data.isDeleted !== true) state.projects.set(entity.entityId, data);
        break;
      case "label":
        if (data.isDeleted !== true) state.labels.set(entity.entityId, data);
        break;
      case "focus_preset":
        if (data.isDeleted !== true) {
          state.focusPresets.set(entity.entityId, data);
        }
        break;
      case "focus_run":
        if (data.isDeleted !== true) state.focusRuns.set(entity.entityId, data);
        break;
      case "focus_interval":
        if (data.isDeleted !== true) {
          state.focusIntervals.set(entity.entityId, data);
        }
        break;
    }
  }
  return state;
}

async function pushChanges(
  client: SupabaseClient,
  deviceId: string,
  operations: PomodoistOperation[],
) {
  const { error } = await client.rpc("push_changes", {
    p_app_id: appId,
    p_device_id: deviceId,
    p_operations: operations,
  });
  if (error) {
    throw new Error(error.message);
  }
}

function taskCreateOps(
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

function commitDraftOps(
  state: PomodoistState,
  command: JsonMap,
  user: User,
  now: Date,
  uuid: () => string,
): PomodoistOperation[] {
  const ops: PomodoistOperation[] = [];
  for (const draft of arrayValue(command.tasks)) {
    const item = mapValue(draft);
    const quickAdd = stringValue(item?.quickAdd ?? item?.input);
    if (quickAdd == null || quickAdd.trim().length === 0) continue;
    ops.push(
      ...createTaskOps(
        state,
        quickAdd,
        user,
        now,
        uuid,
        command,
        stringValue(item?.description),
      ),
    );
  }
  return ops;
}

function createTaskOps(
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

function createParsedTaskOps(
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
  for (const labelName of parsed.labels) {
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

function completeTaskOps(
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

function uncompleteTaskOps(
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

function focusStartOps(
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

function focusUpdateOps(
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

function buildSnapshot(state: PomodoistState, now: Date) {
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

function watchTask(task: JsonMap) {
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

function watchPreset(preset: JsonMap) {
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

function activeFocus(state: PomodoistState) {
  const run = [...state.focusRuns.values()].find((item) =>
    item.isDeleted !== true &&
    item.endedAt == null &&
    (item.status === "active" || item.status === "paused")
  );
  const runId = stringValue(run?.id);
  const interval = runId == null
    ? undefined
    : [...state.focusIntervals.values()]
      .filter((item) =>
        item.runId === runId &&
        item.isDeleted !== true &&
        item.completedAt == null &&
        item.stoppedAt == null &&
        (item.status === "running" || item.status === "paused" ||
          item.status === "ready")
      )
      .sort((a, b) =>
        (numberValue(b.sequenceNumber) ?? 0) -
        (numberValue(a.sequenceNumber) ?? 0)
      )[0];
  return { run, interval };
}

function selectedPreset(state: PomodoistState, presetId?: string) {
  const presets = [...state.focusPresets.values()].filter((item) =>
    item.isDeleted !== true
  );
  return (presetId == null ? undefined : state.focusPresets.get(presetId)) ??
    presets.find((item) => item.isDefault === true) ??
    presets[0] ??
    defaultPreset;
}

function parseQuickAdd(input: string, now: Date): ParsedQuickAdd {
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

function dueJsonFrom(
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

class TaskDecompositionError extends Error {
  constructor(
    readonly code: string,
    readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

const taskDecompositionPrompt = `
You turn a spoken Pomodoist transcript into separate quick-add tasks.
Return only JSON: {"tasks":[{"quickAdd":"task 1","description":"optional comment","subtasks":[{"quickAdd":"subtask"}]}]}.

Rules:
- Split into logical actionable tasks. If there is one task, return one item.
- Use subtasks only when the user explicitly describes child steps under a parent task.
- Correct only obvious gross typos. Do not rewrite style.
- Do not invent tasks, projects, labels, or times.
- Use the user's language for task titles.
- Put the actionable task title and Pomodoist tokens in quickAdd.
- Put extra context, notes, clarifications, and non-actionable details in description.
- Omit description or use null when there is no comment for the task.
- Preserve explicit #project, @label, p1-p4 priority, and focus estimates like 3p.
- Infer priority only when the user explicitly expresses importance, urgency, ranking, or low priority.
- Normalize spoken priorities to p1-p4 in quickAdd: p1 is critical/urgent/highest ("горит", "срочно", "обязательно первым"), p2 is important/high, p3 is normal/medium ("не срочно, но надо"), p4 is low/optional/backlog ("когда будет время", "можно потом", "низкий приоритет").
- Exact spoken ranks like "priority one" or "приоритет один" win over emotional wording.
- If there is no clear priority signal, omit priority. Do not add p4 by default.
- Interpret spoken dates and times in the transcript's language, including localized month names, AM/PM, and conversational phrases such as "half past five".
- Resolve dates and times against the supplied current local time. Treat numeric dates as day/month, never month/day.
- Emit every recognized date and time as YYYY-MM-DD and HH:mm scheduling tokens. If a date or time is ambiguous or cannot be determined, omit it rather than guess.
- Add scheduling tokens at the end using Pomodoist quick-add syntax: today, tomorrow, YYYY-MM-DD, HH:mm, 30m, 2h.
- For "distribute over 5 hours" style requests, spread tasks evenly inside that window.
- For "all day", use the waking day 09:00-22:00 unless the user gave another window.
- For "today", keep tasks on the current local date.
- For "this week" or "whole week", spread tasks across the next 7 calendar days.
- Use compact task strings. No Markdown, bullets, explanations, or keys other than quickAdd, description, subtasks.
`.trim();

async function decomposeTranscript(
  command: JsonMap,
  deps: PomodoistWatchDeps,
  requestId: string,
) {
  const startedAt = performance.now();
  const transcript = stringValue(command.transcript)?.trim() ?? "";
  if (transcript.length === 0 || transcript.length > 20_000) {
    throw new TaskDecompositionError(
      "invalid_transcript",
      400,
      "Transcript must contain between 1 and 20000 characters.",
    );
  }
  const locale = stringValue(command.locale) ?? "";
  if (locale.length === 0 || locale.length > 35 || /[\r\n]/.test(locale)) {
    throw new TaskDecompositionError(
      "invalid_locale",
      400,
      "Locale must be a valid language tag.",
    );
  }
  if (command.smart != null && typeof command.smart !== "boolean") {
    throw new TaskDecompositionError(
      "invalid_smart_mode",
      400,
      "Smart mode must be a boolean.",
    );
  }
  const smart = command.smart === true;
  const currentLocalTime = stringValue(command.currentLocalTime) ??
    (deps.now?.() ?? new Date()).toISOString();
  if (
    currentLocalTime.length > 50 ||
    !Number.isFinite(Date.parse(currentLocalTime))
  ) {
    throw new TaskDecompositionError(
      "invalid_local_time",
      400,
      "Current local time must be an ISO-8601 timestamp.",
    );
  }

  // Finish before the client's 45s / 120s timeout, including fallback requests.
  const deadline = startedAt + (smart ? 115_000 : 40_000);
  const providers = [
    ...(!smart
      ? [
        {
          name: "cerebras",
          url: "https://api.cerebras.ai/v1/chat/completions",
          key: "CEREBRAS_API_KEY",
          timeoutMs: 8_000,
          options: {
            model: "gpt-oss-120b",
            reasoning_effort: "low",
            temperature: 0.1,
          },
        },
        {
          name: "openrouter",
          url: "https://openrouter.ai/api/v1/chat/completions",
          key: "POMODOIST_OPENROUTER_API_KEY",
          timeoutMs: 12_000,
          options: {
            model: "openai/gpt-oss-120b",
            reasoning: { effort: "low" },
            temperature: 0.1,
            provider: {
              sort: "latency",
              allow_fallbacks: true,
              require_parameters: true,
              // Cerebras has already failed; try independent providers.
              ignore: ["cerebras"],
            },
          },
        },
      ]
      : []),
    {
      name: "deepseek",
      url: "https://api.deepseek.com/chat/completions",
      key: "DEEPSEEK_API_KEY",
      timeoutMs: smart ? 115_000 : 40_000,
      options: {
        model: "deepseek-v4-flash",
        thinking: { type: smart ? "enabled" : "disabled" },
        ...(smart ? { reasoning_effort: "high" } : { temperature: 0.1 }),
      },
    },
  ];
  const requestBody = {
    response_format: { type: "json_object" },
    max_tokens: 4096,
    messages: [
      { role: "system", content: taskDecompositionPrompt },
      {
        role: "user",
        content:
          `Locale: ${locale}\nCurrent local time: ${currentLocalTime}\n\nTranscript:\n${transcript}`,
      },
    ],
  };
  let lastError = new TaskDecompositionError(
    "deepseek_not_configured",
    503,
    "No task analysis provider is configured.",
  );

  for (const provider of providers) {
    const apiKey = deps.env.get(provider.key)?.trim();
    if (!apiKey) continue;
    // Retry invalid JSON only at the last provider, within the same deadline.
    const attempts = provider.name === "deepseek" ? 2 : 1;
    for (let attempt = 0; attempt < attempts; attempt += 1) {
      const remainingMs = Math.floor(deadline - performance.now());
      if (remainingMs <= 0) {
        throw new TaskDecompositionError(
          `${provider.name}_timeout`,
          504,
          "Task analysis timed out.",
        );
      }
      try {
        const response = await deps.fetch(provider.url, {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${apiKey}`,
            "content-type": "application/json",
          },
          body: JSON.stringify({ ...requestBody, ...provider.options }),
          signal: AbortSignal.timeout(
            Math.min(provider.timeoutMs, remainingMs),
          ),
        });
        if (!response.ok) {
          await response.body?.cancel();
          throw new TaskDecompositionError(
            `${provider.name}_http_${response.status}`,
            502,
            "Task analysis provider request failed.",
          );
        }
        // Body reads must also complete within this attempt's timeout.
        const payload = await response.json();
        const choice = mapValue(arrayValue(mapValue(payload)?.choices)[0]);
        const content = stringValue(mapValue(choice?.message)?.content);
        const parsed = JSON.parse(content ?? "");
        const tasks = decodeTaskDrafts(mapValue(parsed)?.tasks ?? parsed);
        if (tasks.length === 0 || choice?.finish_reason === "length") {
          throw new SyntaxError("Invalid or truncated task JSON.");
        }
        console.info(JSON.stringify({
          requestId,
          smart,
          provider: provider.name,
          model: provider.options.model,
          stage: "complete",
          durationMs: Math.round(performance.now() - startedAt),
        }));
        return tasks;
      } catch (error) {
        const timedOut = error instanceof DOMException &&
          (error.name === "TimeoutError" || error.name === "AbortError");
        lastError = error instanceof TaskDecompositionError
          ? error
          : new TaskDecompositionError(
            `${provider.name}_${
              timedOut
                ? "timeout"
                : error instanceof SyntaxError
                ? "invalid_response"
                : "http_error"
            }`,
            timedOut ? 504 : 502,
            timedOut
              ? "Task analysis timed out."
              : "Task analysis provider returned an unusable response.",
          );
        console.warn(JSON.stringify({
          requestId,
          smart,
          provider: provider.name,
          stage: "provider_failed",
          code: lastError.code,
          durationMs: Math.round(performance.now() - startedAt),
        }));
        if (!lastError.code.endsWith("_invalid_response")) break;
      }
    }
  }
  throw lastError;
}

function decodeTaskDrafts(value: unknown): JsonMap[] {
  return arrayValue(value)
    .map(decodeTaskDraft)
    .filter((draft): draft is JsonMap => draft != null);
}

function decodeTaskDraft(value: unknown): JsonMap | null {
  const item = mapValue(value);
  if (item == null) return null;
  const quickAdd = stringValue(
    item.quickAdd ?? item.task ?? item.content ?? item.title,
  )?.trim();
  if (quickAdd == null || quickAdd.length === 0) return null;
  const description = stringValue(item.description ?? item.note)?.trim();
  const subtasks = decodeTaskDrafts(
    item.subtasks ?? item.subTasks ?? item.children ?? item.steps,
  );
  return {
    quickAdd,
    ...(description == null || description.length === 0 ? {} : { description }),
    ...(subtasks.length === 0 ? {} : { subtasks }),
  };
}

function op(
  opId: string,
  entityType: string,
  entityId: string,
  payload: JsonMap,
  clientUpdatedAt: Date,
): PomodoistOperation {
  return {
    opId,
    entityType,
    entityId,
    operation: "upsert",
    payload: { schemaVersion: 1, ...payload },
    clientUpdatedAt: clientUpdatedAt.toISOString(),
  };
}

function projectIdFor(state: PomodoistState, name?: string) {
  if (name == null) return undefined;
  const target = name.trim().toLowerCase();
  return stringValue(
    [...state.projects.values()].find((project) =>
      stringValue(project.name)?.toLowerCase() === target
    )?.id,
  );
}

function labelFor(state: PomodoistState, name: string) {
  const target = name.trim().toLowerCase();
  return [...state.labels.values()].find((label) =>
    stringValue(label.name)?.toLowerCase() === target
  );
}

function requiredTaskId(command: JsonMap) {
  return requiredString(command, "taskId", "id");
}

function commandOpId(command: JsonMap, fallback: string) {
  return stringValue(command.id) ?? `watch:${fallback}`;
}

function deterministicCommandUuid(command: JsonMap) {
  const raw = requiredString(command, "id").replaceAll("-", "").toLowerCase();
  if (!/^[0-9a-f]{32}$/.test(raw)) throw new Error("Invalid command UUID.");
  let sequence = 0n;
  return () => {
    sequence += 1n;
    const suffix = (BigInt(`0x${raw.slice(20)}`) ^ sequence)
      .toString(16)
      .padStart(12, "0");
    const variant = ((Number.parseInt(raw[16], 16) & 3) | 8).toString(16);
    return `${raw.slice(0, 8)}-${raw.slice(8, 12)}-5${
      raw.slice(13, 16)
    }-${variant}${raw.slice(17, 20)}-${suffix}`;
  };
}

function requiredString(map: JsonMap, ...keys: string[]) {
  for (const key of keys) {
    const value = stringValue(map[key]);
    if (value != null && value.trim().length > 0) return value;
  }
  throw new Error(`Missing string: ${keys.join("/")}`);
}

function taskCompare(a: JsonMap, b: JsonMap) {
  const dayOrder = (numberValue(a.dayOrder) ?? 999999) -
    (numberValue(b.dayOrder) ?? 999999);
  if (dayOrder !== 0) return dayOrder;
  return `${a.orderKey ?? ""}`.localeCompare(`${b.orderKey ?? ""}`);
}

function taskDate(task: JsonMap) {
  const schedule = scheduleMap(stringValue(task.dueJson));
  return stringValue(schedule?.date) ??
    (stringValue(schedule?.start)?.slice(0, 10) ?? undefined);
}

function scheduleMap(raw?: string) {
  if (raw == null || raw.trim().length === 0) return null;
  try {
    const value = mapValue(JSON.parse(raw));
    if (value == null) return null;
    if (value.type === "timed") {
      const start = stringValue(value.start);
      const end = stringValue(value.end);
      return {
        kind: "timed",
        start,
        end,
        durationSeconds: start == null || end == null ? null : Math.max(
          0,
          Math.floor(
            (new Date(end).getTime() - new Date(start).getTime()) / 1000,
          ),
        ),
      };
    }
    return { kind: "allDay", date: stringValue(value.date) };
  } catch {
    return null;
  }
}

function dateOnly(date: Date) {
  return date.toISOString().slice(0, 10);
}

function addDays(date: string, days: number) {
  const value = new Date(`${date}T00:00:00.000Z`);
  value.setUTCDate(value.getUTCDate() + days);
  return dateOnly(value);
}

function orderKey(now: Date) {
  return String(now.getTime() * 1000).padStart(20, "0");
}

function mapValue(value: unknown): JsonMap | null {
  return value != null && typeof value === "object" && !Array.isArray(value)
    ? value as JsonMap
    : null;
}

function arrayValue(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function stringValue(value: unknown): string | undefined {
  return typeof value === "string" ? value : undefined;
}

function numberValue(value: unknown): number | undefined {
  return typeof value === "number"
    ? value
    : typeof value === "string"
    ? Number(value)
    : undefined;
}

function dateValue(value: unknown): Date | null {
  const raw = stringValue(value);
  if (raw == null) return null;
  const date = new Date(raw);
  return Number.isNaN(date.getTime()) ? null : date;
}

async function readJson(req: Request): Promise<JsonMap | null> {
  try {
    return mapValue(await req.json());
  } catch {
    return null;
  }
}

function json(body: unknown, status = 200) {
  return Response.json(body, { status, headers: corsHeaders });
}

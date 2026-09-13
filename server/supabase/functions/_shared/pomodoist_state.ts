export const appId = "pomodoist";
export const localUserId = "local-user";
export const inboxProjectId = "inbox";
export const defaultPreset = {
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

export type User = { id: string; email?: string };
export type RpcResult = { data: unknown; error: { message: string } | null };
export type SupabaseClient = {
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

export type JsonMap = Record<string, unknown>;
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
export type ParsedQuickAdd = {
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

export function op(
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

export function projectIdFor(state: PomodoistState, name?: string) {
  if (name == null) return undefined;
  const target = name.trim().toLowerCase();
  return stringValue(
    [...state.projects.values()].find((project) =>
      stringValue(project.name)?.toLowerCase() === target
    )?.id,
  );
}

export function labelFor(state: PomodoistState, name: string) {
  const target = name.trim().toLowerCase();
  return [...state.labels.values()].find((label) =>
    stringValue(label.name)?.toLowerCase() === target
  );
}

export function requiredTaskId(command: JsonMap) {
  return requiredString(command, "taskId", "id");
}

export function commandOpId(command: JsonMap, fallback: string) {
  return stringValue(command.id) ?? `watch:${fallback}`;
}

export function deterministicCommandUuid(command: JsonMap) {
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

export function requiredString(map: JsonMap, ...keys: string[]) {
  for (const key of keys) {
    const value = stringValue(map[key]);
    if (value != null && value.trim().length > 0) return value;
  }
  throw new Error(`Missing string: ${keys.join("/")}`);
}

export function taskCompare(a: JsonMap, b: JsonMap) {
  const dayOrder = (numberValue(a.dayOrder) ?? 999999) -
    (numberValue(b.dayOrder) ?? 999999);
  if (dayOrder !== 0) return dayOrder;
  return `${a.orderKey ?? ""}`.localeCompare(`${b.orderKey ?? ""}`);
}

export function taskDate(task: JsonMap) {
  const schedule = scheduleMap(stringValue(task.dueJson));
  return stringValue(schedule?.date) ??
    (stringValue(schedule?.start)?.slice(0, 10) ?? undefined);
}

export function scheduleMap(raw?: string) {
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

export function dateOnly(date: Date) {
  return date.toISOString().slice(0, 10);
}

export function addDays(date: string, days: number) {
  const value = new Date(`${date}T00:00:00.000Z`);
  value.setUTCDate(value.getUTCDate() + days);
  return dateOnly(value);
}

export function orderKey(now: Date) {
  return String(now.getTime() * 1000).padStart(20, "0");
}

export function mapValue(value: unknown): JsonMap | null {
  return value != null && typeof value === "object" && !Array.isArray(value)
    ? value as JsonMap
    : null;
}

export function arrayValue(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

export function stringValue(value: unknown): string | undefined {
  return typeof value === "string" ? value : undefined;
}

export function numberValue(value: unknown): number | undefined {
  return typeof value === "number"
    ? value
    : typeof value === "string"
    ? Number(value)
    : undefined;
}

export function dateValue(value: unknown): Date | null {
  const raw = stringValue(value);
  if (raw == null) return null;
  const date = new Date(raw);
  return Number.isNaN(date.getTime()) ? null : date;
}

export function activeFocus(state: PomodoistState) {
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

export function selectedPreset(state: PomodoistState, presetId?: string) {
  const presets = [...state.focusPresets.values()].filter((item) =>
    item.isDeleted !== true
  );
  return (presetId == null ? undefined : state.focusPresets.get(presetId)) ??
    presets.find((item) => item.isDefault === true) ??
    presets[0] ??
    defaultPreset;
}

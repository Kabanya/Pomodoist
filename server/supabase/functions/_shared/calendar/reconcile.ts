export type CalendarProvider = "google" | "outlook";
export type EditSource = "pomodoist" | CalendarProvider;
export type Schedule = { type: "allDay"; date: string } | {
  type: "timed";
  start: string;
  end: string;
  timeZone?: string;
};
export type Field = "content" | "description" | "status" | "schedule";
export type Fields = {
  content: string;
  description: string | null;
  status: string;
  schedule: Schedule | null;
};
export type SourceStamp = {
  modifiedAt: string;
  source: EditSource;
  changeId: string;
};
export type TaskSnapshot = Fields & {
  id: string;
  deleted: boolean;
  revision: number;
  incarnation: number;
  clearedIncarnation?: number;
  stamps: Partial<Record<Field, SourceStamp>>;
};
export type LinkSnapshot = {
  taskId: string;
  connectionId: string;
  provider: CalendarProvider;
  eventId: string;
  incarnation: number;
  version: string | null;
  baseline: Fields;
  unsupportedReason?: string | null;
};
export type EventSnapshot = {
  connectionId: string;
  eventId: string;
  version: string | null;
  modifiedAt: string;
  state: "active" | "deleted" | "unsupported";
  fields: Fields;
};
export type CalendarEffect = {
  connectionId: string;
  taskId: string;
  eventId: string;
  kind: "patch" | "delete";
  expectedVersion: string | null;
  incarnation: number;
  taskRevision: number;
  fields: Fields;
};
export type ReconcileInput = {
  task: TaskSnapshot;
  links: LinkSnapshot[];
  remote: EventSnapshot[];
};
export type ReconcileResult = {
  task: TaskSnapshot;
  links: LinkSnapshot[];
  effects: CalendarEffect[];
};
export function reconcile(input: ReconcileInput): ReconcileResult {
  const task = structuredClone(input.task);
  const links = structuredClone(input.links);
  const remote = new Map(
    input.remote.map(
      (event) => [`${event.connectionId}:${event.eventId}`, event],
    ),
  );
  const removed = new Set<string>();
  const unsupported = new Set<string>();
  const fields: Field[] = ["content", "description", "status", "schedule"];
  for (const link of links) {
    const event = remote.get(`${link.connectionId}:${link.eventId}`);
    if (!event || link.taskId !== task.id) continue;
    if (event.state === "unsupported") {
      link.unsupportedReason = "unsupported_event";
      unsupported.add(link.connectionId);
      continue;
    }
    link.unsupportedReason = null;
    link.version = event.version;
    if (event.state === "deleted") {
      removed.add(link.connectionId);
      if (link.incarnation === task.incarnation && !task.deleted) {
        task.schedule = null;
        task.clearedIncarnation = task.incarnation;
        task.stamps.schedule = {
          modifiedAt: event.modifiedAt,
          source: link.provider,
          changeId: event.version ?? event.eventId,
        };
      }
      continue;
    }
    if (link.incarnation !== task.incarnation || task.deleted) continue;
    const stamp: SourceStamp = {
      modifiedAt: event.modifiedAt,
      source: link.provider,
      changeId: event.version ?? event.modifiedAt,
    };
    if (!Number.isFinite(Date.parse(stamp.modifiedAt))) continue;
    for (const field of fields) {
      if (
        field === "schedule" && task.clearedIncarnation === task.incarnation
      ) continue;
      if (equal(event.fields[field], link.baseline[field])) continue;
      if (wins(stamp, task.stamps[field])) {
        Object.assign(task, { [field]: event.fields[field] });
        task.stamps[field] = stamp;
      }
    }
    link.version = event.version;
    link.baseline = structuredClone(event.fields);
  }
  if (task.clearedIncarnation === task.incarnation) task.schedule = null;
  if (!equal(task, input.task)) task.revision++;
  const desired = fieldsOf(task);
  const effects: CalendarEffect[] = [];
  for (const link of links) {
    if (
      link.taskId !== task.id || unsupported.has(link.connectionId) ||
      link.unsupportedReason || removed.has(link.connectionId)
    ) continue;
    const kind = task.deleted || task.schedule === null ||
        link.incarnation !== task.incarnation
      ? "delete"
      : "patch";
    if (kind === "patch" && equal(desired, link.baseline)) continue;
    effects.push({
      connectionId: link.connectionId,
      taskId: task.id,
      eventId: link.eventId,
      kind,
      expectedVersion: link.version,
      incarnation: link.incarnation,
      taskRevision: task.revision,
      fields: desired,
    });
  }
  return {
    task,
    links: links.filter((link) => !removed.has(link.connectionId)),
    effects,
  };
}

export function fieldsOf(task: Fields): Fields {
  return {
    content: task.content,
    description: task.description,
    status: task.status,
    schedule: task.schedule,
  };
}
export function equal(a: unknown, b: unknown): boolean {
  return canonical(a) === canonical(b);
}
function canonical(value: unknown): string {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return JSON.stringify(value.map(canonical));
  return JSON.stringify(
    Object.entries(value).sort(([a], [b]) => a.localeCompare(b)).map((
      [key, value],
    ) => [key, canonical(value)]),
  );
}
function wins(incoming: SourceStamp, current?: SourceStamp): boolean {
  if (!current) return true;
  const time = Date.parse(incoming.modifiedAt) - Date.parse(current.modifiedAt);
  if (time !== 0) return time > 0;
  const rank: Record<EditSource, number> = {
    pomodoist: 3,
    google: 2,
    outlook: 1,
  };
  if (incoming.source !== current.source) {
    return rank[incoming.source] > rank[current.source];
  }
  return incoming.changeId > current.changeId;
}

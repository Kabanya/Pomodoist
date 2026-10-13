import {
  equal,
  type Field,
  fieldsOf,
  type LinkSnapshot,
  type Schedule,
  type SourceStamp,
  type TaskSnapshot,
} from "./reconcile.ts";
import { record } from "./security.ts";
import { emptyWork } from "./work.ts";
import type { CalendarStore, ConnectionSnapshot } from "./worker.ts";
export type CalendarRpc = (
  action: string,
  userId: string | null,
  provider: string | null,
  payload: Record<string, unknown>,
) => Promise<unknown>;
export function decodeConnection(value: unknown): ConnectionSnapshot {
  if (
    !record(value) || typeof value.id !== "string" ||
    typeof value.userId !== "string" ||
    !["google", "outlook"].includes(String(value.provider))
  ) throw new Error("Invalid calendar connection.");
  return {
    id: value.id,
    userId: value.userId,
    provider: value.provider as "google" | "outlook",
    generation: Number(value.generation ?? 1),
    lease: String(value.lease ?? ""),
    calendarId: typeof value.calendarId === "string" ? value.calendarId : null,
    state: record(value.state) ? value.state : {},
    work: { ...emptyWork(), ...(record(value.work) ? value.work : {}) },
    tasks: Array.isArray(value.tasks) ? value.tasks.map(decodeTask) : [],
    links: Array.isArray(value.links) ? value.links as LinkSnapshot[] : [],
    pendingEffects: Array.isArray(value.pendingEffects)
      ? value.pendingEffects as ConnectionSnapshot["pendingEffects"]
      : [],
  };
}
export function decodeTask(raw: unknown): TaskSnapshot {
  if (
    !record(raw) || typeof raw.id !== "string" ||
    typeof raw.content !== "string"
  ) throw new Error("Invalid calendar task.");
  const metadata = record(raw._metadata) ? raw._metadata : {};
  const previous = record(metadata.snapshot) ? metadata.snapshot : {};
  let schedule: Schedule | null = null;
  if (typeof raw.dueJson === "string" && raw.dueJson) {
    const parsed = JSON.parse(raw.dueJson);
    if (parsed?.type === "allDay" && /^\d{4}-\d{2}-\d{2}$/.test(parsed.date)) {
      schedule = { type: "allDay", date: parsed.date };
    } else if (
      parsed?.type === "timed" &&
      Date.parse(parsed.end) > Date.parse(parsed.start)
    ) {
      schedule = {
        type: "timed",
        start: new Date(parsed.start).toISOString(),
        end: new Date(parsed.end).toISOString(),
        ...(typeof parsed.timeZone === "string"
          ? { timeZone: parsed.timeZone }
          : {}),
      };
    } else throw new Error("Unsupported task calendar schedule.");
  }
  const task: TaskSnapshot = {
    id: raw.id,
    content: raw.content,
    description: typeof raw.description === "string" && raw.description
      ? raw.description
      : null,
    status: typeof raw.status === "string" ? raw.status : "open",
    schedule,
    deleted: raw.isDeleted === true || raw._deletedAt != null,
    revision: Number(raw._revision ?? raw.revision ?? 0),
    incarnation: Number(metadata.incarnation ?? 1),
    stamps: record(previous.stamps)
      ? { ...previous.stamps } as Partial<Record<Field, SourceStamp>>
      : {},
    ...(metadata.clearedIncarnation == null
      ? {}
      : { clearedIncarnation: Number(metadata.clearedIncarnation) }),
  };
  const clock = record(raw._fieldClock) ? raw._fieldClock : {};
  for (
    const field of ["content", "description", "status", "schedule"] as Field[]
  ) {
    if (!equal(task[field], previous[field])) {
      task.stamps[field] = {
        source: "pomodoist",
        modifiedAt: String(
          clock[field === "schedule" ? "dueJson" : field] ??
            raw._clientUpdatedAt ?? raw.updatedAt ?? "1970-01-01T00:00:00Z",
        ),
        changeId: String(task.revision),
      };
    }
  }
  return task;
}
export class RpcCalendarStore implements CalendarStore {
  constructor(readonly rpc: CalendarRpc) {}
  private call(
    action: string,
    connection: ConnectionSnapshot,
    payload: Record<string, unknown> = {},
  ) {
    return this.rpc(action, connection.userId, connection.provider, {
      guard: {
        connectionId: connection.id,
        generation: connection.generation,
        lease: connection.lease,
      },
      ...payload,
    });
  }
  snapshot: CalendarStore["snapshot"] = async (c) =>
    decodeConnection(await this.call("snapshot", c));
  accept: CalendarStore["accept"] = async (c, input, result) => {
    const response = await this.call("accept", c, {
      expectedRevision: input.task.revision,
      task: result.task,
      links: result.links,
      taskChanged: !equal(fieldsOf(input.task), fieldsOf(result.task)) ||
        input.task.clearedIncarnation !== result.task.clearedIncarnation,
    });
    return record(response) && record(response.task)
      ? response.task as TaskSnapshot
      : null;
  };
  saveLink: CalendarStore["saveLink"] = async (c, task, link) => {
    await this.call("save_link", c, {
      taskId: task.id,
      revision: task.revision,
      link,
    });
  };
  removeLink: CalendarStore["removeLink"] = async (c, taskId) => {
    await this.call("remove_link", c, { taskId });
  };
  prepareEffect: CalendarStore["prepareEffect"] = async (
    c,
    task,
    kind,
    eventId,
  ) => {
    const value = await this.call("prepare_effect", c, {
      taskId: task.id,
      revision: task.revision,
      incarnation: task.incarnation,
      kind,
      eventId,
      fields: fieldsOf(task),
    });
    return record(value) && value.accepted === true;
  };
  checkpoint: CalendarStore["checkpoint"] = async (c) => {
    await this.call("checkpoint", c, {
      calendarId: c.calendarId,
      state: c.state,
    });
  };
  complete: CalendarStore["complete"] = async (c) => {
    await this.call("complete", c, {
      calendarId: c.calendarId,
      state: c.state,
      claimedGeneration: c.work.generation,
    });
  };
  fail: CalendarStore["fail"] = async (c, error) => {
    const status = error && typeof error === "object" && "status" in error
      ? Number(error.status)
      : 0;
    const seconds =
      error && typeof error === "object" && "retrySeconds" in error
        ? Number(error.retrySeconds)
        : 30;
    await this.call("fail", c, {
      error: status === 401 || status === 403
        ? "authorization_required"
        : status === 429
        ? "rate_limited"
        : "calendar_unavailable",
      retrySeconds: Number.isFinite(seconds) ? seconds : 30,
    });
  };
}

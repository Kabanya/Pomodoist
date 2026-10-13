import {
  type CalendarProvider,
  equal,
  type EventSnapshot,
  type Fields,
  fieldsOf,
  type LinkSnapshot,
  reconcile,
  type ReconcileInput,
  type TaskSnapshot,
} from "./reconcile.ts";
import type { RemoteHint, Work } from "./work.ts";
export type StoredTask = TaskSnapshot;
export type PendingEffect = {
  taskId: string;
  revision: number;
  incarnation: number;
  kind: string;
  eventId?: string;
  fields: Fields;
};
export type ConnectionSnapshot = {
  id: string;
  userId: string;
  provider: CalendarProvider;
  generation: number;
  lease: string;
  calendarId: string | null;
  tasks: StoredTask[];
  links: LinkSnapshot[];
  pendingEffects?: PendingEffect[];
  work: Work;
  state: Record<string, unknown>;
};
export type AdapterEvent = EventSnapshot & {
  taskId?: string;
  incarnation?: number;
};
export type WriteResult = {
  eventId: string;
  version: string | null;
  fields: Fields;
};
export type CalendarAdapter = {
  ensureCalendar: (calendarId: string | null) => Promise<string>;
  maintain: (
    state: Record<string, unknown>,
    force?: boolean,
  ) => Promise<{ state: Record<string, unknown>; replaced: boolean }>;
  read: () => Promise<AdapterEvent[]>;
  fullRead?: boolean;
  cursorState?: () => Record<string, unknown>;
  lookup: (eventId: string, baseline: Fields) => Promise<AdapterEvent | null>;
  classifyHint: (hint: RemoteHint) => Promise<boolean>;
  create: (task: TaskSnapshot) => Promise<WriteResult>;
  patch: (
    eventId: string,
    version: string | null,
    task: TaskSnapshot,
  ) => Promise<WriteResult>;
  delete: (eventId: string, version?: string | null) => Promise<void>;
};
export type CalendarStore = {
  snapshot: (connection: ConnectionSnapshot) => Promise<ConnectionSnapshot>;
  accept: (
    connection: ConnectionSnapshot,
    input: ReconcileInput,
    result: import("./reconcile.ts").ReconcileResult,
  ) => Promise<TaskSnapshot | null>;
  saveLink: (
    connection: ConnectionSnapshot,
    task: TaskSnapshot,
    link: LinkSnapshot,
  ) => Promise<void>;
  removeLink: (connection: ConnectionSnapshot, taskId: string) => Promise<void>;
  prepareEffect: (
    connection: ConnectionSnapshot,
    task: TaskSnapshot,
    kind: string,
    eventId?: string,
  ) => Promise<boolean>;
  checkpoint: (connection: ConnectionSnapshot) => Promise<void>;
  complete: (connection: ConnectionSnapshot) => Promise<void>;
  fail: (connection: ConnectionSnapshot, error: unknown) => Promise<void>;
};
export async function processConnection(
  connection: ConnectionSnapshot,
  store: CalendarStore,
  adapter: CalendarAdapter,
): Promise<void> {
  connection.calendarId = await adapter.ensureCalendar(connection.calendarId);
  await store.checkpoint(connection);
  const maintained = await adapter.maintain(
    connection.state,
    connection.work.maintenance,
  );
  connection.state = { ...connection.state, ...maintained.state };
  await store.checkpoint(connection);
  let read = maintained.replaced || connection.work.refresh ||
    connection.work.recovery || connection.work.publishRevision !== null;
  if (!read) {
    for (const hint of connection.work.hints) {
      const link = connection.links.find((link) =>
        link.eventId === hint.eventId
      );
      if (
        hint.kind !== "deleted" && link && hint.version &&
        link.version === hint.version
      ) continue;
      if (
        link || (hint.kind !== "deleted" && await adapter.classifyHint(hint))
      ) {
        read = true;
        break;
      }
    }
  }
  if (!read) {
    await store.complete(connection);
    return;
  }
  const events = await adapter.read();
  const fresh = await store.snapshot(connection);
  connection.tasks = fresh.tasks;
  connection.links = fresh.links;
  connection.pendingEffects = fresh.pendingEffects;
  for (const originalTask of connection.tasks) {
    let links = connection.links.filter((link) =>
      link.taskId === originalTask.id
    );
    const pending = connection.pendingEffects?.find((effect) =>
      effect.taskId === originalTask.id
    );
    // A successful write can precede its durable acknowledgement. Its submitted
    // fields are the baseline, even if the task changed during the HTTP request.
    if (pending?.kind === "patch") {
      const acknowledged = events.find((event) =>
        event.eventId === pending.eventId && event.state === "active" &&
        equal(event.fields, pending.fields)
      );
      if (acknowledged) {
        links = links.map((link) =>
          link.eventId === acknowledged.eventId
            ? {
              ...link,
              version: acknowledged.version,
              baseline: pending.fields,
            }
            : link
        );
      }
    }
    if (!links.length && pending?.kind === "create") {
      const acknowledged = events.find((event) =>
        event.taskId === originalTask.id &&
        event.incarnation === pending.incarnation && event.state === "active"
      );
      if (acknowledged) {
        links = [{
          taskId: originalTask.id,
          connectionId: connection.id,
          provider: connection.provider,
          eventId: acknowledged.eventId,
          incarnation: pending.incarnation,
          version: acknowledged.version,
          baseline: pending.fields,
        }];
      }
    }
    if (!links.length) {
      const recovered = events.find((event) =>
        event.taskId === originalTask.id &&
        event.incarnation === originalTask.incarnation &&
        event.state === "active"
      );
      if (recovered) {
        links = [{
          taskId: originalTask.id,
          connectionId: connection.id,
          provider: connection.provider,
          eventId: recovered.eventId,
          incarnation: originalTask.incarnation,
          version: recovered.version,
          baseline: recovered.fields,
        }];
      }
    }
    const remote: AdapterEvent[] = [];
    for (const link of links) {
      let event = events.find((event) => event.eventId === link.eventId);
      if (!event && adapter.fullRead !== false) {
        event = await adapter.lookup(link.eventId, link.baseline) ?? {
          connectionId: connection.id,
          eventId: link.eventId,
          version: link.version,
          modifiedAt: new Date().toISOString(),
          state: "deleted",
          fields: link.baseline,
        };
      }
      if (event) remote.push(event);
    }
    const input = { task: originalTask, links, remote };
    const result = reconcile(input);
    const task = await store.accept(connection, input, result);
    if (!task) continue;
    let liveLink: LinkSnapshot | undefined = result.links[0];
    for (const effect of result.effects) {
      if (
        !(await store.prepareEffect(
          connection,
          task,
          effect.kind,
          effect.eventId,
        ))
      ) continue;
      if (effect.kind === "delete") {
        await adapter.delete(effect.eventId, effect.expectedVersion);
        await store.removeLink(connection, task.id);
        liveLink = undefined;
      } else {
        const written = await adapter.patch(
          effect.eventId,
          effect.expectedVersion,
          task,
        );
        const link = {
          ...links[0],
          version: written.version,
          baseline: written.fields,
        };
        await store.saveLink(connection, task, link);
      }
    }
    if (!liveLink && task.schedule && !task.deleted && !isUnsupported(remote)) {
      if (!(await store.prepareEffect(connection, task, "create"))) continue;
      const created = await adapter.create(task);
      await store.saveLink(connection, task, {
        taskId: task.id,
        connectionId: connection.id,
        provider: connection.provider,
        eventId: created.eventId,
        version: created.version,
        incarnation: task.incarnation,
        baseline: fieldsOf(task),
      });
    }
  }
  connection.state = { ...connection.state, ...adapter.cursorState?.() };
  await store.complete(connection);
}
function isUnsupported(events: AdapterEvent[]): boolean {
  return events.some((event) => event.state === "unsupported");
}

import {
  type Fields,
  fieldsOf,
  type TaskSnapshot,
} from "../_shared/calendar/reconcile.ts";
import type {
  AdapterEvent,
  CalendarAdapter,
  WriteResult,
} from "../_shared/calendar/worker.ts";
import type { RemoteHint } from "../_shared/calendar/work.ts";
import {
  GraphCalendarApi,
  GraphError,
  graphEventBody,
  graphEventFields,
  graphMetadata,
  type JsonMap,
} from "./graph_adapter.ts";
import { maintainSubscription } from "./outlook_subscriptions.ts";
export class OutlookAdapter implements CalendarAdapter {
  fullRead = true;
  private rename = false;
  constructor(
    readonly graph: GraphCalendarApi,
    readonly connectionId: string,
    public calendarId: string | null,
  ) {}
  async ensureCalendar(id: string | null): Promise<string> {
    const temporaryName = `Pomodoist (${this.connectionId})`;
    if (id) {
      const value = await this.graph.getCalendar(id);
      this.rename = value.name === temporaryName;
      return this.calendarId = id;
    }
    const calendars = await this.graph.pages("/me/calendars");
    const previous = calendars.find((calendar) =>
      calendar.name === temporaryName
    );
    const created = previous ??
      await this.graph.request("/me/calendars", {
        method: "POST",
        body: { name: temporaryName },
      });
    if (typeof created.id !== "string") {
      throw new Error("Missing Outlook calendar identity.");
    }
    this.rename = true;
    return this.calendarId = created.id;
  }
  async maintain(
    state: JsonMap,
    force = false,
  ): Promise<{ state: JsonMap; replaced: boolean }> {
    // The worker checkpoints the calendar ID before renaming, making creation recoverable.
    if (this.rename) {
      await this.graph.request(
        `/me/calendars/${encodeURIComponent(this.calendarId!)}`,
        { method: "PATCH", body: { name: "Pomodoist" } },
      );
    }
    const result = await maintainSubscription({
      id: typeof state.subscriptionId === "string"
        ? state.subscriptionId
        : null,
      expiresAt: !force && typeof state.subscriptionExpiresAt === "string"
        ? state.subscriptionExpiresAt
        : null,
      notificationUrl: String(state.notificationUrl),
      lifecycleUrl: String(state.lifecycleUrl),
      clientState: String(state.clientState),
      resource: "me/events",
    }, (path, options) => this.graph.request(path, options));
    return {
      state: {
        ...state,
        subscriptionId: result.state.id,
        subscriptionExpiresAt: result.state.expiresAt,
      },
      replaced: result.replaced,
    };
  }
  async read(): Promise<AdapterEvent[]> {
    return (await this.graph.listEvents(this.calendarId!)).map((event) =>
      this.normalized(event)
    );
  }
  async lookup(id: string, baseline: Fields): Promise<AdapterEvent | null> {
    let event: JsonMap;
    try {
      event = await this.graph.getEvent(id);
    } catch (error) {
      if (error instanceof GraphError && error.status === 404) {
        await this.graph.getCalendar(this.calendarId!);
        return null;
      }
      throw error;
    }
    const calendar = await this.graph.eventCalendar(id);
    if (calendar.id !== this.calendarId) {
      return {
        connectionId: this.connectionId,
        eventId: id,
        version: String(event["@odata.etag"] ?? ""),
        modifiedAt: String(event.lastModifiedDateTime),
        state: "unsupported",
        fields: baseline,
      };
    }
    return this.normalized(event, baseline);
  }
  async classifyHint(hint: RemoteHint): Promise<boolean> {
    let event: JsonMap;
    try {
      event = await this.graph.getEvent(hint.eventId);
    } catch (error) {
      if (error instanceof GraphError && error.status === 404) return false;
      throw error;
    }
    if (!graphMetadata(event)) return false;
    return (await this.graph.eventCalendar(hint.eventId)).id ===
      this.calendarId;
  }
  async create(task: TaskSnapshot): Promise<WriteResult> {
    const event = await this.graph.createEvent(
      this.calendarId!,
      task.id,
      task.incarnation,
      fieldsOf(task),
    );
    return {
      eventId: String(event.id),
      version: typeof event["@odata.etag"] === "string"
        ? event["@odata.etag"]
        : null,
      fields: fieldsOf(task),
    };
  }
  async patch(
    eventId: string,
    version: string | null,
    task: TaskSnapshot,
  ): Promise<WriteResult> {
    const event = await this.graph.patchEvent(
      this.calendarId!,
      eventId,
      graphEventBody(task.id, task.incarnation, fieldsOf(task)),
      version,
    );
    return {
      eventId,
      version: typeof event["@odata.etag"] === "string"
        ? event["@odata.etag"]
        : null,
      fields: fieldsOf(task),
    };
  }
  delete(eventId: string, version?: string | null): Promise<void> {
    return this.graph.deleteEvent(this.calendarId!, eventId, version);
  }
  private normalized(
    event: JsonMap,
    fallback: Fields = {
      content: "",
      description: null,
      status: "open",
      schedule: null,
    },
  ): AdapterEvent {
    const metadata = graphMetadata(event);
    let fields = fallback;
    let state: AdapterEvent["state"] = "active";
    try {
      fields = graphEventFields(event);
    } catch {
      state = "unsupported";
    }
    return {
      connectionId: this.connectionId,
      eventId: String(event.id),
      version: typeof event["@odata.etag"] === "string"
        ? event["@odata.etag"]
        : null,
      modifiedAt: String(event.lastModifiedDateTime ?? "1970-01-01T00:00:00Z"),
      state,
      fields,
      taskId: metadata?.taskId,
      incarnation: metadata?.incarnation,
    };
  }
}

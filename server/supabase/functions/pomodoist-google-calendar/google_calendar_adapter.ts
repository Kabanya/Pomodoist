import {
  type Fields,
  fieldsOf,
  type Schedule,
  type TaskSnapshot,
} from "../_shared/calendar/reconcile.ts";
import { randomToken, record, sha256 } from "../_shared/calendar/security.ts";
import type {
  AdapterEvent,
  CalendarAdapter,
  WriteResult,
} from "../_shared/calendar/worker.ts";
import { GraphError } from "../pomodoist-outlook-calendar/graph_adapter.ts";
import { shouldRenewWatch } from "./pomodoist_google_calendar.ts";
type Json = Record<string, unknown>;
export class GoogleAdapter implements CalendarAdapter {
  fullRead = true;
  private nextSyncToken: string | null = null;
  constructor(
    readonly accessToken: string,
    readonly connectionId: string,
    public calendarId: string | null,
    readonly state: Json,
    readonly webhookUrl: string,
    readonly http: typeof fetch = fetch,
  ) {}
  private path(suffix = ""): string {
    return `/calendars/${encodeURIComponent(this.calendarId!)}${suffix}`;
  }
  async request(
    path: string,
    options: { method?: string; body?: Json; version?: string | null } = {},
  ): Promise<Json> {
    const response = await this.http(
      `https://www.googleapis.com/calendar/v3${path}`,
      {
        method: options.method ?? "GET",
        redirect: "error",
        headers: {
          Authorization: `Bearer ${this.accessToken}`,
          ...(options.body ? { "Content-Type": "application/json" } : {}),
          ...(options.version ? { "If-Match": options.version } : {}),
        },
        body: options.body ? JSON.stringify(options.body) : undefined,
      },
    );
    if (!response.ok) {
      let status = response.status;
      if (status === 403) {
        const error = await response.json().catch(() => null);
        const reasons = record(error) && record(error.error) &&
            Array.isArray(error.error.errors)
          ? error.error.errors
          : [];
        if (
          reasons.some((reason) =>
            record(reason) &&
            ["rateLimitExceeded", "userRateLimitExceeded", "quotaExceeded"]
              .includes(String(reason.reason))
          )
        ) status = 429;
      } else await response.body?.cancel();
      throw new GraphError(
        status,
        Number(response.headers.get("Retry-After")) || 30,
      );
    }
    if (response.status === 204) return {};
    const value = await response.json();
    if (!record(value)) throw new Error("Invalid Google calendar response.");
    return value;
  }
  async ensureCalendar(id: string | null): Promise<string> {
    if (id) {
      await this.request(`/calendars/${encodeURIComponent(id)}`);
      return this.calendarId = id;
    }
    // A connection-specific description identifies calendars created before a lost response.
    const description = `Pomodoist connection ${this.connectionId}`;
    let page: string | null = null;
    do {
      const list = await this.request(
        `/users/me/calendarList?showHidden=true${
          page ? `&pageToken=${encodeURIComponent(page)}` : ""
        }`,
      );
      const owned = Array.isArray(list.items)
        ? list.items.find((item) =>
          item.description === description && item.accessRole === "owner" &&
          item.primary !== true
        )
        : null;
      if (owned) return this.calendarId = String(owned.id);
      page = typeof list.nextPageToken === "string" ? list.nextPageToken : null;
    } while (page);
    const created = await this.request("/calendars", {
      method: "POST",
      body: { summary: "Pomodoist", description },
    });
    if (typeof created.id !== "string") {
      throw new Error("Missing Google calendar identity.");
    }
    return this.calendarId = created.id;
  }
  async maintain(state: Json): Promise<{ state: Json; replaced: boolean }> {
    if (
      !shouldRenewWatch(
        typeof state.watchExpiresAt === "string" ? state.watchExpiresAt : null,
      )
    ) return { state, replaced: false };
    const token = randomToken();
    const channel = crypto.randomUUID();
    const watch = await this.request(this.path("/events/watch"), {
      method: "POST",
      body: {
        id: channel,
        type: "web_hook",
        address: this.webhookUrl,
        token,
        params: { ttl: "604800" },
      },
    });
    if (state.watchChannelId && state.watchResourceId) {
      await this.request("/channels/stop", {
        method: "POST",
        body: { id: state.watchChannelId, resourceId: state.watchResourceId },
      }).catch(() => undefined);
    }
    return {
      state: {
        ...state,
        watchChannelId: channel,
        watchResourceId: watch.resourceId,
        watchTokenHash: await sha256(token),
        watchExpiresAt: new Date(Number(watch.expiration)).toISOString(),
      },
      replaced: !state.watchChannelId,
    };
  }
  async read(): Promise<AdapterEvent[]> {
    let token = typeof this.state.syncToken === "string"
      ? this.state.syncToken
      : null;
    for (let attempt = 0; attempt < 2; attempt++) {
      const events: AdapterEvent[] = [];
      let page: string | null = null;
      this.fullRead = token === null;
      try {
        do {
          const query = new URLSearchParams({
            showDeleted: "true",
            maxResults: "2500",
          });
          if (token) query.set("syncToken", token);
          if (page) query.set("pageToken", page);
          const result = await this.request(this.path(`/events?${query}`));
          if (!Array.isArray(result.items)) {
            throw new Error("Incomplete Google listing.");
          }
          events.push(...result.items.map((event) => this.normalized(event)));
          page = typeof result.nextPageToken === "string"
            ? result.nextPageToken
            : null;
          if (typeof result.nextSyncToken === "string") {
            this.nextSyncToken = result.nextSyncToken;
          }
        } while (page);
        return events;
      } catch (error) {
        if (!(error instanceof GraphError) || error.status !== 410 || !token) {
          throw error;
        }
        token = null;
      }
    }
    throw new Error("Google sync cursor could not be recovered.");
  }
  cursorState(): Json {
    return { syncToken: this.nextSyncToken };
  }
  async lookup(
    eventId: string,
    baseline: Fields,
  ): Promise<AdapterEvent | null> {
    try {
      return this.normalized(
        await this.request(this.path(`/events/${encodeURIComponent(eventId)}`)),
        baseline,
      );
    } catch (error) {
      if (error instanceof GraphError && [404, 410].includes(error.status)) {
        await this.request(this.path());
        return null;
      }
      throw error;
    }
  }
  async classifyHint(): Promise<boolean> {
    return true;
  }
  async create(task: TaskSnapshot): Promise<WriteResult> {
    const id = await sha256(
      `${this.connectionId}:${task.id}:${task.incarnation}`,
    );
    let event: Json;
    try {
      event = await this.request(this.path("/events?sendUpdates=none"), {
        method: "POST",
        body: { ...googleBody(task), id },
      });
    } catch (error) {
      if (!(error instanceof GraphError) || error.status !== 409) throw error;
      event = await this.request(this.path(`/events/${id}`));
    }
    return {
      eventId: String(event.id),
      version: typeof event.etag === "string" ? event.etag : null,
      fields: fieldsOf(task),
    };
  }
  async patch(
    eventId: string,
    version: string | null,
    task: TaskSnapshot,
  ): Promise<WriteResult> {
    const event = await this.request(
      this.path(`/events/${encodeURIComponent(eventId)}?sendUpdates=none`),
      { method: "PATCH", version, body: googleBody(task) },
    );
    return {
      eventId,
      version: typeof event.etag === "string" ? event.etag : null,
      fields: fieldsOf(task),
    };
  }
  async delete(eventId: string, version?: string | null): Promise<void> {
    try {
      await this.request(
        this.path(`/events/${encodeURIComponent(eventId)}?sendUpdates=none`),
        { method: "DELETE", version },
      );
    } catch (error) {
      if (
        !(error instanceof GraphError) || ![404, 410].includes(error.status)
      ) throw error;
    }
  }
  normalized(
    event: Json,
    baseline: Fields = {
      content: "",
      description: null,
      status: "open",
      schedule: null,
    },
  ): AdapterEvent {
    const start = record(event.start) ? event.start : {};
    const end = record(event.end) ? event.end : {};
    const metadata = record(event.extendedProperties) &&
        record(event.extendedProperties.private)
      ? event.extendedProperties.private
      : {};
    let schedule: Schedule | null = null;
    if (typeof start.date === "string") {
      schedule = { type: "allDay", date: start.date };
    } else if (
      typeof start.dateTime === "string" && typeof end.dateTime === "string"
    ) {
      schedule = {
        type: "timed",
        start: new Date(start.dateTime).toISOString(),
        end: new Date(end.dateTime).toISOString(),
        ...(typeof start.timeZone === "string"
          ? { timeZone: start.timeZone }
          : {}),
      };
    }
    const title = typeof event.summary === "string"
      ? event.summary.trim()
      : baseline.content;
    return {
      connectionId: this.connectionId,
      eventId: String(event.id),
      version: typeof event.etag === "string" ? event.etag : null,
      modifiedAt: typeof event.updated === "string"
        ? event.updated
        : "1970-01-01T00:00:00Z",
      state: event.status === "cancelled"
        ? "deleted"
        : event.recurrence || !schedule
        ? "unsupported"
        : "active",
      fields: {
        content: title.replace(/^✓\s*/, ""),
        description: typeof event.description === "string" && event.description
          ? event.description
          : null,
        status: title.startsWith("✓") ? "completed" : "open",
        schedule,
      },
      taskId: typeof metadata.pomodoistTaskId === "string"
        ? metadata.pomodoistTaskId
        : undefined,
      incarnation: Number(metadata.pomodoistIncarnation ?? 1),
    };
  }
}
function googleBody(task: TaskSnapshot): Json {
  const s = task.schedule;
  if (!s) throw new Error("Task has no calendar schedule.");
  const timed = s.type === "timed";
  return {
    summary: task.status === "completed"
      ? `✓ ${task.content.replace(/^✓\s*/, "")}`
      : task.content.replace(/^✓\s*/, ""),
    description: task.description ?? "",
    start: timed
      ? { date: null, dateTime: s.start, timeZone: s.timeZone ?? null }
      : { date: s.date, dateTime: null, timeZone: null },
    end: timed
      ? { date: null, dateTime: s.end, timeZone: s.timeZone ?? null }
      : {
        date: new Date(Date.parse(`${s.date}T00:00:00Z`) + 86400000)
          .toISOString().slice(0, 10),
        dateTime: null,
        timeZone: null,
      },
    extendedProperties: {
      private: {
        pomodoistSource: "pomodoist",
        pomodoistTaskId: task.id,
        pomodoistIncarnation: String(task.incarnation),
      },
    },
  };
}

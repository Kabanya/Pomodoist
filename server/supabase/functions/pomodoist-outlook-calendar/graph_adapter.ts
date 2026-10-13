import type { Fields, Schedule } from "../_shared/calendar/reconcile.ts";
export type JsonMap = Record<string, unknown>;
export const taskProperty =
  "String {b5e88c8a-53b2-4e60-b9c4-f82a4b6678c1} Name PomodoistTask";
const expand =
  `$expand=singleValueExtendedProperties($filter=id eq '${taskProperty}')`;
const base = "https://graph.microsoft.com/v1.0";
export class GraphError extends Error {
  constructor(readonly status: number, readonly retrySeconds = 30) {
    super(`Microsoft Graph request failed (${status}).`);
  }
}
export class GraphCalendarApi {
  constructor(
    readonly accessToken: string,
    readonly http: typeof fetch = fetch,
  ) {}
  async request(
    path: string,
    options: { method?: string; body?: JsonMap; version?: string | null } = {},
  ): Promise<JsonMap> {
    const url = new URL(path.startsWith("https:") ? path : `${base}${path}`);
    if (
      url.origin !== "https://graph.microsoft.com" ||
      !url.pathname.startsWith("/v1.0/") || url.username || url.password ||
      url.hash
    ) throw new Error("Invalid Graph paging destination.");
    const response = await this.http(url, {
      method: options.method ?? "GET",
      redirect: "error",
      headers: {
        Authorization: `Bearer ${this.accessToken}`,
        Prefer:
          'IdType="ImmutableId", outlook.timezone="UTC", outlook.body-content-type="text"',
        ...(options.body ? { "Content-Type": "application/json" } : {}),
        ...(options.version ? { "If-Match": options.version } : {}),
      },
      body: options.body ? JSON.stringify(options.body) : undefined,
    });
    if (!response.ok) {
      const retry = response.headers.get("Retry-After");
      const seconds = retry && /^\d+$/.test(retry)
        ? Number(retry)
        : retry
        ? Math.ceil((Date.parse(retry) - Date.now()) / 1000)
        : 30;
      await response.body?.cancel();
      throw new GraphError(
        response.status,
        Number.isFinite(seconds) ? Math.max(1, seconds) : 30,
      );
    }
    if (response.status === 204) return {};
    const value = await response.json();
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      throw new Error("Invalid Graph response.");
    }
    return value;
  }
  async pages(path: string): Promise<JsonMap[]> {
    const result: JsonMap[] = [];
    const visited = new Set<string>();
    let next: string | null = path;
    while (next) {
      if (visited.has(next) || visited.size >= 10000) {
        throw new Error("Invalid Graph paging cycle.");
      }
      visited.add(next);
      const page = await this.request(next);
      if (!Array.isArray(page.value)) {
        throw new Error("Incomplete Graph event listing.");
      }
      result.push(...page.value as JsonMap[]);
      next = typeof page["@odata.nextLink"] === "string"
        ? page["@odata.nextLink"]
        : null;
    }
    return result;
  }
  listEvents(calendarId: string): Promise<JsonMap[]> {
    return this.pages(
      `/me/calendars/${
        encodeURIComponent(calendarId)
      }/events?$top=250&${expand}`,
    );
  }
  getEvent(eventId: string): Promise<JsonMap> {
    return this.request(`/me/events/${encodeURIComponent(eventId)}?${expand}`);
  }
  getCalendar(calendarId: string): Promise<JsonMap> {
    return this.request(`/me/calendars/${encodeURIComponent(calendarId)}`);
  }
  eventCalendar(eventId: string): Promise<JsonMap> {
    return this.request(`/me/events/${encodeURIComponent(eventId)}/calendar`);
  }
  createCalendar(): Promise<JsonMap> {
    return this.request("/me/calendars", {
      method: "POST",
      body: { name: "Pomodoist" },
    });
  }
  patchEvent(
    calendarId: string,
    eventId: string,
    body: JsonMap,
    version: string | null,
  ): Promise<JsonMap> {
    return this.request(
      `/me/calendars/${encodeURIComponent(calendarId)}/events/${
        encodeURIComponent(eventId)
      }`,
      { method: "PATCH", body, version },
    );
  }
  async deleteEvent(
    calendarId: string,
    eventId: string,
    version?: string | null,
  ): Promise<void> {
    try {
      await this.request(
        `/me/calendars/${encodeURIComponent(calendarId)}/events/${
          encodeURIComponent(eventId)
        }`,
        { method: "DELETE", version },
      );
    } catch (error) {
      if (!(error instanceof GraphError) || error.status !== 404) throw error;
    }
  }
  createEvent(
    calendarId: string,
    taskId: string,
    incarnation: number,
    fields: Fields,
  ): Promise<JsonMap> {
    return this.request(
      `/me/calendars/${encodeURIComponent(calendarId)}/events`,
      {
        method: "POST",
        body: {
          ...graphEventBody(taskId, incarnation, fields),
          transactionId: `pomodoist:${calendarId}:${taskId}:${incarnation}`,
        },
      },
    );
  }
}
export function graphEventBody(
  taskId: string,
  incarnation: number,
  fields: Fields,
): JsonMap {
  const schedule = fields.schedule;
  if (!schedule) {
    throw new Error("Cannot create an unscheduled calendar event.");
  }
  const allDay = schedule.type === "allDay";
  const start = allDay ? `${schedule.date}T00:00:00` : schedule.start;
  const end = allDay
    ? `${
      new Date(Date.parse(`${schedule.date}T00:00:00Z`) + 86400000)
        .toISOString().slice(0, 10)
    }T00:00:00`
    : schedule.end;
  return {
    subject: fields.status === "completed"
      ? `✓ ${fields.content.replace(/^✓\s*/, "")}`
      : fields.content.replace(/^✓\s*/, ""),
    body: { contentType: "text", content: fields.description ?? "" },
    isAllDay: allDay,
    start: { dateTime: start.replace(/Z$/, ""), timeZone: "UTC" },
    end: { dateTime: end.replace(/Z$/, ""), timeZone: "UTC" },
    singleValueExtendedProperties: [{
      id: taskProperty,
      value: JSON.stringify({
        taskId,
        incarnation,
        timeZone: schedule.type === "timed" ? schedule.timeZone ?? "UTC" : null,
      }),
    }],
  };
}
export function graphMetadata(
  event: JsonMap,
): { taskId: string; incarnation: number; timeZone?: string } | null {
  const properties = event.singleValueExtendedProperties;
  if (!Array.isArray(properties)) return null;
  const value = properties.find((p) => p?.id === taskProperty)?.value;
  if (typeof value !== "string") return null;
  try {
    const parsed = JSON.parse(value);
    return typeof parsed.taskId === "string" &&
        Number.isSafeInteger(parsed.incarnation)
      ? parsed
      : null;
  } catch {
    return null;
  }
}
export function graphEventFields(event: JsonMap): Fields {
  if (event.recurrence || (event.type && event.type !== "singleInstance")) {
    throw new Error("Recurring Outlook events are not supported.");
  }
  const start = event.start as
    | { dateTime?: string; timeZone?: string }
    | undefined;
  const end = event.end as { dateTime?: string; timeZone?: string } | undefined;
  if (!start?.dateTime || !end?.dateTime) {
    throw new Error("Outlook event has no valid schedule.");
  }
  let schedule: Schedule;
  if (event.isAllDay === true) {
    schedule = { type: "allDay", date: start.dateTime.slice(0, 10) };
  } else {
    const instant = (value: string, zone?: string) => {
      if (
        !/(Z|[+-]\d\d:\d\d)$/.test(value) && zone !== "UTC" &&
        zone !== "Etc/UTC"
      ) throw new Error("Expected UTC Graph response.");
      return new Date(/(Z|[+-]\d\d:\d\d)$/.test(value) ? value : `${value}Z`)
        .toISOString();
    };
    schedule = {
      type: "timed",
      start: instant(start.dateTime, start.timeZone),
      end: instant(end.dateTime, end.timeZone),
      timeZone: graphMetadata(event)?.timeZone ?? "UTC",
    };
    if (Date.parse(schedule.end) <= Date.parse(schedule.start)) {
      throw new Error("Invalid Outlook event duration.");
    }
  }
  const title = typeof event.subject === "string" ? event.subject.trim() : "";
  const body = event.body as
    | { content?: string; contentType?: string }
    | undefined;
  if (body?.contentType?.toLowerCase() === "html") {
    throw new Error("Expected plain-text Graph body.");
  }
  return {
    content: title.replace(/^✓\s*/, ""),
    description: body?.content || null,
    status: title.startsWith("✓") ? "completed" : "open",
    schedule,
  };
}

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { createClient } from "npm:@supabase/supabase-js@2";

import {
  calendarFailurePayload,
  type CalendarTask,
  GoogleCalendarHttpError,
  type GoogleEvent,
  handlePomodoistGoogleCalendar,
  processWorkerBatch,
  pullWithExpiredSyncTokenRetry,
  reconcileCalendar,
  reusablePomodoistCalendar,
  shouldRenewWatch,
  type StoredCalendarLink,
} from "./pomodoist_google_calendar.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const oauthClientId = Deno.env.get("GOOGLE_CALENDAR_CLIENT_ID") ?? "";
const oauthClientSecret = Deno.env.get("GOOGLE_CALENDAR_CLIENT_SECRET") ?? "";
const functionUrl = Deno.env.get("GOOGLE_CALENDAR_FUNCTION_URL") ??
  `${supabaseUrl}/functions/v1/pomodoist-google-calendar`;
const appRedirectUri = Deno.env.get("GOOGLE_CALENDAR_APP_REDIRECT_URI") ??
  "pomodoist://google-calendar-connected";
const webhookUrl = Deno.env.get("GOOGLE_CALENDAR_WEBHOOK_URL") ?? functionUrl;
const workerSecret = Deno.env.get("GOOGLE_CALENDAR_WORKER_SECRET") ?? "";
const admin = createClient(supabaseUrl, serviceRoleKey);

Deno.serve((req) =>
  handlePomodoistGoogleCalendar(req, {
    oauthClientId,
    oauthConfigured: oauthClientId.length > 0 && oauthClientSecret.length > 0,
    redirectUri: functionUrl,
    appRedirectUri,
    workerSecret,
    authenticate: async (authorization) => {
      const client = createClient(supabaseUrl, anonKey, {
        global: { headers: { Authorization: authorization } },
      });
      const { data: { user }, error } = await client.auth.getUser();
      return error == null && user != null ? { id: user.id } : null;
    },
    storeOAuthState: async (input) => {
      await rpc("store_oauth_state", input.userId, input);
    },
    consumeOAuthState: async (stateHash) => {
      const value = await rpc("consume_oauth_state", null, { stateHash });
      return isRecord(value) && typeof value.userId === "string" &&
          typeof value.codeVerifier === "string"
        ? { userId: value.userId, codeVerifier: value.codeVerifier }
        : null;
    },
    exchangeOAuthCode: exchangeOAuthCode,
    configureWorker,
    connect: async (input) => {
      await rpc("connect", input.userId, { refreshToken: input.refreshToken });
    },
    queue: async (userId) => {
      await rpc("queue", userId, {});
    },
    disconnect: async (userId) => {
      const value = await rpc("disconnect", userId, {});
      if (isRecord(value) && typeof value.refreshToken === "string") {
        await fetch("https://oauth2.googleapis.com/revoke", {
          method: "POST",
          headers: { "Content-Type": "application/x-www-form-urlencoded" },
          body: new URLSearchParams({ token: value.refreshToken }),
        }).catch(() => undefined);
      }
    },
    queueWebhook: async (input) => {
      const value = await rpc("webhook", null, input);
      return isRecord(value) && value.accepted === true;
    },
    runWorker,
  })
);

async function configureWorker() {
  if (
    oauthClientId.length === 0 || oauthClientSecret.length === 0 ||
    workerSecret.length === 0 || !functionUrl.startsWith("https://") ||
    !webhookUrl.startsWith("https://")
  ) {
    throw new Error("Google Calendar worker configuration is incomplete.");
  }
  await rpc("configure_worker", null, { functionUrl, workerSecret });
}

async function runWorker() {
  await configureWorker();
  const claimed = await rpc("claim", null, { limit: 10 });
  if (!Array.isArray(claimed)) {
    throw new Error("Invalid calendar claim response.");
  }
  const accounts = claimed.filter((raw): raw is JsonMap =>
    isRecord(raw) && typeof raw.userId === "string"
  );
  return processWorkerBatch(
    accounts,
    processAccount,
    async (raw, error) => {
      await rpc("fail", string(raw.userId), calendarFailurePayload(raw, error));
    },
  );
}

async function processAccount(raw: JsonMap) {
  const userId = string(raw.userId);
  const refreshToken = string(raw.refreshToken);
  if (userId == null || refreshToken == null) {
    throw new Error("Calendar credential is missing.");
  }
  const token = await refreshAccessToken(refreshToken);
  const google = new GoogleCalendarApi(token.accessToken);
  const ensured = await google.ensureCalendar(string(raw.calendarId));
  const listed = await google.listEvents(
    ensured.id,
    ensured.recreated ? null : string(raw.syncToken),
  );
  const tasks = arrayOfRecords(raw.tasks).map(normalizeTask).filter(notNull);
  const links = ensured.recreated
    ? []
    : arrayOfRecords(raw.links).map(normalizeLink).filter(notNull);
  const reconciled = await reconcileCalendar(
    {
      userId,
      calendarId: ensured.id,
      tasks,
      links,
      fullSync: listed.fullSync,
    },
    {
      events: listed.events,
      insertEvent: (body) => google.insertEvent(ensured.id, body),
      patchEvent: (eventId, body, etag) =>
        google.patchEvent(ensured.id, eventId, body, etag),
      deleteEvent: (eventId) => google.deleteEvent(ensured.id, eventId),
    },
  );
  const now = new Date().toISOString();
  const watch = await google.ensureWatch({
    calendarId: ensured.id,
    currentChannelId: string(raw.watchChannelId),
    currentResourceId: string(raw.watchResourceId),
    currentExpiresAt: string(raw.watchExpiresAt),
  });
  const operations: JsonMap[] = [...reconciled.operations];
  if (raw.status !== "connected" || ensured.recreated) {
    operations.push(
      connectionOperation(raw, ensured, listed.nextSyncToken, now),
    );
  }
  operations.push(
    ...reconciled.changedLinks.map((link) => linkOperation(link, now)),
  );
  operations.push(...reconciled.removedTaskIds.map((taskId) => ({
    opId: `google-calendar:link-delete:${taskId}:${now}`,
    entityType: "google_calendar_event_link",
    entityId: taskId,
    operation: "delete" as const,
    payload: {},
    clientUpdatedAt: now,
  })));
  await rpc("complete", userId, {
    claimedGeneration: raw.claimedGeneration,
    account: {
      calendarId: ensured.id,
      calendarName: ensured.summary,
      syncToken: listed.nextSyncToken,
      ...(token.refreshToken == null
        ? {}
        : { refreshToken: token.refreshToken }),
      ...(watch == null ? {} : watch),
    },
    links: reconciled.changedLinks,
    removedTaskIds: reconciled.removedTaskIds,
    operations,
  });
}

async function exchangeOAuthCode(code: string, codeVerifier: string) {
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: oauthClientId,
      client_secret: oauthClientSecret,
      code,
      code_verifier: codeVerifier,
      grant_type: "authorization_code",
      redirect_uri: functionUrl,
    }),
  });
  const value = await jsonResponse(response);
  const refreshToken = string(value.refresh_token);
  const accessToken = string(value.access_token);
  if (!response.ok || refreshToken == null || accessToken == null) {
    throw new Error("Could not exchange the Google authorization code.");
  }
  return {
    refreshToken,
    accessToken,
    expiresIn: number(value.expires_in) ?? 3600,
  };
}

async function refreshAccessToken(refreshToken: string) {
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: oauthClientId,
      client_secret: oauthClientSecret,
      refresh_token: refreshToken,
      grant_type: "refresh_token",
    }),
  });
  const value = await jsonResponse(response);
  const accessToken = string(value.access_token);
  if (!response.ok || accessToken == null) {
    throw new Error("Google Calendar authorization expired.");
  }
  return { accessToken, refreshToken: string(value.refresh_token) };
}

class GoogleCalendarApi {
  constructor(private readonly accessToken: string) {}

  async ensureCalendar(calendarId: string | null) {
    if (calendarId != null) {
      try {
        const value = await this.request(
          `/calendars/${encodeURIComponent(calendarId)}`,
        );
        return {
          id: string(value.id)!,
          summary: string(value.summary) ?? "Pomodoist",
          recreated: false,
        };
      } catch (error) {
        if (
          !(error instanceof GoogleCalendarHttpError) || error.status !== 404
        ) throw error;
      }
    }
    try {
      const list = await this.request(
        "/users/me/calendarList?minAccessRole=writer&showHidden=true",
      );
      const reusable = reusablePomodoistCalendar(arrayOfRecords(list.items));
      if (reusable != null) {
        const reusableId = string(reusable.id)!;
        return {
          id: reusableId,
          summary: string(reusable.summary) ?? "Pomodoist",
          recreated: calendarId != null && reusableId !== calendarId,
        };
      }
    } catch (error) {
      if (
        !(error instanceof GoogleCalendarHttpError) || error.status !== 403
      ) throw error;
    }
    const value = await this.request("/calendars", {
      method: "POST",
      body: { summary: "Pomodoist" },
    });
    return {
      id: string(value.id)!,
      summary: string(value.summary) ?? "Pomodoist",
      recreated: true,
    };
  }

  async listEvents(calendarId: string, syncToken: string | null) {
    return pullWithExpiredSyncTokenRetry(
      syncToken,
      (token) => this.listPages(calendarId, token),
    );
  }

  async insertEvent(calendarId: string, body: JsonMap) {
    return await this.request(
      `/calendars/${encodeURIComponent(calendarId)}/events?sendUpdates=none`,
      { method: "POST", body },
    ) as GoogleEvent;
  }

  async patchEvent(
    calendarId: string,
    eventId: string,
    body: JsonMap,
    etag: string | null,
  ) {
    return await this.request(
      `/calendars/${encodeURIComponent(calendarId)}/events/${
        encodeURIComponent(eventId)
      }?sendUpdates=none`,
      { method: "PATCH", body, etag },
    ) as GoogleEvent;
  }

  async deleteEvent(calendarId: string, eventId: string) {
    try {
      await this.request(
        `/calendars/${encodeURIComponent(calendarId)}/events/${
          encodeURIComponent(eventId)
        }?sendUpdates=none`,
        { method: "DELETE" },
      );
    } catch (error) {
      if (
        !(error instanceof GoogleCalendarHttpError) ||
        ![404, 410].includes(error.status)
      ) throw error;
    }
  }

  async ensureWatch(input: {
    calendarId: string;
    currentChannelId: string | null;
    currentResourceId: string | null;
    currentExpiresAt: string | null;
  }) {
    if (!shouldRenewWatch(input.currentExpiresAt)) return null;
    if (input.currentChannelId != null && input.currentResourceId != null) {
      await this.request("/channels/stop", {
        method: "POST",
        body: {
          id: input.currentChannelId,
          resourceId: input.currentResourceId,
        },
      }).catch(() => undefined);
    }
    const token = randomToken();
    const channelId = crypto.randomUUID();
    const value = await this.request(
      `/calendars/${encodeURIComponent(input.calendarId)}/events/watch`,
      {
        method: "POST",
        body: {
          id: channelId,
          type: "web_hook",
          address: webhookUrl,
          token,
          params: { ttl: "604800" },
        },
      },
    );
    return {
      watchChannelId: channelId,
      watchResourceId: string(value.resourceId),
      watchTokenHash: await sha256(token),
      watchExpiresAt: new Date(Number(value.expiration)).toISOString(),
    };
  }

  private async listPages(calendarId: string, syncToken: string | null) {
    const events: GoogleEvent[] = [];
    let pageToken: string | null = null;
    let nextSyncToken: string | null = null;
    do {
      const query = new URLSearchParams({
        showDeleted: "true",
        maxResults: "2500",
      });
      if (syncToken != null) query.set("syncToken", syncToken);
      if (pageToken != null) query.set("pageToken", pageToken);
      const value = await this.request(
        `/calendars/${encodeURIComponent(calendarId)}/events?${query}`,
      );
      events.push(...arrayOfRecords(value.items) as GoogleEvent[]);
      pageToken = string(value.nextPageToken);
      nextSyncToken = string(value.nextSyncToken) ?? nextSyncToken;
    } while (pageToken != null);
    return { events, nextSyncToken, fullSync: syncToken == null };
  }

  private async request(
    path: string,
    options: { method?: string; body?: JsonMap; etag?: string | null } = {},
  ): Promise<JsonMap> {
    const response = await fetch(
      `https://www.googleapis.com/calendar/v3${path}`,
      {
        method: options.method ?? "GET",
        headers: {
          Authorization: `Bearer ${this.accessToken}`,
          ...(options.body == null
            ? {}
            : { "Content-Type": "application/json" }),
          ...(options.etag == null ? {} : { "If-Match": options.etag }),
        },
        body: options.body == null ? undefined : JSON.stringify(options.body),
      },
    );
    if (!response.ok) {
      const message = await response.text();
      throw new GoogleCalendarHttpError(response.status, message.slice(0, 500));
    }
    if (response.status === 204) return {};
    const value = await response.json();
    if (!isRecord(value)) {
      throw new Error("Google Calendar returned invalid JSON.");
    }
    return value;
  }
}

function connectionOperation(
  raw: JsonMap,
  calendar: { id: string; summary: string },
  syncToken: string | null,
  now: string,
) {
  return {
    opId: `google-calendar:connection:${calendar.id}:${now}`,
    entityType: "google_calendar_connection" as const,
    entityId: "primary",
    operation: "upsert" as const,
    payload: {
      id: "primary",
      accountEmail: raw.accountEmail ?? null,
      calendarId: calendar.id,
      ownerDeviceId: null,
      calendarName: calendar.summary,
      syncToken,
      status: "connected",
      lastError: null,
      warning: null,
      lastSyncStartedAt: raw.lastSyncStartedAt ?? now,
      lastSyncFinishedAt: now,
      createdAt: raw.createdAt ?? now,
      updatedAt: now,
    },
    clientUpdatedAt: now,
  };
}

function linkOperation(link: StoredCalendarLink, now: string) {
  return {
    opId: `google-calendar:link:${link.taskId}:${link.etag ?? link.eventId}`,
    entityType: "google_calendar_event_link" as const,
    entityId: link.taskId,
    operation: "upsert" as const,
    payload: {
      taskId: link.taskId,
      calendarId: link.calendarId,
      eventId: link.eventId,
      etag: link.etag,
      googleUpdatedAt: link.googleUpdatedAt,
      lastSyncedLocalUpdatedAt: link.localScheduleUpdatedAt,
      unsupportedReason: link.unsupportedReason,
      createdAt: link.createdAt,
      updatedAt: now,
    },
    clientUpdatedAt: now,
  };
}

function normalizeTask(value: JsonMap): CalendarTask | null {
  const id = string(value.id);
  const updatedAt = string(value.updatedAt) ?? string(value._clientUpdatedAt);
  if (id == null || updatedAt == null || typeof value.content !== "string") {
    return null;
  }
  return {
    ...value,
    id,
    content: value.content,
    dueJson: string(value.dueJson),
    updatedAt,
    _clientUpdatedAt: string(value._clientUpdatedAt) ?? updatedAt,
    _localScheduleUpdatedAt: string(value._localScheduleUpdatedAt) ?? updatedAt,
    isDeleted: value.isDeleted === true || value._deletedAt != null,
  };
}

function normalizeLink(value: JsonMap): StoredCalendarLink | null {
  const taskId = string(value.taskId) ?? string(value.task_id);
  const eventId = string(value.eventId) ?? string(value.event_id);
  const calendarId = string(value.calendarId) ?? string(value.calendar_id);
  const localUpdated = string(value.localScheduleUpdatedAt) ??
    string(value.local_schedule_updated_at);
  const createdAt = string(value.createdAt) ?? string(value.created_at);
  if (
    [taskId, eventId, calendarId, localUpdated, createdAt].some((value) =>
      value == null
    )
  ) return null;
  return {
    taskId: taskId!,
    eventId: eventId!,
    calendarId: calendarId!,
    etag: string(value.etag),
    googleUpdatedAt: string(value.googleUpdatedAt) ??
      string(value.google_updated_at),
    localScheduleUpdatedAt: localUpdated!,
    lastScheduleFingerprint: string(value.lastScheduleFingerprint) ??
      string(value.last_schedule_fingerprint),
    unsupportedReason: string(value.unsupportedReason) ??
      string(value.unsupported_reason),
    createdAt: createdAt!,
  };
}

async function rpc(action: string, userId: string | null, payload: JsonMap) {
  const { data, error } = await admin.rpc("pomodoist_google_calendar_service", {
    p_action: action,
    p_user_id: userId,
    p_payload: payload,
  });
  if (error) throw new Error(error.message);
  return data;
}

async function jsonResponse(response: Response) {
  try {
    const value = await response.json();
    return isRecord(value) ? value : {};
  } catch {
    return {};
  }
}

function randomToken() {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes)).replaceAll("+", "-").replaceAll(
    "/",
    "_",
  ).replace(/=+$/, "");
}

async function sha256(value: string) {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest)).map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

type JsonMap = Record<string, unknown>;
function isRecord(value: unknown): value is JsonMap {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
function arrayOfRecords(value: unknown) {
  return Array.isArray(value) ? value.filter(isRecord) : [];
}
function string(value: unknown) {
  return typeof value === "string" && value.length > 0 ? value : null;
}
function number(value: unknown) {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}
function notNull<T>(value: T | null): value is T {
  return value != null;
}

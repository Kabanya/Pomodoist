import { readLimitedJson } from "../_shared/limited_json.ts";

const calendarScope = "https://www.googleapis.com/auth/calendar.app.created";
const maxBodyBytes = 16_384;

type JsonMap = Record<string, unknown>;

export type OAuthStateInput = {
  userId: string;
  stateHash: string;
  codeVerifier: string;
  expiresAt: string;
};

export type WorkerRunResult = {
  claimed: number;
  succeeded: number;
  failed: number;
};

export type GoogleCalendarDeps = {
  oauthClientId: string;
  oauthConfigured: boolean;
  redirectUri: string;
  appRedirectUri: string;
  workerSecret?: string;
  authenticate: (authorization: string) => Promise<{ id: string } | null>;
  storeOAuthState: (input: OAuthStateInput) => Promise<void>;
  consumeOAuthState: (
    stateHash: string,
  ) => Promise<{ userId: string; codeVerifier: string } | null>;
  exchangeOAuthCode: (
    code: string,
    codeVerifier: string,
  ) => Promise<
    { refreshToken: string; accessToken: string; expiresIn: number }
  >;
  configureWorker: () => Promise<void>;
  connect: (input: {
    userId: string;
    refreshToken: string;
    accessToken: string;
    expiresIn: number;
  }) => Promise<void>;
  queue: (userId: string) => Promise<void>;
  disconnect: (userId: string) => Promise<void>;
  queueWebhook: (input: {
    channelId: string;
    resourceId: string;
    tokenHash: string;
  }) => Promise<boolean>;
  runWorker: () => Promise<WorkerRunResult>;
  randomBytes?: (length: number) => Uint8Array;
  now?: () => Date;
};

export async function handlePomodoistGoogleCalendar(
  req: Request,
  deps: GoogleCalendarDeps,
) {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  const url = new URL(req.url);
  if (req.method === "GET") return oauthCallback(url, deps);
  if (req.method !== "POST") return json({ error: "Method not allowed." }, 405);
  if (req.headers.has("X-Goog-Channel-ID")) return webhook(req, deps);
  if (req.headers.has("X-Pomodoist-Worker-Secret")) {
    if (
      !constantTimeEqual(
        req.headers.get("X-Pomodoist-Worker-Secret") ?? "",
        deps.workerSecret ?? "",
      )
    ) {
      return json({ error: "Unauthorized." }, 401);
    }
    try {
      return json(await deps.runWorker());
    } catch (_) {
      return json({ error: "Google Calendar worker is unavailable." }, 503);
    }
  }

  const authorization = req.headers.get("Authorization") ?? "";
  const user = authorization.length > 0
    ? await deps.authenticate(authorization)
    : null;
  if (user == null) return json({ error: "Authentication required." }, 401);
  const parsed = await readLimitedJson(req, maxBodyBytes);
  if (!parsed.ok) return json({ error: parsed.error }, parsed.status);
  if (!isRecord(parsed.value)) return json({ error: "Invalid request." }, 400);

  switch (parsed.value.action) {
    case "start":
      return startOAuth(user.id, deps);
    case "sync":
      await deps.configureWorker();
      await deps.queue(user.id);
      return json({ queued: true });
    case "disconnect":
      await deps.disconnect(user.id);
      return json({ disconnected: true });
    default:
      return json({ error: "Unsupported action." }, 400);
  }
}

export async function processWorkerBatch<T>(
  accounts: T[],
  process: (account: T) => Promise<void>,
  fail: (account: T, error: unknown) => Promise<void>,
): Promise<WorkerRunResult> {
  const settled = await Promise.allSettled(accounts.map(process));
  let failed = 0;
  for (let index = 0; index < settled.length; index++) {
    const result = settled[index];
    if (result.status === "fulfilled") continue;
    failed++;
    await fail(accounts[index], result.reason);
  }
  return {
    claimed: accounts.length,
    succeeded: accounts.length - failed,
    failed,
  };
}

async function startOAuth(userId: string, deps: GoogleCalendarDeps) {
  if (
    !deps.oauthConfigured ||
    deps.oauthClientId.trim().length === 0 ||
    deps.redirectUri.trim().length === 0
  ) {
    return json({ error: "Google Calendar is not configured." }, 503);
  }
  const random = deps.randomBytes ??
    ((length: number) => crypto.getRandomValues(new Uint8Array(length)));
  const state = base64Url(random(32));
  const verifier = base64Url(random(64));
  const challenge = base64Url(await digest(verifier));
  const expiresAt = new Date(
    (deps.now?.() ?? new Date()).getTime() + 10 * 60_000,
  );
  await deps.storeOAuthState({
    userId,
    stateHash: await sha256(state),
    codeVerifier: verifier,
    expiresAt: expiresAt.toISOString(),
  });
  const url = new URL("https://accounts.google.com/o/oauth2/v2/auth");
  url.search = new URLSearchParams({
    client_id: deps.oauthClientId,
    redirect_uri: deps.redirectUri,
    response_type: "code",
    scope: calendarScope,
    access_type: "offline",
    prompt: "consent",
    include_granted_scopes: "true",
    state,
    code_challenge: challenge,
    code_challenge_method: "S256",
  }).toString();
  return json({ authorizationUrl: url.toString() });
}

async function oauthCallback(url: URL, deps: GoogleCalendarDeps) {
  const code = url.searchParams.get("code") ?? "";
  const state = url.searchParams.get("state") ?? "";
  if (code.length === 0 || state.length === 0) {
    return json({ error: "Invalid OAuth callback." }, 400);
  }
  const pending = await deps.consumeOAuthState(await sha256(state));
  if (pending == null) {
    return json({ error: "OAuth state expired or was already used." }, 400);
  }
  const tokens = await deps.exchangeOAuthCode(code, pending.codeVerifier);
  if (tokens.refreshToken.length === 0) {
    return json({ error: "Google did not return offline access." }, 400);
  }
  await deps.configureWorker();
  await deps.connect({ userId: pending.userId, ...tokens });
  return Response.redirect(deps.appRedirectUri, 302);
}

async function webhook(req: Request, deps: GoogleCalendarDeps) {
  const channelId = req.headers.get("X-Goog-Channel-ID") ?? "";
  const resourceId = req.headers.get("X-Goog-Resource-ID") ?? "";
  const token = req.headers.get("X-Goog-Channel-Token") ?? "";
  if (channelId.length === 0 || resourceId.length === 0 || token.length === 0) {
    return json({ error: "Invalid Google webhook." }, 401);
  }
  const accepted = await deps.queueWebhook({
    channelId,
    resourceId,
    tokenHash: await sha256(token),
  });
  return accepted
    ? new Response(null, { status: 204 })
    : json({ error: "Unauthorized." }, 401);
}

export type CalendarLink = {
  taskId: string;
  eventId: string;
  createdAt: string;
};

export function canonicalLinkForEvent(eventId: string, links: CalendarLink[]) {
  return links
    .filter((link) => link.eventId === eventId)
    .toSorted((a, b) =>
      a.createdAt.localeCompare(b.createdAt) || a.taskId.localeCompare(b.taskId)
    )[0];
}

export function reusablePomodoistCalendar(items: JsonMap[]) {
  return items
    .filter((item) =>
      item.primary !== true && item.deleted !== true &&
      item.summary === "Pomodoist" && typeof item.id === "string"
    )
    .toSorted((a, b) => String(a.id).localeCompare(String(b.id)))[0];
}

export function resolveScheduleConflict(input: {
  lastScheduleFingerprint: string | null;
  localScheduleFingerprint: string | null;
  googleScheduleFingerprint: string | null;
  localScheduleChangedAt: string;
  googleUpdatedAt: string;
}): "local" | "google" | "same" {
  if (input.localScheduleFingerprint === input.googleScheduleFingerprint) {
    return "same";
  }
  const localChanged =
    input.localScheduleFingerprint !== input.lastScheduleFingerprint;
  const googleChanged =
    input.googleScheduleFingerprint !== input.lastScheduleFingerprint;
  if (localChanged && !googleChanged) return "local";
  if (googleChanged && !localChanged) return "google";
  return Date.parse(input.localScheduleChangedAt) >
      Date.parse(input.googleUpdatedAt)
    ? "local"
    : "google";
}

export async function syncCalendarAccount<T>(
  account: T,
  deps: {
    pullGoogle: (
      account: T,
    ) => Promise<{ events: unknown[]; nextSyncToken: string | null }>;
    applyPulledEvents: (account: T, events: unknown[]) => Promise<void>;
    pushLocalTasks: (account: T) => Promise<void>;
  },
) {
  const pulled = await deps.pullGoogle(account);
  await deps.applyPulledEvents(account, pulled.events);
  await deps.pushLocalTasks(account);
  return pulled.nextSyncToken;
}

export type CalendarTask = JsonMap & {
  id: string;
  content: string;
  dueJson: string | null;
  updatedAt: string;
  _clientUpdatedAt: string;
  _localScheduleUpdatedAt: string;
};

export type StoredCalendarLink = CalendarLink & {
  calendarId: string;
  etag: string | null;
  googleUpdatedAt: string | null;
  localScheduleUpdatedAt: string;
  lastScheduleFingerprint: string | null;
  unsupportedReason: string | null;
};

export type GoogleEvent = JsonMap & {
  id: string;
  status?: string;
  summary?: string;
  description?: string;
  etag?: string;
  updated?: string;
  start?: JsonMap;
  end?: JsonMap;
  recurrence?: unknown[];
  extendedProperties?: { private?: Record<string, string> };
};

export type CalendarOperation = {
  opId: string;
  entityType: "task";
  entityId: string;
  operation: "upsert";
  payload: JsonMap;
  clientUpdatedAt: string;
};

export type CalendarReconcileApi = {
  events: GoogleEvent[];
  insertEvent: (body: JsonMap) => Promise<GoogleEvent>;
  patchEvent: (
    eventId: string,
    body: JsonMap,
    etag: string | null,
  ) => Promise<GoogleEvent>;
  deleteEvent: (eventId: string) => Promise<void>;
};

export class GoogleCalendarHttpError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
  }
}

export function calendarFailurePayload(raw: JsonMap, error: unknown) {
  const precondition = error instanceof GoogleCalendarHttpError &&
    error.status === 412;
  const attempts = typeof raw.attempts === "number" ? raw.attempts : 0;
  return {
    ...(raw.claimedGeneration == null
      ? {}
      : { claimedGeneration: raw.claimedGeneration }),
    error: error instanceof Error ? error.message : `${error}`,
    retrySeconds: precondition
      ? 5
      : Math.min(3600, 30 * 2 ** Math.min(attempts, 7)),
    ...(precondition ? { transientConflict: true } : {}),
  };
}

export async function pullWithExpiredSyncTokenRetry<T>(
  syncToken: string | null,
  pull: (syncToken: string | null) => Promise<T>,
) {
  try {
    return await pull(syncToken);
  } catch (error) {
    if (
      syncToken != null && error instanceof GoogleCalendarHttpError &&
      error.status === 410
    ) {
      return pull(null);
    }
    throw error;
  }
}

export function shouldRenewWatch(expiresAt: string | null, now = new Date()) {
  return expiresAt == null ||
    Date.parse(expiresAt) <= now.getTime() + 24 * 60 * 60_000;
}

export async function reconcileCalendar(
  input: {
    userId: string;
    calendarId: string;
    tasks: CalendarTask[];
    links: StoredCalendarLink[];
    fullSync?: boolean;
  },
  api: CalendarReconcileApi,
) {
  const tasks = new Map(input.tasks.map((task) => [task.id, { ...task }]));
  const originalLinks = new Map(
    input.links.map((link) => [link.taskId, JSON.stringify(link)]),
  );
  const seenEventIds = new Set<string>();
  const suppressedTaskIds = new Set<string>();
  const links = input.links
    .toSorted((a, b) =>
      a.createdAt.localeCompare(b.createdAt) ||
      a.taskId.localeCompare(b.taskId)
    )
    .filter((link) => {
      if (seenEventIds.has(link.eventId)) {
        suppressedTaskIds.add(link.taskId);
        return false;
      }
      seenEventIds.add(link.eventId);
      return true;
    })
    .map((link) => ({ ...link }));
  const events = new Map(api.events.map((event) => [event.id, event]));
  const decisions = new Map<string, "local" | "google" | "same">();
  const operations: CalendarOperation[] = [];

  for (const event of api.events) {
    const metadataTaskId = event.extendedProperties?.private?.pomodoistTaskId;
    let link = canonicalLinkForEvent(event.id, links) as
      | StoredCalendarLink
      | undefined;
    if (link == null && metadataTaskId != null && tasks.has(metadataTaskId)) {
      link = links.find((value) => value.taskId === metadataTaskId);
      if (link == null) {
        const task = tasks.get(metadataTaskId)!;
        link = {
          taskId: metadataTaskId,
          calendarId: input.calendarId,
          eventId: event.id,
          etag: event.etag ?? null,
          googleUpdatedAt: event.updated ?? null,
          localScheduleUpdatedAt: task._localScheduleUpdatedAt,
          lastScheduleFingerprint: scheduleFromGoogle(event)?.fingerprint ??
            null,
          unsupportedReason: null,
          createdAt: task.updatedAt,
        };
        links.push(link);
      }
    }
    if (link == null) continue; // Foreign/orphan events never create tasks.
    const task = tasks.get(link.taskId);
    if (task == null) continue;
    if (task.isDeleted === true) {
      decisions.set(task.id, "local");
      continue;
    }

    if (metadataTaskId !== link.taskId) {
      const repaired = await api.patchEvent(event.id, {
        extendedProperties: {
          private: {
            pomodoistSource: "pomodoist",
            pomodoistTaskId: link.taskId,
          },
        },
      }, event.etag ?? link.etag);
      link.etag = repaired.etag ?? event.etag ?? link.etag;
      link.googleUpdatedAt = repaired.updated ?? event.updated ??
        link.googleUpdatedAt;
    }

    if (Array.isArray(event.recurrence) && event.recurrence.length > 0) {
      link.unsupportedReason = "Recurring Google events are not supported yet.";
      continue;
    }
    const remoteUpdated = event.updated ?? link.googleUpdatedAt ??
      task.updatedAt;
    const googleSchedule = event.status === "cancelled"
      ? null
      : scheduleFromGoogle(event);
    const decision = resolveScheduleConflict({
      lastScheduleFingerprint: link.lastScheduleFingerprint,
      localScheduleFingerprint: scheduleFromTask(task)?.fingerprint ?? null,
      googleScheduleFingerprint: googleSchedule?.fingerprint ?? null,
      localScheduleChangedAt: task._localScheduleUpdatedAt,
      googleUpdatedAt: remoteUpdated,
    });
    decisions.set(task.id, decision);
    const payload: JsonMap = {};
    if (decision === "google") {
      payload.dueJson = googleSchedule?.dueJson ?? null;
      payload.durationSeconds = googleSchedule?.durationSeconds ?? null;
    }
    if (Date.parse(remoteUpdated) >= Date.parse(task._clientUpdatedAt)) {
      const title = (event.summary ?? task.content).trim();
      const content = stripCompletedPrefix(title) || task.content;
      const description = event.description ?? null;
      const status = title.startsWith("✓") ? "completed" : "open";
      if (content !== task.content) payload.content = content;
      if (description !== (task.description ?? null)) {
        payload.description = description;
      }
      if (status !== task.status) payload.status = status;
    }
    if (Object.keys(payload).length > 0) {
      payload.updatedAt = remoteUpdated;
      operations.push({
        opId: `google-calendar:${event.id}:${event.etag ?? remoteUpdated}`,
        entityType: "task",
        entityId: task.id,
        operation: "upsert",
        payload,
        clientUpdatedAt: remoteUpdated,
      });
      if (decision === "google") {
        task.dueJson = googleSchedule?.dueJson ?? null;
        task._localScheduleUpdatedAt = remoteUpdated;
      }
      task._clientUpdatedAt = remoteUpdated;
      Object.assign(task, payload);
    }
    link.etag = event.etag ?? link.etag;
    link.googleUpdatedAt = remoteUpdated;
    link.localScheduleUpdatedAt = task._localScheduleUpdatedAt;
    link.lastScheduleFingerprint = googleSchedule?.fingerprint ?? null;
  }

  for (const task of tasks.values()) {
    if (suppressedTaskIds.has(task.id)) continue;
    const taskLink = links.find((link) => link.taskId === task.id);
    if (taskLink?.unsupportedReason != null) continue;
    if (
      taskLink != null &&
      canonicalLinkForEvent(taskLink.eventId, links)?.taskId !== task.id
    ) continue;
    if (task.isDeleted === true) {
      if (taskLink != null) {
        await api.deleteEvent(taskLink.eventId);
        links.splice(links.indexOf(taskLink), 1);
      }
      continue;
    }
    const localSchedule = scheduleFromTask(task);
    if (
      input.fullSync === true && taskLink != null &&
      !events.has(taskLink.eventId)
    ) {
      const localNewer = taskLink.googleUpdatedAt == null ||
        Date.parse(task._localScheduleUpdatedAt) >
          Date.parse(taskLink.googleUpdatedAt);
      links.splice(links.indexOf(taskLink), 1);
      if (localSchedule != null && localNewer) {
        const created = await api.insertEvent(
          eventFromTask(task, localSchedule),
        );
        links.push(
          linkFromEvent(task, input.calendarId, created, localSchedule),
        );
      }
      continue;
    }
    if (localSchedule == null) {
      if (taskLink != null && decisions.get(task.id) === "local") {
        await api.deleteEvent(taskLink.eventId);
        links.splice(links.indexOf(taskLink), 1);
      }
      continue;
    }
    if (taskLink == null) {
      const created = await api.insertEvent(eventFromTask(task, localSchedule));
      links.push(linkFromEvent(task, input.calendarId, created, localSchedule));
      continue;
    }
    const remote = events.get(taskLink.eventId);
    const contentDiffers = remote != null &&
      ((remote.summary ?? "") !== titleForGoogle(task) ||
        (remote.description ?? null) !== (task.description ?? null));
    const localIsNewer = taskLink.googleUpdatedAt == null ||
      Date.parse(task._clientUpdatedAt) > Date.parse(taskLink.googleUpdatedAt);
    if (
      decisions.get(task.id) !== "local" &&
      !((contentDiffers ||
        (remote == null && input.fullSync !== true)) && localIsNewer)
    ) {
      continue;
    }
    let patched: GoogleEvent;
    try {
      patched = await api.patchEvent(
        taskLink.eventId,
        eventFromTask(task, localSchedule, true),
        remote?.etag ?? taskLink.etag,
      );
    } catch (error) {
      if (error instanceof GoogleCalendarHttpError && error.status === 404) {
        const localNewer = taskLink.googleUpdatedAt == null ||
          Date.parse(task._localScheduleUpdatedAt) >
            Date.parse(taskLink.googleUpdatedAt);
        links.splice(links.indexOf(taskLink), 1);
        if (!localNewer) continue;
        patched = await api.insertEvent(eventFromTask(task, localSchedule));
        links.push(
          linkFromEvent(task, input.calendarId, patched, localSchedule),
        );
        continue;
      }
      throw error;
    }
    taskLink.etag = patched.etag ?? taskLink.etag;
    taskLink.googleUpdatedAt = patched.updated ?? taskLink.googleUpdatedAt;
    taskLink.localScheduleUpdatedAt = task._localScheduleUpdatedAt;
    taskLink.lastScheduleFingerprint = localSchedule.fingerprint;
  }
  const changedLinks = links.filter(
    (link) => originalLinks.get(link.taskId) !== JSON.stringify(link),
  );
  const removedTaskIds = input.links
    .filter((link) => !links.some((value) => value.taskId === link.taskId))
    .map((link) => link.taskId);
  return { operations, links, changedLinks, removedTaskIds };
}

function scheduleFromTask(task: CalendarTask) {
  if (typeof task.dueJson !== "string") return null;
  try {
    return normalizeSchedule(JSON.parse(task.dueJson));
  } catch {
    return null;
  }
}

function scheduleFromGoogle(event: GoogleEvent) {
  const start = event.start;
  const end = event.end;
  if (typeof start?.date === "string") {
    return normalizeSchedule({ type: "allDay", date: start.date });
  }
  if (
    typeof start?.dateTime === "string" && typeof end?.dateTime === "string"
  ) {
    return normalizeSchedule({
      type: "timed",
      start: new Date(start.dateTime).toISOString(),
      end: new Date(end.dateTime).toISOString(),
      ...(typeof start.timeZone === "string"
        ? { timeZone: start.timeZone }
        : {}),
    });
  }
  return null;
}

function normalizeSchedule(value: JsonMap) {
  if (value.type === "allDay" && typeof value.date === "string") {
    const normalized = { type: "allDay", date: value.date };
    const dueJson = JSON.stringify(normalized);
    return {
      dueJson,
      fingerprint: dueJson,
      durationSeconds: null,
      value: normalized,
    };
  }
  if (
    value.type === "timed" && typeof value.start === "string" &&
    typeof value.end === "string" &&
    Date.parse(value.end) > Date.parse(value.start)
  ) {
    const normalized = {
      type: "timed",
      start: new Date(value.start).toISOString(),
      end: new Date(value.end).toISOString(),
      ...(typeof value.timeZone === "string" && value.timeZone.trim().length > 0
        ? { timeZone: value.timeZone }
        : {}),
    };
    const dueJson = JSON.stringify(normalized);
    return {
      dueJson,
      fingerprint: dueJson,
      durationSeconds: Math.round(
        (Date.parse(normalized.end) - Date.parse(normalized.start)) / 1000,
      ),
      value: normalized,
    };
  }
  return null;
}

function eventFromTask(
  task: CalendarTask,
  schedule: NonNullable<ReturnType<typeof normalizeSchedule>>,
  patch = false,
) {
  const value: JsonMap = schedule.value;
  const timed = value.type === "timed";
  return {
    summary: titleForGoogle(task),
    description: task.description ?? null,
    start: timed
      ? {
        ...(patch ? { date: null } : {}),
        dateTime: value.start,
        ...(patch
          ? { timeZone: value.timeZone ?? null }
          : value.timeZone == null
          ? {}
          : { timeZone: value.timeZone }),
      }
      : {
        date: value.date,
        ...(patch ? { dateTime: null, timeZone: null } : {}),
      },
    end: timed
      ? {
        ...(patch ? { date: null } : {}),
        dateTime: value.end,
        ...(patch
          ? { timeZone: value.timeZone ?? null }
          : value.timeZone == null
          ? {}
          : { timeZone: value.timeZone }),
      }
      : {
        date: addDay(value.date as string),
        ...(patch ? { dateTime: null, timeZone: null } : {}),
      },
    extendedProperties: {
      private: { pomodoistSource: "pomodoist", pomodoistTaskId: task.id },
    },
    ...(task.status === "completed" ? { colorId: "8" } : {}),
  };
}

function linkFromEvent(
  task: CalendarTask,
  calendarId: string,
  event: GoogleEvent,
  schedule: NonNullable<ReturnType<typeof normalizeSchedule>>,
): StoredCalendarLink {
  return {
    taskId: task.id,
    calendarId,
    eventId: event.id,
    etag: event.etag ?? null,
    googleUpdatedAt: event.updated ?? null,
    localScheduleUpdatedAt: task._localScheduleUpdatedAt,
    lastScheduleFingerprint: schedule.fingerprint,
    unsupportedReason: null,
    createdAt: task.updatedAt,
  };
}

function titleForGoogle(task: CalendarTask) {
  const title = stripCompletedPrefix(task.content);
  return task.status === "completed" ? `✓ ${title}` : title;
}

function stripCompletedPrefix(value: string) {
  const trimmed = value.trim();
  return trimmed.startsWith("✓") ? trimmed.slice(1).trim() : trimmed;
}

function addDay(value: string) {
  const date = new Date(`${value}T00:00:00.000Z`);
  date.setUTCDate(date.getUTCDate() + 1);
  return date.toISOString().slice(0, 10);
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-pomodoist-worker-secret",
};

function json(value: unknown, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function isRecord(value: unknown): value is JsonMap {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function base64Url(bytes: Uint8Array) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(
    /=+$/,
    "",
  );
}

async function digest(value: string) {
  return new Uint8Array(
    await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)),
  );
}

async function sha256(value: string) {
  return Array.from(await digest(value))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function constantTimeEqual(left: string, right: string) {
  if (left.length === 0 || left.length !== right.length) return false;
  let mismatch = 0;
  for (let index = 0; index < left.length; index++) {
    mismatch |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return mismatch === 0;
}

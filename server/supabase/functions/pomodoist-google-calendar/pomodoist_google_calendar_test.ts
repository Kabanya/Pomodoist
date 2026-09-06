import { assertEquals, assertMatch, assertRejects } from "@std/assert";

import {
  calendarFailurePayload,
  canonicalLinkForEvent,
  type GoogleCalendarDeps,
  GoogleCalendarHttpError,
  handlePomodoistGoogleCalendar,
  processWorkerBatch,
  pullWithExpiredSyncTokenRetry,
  reconcileCalendar,
  resolveScheduleConflict,
  reusablePomodoistCalendar,
  shouldRenewWatch,
  syncCalendarAccount,
} from "./pomodoist_google_calendar.ts";

const userId = "11111111-1111-4111-8111-111111111111";

Deno.test("OAuth start stores one-time PKCE state and returns the Google authorization URL", async () => {
  const stored: Array<Record<string, unknown>> = [];
  const response = await handlePomodoistGoogleCalendar(
    request({ action: "start" }, { Authorization: "Bearer user" }),
    deps({
      storeOAuthState: (value) => {
        stored.push(value);
        return Promise.resolve();
      },
    }),
  );

  assertEquals(response.status, 200);
  const body = await response.json();
  assertMatch(
    body.authorizationUrl,
    /^https:\/\/accounts\.google\.com\/o\/oauth2\/v2\/auth\?/,
  );
  const url = new URL(body.authorizationUrl);
  assertEquals(url.searchParams.get("access_type"), "offline");
  assertEquals(url.searchParams.get("prompt"), "consent");
  assertEquals(url.searchParams.get("code_challenge_method"), "S256");
  assertEquals(stored.length, 1);
  assertEquals(stored[0].userId, userId);
  assertEquals(
    stored[0].stateHash,
    await sha256(url.searchParams.get("state")!),
  );
  assertEquals(typeof stored[0].codeVerifier, "string");
});

Deno.test("OAuth start rejects an incomplete server configuration", async () => {
  const response = await handlePomodoistGoogleCalendar(
    request({ action: "start" }, { Authorization: "Bearer user" }),
    deps({ oauthConfigured: false }),
  );

  assertEquals(response.status, 503);
  assertEquals(await response.json(), {
    error: "Google Calendar is not configured.",
  });
});

Deno.test("OAuth callback consumes state before exchanging the code", async () => {
  const calls: string[] = [];
  const response = await handlePomodoistGoogleCalendar(
    new Request(
      "https://functions.test/pomodoist-google-calendar?code=google-code&state=one-time",
    ),
    deps({
      consumeOAuthState: async (stateHash) => {
        calls.push(`consume:${stateHash}`);
        return { userId, codeVerifier: "verifier" };
      },
      exchangeOAuthCode: async (code, verifier) => {
        calls.push(`exchange:${code}:${verifier}`);
        return {
          refreshToken: "refresh",
          accessToken: "access",
          expiresIn: 3600,
        };
      },
      connect: async (input) => {
        calls.push(`connect:${input.refreshToken}`);
      },
    }),
  );

  assertEquals(response.status, 302);
  assertEquals(calls, [
    `consume:${await sha256("one-time")}`,
    "exchange:google-code:verifier",
    "connect:refresh",
  ]);
});

Deno.test("OAuth callback rejects expired or replayed state", async () => {
  let exchanges = 0;
  const response = await handlePomodoistGoogleCalendar(
    new Request(
      "https://functions.test/pomodoist-google-calendar?code=google-code&state=expired",
    ),
    deps({
      consumeOAuthState: () => Promise.resolve(null),
      exchangeOAuthCode: () => {
        exchanges++;
        return Promise.reject(new Error("must not exchange"));
      },
    }),
  );

  assertEquals(response.status, 400);
  assertEquals(exchanges, 0);
});

Deno.test("a fresh Calendar connection and manual sync configure the worker before queueing", async () => {
  let configured = false;
  const calls: string[] = [];
  const bootstrapDeps = {
    ...deps({
      consumeOAuthState: () =>
        Promise.resolve({ userId, codeVerifier: "verifier" }),
      exchangeOAuthCode: () =>
        Promise.resolve({
          refreshToken: "refresh",
          accessToken: "access",
          expiresIn: 3600,
        }),
      connect: async () => {
        assertEquals(
          configured,
          true,
          "connection must be able to wake its first job",
        );
        calls.push("connect");
      },
      queue: async () => {
        assertEquals(
          configured,
          true,
          "manual sync must be able to wake the worker",
        );
        calls.push("queue");
      },
    }),
    configureWorker: async () => {
      await Promise.resolve();
      configured = true;
      calls.push("configure");
    },
  };

  const connected = await handlePomodoistGoogleCalendar(
    new Request(
      "https://functions.test/pomodoist-google-calendar?code=code&state=state",
    ),
    bootstrapDeps,
  );
  assertEquals(connected.status, 302);
  assertEquals(calls, ["configure", "connect"]);

  configured = false;
  calls.length = 0;
  const unauthorized = await handlePomodoistGoogleCalendar(
    request({ action: "sync" }),
    bootstrapDeps,
  );
  assertEquals(unauthorized.status, 401);
  assertEquals(calls, []);
  const synced = await handlePomodoistGoogleCalendar(
    request({ action: "sync" }, { Authorization: "Bearer user" }),
    bootstrapDeps,
  );
  assertEquals(synced.status, 200);
  assertEquals(calls, ["configure", "queue"]);
});

Deno.test("webhook validates channel identity and token before queueing", async () => {
  let queued = 0;
  const valid = await handlePomodoistGoogleCalendar(
    new Request("https://functions.test/pomodoist-google-calendar", {
      method: "POST",
      headers: {
        "X-Goog-Channel-ID": "channel-1",
        "X-Goog-Channel-Token": "secret-token",
        "X-Goog-Resource-ID": "resource-1",
        "X-Goog-Resource-State": "exists",
      },
    }),
    deps({
      queueWebhook: async (input) => {
        queued++;
        return input.channelId === "channel-1" &&
          input.resourceId === "resource-1" &&
          input.tokenHash === await sha256("secret-token");
      },
    }),
  );
  const invalid = await handlePomodoistGoogleCalendar(
    new Request("https://functions.test/pomodoist-google-calendar", {
      method: "POST",
      headers: { "X-Goog-Channel-ID": "unknown" },
    }),
    deps(),
  );

  assertEquals(valid.status, 204);
  assertEquals(invalid.status, 401);
  assertEquals(queued, 1);
});

Deno.test("the internal worker requires its exact secret", async () => {
  let runs = 0;
  const workerDeps = deps({
    workerSecret: "worker-secret",
    runWorker: () => {
      runs++;
      return Promise.resolve({ claimed: 1, succeeded: 1, failed: 0 });
    },
  });
  const rejected = await handlePomodoistGoogleCalendar(
    request({}, { "X-Pomodoist-Worker-Secret": "wrong-secret" }),
    workerDeps,
  );
  const accepted = await handlePomodoistGoogleCalendar(
    request({}, { "X-Pomodoist-Worker-Secret": "worker-secret" }),
    workerDeps,
  );

  assertEquals(rejected.status, 401);
  assertEquals(accepted.status, 200);
  assertEquals(await accepted.json(), {
    claimed: 1,
    succeeded: 1,
    failed: 0,
  });
  assertEquals(runs, 1);
});

Deno.test("the internal worker reports configuration failures instead of a false success", async () => {
  const response = await handlePomodoistGoogleCalendar(
    request({}, { "X-Pomodoist-Worker-Secret": "worker-secret" }),
    deps({
      workerSecret: "worker-secret",
      runWorker: () => Promise.reject(new Error("missing configuration")),
    }),
  );

  assertEquals(response.status, 503);
  assertEquals(await response.json(), {
    error: "Google Calendar worker is unavailable.",
  });
});

Deno.test("worker accounts run concurrently and failures are counted", async () => {
  let active = 0;
  let maxActive = 0;
  const failed: string[] = [];

  const result = await processWorkerBatch(
    [{ userId: "one" }, { userId: "two" }, { userId: "three" }],
    async (account) => {
      active++;
      maxActive = Math.max(maxActive, active);
      await new Promise((resolve) => setTimeout(resolve, 1));
      active--;
      if (account.userId === "two") throw new Error("temporary");
    },
    (account) => {
      failed.push(account.userId);
      return Promise.resolve();
    },
  );

  assertEquals(maxActive, 3);
  assertEquals(failed, ["two"]);
  assertEquals(result, { claimed: 3, succeeded: 2, failed: 1 });
});

Deno.test("schedule conflict uses the side changed since the last fingerprint", () => {
  const baseline = '{"date":"2026-08-27"}';
  assertEquals(
    resolveScheduleConflict({
      lastScheduleFingerprint: baseline,
      localScheduleFingerprint: '{"date":"2026-08-28"}',
      googleScheduleFingerprint: baseline,
      localScheduleChangedAt: "2026-08-26T10:00:00.000Z",
      googleUpdatedAt: "2026-08-26T11:00:00.000Z",
    }),
    "local",
  );
  assertEquals(
    resolveScheduleConflict({
      lastScheduleFingerprint: baseline,
      localScheduleFingerprint: baseline,
      googleScheduleFingerprint: '{"date":"2026-08-29"}',
      localScheduleChangedAt: "2026-08-26T12:00:00.000Z",
      googleUpdatedAt: "2026-08-26T11:00:00.000Z",
    }),
    "google",
  );
  assertEquals(
    resolveScheduleConflict({
      lastScheduleFingerprint: baseline,
      localScheduleFingerprint: '{"date":"2026-08-28"}',
      googleScheduleFingerprint: '{"date":"2026-08-29"}',
      localScheduleChangedAt: "2026-08-26T12:00:00.000Z",
      googleUpdatedAt: "2026-08-26T11:00:00.000Z",
    }),
    "local",
  );
  assertEquals(
    resolveScheduleConflict({
      lastScheduleFingerprint: baseline,
      localScheduleFingerprint: '{"date":"2026-08-28"}',
      googleScheduleFingerprint: '{"date":"2026-08-29"}',
      localScheduleChangedAt: "2026-08-26T11:00:00.000Z",
      googleUpdatedAt: "2026-08-26T11:00:00.000Z",
    }),
    "google",
  );
});

Deno.test("duplicate event links choose the oldest canonical task", () => {
  assertEquals(
    canonicalLinkForEvent("event-1", [
      { taskId: "new", eventId: "event-1", createdAt: "2026-08-02T00:00:00Z" },
      {
        taskId: "old-b",
        eventId: "event-1",
        createdAt: "2026-08-01T00:00:00Z",
      },
      {
        taskId: "old-a",
        eventId: "event-1",
        createdAt: "2026-08-01T00:00:00Z",
      },
    ])?.taskId,
    "old-a",
  );
});

Deno.test("an existing non-primary Pomodoist calendar is reused", () => {
  assertEquals(
    reusablePomodoistCalendar([
      { id: "primary", summary: "Pomodoist", primary: true },
      { id: "z-calendar", summary: "Pomodoist" },
      { id: "a-calendar", summary: "Pomodoist" },
      { id: "other", summary: "Personal" },
    ])?.id,
    "a-calendar",
  );
});

Deno.test("worker always pulls Google before pushing local changes", async () => {
  const order: string[] = [];
  await syncCalendarAccount(
    {
      userId,
      calendarId: "calendar-1",
      accessToken: "access",
      syncToken: null,
      tasks: [],
      links: [],
    },
    {
      pullGoogle: async () => {
        order.push("pull");
        return { events: [], nextSyncToken: "next" };
      },
      applyPulledEvents: async () => {
        order.push("apply");
      },
      pushLocalTasks: async () => {
        order.push("push");
      },
    },
  );
  assertEquals(order, ["pull", "apply", "push"]);
});

Deno.test("reconciliation repairs stale event metadata through the oldest link without creating a task", async () => {
  const patched: Array<JsonMap> = [];
  const result = await reconcileCalendar(
    snapshot({
      links: [
        link({ taskId: "task-new", createdAt: "2026-08-02T00:00:00.000Z" }),
        link({ taskId: "task-old", createdAt: "2026-08-01T00:00:00.000Z" }),
      ],
      tasks: [task("task-new"), task("task-old")],
    }),
    api({
      events: [{
        id: "event-1",
        status: "confirmed",
        summary: "Breakfast",
        updated: "2026-08-26T09:00:00.000Z",
        etag: "etag-1",
        start: { date: "2026-08-27" },
        end: { date: "2026-08-28" },
        extendedProperties: {
          private: { pomodoistTaskId: "foreign-task" },
        },
      }],
      insertEvent: () => Promise.reject(new Error("must not insert")),
      patchEvent: async (_eventId: string, body: JsonMap) => {
        patched.push(body);
        return {
          id: "event-1",
          etag: "etag-2",
          updated: "2026-08-26T09:01:00.000Z",
          ...body,
        };
      },
    }),
  );

  assertEquals(patched.length, 1);
  assertEquals(
    (patched[0].extendedProperties as JsonMap).private,
    { pomodoistSource: "pomodoist", pomodoistTaskId: "task-old" },
  );
  assertEquals(
    result.operations.filter((op) => op.entityType === "task").length,
    0,
  );
  assertEquals(
    canonicalLinkForEvent("event-1", result.links)?.taskId,
    "task-old",
  );
});

Deno.test("Google schedule wins independently when only Google changed", async () => {
  const result = await reconcileCalendar(
    snapshot(),
    api({
      events: [{
        id: "event-1",
        status: "confirmed",
        summary: "Breakfast",
        updated: "2026-08-26T11:00:00.000Z",
        etag: "etag-2",
        start: {
          dateTime: "2026-08-27T12:00:00.000Z",
          timeZone: "Europe/Moscow",
        },
        end: {
          dateTime: "2026-08-27T13:00:00.000Z",
          timeZone: "Europe/Moscow",
        },
        extendedProperties: { private: { pomodoistTaskId: "task-1" } },
      }],
    }),
  );

  const operation = result.operations.find((op) => op.entityType === "task")!;
  assertEquals(
    operation.payload.dueJson,
    JSON.stringify({
      type: "timed",
      start: "2026-08-27T12:00:00.000Z",
      end: "2026-08-27T13:00:00.000Z",
      timeZone: "Europe/Moscow",
    }),
  );
  assertEquals(operation.payload.durationSeconds, 3600);
});

Deno.test("a newer Google title wins without changing the schedule", async () => {
  const result = await reconcileCalendar(
    snapshot(),
    api({
      events: [{
        id: "event-1",
        status: "confirmed",
        summary: "Buy breakfast",
        description: "Milk and bread",
        updated: "2026-08-26T11:00:00.000Z",
        etag: "etag-2",
        start: { date: "2026-08-27" },
        end: { date: "2026-08-28" },
        extendedProperties: { private: { pomodoistTaskId: "task-1" } },
      }],
    }),
  );

  assertEquals(result.operations.length, 1);
  assertEquals(result.operations[0].payload, {
    content: "Buy breakfast",
    description: "Milk and bread",
    updatedAt: "2026-08-26T11:00:00.000Z",
  });
});

Deno.test("completed tasks use a checkmark in Google Calendar", async () => {
  const inserted: JsonMap[] = [];
  await reconcileCalendar(
    snapshot({
      tasks: [task("task-1", { status: "completed" })],
      links: [],
    }),
    api({
      insertEvent: async (body: JsonMap) => {
        inserted.push(body);
        return {
          id: "event-1",
          etag: "etag-1",
          updated: "2026-08-26T11:00:00.000Z",
          ...body,
        };
      },
    }),
  );

  assertEquals(inserted[0].summary, "✓ Breakfast");
});

Deno.test("incremental pull still pushes a newer linked task", async () => {
  const patches: JsonMap[] = [];
  await reconcileCalendar(
    snapshot({
      tasks: [task("task-1", {
        status: "completed",
        dueJson: JSON.stringify({
          type: "timed",
          start: "2026-08-27T15:00:00.000Z",
          end: "2026-08-27T16:00:00.000Z",
          timeZone: "Europe/Moscow",
        }),
        _clientUpdatedAt: "2026-08-26T12:00:00.000Z",
        _localScheduleUpdatedAt: "2026-08-26T12:00:00.000Z",
      })],
    }),
    api({
      patchEvent: (
        eventId: string,
        body: JsonMap,
        _etag: string | null,
      ) => {
        patches.push(body);
        return Promise.resolve({
          id: eventId,
          ...body,
          etag: "etag-new",
          updated: "2026-08-26T12:01:00.000Z",
        });
      },
    }),
  );

  assertEquals(patches.length, 1);
  assertEquals(patches[0].summary, "✓ Breakfast");
  assertEquals(patches[0].start, {
    date: null,
    dateTime: "2026-08-27T15:00:00.000Z",
    timeZone: "Europe/Moscow",
  });
});

Deno.test("a Google checkmark marks the task completed", async () => {
  const result = await reconcileCalendar(
    snapshot(),
    api({
      events: [{
        id: "event-1",
        status: "confirmed",
        summary: "✓ Breakfast",
        updated: "2026-08-26T11:00:00.000Z",
        etag: "etag-2",
        start: { date: "2026-08-27" },
        end: { date: "2026-08-28" },
        extendedProperties: { private: { pomodoistTaskId: "task-1" } },
      }],
    }),
  );

  assertEquals(result.operations[0].payload, {
    status: "completed",
    updatedAt: "2026-08-26T11:00:00.000Z",
  });
});

Deno.test("a deleted task removes its linked event", async () => {
  const deleted: string[] = [];
  const result = await reconcileCalendar(
    snapshot({ tasks: [task("task-1", { isDeleted: true })] }),
    api({
      events: [{
        id: "event-1",
        status: "confirmed",
        summary: "Breakfast",
        updated: "2026-08-26T11:00:00.000Z",
        etag: "etag-2",
        start: { date: "2026-08-27" },
        end: { date: "2026-08-28" },
      }],
      deleteEvent: (eventId: string) => {
        deleted.push(eventId);
        return Promise.resolve();
      },
    }),
  );

  assertEquals(deleted, ["event-1"]);
  assertEquals(result.links, []);
  assertEquals(result.removedTaskIds, ["task-1"]);
});

Deno.test("a missing duplicated event is recreated only for the oldest link", async () => {
  let inserts = 0;
  const result = await reconcileCalendar(
    {
      ...snapshot({
        tasks: [
          task("task-old", {
            _localScheduleUpdatedAt: "2026-08-26T12:00:00.000Z",
          }),
          task("task-new", {
            _localScheduleUpdatedAt: "2026-08-26T12:00:00.000Z",
          }),
        ],
        links: [
          link({ taskId: "task-new", createdAt: "2026-08-02T00:00:00.000Z" }),
          link({ taskId: "task-old", createdAt: "2026-08-01T00:00:00.000Z" }),
        ],
      }),
      fullSync: true,
    },
    api({
      insertEvent: async (body: JsonMap) => {
        inserts++;
        return {
          id: "replacement",
          etag: "etag-replacement",
          updated: "2026-08-26T12:01:00.000Z",
          ...body,
        };
      },
    }),
  );

  assertEquals(inserts, 1);
  assertEquals(result.links[0]?.taskId, "task-old");
  assertEquals(result.links[0]?.eventId, "replacement");
  assertEquals(result.removedTaskIds, ["task-new"]);
});

Deno.test("all-day to timed patch clears the incompatible date fields", async () => {
  const patches: Array<
    { eventId: string; etag: string | null; body: JsonMap }
  > = [];
  await reconcileCalendar(
    snapshot({
      tasks: [task("task-1", {
        dueJson: JSON.stringify({
          type: "timed",
          start: "2026-08-27T15:00:00.000Z",
          end: "2026-08-27T16:00:00.000Z",
          timeZone: "Europe/Moscow",
        }),
        _localScheduleUpdatedAt: "2026-08-26T12:00:00.000Z",
      })],
    }),
    api({
      events: [{
        id: "event-1",
        status: "confirmed",
        summary: "Breakfast",
        updated: "2026-08-26T11:00:00.000Z",
        etag: "etag-remote",
        start: { date: "2026-08-27" },
        end: { date: "2026-08-28" },
        extendedProperties: { private: { pomodoistTaskId: "task-1" } },
      }],
      patchEvent: async (
        eventId: string,
        body: JsonMap,
        etag: string | null,
      ) => {
        patches.push({ eventId, body, etag });
        return {
          id: eventId,
          ...body,
          etag: "etag-new",
          updated: "2026-08-26T12:01:00.000Z",
        };
      },
    }),
  );

  assertEquals(patches.length, 1);
  assertEquals(patches[0].etag, "etag-remote");
  assertEquals(patches[0].body.start, {
    date: null,
    dateTime: "2026-08-27T15:00:00.000Z",
    timeZone: "Europe/Moscow",
  });
  assertEquals(patches[0].body.end, {
    date: null,
    dateTime: "2026-08-27T16:00:00.000Z",
    timeZone: "Europe/Moscow",
  });
});

Deno.test("timed to all-day patch clears dateTime and timeZone", async () => {
  const patches: JsonMap[] = [];
  const previous = JSON.stringify({
    type: "timed",
    start: "2026-08-27T12:00:00.000Z",
    end: "2026-08-27T13:00:00.000Z",
    timeZone: "Europe/Moscow",
  });
  await reconcileCalendar(
    snapshot({
      tasks: [task("task-1", {
        dueJson: '{"type":"allDay","date":"2026-08-28"}',
        _localScheduleUpdatedAt: "2026-08-26T12:00:00.000Z",
      })],
      links: [link({ lastScheduleFingerprint: previous })],
    }),
    api({
      events: [{
        id: "event-1",
        status: "confirmed",
        updated: "2026-08-26T11:00:00.000Z",
        etag: "etag-remote",
        start: {
          dateTime: "2026-08-27T12:00:00.000Z",
          timeZone: "Europe/Moscow",
        },
        end: {
          dateTime: "2026-08-27T13:00:00.000Z",
          timeZone: "Europe/Moscow",
        },
        extendedProperties: { private: { pomodoistTaskId: "task-1" } },
      }],
      patchEvent: async (_eventId: string, body: JsonMap) => {
        patches.push(body);
        return { id: "event-1", ...body };
      },
    }),
  );

  assertEquals(patches[0].start, {
    date: "2026-08-28",
    dateTime: null,
    timeZone: null,
  });
  assertEquals(patches[0].end, {
    date: "2026-08-29",
    dateTime: null,
    timeZone: null,
  });
});

Deno.test("timed patch clears a removed timezone", async () => {
  const patches: JsonMap[] = [];
  const previous = JSON.stringify({
    type: "timed",
    start: "2026-08-27T12:00:00.000Z",
    end: "2026-08-27T13:00:00.000Z",
    timeZone: "Europe/Moscow",
  });
  await reconcileCalendar(
    snapshot({
      tasks: [task("task-1", {
        dueJson: JSON.stringify({
          type: "timed",
          start: "2026-08-27T15:00:00.000Z",
          end: "2026-08-27T16:00:00.000Z",
        }),
        _localScheduleUpdatedAt: "2026-08-26T12:00:00.000Z",
      })],
      links: [link({ lastScheduleFingerprint: previous })],
    }),
    api({
      events: [{
        id: "event-1",
        status: "confirmed",
        updated: "2026-08-26T11:00:00.000Z",
        etag: "etag-remote",
        start: {
          dateTime: "2026-08-27T12:00:00.000Z",
          timeZone: "Europe/Moscow",
        },
        end: {
          dateTime: "2026-08-27T13:00:00.000Z",
          timeZone: "Europe/Moscow",
        },
        extendedProperties: { private: { pomodoistTaskId: "task-1" } },
      }],
      patchEvent: async (_eventId: string, body: JsonMap) => {
        patches.push(body);
        return { id: "event-1", ...body };
      },
    }),
  );

  assertEquals(patches[0].start, {
    date: null,
    dateTime: "2026-08-27T15:00:00.000Z",
    timeZone: null,
  });
  assertEquals(patches[0].end, {
    date: null,
    dateTime: "2026-08-27T16:00:00.000Z",
    timeZone: null,
  });
});

Deno.test("missing Google event is recreated only after a newer local schedule change", async () => {
  let inserts = 0;
  const older = await reconcileCalendar(
    {
      ...snapshot(),
      fullSync: true,
    },
    api({
      insertEvent: async (body: JsonMap) => {
        inserts++;
        return {
          id: "replacement",
          etag: "etag-replacement",
          updated: "2026-08-26T12:01:00.000Z",
          ...body,
        };
      },
    }),
  );
  const newer = await reconcileCalendar(
    {
      ...snapshot({
        tasks: [task("task-1", {
          _localScheduleUpdatedAt: "2026-08-26T12:00:00.000Z",
        })],
      }),
      fullSync: true,
    },
    api({
      insertEvent: async (body: JsonMap) => {
        inserts++;
        return {
          id: "replacement",
          etag: "etag-replacement",
          updated: "2026-08-26T12:01:00.000Z",
          ...body,
        };
      },
    }),
  );

  assertEquals(older.links.length, 0);
  assertEquals(newer.links[0]?.eventId, "replacement");
  assertEquals(inserts, 1);
});

Deno.test("expired Google sync token retries one full pull", async () => {
  const tokens: Array<string | null> = [];
  const result = await pullWithExpiredSyncTokenRetry("stale", async (token) => {
    tokens.push(token);
    if (token != null) throw new GoogleCalendarHttpError(410, "Gone");
    return { events: [], nextSyncToken: "fresh", fullSync: true };
  });

  assertEquals(tokens, ["stale", null]);
  assertEquals(result.nextSyncToken, "fresh");
});

Deno.test("ETag precondition failure aborts the pass for a fresh pull", async () => {
  await assertRejects(
    () =>
      reconcileCalendar(
        snapshot({
          tasks: [task("task-1", {
            dueJson: '{"type":"allDay","date":"2026-08-28"}',
            _localScheduleUpdatedAt: "2026-08-26T12:00:00.000Z",
          })],
        }),
        api({
          events: [{
            id: "event-1",
            status: "confirmed",
            updated: "2026-08-26T11:00:00.000Z",
            etag: "etag-remote",
            start: { date: "2026-08-27" },
            end: { date: "2026-08-28" },
            extendedProperties: { private: { pomodoistTaskId: "task-1" } },
          }],
          patchEvent: () =>
            Promise.reject(new GoogleCalendarHttpError(412, "Precondition")),
        }),
      ),
    GoogleCalendarHttpError,
    "Precondition",
  );
});

Deno.test("ETag precondition failures request an immediate clean retry", () => {
  assertEquals(
    calendarFailurePayload(
      { attempts: 4, claimedGeneration: 12 },
      new GoogleCalendarHttpError(412, "Precondition"),
    ),
    {
      claimedGeneration: 12,
      error: "Precondition",
      retrySeconds: 5,
      transientConflict: true,
    },
  );
});

Deno.test("watch channel renews inside its one-day safety window", () => {
  const now = new Date("2026-08-26T10:00:00.000Z");
  assertEquals(shouldRenewWatch("2026-08-28T10:00:00.000Z", now), false);
  assertEquals(shouldRenewWatch("2026-08-27T09:59:59.000Z", now), true);
  assertEquals(shouldRenewWatch(null, now), true);
});

function request(body: unknown, headers: HeadersInit = {}) {
  return new Request("https://functions.test/pomodoist-google-calendar", {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
}

function deps(overrides: Partial<GoogleCalendarDeps> = {}): GoogleCalendarDeps {
  return {
    oauthClientId: "client-id",
    oauthConfigured: true,
    redirectUri: "https://functions.test/pomodoist-google-calendar",
    appRedirectUri: "pomodoist://google-calendar-connected",
    authenticate: async (authorization) =>
      authorization === "Bearer user" ? { id: userId } : null,
    storeOAuthState: () => Promise.resolve(),
    consumeOAuthState: () => Promise.resolve(null),
    exchangeOAuthCode: () => Promise.reject(new Error("unexpected exchange")),
    configureWorker: () => Promise.resolve(),
    connect: () => Promise.resolve(),
    queue: () => Promise.resolve(),
    disconnect: () => Promise.resolve(),
    queueWebhook: () => Promise.resolve(false),
    runWorker: () => Promise.resolve({ claimed: 0, succeeded: 0, failed: 0 }),
    randomBytes: (length) => new Uint8Array(length).fill(7),
    now: () => new Date("2026-08-26T10:00:00.000Z"),
    ...overrides,
  };
}

async function sha256(value: string) {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

type JsonMap = Record<string, unknown>;

function snapshot(overrides: JsonMap = {}) {
  return {
    userId,
    calendarId: "calendar-1",
    tasks: [task("task-1")],
    links: [link()],
    ...overrides,
  };
}

function task(id: string, overrides: JsonMap = {}) {
  return {
    id,
    content: "Breakfast",
    description: null,
    status: "open",
    isDeleted: false,
    dueJson: '{"type":"allDay","date":"2026-08-27"}',
    durationSeconds: null,
    updatedAt: "2026-08-26T10:00:00.000Z",
    _clientUpdatedAt: "2026-08-26T10:00:00.000Z",
    _localScheduleUpdatedAt: "2026-08-26T10:00:00.000Z",
    ...overrides,
  };
}

function link(overrides: JsonMap = {}) {
  return {
    taskId: "task-1",
    calendarId: "calendar-1",
    eventId: "event-1",
    etag: "etag-1",
    googleUpdatedAt: "2026-08-26T10:00:00.000Z",
    localScheduleUpdatedAt: "2026-08-26T10:00:00.000Z",
    lastScheduleFingerprint: '{"type":"allDay","date":"2026-08-27"}',
    unsupportedReason: null,
    createdAt: "2026-08-01T00:00:00.000Z",
    ...overrides,
  };
}

function api(overrides: JsonMap = {}) {
  return {
    events: [],
    insertEvent: async (_body: JsonMap) => ({
      id: "created",
      etag: "etag-created",
      updated: "2026-08-26T10:01:00.000Z",
    }),
    patchEvent: async (
      eventId: string,
      body: JsonMap,
      _etag: string | null,
    ) => ({
      id: eventId,
      ...body,
      etag: "etag-patched",
      updated: "2026-08-26T10:01:00.000Z",
    }),
    deleteEvent: (_eventId: string) => Promise.resolve(),
    ...overrides,
  };
}

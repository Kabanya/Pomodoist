import {
  assertEquals,
  assertExists,
  assertMatch,
  assertThrows,
} from "jsr:@std/assert";

import type { AppleStoreTransaction } from "../_shared/apple_app_transaction.ts";
import {
  handlePomodoistWatch,
  pomodoistState,
  telegramCommandOps,
  telegramSnapshot,
} from "./pomodoist_watch.ts";

Deno.test("pomodoist-watch lets StoreKit-authenticated requests reach the handler", async () => {
  const config = await Deno.readTextFile(
    new URL("../../config.toml", import.meta.url),
  );
  assertMatch(
    config,
    /\[functions\.pomodoist-watch\]\s+verify_jwt = false/,
  );
});

Deno.test("quick add writes task label and task_label operations", async () => {
  const rpcCalls: Array<
    { functionName: string; args: Record<string, unknown> }
  > = [];
  const response = await handlePomodoistWatch(
    request({
      command: {
        type: "task.createQuickAdd",
        id: "cmd-1",
        input: "Write report #Work @urgent p1 today 10:00 30m 2p",
      },
    }),
    deps({ rpcCalls, entities: [project("work", "Work")] }),
  );

  assertEquals(response.status, 200);
  const push = rpcCalls.find((call) => call.functionName === "push_changes");
  const ops = push?.args.p_operations as Array<Record<string, unknown>>;
  assertEquals(ops?.map((op) => op.entityType), [
    "task",
    "label",
    "task_label",
  ]);
  const task = ops[0].payload as Record<string, unknown>;
  assertEquals(task.content, "Write report");
  assertEquals(task.projectId, "work");
  assertEquals(task.priority, 1);
  assertEquals(task.estimatedFocusIntervals, 2);
  assertExists(JSON.parse(task.dueJson as string).start);
});

Deno.test("complete task writes task_completion operation", async () => {
  const rpcCalls: Array<
    { functionName: string; args: Record<string, unknown> }
  > = [];
  const response = await handlePomodoistWatch(
    request({
      command: { type: "task.complete", id: "cmd-2", taskId: "task-1" },
    }),
    deps({
      rpcCalls,
      entities: [task("task-1", { status: "open" })],
    }),
  );

  assertEquals(response.status, 200);
  const push = rpcCalls.find((call) => call.functionName === "push_changes");
  const ops = push?.args.p_operations as Array<Record<string, unknown>>;
  assertEquals(ops?.map((op) => op.entityType), ["task", "task_completion"]);
  assertEquals((ops[0].payload as Record<string, unknown>).status, "completed");
  assertEquals((ops[1].payload as Record<string, unknown>).taskId, "task-1");
});

Deno.test("Telegram task creation keeps literal content and shared entity format", () => {
  const state = pomodoistState([]);
  const operations = telegramCommandOps(
    state,
    {
      type: "task.create",
      id: "11111111-1111-4111-8111-111111111111",
      content: "Call @home",
    },
    new Date("2026-07-07T12:00:00Z"),
    () => "task-telegram",
  );

  assertEquals(operations.map((operation) => operation.entityType), ["task"]);
  assertEquals(operations[0].payload.content, "Call @home");
  assertEquals(operations[0].payload.projectId, "inbox");
});

Deno.test("Telegram focus is one work interval and emits shared focus events", () => {
  let counter = 0;
  const state = pomodoistState([
    task("task-1", { estimatedFocusIntervals: 4 }),
    focusPreset("deep", { isDefault: true, workSeconds: 3000 }),
  ]);
  const operations = telegramCommandOps(
    state,
    {
      type: "focus.start",
      id: "22222222-2222-4222-8222-222222222222",
      taskId: "task-1",
    },
    new Date("2026-07-07T12:00:00Z"),
    () => `telegram-${++counter}`,
  );

  assertEquals(operations.map((operation) => operation.entityType), [
    "focus_run", "focus_interval", "focus_event", "focus_event",
  ]);
  assertEquals(operations[0].payload.targetWorkIntervals, 1);
  assertEquals(operations[1].payload.plannedSeconds, 1500);
  assertEquals(operations.slice(2).map((operation) => operation.payload.type), [
    "runStarted",
    "intervalStarted",
  ]);
});

Deno.test("Telegram standalone Focus creates an unlinked interval without creating a task", () => {
  const operations = telegramCommandOps(
    pomodoistState([]),
    { type: "focus.start", id: "22222222-2222-4222-8222-222222222222" },
    new Date("2026-09-08T12:00:00Z"),
  );
  assertEquals(operations.map((op) => op.entityType), [
    "focus_run",
    "focus_interval",
    "focus_event",
    "focus_event",
  ]);
  assertEquals(operations[0].payload.taskId, null);
  assertEquals(operations[0].payload.projectId, null);
  assertEquals(operations[1].payload.taskId, null);
  assertEquals(operations[1].payload.plannedSeconds, 1500);
});

Deno.test("Telegram command UUID makes every generated entity idempotent", () => {
  const now = new Date("2026-07-07T12:00:00Z");
  for (
    const [state, command] of [
      [
        pomodoistState([task("task-1")]),
        {
          type: "task.complete",
          id: "33333333-3333-4333-8333-333333333333",
          taskId: "task-1",
        },
      ],
      [
        pomodoistState([task("task-1")]),
        {
          type: "focus.start",
          id: "44444444-4444-4444-8444-444444444444",
          taskId: "task-1",
        },
      ],
    ] as const
  ) {
    assertEquals(
      telegramCommandOps(state, command, now),
      telegramCommandOps(state, command, now),
    );
  }
});

Deno.test("Telegram rejects completing Focus before 25 active minutes", () => {
  const state = pomodoistState([
    focusRun("run-1"),
    focusInterval("interval-1", "run-1", {
      startedAt: "2026-07-07T12:00:00Z",
    }),
  ]);
  const command = {
    type: "focus.complete",
    id: "55555555-5555-4555-8555-555555555555",
  };

  assertThrows(
    () => telegramCommandOps(state, command, new Date("2026-07-07T12:24:59Z")),
    Error,
    "Focus interval has not elapsed.",
  );
  assertEquals(
    telegramCommandOps(state, command, new Date("2026-07-07T12:25:00Z"))[0]
      .payload.status,
    "completed",
  );
});

Deno.test("Telegram snapshot returns the whole Inbox page and active timer", () => {
  const state = pomodoistState([
    ...Array.from({ length: 13 }, (_, index) => task(`task-${index + 1}`)),
    focusRun("run-1"),
    focusInterval("interval-1", "run-1"),
  ]);
  const snapshot = telegramSnapshot(state, new Date("2026-07-07T12:00:00Z"));

  assertEquals(snapshot.inbox.length, 13);
  assertEquals(snapshot.focus?.run.id, "run-1");
  assertEquals(snapshot.focus?.interval.id, "interval-1");
});

Deno.test("snapshot includes at most twelve open tasks per project", async () => {
  const response = await handlePomodoistWatch(
    request({ command: { type: "snapshot.request" } }),
    deps({
      entities: [
        project("work", "Work"),
        ...Array.from({ length: 13 }, (_, index) =>
          task(`task-${index + 1}`, {
            projectId: "work",
            orderKey: `${index + 1}`.padStart(2, "0"),
          })),
      ],
    }),
  );

  const body = await response.json();
  const snapshot = body.snapshot as Record<string, unknown>;
  const tasks = snapshot.tasks as Record<string, unknown>;
  const byProject = tasks.byProject as
    | Record<string, Array<Record<string, unknown>>>
    | undefined;

  assertEquals(byProject?.work?.length, 12);
  assertEquals(byProject?.work?.map((item) => item.id), [
    "task-1",
    "task-2",
    "task-3",
    "task-4",
    "task-5",
    "task-6",
    "task-7",
    "task-8",
    "task-9",
    "task-10",
    "task-11",
    "task-12",
  ]);
});

Deno.test("task focus derives trusted task fields and requested preset", async () => {
  const rpcCalls: Array<
    { functionName: string; args: Record<string, unknown> }
  > = [];
  const response = await handlePomodoistWatch(
    request({
      command: {
        type: "focus.startDefault",
        id: "focus-task",
        presetId: "deep",
        taskId: "task-1",
        projectId: "stale-project",
        targetWorkIntervals: 99,
      },
    }),
    deps({
      rpcCalls,
      entities: [
        task("task-1", {
          projectId: "work",
          estimatedFocusIntervals: 3,
        }),
        focusPreset("deep", { workSeconds: 3000 }),
      ],
    }),
  );

  assertEquals(response.status, 200);
  const push = rpcCalls.find((call) => call.functionName === "push_changes");
  const ops = push?.args.p_operations as Array<Record<string, unknown>>;
  const run = ops?.[0]?.payload as Record<string, unknown>;
  const interval = ops?.[1]?.payload as Record<string, unknown>;
  assertEquals(run.taskId, "task-1");
  assertEquals(run.projectId, "work");
  assertEquals(run.presetId, "deep");
  assertEquals(run.targetWorkIntervals, 3);
  assertEquals(interval.taskId, "task-1");
  assertEquals(interval.projectId, "work");
  assertEquals(interval.plannedSeconds, 3000);
});

Deno.test("task focus replaces an active run only when confirmed", async () => {
  const entities = [
    task("task-1", { projectId: "work", estimatedFocusIntervals: 2 }),
    focusRun("run-1"),
    focusInterval("interval-1", "run-1"),
  ];
  const conflict = await handlePomodoistWatch(
    request({
      command: {
        type: "focus.startDefault",
        id: "focus-conflict",
        taskId: "task-1",
      },
    }),
    deps({ entities }),
  );
  assertEquals(conflict.status, 400);

  const rpcCalls: Array<
    { functionName: string; args: Record<string, unknown> }
  > = [];
  const replacement = await handlePomodoistWatch(
    request({
      command: {
        type: "focus.startDefault",
        id: "focus-replace",
        taskId: "task-1",
        replaceActive: true,
      },
    }),
    deps({ entities, rpcCalls }),
  );

  assertEquals(replacement.status, 200);
  const push = rpcCalls.find((call) => call.functionName === "push_changes");
  const ops = push?.args.p_operations as Array<Record<string, unknown>>;
  assertEquals(ops?.map((item) => item.entityType), [
    "focus_interval",
    "focus_run",
    "focus_run",
    "focus_interval",
  ]);
  assertEquals(ops?.map((item) => item.opId), [
    "focus-replace:stop",
    "focus-replace:stop:run",
    "focus-replace",
    "focus-replace:interval",
  ]);
  assertEquals(
    (ops?.[2]?.payload as Record<string, unknown>).taskId,
    "task-1",
  );
});

Deno.test("task focus rejects missing and completed tasks", async () => {
  for (
    const entities of [
      [],
      [task("task-1", { status: "completed" })],
    ]
  ) {
    const response = await handlePomodoistWatch(
      request({
        command: {
          type: "focus.startDefault",
          taskId: "task-1",
        },
      }),
      deps({ entities }),
    );
    assertEquals(response.status, 400);
  }
});

Deno.test("transcript command uses Cerebras first and returns drafts without writes", async () => {
  const rpcCalls: Array<
    { functionName: string; args: Record<string, unknown> }
  > = [];
  let providerBody: Record<string, unknown> | undefined;
  const urls: string[] = [];
  const response = await handlePomodoistWatch(
    request({
      command: {
        type: "task.decomposeTranscript",
        transcript: "Buy milk. Write notes",
        locale: "en",
      },
    }),
    deps({
      rpcCalls,
      env: { get: () => "test-key" },
      fetch: (async (input, init) => {
        urls.push(String(input));
        const body = (init as { body?: BodyInit } | undefined)?.body;
        providerBody = JSON.parse((body ?? "{}") as string);
        return Response.json({
          choices: [{
            message: {
              content: JSON.stringify({
                tasks: [{ quickAdd: "Buy milk" }, {
                  quickAdd: "Write notes",
                }],
              }),
            },
          }],
        });
      }) as typeof fetch,
    }),
  );

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.tasks, [{ quickAdd: "Buy milk" }, {
    quickAdd: "Write notes",
  }]);
  assertEquals(urls, ["https://api.cerebras.ai/v1/chat/completions"]);
  assertEquals(providerBody?.model, "gpt-oss-120b");
  assertEquals(providerBody?.reasoning_effort, "low");
  assertEquals(providerBody?.thinking, undefined);
  assertEquals(providerBody?.temperature, 0.1);
  assertEquals(providerBody?.max_tokens, 4096);
  assertEquals(rpcCalls, []);
});

Deno.test("transcript fallback preserves the input and uses available OpenRouter providers", async () => {
  const calls: Array<
    { url: string; body: Record<string, unknown>; key: string | null }
  > = [];
  for (
    const failure of [
      "http",
      "network",
      "timeout",
      "body_timeout",
      "json",
      "empty",
      "truncated",
    ]
  ) {
    calls.length = 0;
    const response = await handlePomodoistWatch(
      request({
        command: {
          type: "task.decomposeTranscript",
          transcript: "Позвонить маме завтра в 10. Купить молоко",
          locale: "ru-RU",
          currentLocalTime: "2026-09-05T12:00:00+03:00",
        },
      }),
      deps({
        env: {
          get: (key) =>
            ({
              CEREBRAS_API_KEY: "cerebras-test",
              POMODOIST_OPENROUTER_API_KEY: "openrouter-test",
              DEEPSEEK_API_KEY: "deepseek-test",
            } as Record<string, string>)[key],
        },
        fetch: (async (input, init) => {
          calls.push({
            url: String(input),
            body: JSON.parse((init as { body: string }).body),
            key: new Headers((init as { headers: HeadersInit }).headers).get(
              "Authorization",
            ),
          });
          if (calls.length === 1) {
            if (failure === "http") {
              return new Response("unavailable", { status: 503 });
            }
            if (failure === "network") throw new TypeError("network failed");
            if (failure === "timeout") {
              throw new DOMException("timed out", "TimeoutError");
            }
            if (failure === "body_timeout") {
              return new Response(
                new ReadableStream({
                  start(controller) {
                    controller.error(
                      new DOMException("timed out", "TimeoutError"),
                    );
                  },
                }),
              );
            }
            if (failure === "json") return new Response("not JSON");
            return Response.json({
              choices: [{
                finish_reason: failure === "truncated" ? "length" : "stop",
                message: {
                  content: failure === "empty"
                    ? '{"tasks":[]}'
                    : '{"tasks":[{"quickAdd":"partial"}]}',
                },
              }],
            });
          }
          return Response.json({
            choices: [{
              finish_reason: "stop",
              message: {
                content:
                  '{"tasks":[{"quickAdd":"Позвонить маме 2026-09-06 10:00"},{"quickAdd":"Купить молоко"}]}',
              },
            }],
          });
        }) as typeof fetch,
      }),
    );
    assertEquals(response.status, 200, failure);
    assertEquals((await response.json()).tasks, [{
      quickAdd: "Позвонить маме 2026-09-06 10:00",
    }, { quickAdd: "Купить молоко" }], failure);
    assertEquals(calls.map((call) => call.url), [
      "https://api.cerebras.ai/v1/chat/completions",
      "https://openrouter.ai/api/v1/chat/completions",
    ], failure);
    assertEquals(calls.map((call) => call.key), [
      "Bearer cerebras-test",
      "Bearer openrouter-test",
    ]);
    assertEquals(calls[1].body.model, "openai/gpt-oss-120b");
    assertEquals(calls[1].body.provider, {
      sort: "latency",
      allow_fallbacks: true,
      require_parameters: true,
      ignore: ["cerebras"],
    });
    assertEquals(calls[1].body.reasoning, { effort: "low" });
    assertEquals(calls[1].body.thinking, undefined);
    assertEquals(calls[1].body.messages, calls[0].body.messages);
  }
});

Deno.test("transcript falls through both unavailable APIs to DeepSeek Flash", async () => {
  const calls: Array<{ url: string; body: Record<string, unknown> }> = [];
  const response = await handlePomodoistWatch(
    request({
      command: {
        type: "task.decomposeTranscript",
        transcript: "Buy milk",
        locale: "en",
      },
    }),
    deps({
      env: { get: () => "test-key" },
      fetch: (async (input, init) => {
        calls.push({
          url: String(input),
          body: JSON.parse((init as { body: string }).body),
        });
        if (calls.length < 3) {
          return new Response("rate limited", { status: 429 });
        }
        return Response.json({
          choices: [{
            message: { content: '{"tasks":[{"quickAdd":"Buy milk"}]}' },
          }],
        });
      }) as typeof fetch,
    }),
  );
  assertEquals(response.status, 200);
  assertEquals((await response.json()).tasks, [{ quickAdd: "Buy milk" }]);
  assertEquals(calls.map((call) => call.url), [
    "https://api.cerebras.ai/v1/chat/completions",
    "https://openrouter.ai/api/v1/chat/completions",
    "https://api.deepseek.com/chat/completions",
  ]);
  assertEquals(calls[2].body.model, "deepseek-v4-flash");
  assertEquals(calls[2].body.thinking, { type: "disabled" });
  assertEquals(calls[2].body.temperature, 0.1);
  assertEquals(calls[2].body.reasoning, undefined);
  assertEquals(calls[2].body.reasoning_effort, undefined);
});

Deno.test("transcript skips missing keys and Smart stays on DeepSeek Flash", async () => {
  for (const smart of [false, true]) {
    const urls: string[] = [];
    const response = await handlePomodoistWatch(
      request({
        command: {
          type: "task.decomposeTranscript",
          transcript: "Buy milk",
          locale: "en",
          smart,
        },
      }),
      deps({
        env: {
          get: (key) =>
            smart || key === "DEEPSEEK_API_KEY" ? "test-key" : undefined,
        },
        fetch: (async (input, init) => {
          urls.push(String(input));
          const body = JSON.parse((init as { body: string }).body);
          assertEquals(body.model, "deepseek-v4-flash");
          assertEquals(body.thinking, { type: smart ? "enabled" : "disabled" });
          assertEquals(body.reasoning_effort, smart ? "high" : undefined);
          return Response.json({
            choices: [{
              message: { content: '{"tasks":[{"quickAdd":"Buy milk"}]}' },
            }],
          });
        }) as typeof fetch,
      }),
    );
    assertEquals(response.status, 200);
    assertEquals(urls, ["https://api.deepseek.com/chat/completions"]);
  }
});

Deno.test("transcript fallback and JSON retry share the 40 second budget", async () => {
  const originalNow = performance.now;
  const originalTimeout = AbortSignal.timeout;
  let elapsed = 0;
  const timeouts: number[] = [];
  performance.now = () => elapsed;
  AbortSignal.timeout = (ms) => {
    timeouts.push(ms);
    return new AbortController().signal;
  };
  try {
    let calls = 0;
    const response = await handlePomodoistWatch(
      request({
        command: {
          type: "task.decomposeTranscript",
          transcript: "Buy milk",
          locale: "en",
        },
      }),
      deps({
        env: { get: () => "test-key" },
        fetch: (async () => {
          calls += 1;
          elapsed = [8000, 20000, 39500, 40000][calls - 1];
          if (calls === 3) return Response.json({ choices: [] });
          throw new DOMException("timed out", "TimeoutError");
        }) as typeof fetch,
      }),
    );
    assertEquals(response.status, 504);
    assertEquals(timeouts, [8000, 12000, 20000, 500]);
    assertEquals(calls, 4);
  } finally {
    performance.now = originalNow;
    AbortSignal.timeout = originalTimeout;
  }
});

Deno.test("transcript command retries an invalid DeepSeek response", async () => {
  let fetchCalls = 0;
  const response = await handlePomodoistWatch(
    request({
      command: {
        type: "task.decomposeTranscript",
        transcript: "Call mom. Buy milk",
        locale: "en",
        smart: true,
      },
    }),
    deps({
      env: { get: () => "test-key" },
      fetch: (async () => {
        fetchCalls += 1;
        return Response.json({
          choices: [{
            message: {
              content: fetchCalls === 1
                ? ""
                : '{"tasks":[{"quickAdd":"Call mom"},{"quickAdd":"Buy milk"}]}',
            },
          }],
        });
      }) as typeof fetch,
    }),
  );

  assertEquals(response.status, 200);
  assertEquals((await response.json()).tasks, [
    { quickAdd: "Call mom" },
    { quickAdd: "Buy milk" },
  ]);
  assertEquals(fetchCalls, 2);
});

Deno.test("logged-out transcript accepts active Pomodoist StoreKit proof", async () => {
  const response = await handlePomodoistWatch(
    request({
      command: {
        type: "task.decomposeTranscript",
        transcript: "Buy milk",
        locale: "en-US",
      },
      storeTransactions: ["signed-pomodoist"],
    }),
    deps({
      user: null,
      env: { get: () => "test-key" },
      verifyStoreTransaction: async () => ({
        purchaseId: "original-1",
        transactionId: "tx-1",
        originalTransactionId: "original-1",
        productId: "pomodoist.pro.lifetime",
        bundleId: "com.finchforge.pomodoist",
        environment: "Production",
        claims: {},
      }),
      fetch: (async () =>
        Response.json({
          choices: [{
            message: { content: '{"tasks":[{"quickAdd":"Buy milk"}]}' },
          }],
        })) as typeof fetch,
    }),
  );

  assertEquals(response.status, 200);
});

Deno.test("logged-out transcript rejects a signed transaction for another product", async () => {
  let fetchCalls = 0;
  const response = await handlePomodoistWatch(
    request({
      command: {
        type: "task.decomposeTranscript",
        transcript: "Buy milk",
        locale: "en-US",
      },
      storeTransactions: ["signed-other"],
    }),
    deps({
      user: null,
      verifyStoreTransaction: async () => ({
        purchaseId: "original-1",
        transactionId: "tx-1",
        originalTransactionId: "original-1",
        productId: "other.product",
        bundleId: "com.finchforge.pomodoist",
        environment: "Production",
        claims: {},
      }),
      fetch: (async () => {
        fetchCalls += 1;
        return Response.json({});
      }) as typeof fetch,
    }),
  );

  assertEquals(response.status, 403);
  assertEquals((await response.json()).code, "purchase_verification_failed");
  assertEquals(fetchCalls, 0);
});

Deno.test("logged-out transcript rejects the removed Annual Launch product", async () => {
  const response = await handlePomodoistWatch(
    request({
      command: {
        type: "task.decomposeTranscript",
        transcript: "Buy milk",
        locale: "en-US",
      },
      storeTransactions: ["signed-annual-launch"],
    }),
    deps({
      user: null,
      verifyStoreTransaction: async () => ({
        purchaseId: "original-1",
        transactionId: "tx-1",
        originalTransactionId: "original-1",
        productId: "pomodoist.pro.annual.launch",
        bundleId: "com.finchforge.pomodoist",
        environment: "Production",
        expiresDate: "2026-08-01T00:00:00.000Z",
        claims: {},
      }),
    }),
  );

  assertEquals(response.status, 403);
});

Deno.test("logged-out transcript rejects an expired Pomodoist subscription", async () => {
  let fetchCalls = 0;
  const response = await handlePomodoistWatch(
    request({
      command: {
        type: "task.decomposeTranscript",
        transcript: "Buy milk",
        locale: "en-US",
      },
      storeTransactions: ["signed-expired"],
    }),
    deps({
      user: null,
      verifyStoreTransaction: async () => ({
        purchaseId: "original-1",
        transactionId: "tx-1",
        originalTransactionId: "original-1",
        productId: "pomodoist.pro.monthly",
        bundleId: "com.finchforge.pomodoist",
        environment: "Production",
        expiresDate: "2026-07-01T00:00:00.000Z",
        claims: {},
      }),
      fetch: (async () => {
        fetchCalls += 1;
        return Response.json({});
      }) as typeof fetch,
    }),
  );

  assertEquals(response.status, 403);
  assertEquals(fetchCalls, 0);
});

Deno.test("logged-out transcript rejects a revoked Pomodoist lifetime purchase", async () => {
  const response = await handlePomodoistWatch(
    request({
      command: {
        type: "task.decomposeTranscript",
        transcript: "Buy milk",
        locale: "en-US",
      },
      storeTransactions: ["signed-revoked"],
    }),
    deps({
      user: null,
      verifyStoreTransaction: async () => ({
        purchaseId: "original-1",
        transactionId: "tx-1",
        originalTransactionId: "original-1",
        productId: "pomodoist.pro.lifetime",
        bundleId: "com.finchforge.pomodoist",
        environment: "Production",
        revocationDate: "2026-07-01T00:00:00.000Z",
        claims: {},
      }),
    }),
  );

  assertEquals(response.status, 403);
});

Deno.test("logged-out transcript rejects a local StoreKit flag even with the legacy server flag", async () => {
  const response = await handlePomodoistWatch(
    request({
      command: {
        type: "task.decomposeTranscript",
        transcript: "Buy milk",
        locale: "en-US",
      },
      localStoreKit: true,
    }),
    deps({
      user: null,
      env: {
        get: (key) =>
          key === "DEEPSEEK_API_KEY"
            ? "test-key"
            : key === "POMODOIST_ALLOW_LOCAL_STOREKIT"
            ? "true"
            : undefined,
      },
      fetch: (async () =>
        Response.json({
          choices: [{
            message: { content: '{"tasks":[{"quickAdd":"Buy milk"}]}' },
          }],
        })) as typeof fetch,
    }),
  );

  assertEquals(response.status, 403);
});

Deno.test("transcript command uses the runtime UUID generator", async () => {
  const { uuid: _, ...runtimeDeps } = deps({
    env: { get: () => "test-key" },
    fetch: (async () =>
      Response.json({
        choices: [{
          message: { content: '{"tasks":[{"quickAdd":"Buy milk"}]}' },
        }],
      })) as typeof fetch,
  });

  const response = await handlePomodoistWatch(
    request({
      command: {
        type: "task.decomposeTranscript",
        transcript: "Buy milk",
        locale: "en",
      },
    }),
    runtimeDeps,
  );

  assertEquals(response.status, 200);
});

Deno.test("smart transcript command enables thinking and keeps subtasks", async () => {
  let deepSeekBody: Record<string, unknown> | undefined;
  const response = await handlePomodoistWatch(
    request({
      command: {
        type: "task.decomposeTranscript",
        transcript: "Plan launch with a brief",
        locale: "en-US",
        currentLocalTime: "2026-07-13T12:00:00+03:00",
        smart: true,
      },
    }),
    deps({
      env: {
        get: (key) => key === "DEEPSEEK_API_KEY" ? "test-key" : undefined,
      },
      fetch: (async (_input, init) => {
        const body = (init as { body?: BodyInit } | undefined)?.body;
        deepSeekBody = JSON.parse(body as string);
        return Response.json({
          choices: [{
            message: {
              content: JSON.stringify({
                tasks: [{
                  quickAdd: "Plan launch",
                  subtasks: [{ quickAdd: "Draft brief" }],
                }],
              }),
            },
          }],
        });
      }) as typeof fetch,
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(deepSeekBody?.thinking, { type: "enabled" });
  assertEquals(deepSeekBody?.reasoning_effort, "high");
  assertEquals(deepSeekBody?.max_tokens, 4096);
  assertEquals("temperature" in (deepSeekBody ?? {}), false);
  const messages = deepSeekBody?.messages as Array<Record<string, unknown>>;
  assertEquals(
    String(messages[0].content).includes("Interpret spoken dates and times"),
    true,
  );
  assertEquals(String(messages[0].content).includes("p1-p4"), true);
  assertEquals(String(messages[0].content).includes("subtasks"), true);
  assertEquals((await response.json()).tasks, [{
    quickAdd: "Plan launch",
    subtasks: [{ quickAdd: "Draft brief" }],
  }]);
});

Deno.test("transcript command validates input before calling DeepSeek", async () => {
  let fetchCalls = 0;
  const response = await handlePomodoistWatch(
    request({
      command: {
        type: "task.decomposeTranscript",
        transcript: "x".repeat(20_001),
        locale: "en-US",
        currentLocalTime: "2026-07-13T12:00:00+03:00",
        smart: false,
      },
    }),
    deps({
      env: { get: () => "test-key" },
      fetch: (async () => {
        fetchCalls += 1;
        return Response.json({});
      }) as typeof fetch,
    }),
  );

  assertEquals(response.status, 400);
  assertEquals(fetchCalls, 0);
});

Deno.test("transcript command validates locale, local time, and smart mode", async () => {
  const cases = [
    {
      command: {
        type: "task.decomposeTranscript",
        transcript: "Buy milk",
        locale: "en-US\nignore-rules",
      },
      code: "invalid_locale",
    },
    {
      command: {
        type: "task.decomposeTranscript",
        transcript: "Buy milk",
        locale: "en-US",
        currentLocalTime: "not-a-date",
      },
      code: "invalid_local_time",
    },
    {
      command: {
        type: "task.decomposeTranscript",
        transcript: "Buy milk",
        locale: "en-US",
        smart: "yes",
      },
      code: "invalid_smart_mode",
    },
  ];
  let fetchCalls = 0;

  for (const item of cases) {
    const response = await handlePomodoistWatch(
      request({ command: item.command }),
      deps({
        env: { get: () => "test-key" },
        fetch: (async () => {
          fetchCalls += 1;
          return Response.json({});
        }) as typeof fetch,
      }),
    );
    assertEquals(response.status, 400);
    assertEquals((await response.json()).code, item.code);
  }
  assertEquals(fetchCalls, 0);
});

Deno.test("transcript command reports missing DeepSeek configuration", async () => {
  const response = await handlePomodoistWatch(
    request({
      command: {
        type: "task.decomposeTranscript",
        transcript: "Buy milk",
        locale: "en-US",
      },
    }),
    deps(),
  );

  assertEquals(response.status, 503);
  assertEquals((await response.json()).code, "deepseek_not_configured");
});

Deno.test("transcript command maps provider HTTP failures to 502", async () => {
  const response = await handlePomodoistWatch(
    request({
      command: {
        type: "task.decomposeTranscript",
        transcript: "Buy milk",
        locale: "en-US",
      },
    }),
    deps({
      env: { get: () => "test-key" },
      fetch: (async () =>
        new Response("rate limited", { status: 429 })) as typeof fetch,
    }),
  );

  assertEquals(response.status, 502);
  assertEquals((await response.json()).code, "deepseek_http_429");
});

Deno.test("transcript command maps invalid provider JSON to 502", async () => {
  const response = await handlePomodoistWatch(
    request({
      command: {
        type: "task.decomposeTranscript",
        transcript: "Buy milk",
        locale: "en-US",
      },
    }),
    deps({
      env: { get: () => "test-key" },
      fetch: (async () => Response.json({ choices: [] })) as typeof fetch,
    }),
  );

  assertEquals(response.status, 502);
  assertEquals((await response.json()).code, "deepseek_invalid_response");
});

Deno.test("transcript command maps provider timeout to 504", async () => {
  const response = await handlePomodoistWatch(
    request({
      command: {
        type: "task.decomposeTranscript",
        transcript: "Buy milk",
        locale: "en-US",
      },
    }),
    deps({
      env: { get: () => "test-key" },
      fetch: (async () => {
        throw new DOMException("timed out", "TimeoutError");
      }) as typeof fetch,
    }),
  );

  assertEquals(response.status, 504);
  assertEquals((await response.json()).code, "deepseek_timeout");
});

function request(body: Record<string, unknown>) {
  return new Request("http://localhost/pomodoist-watch", {
    method: "POST",
    headers: {
      Authorization: "Bearer token",
      "content-type": "application/json",
    },
    body: JSON.stringify({ deviceId: "watch-test", ...body }),
  });
}

function deps(args: {
  entities?: Array<Record<string, unknown>>;
  rpcCalls?: Array<{ functionName: string; args: Record<string, unknown> }>;
  fetch?: typeof fetch;
  env?: { get: (key: string) => string | undefined };
  user?: { id: string } | null;
  verifyStoreTransaction?: () => Promise<AppleStoreTransaction>;
} = {}) {
  const entities = args.entities ?? [];
  const rpcCalls = args.rpcCalls ?? [];
  return {
    now: () => new Date("2026-07-07T12:00:00Z"),
    uuid: (() => {
      let counter = 0;
      return () => `uuid-${++counter}`;
    })(),
    fetch: args.fetch ?? fetch,
    env: args.env ?? { get: () => "" },
    verifyStoreTransaction: args.verifyStoreTransaction,
    createClient: () => ({
      auth: {
        getUser: async () => ({
          data: {
            user: args.user === undefined ? { id: "user-1" } : args.user,
          },
        }),
      },
      rpc: async (functionName: string, rpcArgs: Record<string, unknown>) => {
        rpcCalls.push({ functionName, args: rpcArgs });
        if (functionName === "pull_changes") {
          return {
            data: {
              nextCursor: 1,
              hasMore: false,
              changes: entities,
            },
            error: null,
          };
        }
        return { data: { serverRevision: 2, applied: [] }, error: null };
      },
    }),
  };
}

function project(id: string, name: string) {
  return {
    entityType: "project",
    entityId: id,
    serverRevision: 1,
    data: {
      id,
      userId: "local-user",
      name,
      color: null,
      parentId: null,
      viewStyle: "list",
      isFavorite: false,
      isArchived: false,
      isDeleted: false,
      orderKey: "a",
      createdAt: "2026-07-07T00:00:00Z",
      updatedAt: "2026-07-07T00:00:00Z",
    },
  };
}

function task(id: string, overrides: Record<string, unknown> = {}) {
  return {
    entityType: "task",
    entityId: id,
    serverRevision: 1,
    data: {
      id,
      userId: "local-user",
      content: "Write",
      description: null,
      projectId: "inbox",
      sectionId: null,
      parentId: null,
      priority: 4,
      dueJson: null,
      deadlineJson: null,
      durationSeconds: null,
      status: "open",
      estimatedFocusIntervals: null,
      completedFocusIntervals: 0,
      totalFocusSeconds: 0,
      orderKey: "a",
      dayOrder: null,
      isCollapsed: false,
      isDeleted: false,
      createdAt: "2026-07-07T00:00:00Z",
      updatedAt: "2026-07-07T00:00:00Z",
      completedAt: null,
      ...overrides,
    },
  };
}

function focusPreset(
  id: string,
  overrides: Record<string, unknown> = {},
) {
  return {
    entityType: "focus_preset",
    entityId: id,
    serverRevision: 1,
    data: {
      id,
      name: "Deep Work",
      workSeconds: 50 * 60,
      shortBreakSeconds: 10 * 60,
      longBreakSeconds: 20 * 60,
      intervalsBeforeLongBreak: 4,
      allowPause: true,
      strictMode: false,
      isDefault: false,
      isDeleted: false,
      ...overrides,
    },
  };
}

function focusRun(id: string, overrides: Record<string, unknown> = {}) {
  return {
    entityType: "focus_run",
    entityId: id,
    serverRevision: 1,
    data: {
      id,
      status: "active",
      presetId: "classic",
      taskId: null,
      projectId: null,
      startedAt: "2026-07-07T11:00:00Z",
      targetWorkIntervals: 4,
      completedWorkIntervals: 0,
      isDeleted: false,
      ...overrides,
    },
  };
}

function focusInterval(
  id: string,
  runId: string,
  overrides: Record<string, unknown> = {},
) {
  return {
    entityType: "focus_interval",
    entityId: id,
    serverRevision: 1,
    data: {
      id,
      runId,
      status: "running",
      type: "work",
      plannedSeconds: 1500,
      startedAt: "2026-07-07T11:00:00Z",
      pausedAt: null,
      pausedTotalSeconds: 0,
      sequenceNumber: 1,
      isDeleted: false,
      ...overrides,
    },
  };
}

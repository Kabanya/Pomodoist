import { assert, assertEquals } from "@std/assert";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";

import { registerPomodoistTools } from "./tools.ts";

Deno.test("registers exactly the 23 Pomodoist V1 tools", async () => {
  await withClient(() => Promise.reject(new Error("unexpected fetch")), async (
    client,
  ) => {
    const capabilities = client.getServerCapabilities();
    assert(capabilities?.tools);
    assert(!capabilities?.resources);
    assert(!capabilities?.prompts);
    const listed = await client.listTools();
    assertEquals(listed.tools.map((tool) => tool.name), [
      "list_tasks",
      "get_task",
      "list_projects",
      "list_labels",
      "get_kanban_board",
      "list_focus_history",
      "get_productivity_report",
      "get_achievements",
      "create_task",
      "update_task",
      "complete_task",
      "restore_task",
      "delete_task",
      "create_project",
      "update_project",
      "delete_project",
      "create_label",
      "delete_label",
      "create_kanban_status",
      "update_kanban_status",
      "delete_kanban_status",
      "configure_kanban",
      "move_task_on_kanban",
    ]);
    for (const tool of listed.tools) {
      assertEquals(tool.inputSchema.additionalProperties, false, tool.name);
      assert(tool.outputSchema, `${tool.name} lacks outputSchema`);
      assertEquals(tool.annotations?.openWorldHint, false, tool.name);
      const schema = JSON.stringify(tool.inputSchema);
      for (
        const excluded of [
          "confirmed",
          "deadline",
          "duration",
          "timer",
          "preset",
          "billing",
          "calendar",
        ]
      ) {
        assert(!schema.includes(excluded), `${tool.name} exposes ${excluded}`);
      }
    }
    const byName = Object.fromEntries(
      listed.tools.map((tool) => [tool.name, tool]),
    );
    const listTaskVariants = byName.list_tasks.inputSchema
      .oneOf as JsonSchema[];
    assertEquals(listTaskVariants.length, 8);
    const variantsByView = Object.fromEntries(
      listTaskVariants.map((variant) => [
        (variant.properties?.view as JsonSchema).const,
        variant,
      ]),
    );
    assertEquals(
      Object.keys(variantsByView).sort(),
      [
        "all",
        "completed",
        "date",
        "inbox",
        "project",
        "search",
        "today",
        "upcoming",
      ],
    );
    assertEquals(variantsByView.today.required?.sort(), [
      "time_zone",
      "view",
    ]);
    assertEquals(variantsByView.date.required?.sort(), [
      "date",
      "time_zone",
      "view",
    ]);
    assertEquals(variantsByView.project.required?.sort(), [
      "project_id",
      "view",
    ]);
    assertEquals(variantsByView.search.required?.sort(), ["query", "view"]);
    for (const variant of listTaskVariants) {
      assertEquals(variant.additionalProperties, false);
    }
    for (const tool of listed.tools) {
      const schema = tool.outputSchema as JsonSchema;
      assertEquals(schema.oneOf?.length, 2, `${tool.name} envelope`);
      const success = schema.oneOf?.find((variant) =>
        (variant.properties?.ok as JsonSchema | undefined)?.const === true
      );
      const failure = schema.oneOf?.find((variant) =>
        (variant.properties?.ok as JsonSchema | undefined)?.const === false
      );
      assertEquals(success?.required?.sort(), ["data", "ok"], tool.name);
      assertEquals(failure?.required?.sort(), ["error", "ok"], tool.name);
      assert(!success?.properties?.error, tool.name);
      assert(!failure?.properties?.data, tool.name);
      assertEquals(success?.additionalProperties, false, tool.name);
      assertEquals(failure?.additionalProperties, false, tool.name);
      assert(schema.properties?.data, `${tool.name} has no typed data`);
    }
    const taskData = byName.get_task.outputSchema!.properties
      ?.data as JsonSchema;
    assertEquals(taskData.required?.includes("id"), true);
    assertEquals(taskData.required?.includes("content"), true);
    const projectPage = byName.list_projects.outputSchema!.properties
      ?.data as JsonSchema;
    assertEquals(projectPage.required?.sort(), ["items", "nextCursor"]);
    assertEquals(
      projectPage.properties?.items?.items?.required?.includes("name"),
      true,
    );
    const mutationData = byName.create_task.outputSchema!.properties
      ?.data as JsonSchema;
    assertEquals(mutationData.required?.sort(), ["id", "server_revision"]);
    for (
      const name of [
        "list_tasks",
        "get_task",
        "list_projects",
        "list_labels",
        "get_kanban_board",
        "list_focus_history",
        "get_productivity_report",
        "get_achievements",
      ]
    ) {
      assertEquals(byName[name].annotations?.readOnlyHint, true, name);
    }
    for (
      const name of [
        "delete_task",
        "delete_project",
        "delete_label",
        "delete_kanban_status",
      ]
    ) {
      assertEquals(byName[name].annotations?.destructiveHint, true, name);
    }
  });
});

Deno.test("routes every read tool through the closed read dispatcher", async () => {
  const calls: RpcCall[] = [];
  let localizedAchievements: unknown;
  let productivityReport: unknown;
  await withClient(rpcFetcher(calls), async (client) => {
    const cases: [string, Record<string, unknown>][] = [
      ["list_tasks", { view: "today", time_zone: "Europe/Moscow" }],
      ["get_task", { task_id: "task-a" }],
      ["list_projects", {}],
      ["list_labels", { limit: 25 }],
      ["get_kanban_board", {}],
      ["list_focus_history", { cursor: "opaque" }],
      [
        "get_productivity_report",
        { date: "2026-07-30", time_zone: "UTC" },
      ],
      [
        "get_achievements",
        { date: "2026-07-30", time_zone: "UTC", locale: "ru" },
      ],
    ];
    for (const [name, args] of cases) {
      const result = await client.callTool({ name, arguments: args });
      assertSuccessParity(result);
      if (name === "get_achievements") {
        localizedAchievements = result.structuredContent;
      } else if (name === "get_productivity_report") {
        productivityReport = result.structuredContent;
      }
    }
  });
  assertEquals(
    calls.filter((call) => call.rpc === "read_pomodoist_mcp").map((call) =>
      call.body.p_operation
    ),
    [
      "list_tasks",
      "get_task",
      "list_projects",
      "list_labels",
      "get_kanban_board",
      "list_focus_history",
      "get_productivity_report",
      "get_achievements",
    ],
  );
  const achievements = calls.find((call) =>
    call.body.p_operation === "get_achievements"
  );
  assertEquals(achievements?.body.p_arguments, {
    date: "2026-07-30",
    time_zone: "UTC",
  });
  assertEquals(
    (calls.find((call) => call.body.p_operation === "list_tasks")
      ?.body.p_arguments as Record<string, unknown>).limit,
    50,
  );
  const serializedAchievements = JSON.stringify(localizedAchievements);
  assert(serializedAchievements.includes('"title":"Первый помидор"'));
  assert(serializedAchievements.includes('"id":"combo_day_not_wasted"'));
  assert(!serializedAchievements.includes("comboFlags"));
  assert(!serializedAchievements.includes("dayNotWasted"));
  const serializedReport = JSON.stringify(productivityReport);
  assert(!serializedReport.includes("achievementInputs"));
  assert(!serializedReport.includes("comboFlags"));
});

Deno.test("executes one atomic write and a later hint for every mutation tool", async () => {
  const calls: RpcCall[] = [];
  await withClient(rpcFetcher(calls), async (client) => {
    const cases: [string, Record<string, unknown>][] = [
      ["create_task", {
        content: "Created",
        description: "Details",
        priority: 2,
        project_id: "project-a",
        parent_id: "task-a",
        label_names: ["Home"],
        estimate: 2,
        schedule: {
          type: "all_day",
          date: "2026-08-01",
          recurrence: { frequency: "week", interval: 2 },
        },
      }],
      ["update_task", {
        task_id: "task-a",
        description: null,
        parent_id: null,
        schedule: null,
      }],
      ["complete_task", { task_id: "task-a" }],
      ["restore_task", { task_id: "task-completed" }],
      [
        "delete_task",
        { task_id: "task-a", recurrence_scope: "selected_and_following" },
      ],
      ["create_project", { name: "New project", color: "#3B82F6" }],
      ["update_project", {
        project_id: "project-a",
        color: "#6366F1",
        is_favorite: true,
      }],
      ["delete_project", { project_id: "project-a" }],
      ["create_label", { name: "New label" }],
      ["delete_label", { label_id: "label-a" }],
      ["create_kanban_status", { name: "Review", color: "#123456" }],
      ["update_kanban_status", {
        status_id: "status-a",
        name: "Ready",
        target_index: 1,
      }],
      ["delete_kanban_status", { status_id: "status-a" }],
      ["configure_kanban", {
        project_ids: ["inbox", "project-a"],
        focus_status_id: "status-a",
      }],
      ["move_task_on_kanban", {
        task_id: "task-a",
        status_id: "status-a",
        target_index: 0,
      }],
    ];
    for (const [name, args] of cases) {
      const before = calls.length;
      const result = await client.callTool({ name, arguments: args });
      assertSuccessParity(result);
      const mutationCalls = calls.slice(before);
      assertEquals(
        mutationCalls.filter((call) =>
          call.rpc === "push_pomodoist_mcp_changes"
        ).length,
        1,
        name,
      );
      assertEquals(mutationCalls.at(-1)?.rpc, "send_pomodoist_mcp_sync_hint");
      const writeIndex = mutationCalls.findIndex((call) =>
        call.rpc === "push_pomodoist_mcp_changes"
      );
      const hintIndex = mutationCalls.findIndex((call) =>
        call.rpc === "send_pomodoist_mcp_sync_hint"
      );
      assert(writeIndex >= 0 && hintIndex > writeIndex, name);
    }
  });
});

Deno.test("preserves omitted task fields and clears explicit nullable fields", async () => {
  const calls: RpcCall[] = [];
  await withClient(rpcFetcher(calls), async (client) => {
    assertSuccessParity(
      await client.callTool({
        name: "update_task",
        arguments: { task_id: "task-a", description: null, schedule: null },
      }),
    );
  });
  const operations = writeOperations(calls);
  const task = operations.find((operation) => operation.entityType === "task")
    ?.payload as Record<string, unknown>;
  assertEquals(task.content, "Task A");
  assertEquals(task.description, null);
  assertEquals(task.dueJson, null);
  assertEquals(task.priority, 4);
  assert(!("deadlineJson" in task));
  assert(!("durationSeconds" in task));
});

Deno.test("creates a Kanban status with the complete Flutter sync label row", async () => {
  const calls: RpcCall[] = [];
  await withClient(rpcFetcher(calls), async (client) => {
    assertSuccessParity(
      await client.callTool({
        name: "create_kanban_status",
        arguments: { name: "Review", color: "#123456" },
      }),
    );
  });

  const operations = writeOperations(calls);
  const create = operations.find((operation) =>
    operation.payload.commandType === "kanban.status.create"
  )!;
  assertEquals(create.entityType, "label");
  assertEquals(create.operation, "upsert");
  assertEquals(create.entityId, create.payload.id);
  assert(
    /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
      .test(create.opId),
  );
  assertEquals(create.clientUpdatedAt, create.payload.createdAt);
  assertEquals(create.clientUpdatedAt, create.payload.updatedAt);
  assertEquals(payloadKeys(create), [
    "color",
    "commandType",
    "createdAt",
    "id",
    "isDeleted",
    "isFavorite",
    "kind",
    "name",
    "orderKey",
    "systemKey",
    "updatedAt",
    "userId",
  ]);
  assertEquals(create.payload, {
    id: create.entityId,
    userId: "local-user",
    name: "Review",
    color: "#123456",
    kind: "kanbanStatus",
    systemKey: null,
    orderKey: create.payload.orderKey,
    isFavorite: false,
    isDeleted: false,
    createdAt: create.clientUpdatedAt,
    updatedAt: create.clientUpdatedAt,
    commandType: "kanban.status.create",
  });

  const reorders = operations.filter((operation) =>
    operation.payload.commandType === "kanban.status.reorder"
  );
  assert(reorders.length > 0);
  for (const reorder of reorders) {
    assertEquals(payloadKeys(reorder), [
      "changedAt",
      "commandType",
      "id",
      "orderKey",
    ]);
  }
});

Deno.test("emits captured patches and preserves restored status during reorder", async () => {
  const calls: RpcCall[] = [];
  await withClient(rpcFetcher(calls), async (client) => {
    assertSuccessParity(
      await client.callTool({
        name: "update_kanban_status",
        arguments: {
          status_id: "status-a",
          name: "Ready",
          color: "#123456",
          target_index: 1,
        },
      }),
    );
    const statusOperations = writeOperations(calls);
    const rename = statusOperations.find((operation) =>
      operation.payload.commandType === "kanban.status.rename"
    )!;
    assertEquals(payloadKeys(rename), [
      "changedAt",
      "color",
      "commandType",
      "id",
      "name",
    ]);
    for (
      const operation of statusOperations.filter((operation) =>
        operation.payload.commandType === "kanban.status.reorder"
      )
    ) {
      assertEquals(payloadKeys(operation), [
        "changedAt",
        "commandType",
        "id",
        "orderKey",
      ]);
    }

    assertSuccessParity(
      await client.callTool({
        name: "configure_kanban",
        arguments: {
          project_ids: ["inbox"],
          focus_status_id: "status-a",
        },
      }),
    );
    const settingsOperations = writeOperations(calls);
    assertEquals(settingsOperations.length, 2);
    assertEquals(
      settingsOperations.map((operation) => payloadKeys(operation)),
      [
        [
          "changedAt",
          "commandType",
          "id",
          "selectedProjectIdsJson",
        ],
        [
          "changedAt",
          "commandType",
          "focusStatusLabelId",
          "id",
        ],
      ],
    );

    assertSuccessParity(
      await client.callTool({
        name: "move_task_on_kanban",
        arguments: {
          task_id: "task-completed",
          status_id: "status-a",
          target_index: 0,
        },
      }),
    );
    const moveOperations = writeOperations(calls);
    const reorder = moveOperations.find((operation) =>
      operation.payload.commandType === "task.reorder"
    )!;
    assertEquals(payloadKeys(reorder), [
      "changedAt",
      "commandType",
      "id",
      "orderKey",
    ]);
    let resultingTask = structuredClone(snapshot.tasks[2]) as Record<
      string,
      unknown
    >;
    for (
      const operation of moveOperations.filter((operation) =>
        operation.entityType === "task" &&
        operation.entityId === "task-completed" &&
        operation.operation === "upsert"
      )
    ) {
      resultingTask = { ...resultingTask, ...operation.payload };
    }
    assertEquals(resultingTask.status, "open");
    assertEquals(resultingTask.completedAt, null);
  });
});

Deno.test("materializes the next selected recurring subtree in the same atomic batch", async () => {
  const recurring = structuredClone(snapshot);
  (recurring.tasks[0] as Record<string, unknown>).dueJson = JSON.stringify({
    type: "allDay",
    date: "2026-07-01",
    recurrence: { interval: 1, unit: "week", seriesId: "series-a" },
  });
  const calls: RpcCall[] = [];
  await withClient(
    rpcFetcher(calls, { snapshot: recurring }),
    async (client) => {
      assertSuccessParity(
        await client.callTool({
          name: "delete_task",
          arguments: {
            task_id: "task-a",
            recurrence_scope: "selected",
          },
        }),
      );
    },
  );
  const operations = writeOperations(calls);
  const copiedTasks = operations.filter((operation) =>
    operation.entityType === "task" &&
    operation.operation === "upsert" &&
    operation.entityId.startsWith("rec-")
  );
  assertEquals(copiedTasks.length, 2);
  assertEquals(
    copiedTasks.filter((operation) =>
      operation.payload.parentId === copiedTasks[0].entityId
    ).length,
    1,
  );
  assertEquals(
    operations.filter((operation) =>
      operation.entityType === "task" && operation.operation === "delete"
    ).length,
    2,
  );
  assertEquals(
    operations.filter((operation) => operation.entityType === "task_label")
      .length,
    1,
  );
  assertEquals(
    operations.filter((operation) =>
      operation.entityType === "task_kanban_status" &&
      operation.entityId.startsWith("rec-") &&
      operation.payload.labelId === "status-a"
    ).length,
    2,
  );
});

Deno.test("keeps a timed recurrence at the same IANA local time across DST", async () => {
  const recurring = structuredClone(snapshot);
  (recurring.tasks[0] as Record<string, unknown>).dueJson = JSON.stringify({
    type: "timed",
    start: "2026-10-25T13:00:00.000Z",
    end: "2026-10-25T14:00:00.000Z",
    timeZone: "America/New_York",
    recurrence: { interval: 1, unit: "week", seriesId: "series-dst" },
  });
  const calls: RpcCall[] = [];
  await withClient(
    rpcFetcher(calls, { snapshot: recurring }),
    async (client) => {
      assertSuccessParity(
        await client.callTool({
          name: "delete_task",
          arguments: {
            task_id: "task-a",
            recurrence_scope: "selected",
          },
        }),
      );
    },
  );
  const rootCopy = writeOperations(calls).find((operation) =>
    operation.entityType === "task" &&
    operation.operation === "upsert" &&
    operation.payload.parentId === null
  )!;
  assertEquals(
    JSON.parse(rootCopy.payload.dueJson as string).start,
    "2026-11-01T14:00:00.000Z",
  );
});

Deno.test("uses top-level recurrence series for selected-and-following", async () => {
  const recurring = structuredClone(snapshot);
  recurring.tasks = [
    {
      ...recurring.tasks[0],
      dueJson: JSON.stringify({
        type: "allDay",
        date: "2026-08-01",
        recurrenceSeriesId: "legacy-series",
      }),
    },
    {
      ...recurring.tasks[2],
      id: "task-following",
      parentId: null,
      status: "open",
      completedAt: null,
      dueJson: JSON.stringify({
        type: "allDay",
        date: "2026-08-08",
        recurrenceSeriesId: "legacy-series",
      }),
    },
  ] as unknown as typeof recurring.tasks;
  const calls: RpcCall[] = [];
  await withClient(
    rpcFetcher(calls, { snapshot: recurring }),
    async (client) => {
      assertSuccessParity(
        await client.callTool({
          name: "delete_task",
          arguments: {
            task_id: "task-a",
            recurrence_scope: "selected_and_following",
          },
        }),
      );
    },
  );
  assertEquals(
    writeOperations(calls).filter((operation) =>
      operation.entityType === "task" && operation.operation === "delete"
    ).map((operation) => operation.entityId).sort(),
    ["task-a", "task-following"],
  );
});

Deno.test("never materializes malformed legacy recurrence", async () => {
  for (
    const recurrence of [
      { interval: 0, unit: "day", seriesId: "series-zero" },
      { interval: -1, unit: "week", seriesId: "series-negative" },
      { interval: 1000, unit: "month", seriesId: "series-large" },
      { interval: 1.5, unit: "day", seriesId: "series-fraction" },
      { interval: 1, unit: "year", seriesId: "series-unit" },
      { interval: 1, unit: "day", seriesId: " " },
    ]
  ) {
    const recurring = structuredClone(snapshot);
    (recurring.tasks[0] as Record<string, unknown>).dueJson = JSON.stringify({
      type: "allDay",
      date: "2099-07-01",
      recurrence,
    });
    const calls: RpcCall[] = [];
    await withClient(
      rpcFetcher(calls, { snapshot: recurring }),
      async (client) => {
        assertSuccessParity(
          await client.callTool({
            name: "delete_task",
            arguments: {
              task_id: "task-a",
              recurrence_scope: "selected",
            },
          }),
        );
      },
    );
    assertEquals(
      writeOperations(calls).filter((operation) =>
        operation.entityType === "task" &&
        operation.operation === "upsert" &&
        operation.entityId.startsWith("rec-")
      ).length,
      0,
      JSON.stringify(recurrence),
    );
  }
});

Deno.test("does not overwrite an existing deterministic next occurrence", async () => {
  const recurring = structuredClone(snapshot);
  const due = {
    type: "allDay",
    date: "2099-07-01",
    recurrence: { interval: 1, unit: "week", seriesId: "existing-series" },
  };
  (recurring.tasks[0] as Record<string, unknown>).dueJson = JSON.stringify(due);
  const nextId = await deterministicRecurringId(
    "existing-series",
    "2099-07-08",
    "task-a",
  );
  recurring.tasks.push(
    {
      ...recurring.tasks[0],
      id: nextId,
      content: "Already materialized",
      dueJson: JSON.stringify({ ...due, date: "2099-07-08" }),
    } as unknown as typeof recurring.tasks[number],
  );
  const calls: RpcCall[] = [];
  await withClient(
    rpcFetcher(calls, { snapshot: recurring }),
    async (client) => {
      assertSuccessParity(
        await client.callTool({
          name: "delete_task",
          arguments: {
            task_id: "task-a",
            recurrence_scope: "selected",
          },
        }),
      );
    },
  );
  assertEquals(
    writeOperations(calls).filter((operation) =>
      operation.entityId === nextId && operation.operation === "upsert"
    ).length,
    0,
  );
});

Deno.test("allows the first MCP mutation before system anchors exist", async () => {
  const empty = {
    tasks: [],
    projects: [],
    labels: [],
    taskLabels: [],
    assignments: [],
    completions: [],
    settings: null,
  } as unknown as typeof snapshot;
  const calls: RpcCall[] = [];
  await withClient(rpcFetcher(calls, { snapshot: empty }), async (client) => {
    assertSuccessParity(
      await client.callTool({
        name: "create_task",
        arguments: { content: "First task" },
      }),
    );
  });
  assertEquals(
    writeOperations(calls).find((operation) => operation.entityType === "task")
      ?.payload.projectId,
    "inbox",
  );
});

Deno.test("rejects invalid schedules, recurrence, empty updates, and excluded fields", async () => {
  await withClient(rpcFetcher([]), async (client) => {
    for (
      const arguments_ of [
        {
          content: "Bad date",
          schedule: { type: "all_day", date: "2026-02-30" },
        },
        {
          content: "Bad range",
          schedule: {
            type: "timed",
            start: "2026-08-01T10:00:00Z",
            end: "2026-08-01T09:00:00Z",
            time_zone: "UTC",
          },
        },
        {
          content: "Bad recurrence",
          schedule: {
            type: "all_day",
            date: "2026-08-01",
            recurrence: { frequency: "year", interval: 0 },
          },
        },
        { content: "Excluded", deadline: "2026-08-01" },
      ]
    ) {
      const result = await client.callTool({
        name: "create_task",
        arguments: arguments_,
      });
      assertEquals(result.isError, true);
    }
    assertEquals(
      (await client.callTool({
        name: "update_task",
        arguments: { task_id: "task-a" },
      })).isError,
      true,
    );
  });
});

Deno.test("cascades task/project/label/status mutations and protects anchors", async () => {
  const calls: RpcCall[] = [];
  await withClient(rpcFetcher(calls), async (client) => {
    assertSuccessParity(
      await client.callTool({
        name: "complete_task",
        arguments: { task_id: "task-a" },
      }),
    );
    const completed = writeOperations(calls);
    assertEquals(
      completed.filter((operation) =>
        operation.entityType === "task" &&
        operation.payload.status === "completed"
      ).length,
      2,
    );
    assertEquals(
      completed.filter((operation) =>
        operation.entityType === "task_completion"
      ).length,
      2,
    );

    for (
      const [name, arguments_] of [
        ["delete_project", { project_id: "inbox" }],
        [
          "delete_kanban_status",
          { status_id: "kanban-status-backlog-v1" },
        ],
        ["delete_kanban_status", { status_id: "kanban-status-done-v1" }],
      ] as const
    ) {
      const result = await client.callTool({ name, arguments: arguments_ });
      assertToolError(result, "forbidden");
    }
  });
});

Deno.test("maps RPC failures and keeps committed mutations successful after hint failure", async () => {
  const logs: unknown[] = [];
  let hintFails = true;
  const calls: RpcCall[] = [];
  await withClient(
    rpcFetcher(calls, {
      response(call) {
        if (call.rpc === "send_pomodoist_mcp_sync_hint" && hintFails) {
          return Response.json({ code: "hint_failed" }, { status: 500 });
        }
      },
    }),
    async (client) => {
      const result = await client.callTool({
        name: "create_label",
        arguments: { name: "Committed" },
      });
      assertSuccessParity(result);
      hintFails = false;
    },
    logs,
  );
  assert(
    logs.some((entry) =>
      (entry as Record<string, unknown>).outcome === "hint_failed"
    ),
  );

  await withClient(
    rpcFetcher([], {
      response(call) {
        if (call.rpc === "read_pomodoist_mcp") {
          return Response.json({ code: "42501" }, { status: 403 });
        }
      },
    }),
    async (client) => {
      assertToolError(
        await client.callTool({ name: "list_projects", arguments: {} }),
        "forbidden",
      );
    },
  );
});

type RpcCall = {
  rpc: string;
  body: Record<string, unknown>;
};
type JsonSchema = {
  type?: string;
  const?: unknown;
  properties?: Record<string, JsonSchema>;
  required?: string[];
  additionalProperties?: boolean;
  oneOf?: JsonSchema[];
  items?: JsonSchema;
};

const auth = {
  subject: "11111111-1111-4111-8111-111111111111",
  sessionId: "22222222-2222-4222-8222-222222222222",
  clientId: "33333333-3333-4333-8333-333333333333",
  userId: "44444444-4444-4444-8444-444444444444",
};
const config = {
  issuer: "https://example.test/auth/v1",
  resourceUrl: "https://example.test/functions/v1/pomodoist-mcp",
  allowedOrigins: [],
  supabaseUrl: "https://example.test",
  serviceRoleKey: "service-role",
};

async function withClient(
  fetcher: typeof fetch,
  callback: (client: Client) => Promise<void>,
  logs: unknown[] = [],
) {
  const server = new McpServer({ name: "test", version: "1" });
  registerPomodoistTools(server, auth, {
    config,
    fetch: fetcher,
    log: (entry) => logs.push(entry),
  });
  const client = new Client({ name: "test", version: "1" });
  const [clientTransport, serverTransport] = InMemoryTransport
    .createLinkedPair();
  await server.connect(serverTransport);
  await client.connect(clientTransport);
  try {
    await callback(client);
  } finally {
    await client.close();
    await server.close();
  }
}

function rpcFetcher(
  calls: RpcCall[],
  options: {
    response?: (call: RpcCall) => Response | undefined;
    snapshot?: typeof snapshot;
  } = {},
): typeof fetch {
  return (input, init) => {
    const rpc = new URL(String(input)).pathname.split("/").at(-1)!;
    const requestInit = init as RequestInit | undefined;
    const call = {
      rpc,
      body: JSON.parse(
        String(requestInit?.body ?? "{}"),
      ) as Record<string, unknown>,
    };
    calls.push(call);
    const override = options.response?.(call);
    if (override) return Promise.resolve(override);
    if (rpc === "read_pomodoist_mcp") {
      const operation = call.body.p_operation;
      if (operation === "mutation_snapshot") {
        return Promise.resolve(Response.json(options.snapshot ?? snapshot));
      }
      if (operation === "get_task") {
        return Promise.resolve(Response.json({
          status: "found",
          task: publicTask(snapshot.tasks[0]),
        }));
      }
      if (operation === "get_kanban_board") {
        return Promise.resolve(Response.json({
          settings: {
            id: "kanban-settings-primary-v1",
            selectedProjectIds: ["inbox", "project-a"],
            focusStatusLabelId: "status-a",
            createdAt: "2026-07-30T10:00:00.000Z",
            updatedAt: "2026-07-30T10:00:00.000Z",
          },
          statuses: [],
          assignments: [],
        }));
      }
      if (
        operation === "get_productivity_report" ||
        operation === "get_achievements"
      ) {
        return Promise.resolve(Response.json(metrics));
      }
      return Promise.resolve(Response.json({ items: [], nextCursor: null }));
    }
    if (rpc === "push_pomodoist_mcp_changes") {
      return Promise.resolve(Response.json({
        serverRevision: 9,
        applied: [],
      }));
    }
    if (rpc === "send_pomodoist_mcp_sync_hint") {
      return Promise.resolve(Response.json(null));
    }
    return Promise.resolve(Response.json({ code: "unexpected" }, {
      status: 500,
    }));
  };
}

function assertSuccessParity(result: unknown) {
  const value = result as {
    content: Array<{ type: string; text: string }>;
    structuredContent?: unknown;
    isError?: boolean;
  };
  assertEquals(value.isError, undefined, JSON.stringify(value));
  assertEquals(
    JSON.parse(value.content[0].text),
    value.structuredContent,
  );
  assertEquals(
    (value.structuredContent as Record<string, unknown>).ok,
    true,
  );
}

function assertToolError(result: unknown, code: string) {
  const value = result as {
    content: Array<{ text: string }>;
    structuredContent?: {
      ok: boolean;
      error: { code: string };
    };
    isError?: boolean;
  };
  assertEquals(value.isError, true);
  assertEquals(value.structuredContent?.ok, false);
  assertEquals(value.structuredContent?.error.code, code);
  assertEquals(JSON.parse(value.content[0].text), value.structuredContent);
}

function writeOperations(calls: RpcCall[]) {
  const write = calls.findLast((call) =>
    call.rpc === "push_pomodoist_mcp_changes"
  );
  return write?.body.p_operations as Array<{
    opId: string;
    entityType: string;
    entityId: string;
    operation: string;
    payload: Record<string, unknown>;
    clientUpdatedAt: string;
  }>;
}

function publicTask(value: Record<string, unknown>) {
  return {
    id: value.id,
    content: value.content,
    description: value.description,
    projectId: value.projectId,
    parentId: value.parentId,
    priority: value.priority,
    dueJson: value.dueJson,
    status: value.status,
    estimatedFocusIntervals: value.estimatedFocusIntervals,
    completedFocusIntervals: value.completedFocusIntervals,
    totalFocusSeconds: value.totalFocusSeconds,
    orderKey: value.orderKey,
    dayOrder: value.dayOrder,
    createdAt: value.createdAt,
    updatedAt: value.updatedAt,
    completedAt: value.completedAt,
  };
}

function payloadKeys(operation: {
  payload: Record<string, unknown>;
}) {
  return Object.keys(operation.payload).sort();
}

async function deterministicRecurringId(
  seriesId: string,
  occurrenceKey: string,
  sourceId: string,
) {
  const digest = await crypto.subtle.digest(
    "SHA-1",
    new TextEncoder().encode(`${seriesId}|${occurrenceKey}|${sourceId}`),
  );
  return `rec-${
    [...new Uint8Array(digest)].map((byte) =>
      byte.toString(16).padStart(2, "0")
    ).join("")
  }`;
}

const snapshot = {
  tasks: [
    {
      id: "task-a",
      userId: "local-user",
      content: "Task A",
      description: "Old",
      projectId: "project-a",
      parentId: null,
      priority: 4,
      dueJson: null,
      status: "open",
      estimatedFocusIntervals: 1,
      completedFocusIntervals: 0,
      totalFocusSeconds: 0,
      orderKey: "00000000000000000100",
      dayOrder: null,
      isCollapsed: false,
      isDeleted: false,
      createdAt: "2026-07-30T10:00:00.000Z",
      updatedAt: "2026-07-30T10:00:00.000Z",
      completedAt: null,
    },
    {
      id: "task-child",
      userId: "local-user",
      content: "Child",
      description: null,
      projectId: "project-a",
      parentId: "task-a",
      priority: 4,
      dueJson: null,
      status: "open",
      estimatedFocusIntervals: null,
      completedFocusIntervals: 0,
      totalFocusSeconds: 0,
      orderKey: "00000000000000000200",
      dayOrder: null,
      isCollapsed: false,
      isDeleted: false,
      createdAt: "2026-07-30T10:00:00.000Z",
      updatedAt: "2026-07-30T10:00:00.000Z",
      completedAt: null,
    },
    {
      id: "task-completed",
      userId: "local-user",
      content: "Completed",
      description: null,
      projectId: "project-a",
      parentId: null,
      priority: 4,
      dueJson: null,
      status: "completed",
      estimatedFocusIntervals: null,
      completedFocusIntervals: 0,
      totalFocusSeconds: 0,
      orderKey: "00000000000000000300",
      dayOrder: null,
      isCollapsed: false,
      isDeleted: false,
      createdAt: "2026-07-30T10:00:00.000Z",
      updatedAt: "2026-07-30T11:00:00.000Z",
      completedAt: "2026-07-30T11:00:00.000Z",
    },
  ],
  projects: [
    {
      id: "inbox",
      name: "Inbox",
      color: null,
      isFavorite: true,
      isArchived: false,
      orderKey: "a",
    },
    {
      id: "project-a",
      name: "Project A",
      color: "#3B82F6",
      isFavorite: false,
      isArchived: false,
      orderKey: "b",
    },
  ],
  labels: [
    {
      id: "kanban-status-backlog-v1",
      name: "Backlog",
      kind: "kanbanStatus",
      systemKey: "backlog",
      orderKey: "00000000000000000000",
    },
    {
      id: "status-a",
      name: "To do",
      kind: "kanbanStatus",
      systemKey: null,
      orderKey: "00000000000000001000",
    },
    {
      id: "kanban-status-done-v1",
      name: "Done",
      kind: "kanbanStatus",
      systemKey: "done",
      orderKey: "00004503599627370496",
    },
    {
      id: "label-a",
      name: "Home",
      kind: "user",
      orderKey: "a",
    },
  ],
  taskLabels: [{
    entityId: "task-a:label-a",
    taskId: "task-a",
    labelId: "label-a",
    kind: "user",
  }],
  assignments: [
    {
      taskId: "task-a",
      labelId: "status-a",
      changedAt: "2026-07-30T10:00:00.000Z",
    },
    {
      taskId: "task-child",
      labelId: "status-a",
      changedAt: "2026-07-30T10:00:00.000Z",
    },
    {
      taskId: "task-completed",
      labelId: "kanban-status-done-v1",
      changedAt: "2026-07-30T11:00:00.000Z",
    },
  ],
  completions: [{
    id: "completion-old",
    taskId: "task-completed",
    userId: "local-user",
    completedAt: "2026-07-30T11:00:00.000Z",
    snapshotJson: '{"version":1,"kanban":{"previousStatusLabelId":"status-a"}}',
    createdAt: "2026-07-30T11:00:00.000Z",
  }],
  settings: {
    id: "kanban-settings-primary-v1",
    selectedProjectIdsJson: '["inbox","project-a"]',
    focusStatusLabelId: "status-a",
    createdAt: "2026-07-30T10:00:00.000Z",
    updatedAt: "2026-07-30T10:00:00.000Z",
  },
};

const metrics = {
  reportDate: "2026-07-30",
  timeZone: "UTC",
  daily: {
    completedTasks: 3,
    completedFocusIntervals: 3,
    totalFocusSeconds: 4500,
  },
  plannedFocusIntervals: 2,
  openTasks: 1,
  allTime: { completedTasks: 7, completedFocusIntervals: 5 },
  lastSevenDays: Array.from({ length: 7 }, (_, index) => ({
    date: `2026-07-${String(24 + index).padStart(2, "0")}`,
    completedTasks: index,
    completedFocusIntervals: index,
    totalFocusSeconds: index * 1500,
  })),
  achievementInputs: {
    completedTasks: 7,
    completedWorkIntervals: 5,
    comboFlags: {
      dayNotWasted: true,
      focusPlusCheck: true,
      noFuss: false,
      cleanEntry: true,
      tomatoClosed: true,
    },
  },
};

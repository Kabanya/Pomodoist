import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

import {
  type PomodoistMcpAuth,
  type PomodoistMcpConfig,
  type PomodoistMcpFetch,
  type PomodoistMcpLog,
  toolError,
  toolSuccess,
} from "./pomodoist_mcp.ts";

type RecordValue = Record<string, unknown>;
type Operation = {
  opId: string;
  entityType: string;
  entityId: string;
  operation: "upsert" | "delete";
  payload: RecordValue;
  clientUpdatedAt: string;
};

export type PomodoistToolDependencies = {
  config: PomodoistMcpConfig;
  fetch?: PomodoistMcpFetch;
  log?: (entry: PomodoistMcpLog) => void;
};

const localUserId = "local-user";
const inboxId = "inbox";
const backlogId = "kanban-status-backlog-v1";
const doneId = "kanban-status-done-v1";
const settingsId = "kanban-settings-primary-v1";
const maximumOrder = 4503599627370496;
const projectPalette = [
  "#E44332",
  "#E8793E",
  "#C58A16",
  "#8A9A2D",
  "#36A269",
  "#2A9D8F",
  "#2F9CB3",
  "#3B82F6",
  "#6366F1",
  "#8B5CF6",
  "#B657C4",
  "#D45584",
  "#9B6B4F",
  "#64748B",
] as const;
const projectColor = z.enum(projectPalette);

const entityId = z.string().regex(/^[A-Za-z0-9][A-Za-z0-9._:-]{0,199}$/);
const cursor = z.string().min(1).max(4096);
const limit = z.number().int().min(1).max(100).default(50);
const date = z.string().refine(validDate, "Invalid calendar date.");
const timeZone = z.string().refine(validTimeZone, "Invalid IANA time zone.");
const name = z.string().trim().min(1).max(200);
const content = z.string().trim().min(1).max(2000);
const description = z.string().max(10000);
const color = z.string().trim().toUpperCase().regex(/^#[0-9A-F]{6}$/);
const recurrence = z.object({
  frequency: z.enum(["day", "week", "month"]),
  interval: z.number().int().min(1).max(999),
}).strict();
const allDaySchedule = z.object({
  type: z.literal("all_day"),
  date,
  recurrence: recurrence.optional(),
}).strict();
const timedSchedule = z.object({
  type: z.literal("timed"),
  start: z.string().refine(validRfc3339, "Invalid RFC 3339 start."),
  end: z.string().refine(validRfc3339, "Invalid RFC 3339 end."),
  time_zone: timeZone,
  recurrence: recurrence.optional(),
}).strict().refine(
  (value) => Date.parse(value.end) > Date.parse(value.start),
  "Timed schedule end must be after start.",
);
const schedule = z.discriminatedUnion("type", [
  allDaySchedule,
  timedSchedule,
]);
const pagination = { limit, cursor: cursor.optional() };
const publicTaskSchema = z.object({
  id: entityId,
  content: z.string().nullable(),
  description: z.string().nullable(),
  projectId: entityId.nullable(),
  parentId: entityId.nullable(),
  priority: z.number().int().nullable(),
  dueJson: z.string().nullable(),
  status: z.enum(["open", "completed"]).nullable(),
  estimatedFocusIntervals: z.number().int().nullable(),
  completedFocusIntervals: z.number().int().nullable(),
  totalFocusSeconds: z.number().int().nullable(),
  orderKey: z.string().nullable(),
  dayOrder: z.number().int().nullable(),
  createdAt: z.string().nullable(),
  updatedAt: z.string().nullable(),
  completedAt: z.string().nullable(),
}).strict();
const publicProjectSchema = z.object({
  id: entityId,
  name: z.string().nullable(),
  color: z.string().nullable(),
  parentId: entityId.nullable(),
  viewStyle: z.string().nullable(),
  isFavorite: z.boolean().nullable(),
  isArchived: z.boolean().nullable(),
  orderKey: z.string().nullable(),
  createdAt: z.string().nullable(),
  updatedAt: z.string().nullable(),
}).strict();
const publicLabelSchema = z.object({
  id: entityId,
  name: z.string().nullable(),
  color: z.string().nullable(),
  orderKey: z.string().nullable(),
  isFavorite: z.boolean().nullable(),
  createdAt: z.string().nullable(),
  updatedAt: z.string().nullable(),
}).strict();
const focusHistorySchema = z.object({
  id: entityId,
  taskId: entityId.nullable(),
  projectId: entityId.nullable(),
  startedAt: z.string(),
  completedAt: z.string(),
  actualSeconds: z.number().int().nonnegative(),
}).strict();
const kanbanBoardSchema = z.object({
  settings: z.object({
    id: entityId,
    selectedProjectIds: z.array(entityId),
    focusStatusLabelId: entityId.nullable(),
    createdAt: z.string().nullable().optional(),
    updatedAt: z.string().nullable().optional(),
  }).strict(),
  statuses: z.array(
    z.object({
      id: entityId,
      name: z.string().nullable(),
      color: z.string().nullable(),
      systemKey: z.string().nullable(),
      orderKey: z.string().nullable(),
      createdAt: z.string().nullable(),
      updatedAt: z.string().nullable(),
    }).strict(),
  ),
  assignments: z.array(
    z.object({
      taskId: entityId,
      statusId: entityId,
    }).strict(),
  ),
}).strict();
const dailyMetricsSchema = z.object({
  completedTasks: z.number().int().nonnegative(),
  completedFocusIntervals: z.number().int().nonnegative(),
  totalFocusSeconds: z.number().int().nonnegative(),
}).strict();
const productivityReportSchema = z.object({
  reportDate: date,
  timeZone,
  daily: dailyMetricsSchema,
  plannedFocusIntervals: z.number().int().nonnegative(),
  openTasks: z.number().int().nonnegative(),
  allTime: z.object({
    completedTasks: z.number().int().nonnegative(),
    completedFocusIntervals: z.number().int().nonnegative(),
  }).strict(),
  lastSevenDays: z.array(
    z.object({
      date,
      completedTasks: z.number().int().nonnegative(),
      completedFocusIntervals: z.number().int().nonnegative(),
      totalFocusSeconds: z.number().int().nonnegative(),
    }).strict(),
  ).length(7),
}).strict();
const achievementSchema = z.object({
  id: z.string().min(1),
  group: z.enum(["focus", "task", "combo"]),
  presentation: z.enum(["globalBanner", "bottomPlaque"]),
  title: z.string(),
  subtitle: z.string(),
  progress: z.number().int().nonnegative(),
  target: z.number().int().positive(),
  unlocked: z.boolean(),
}).strict();
const mutationResultSchema = z.object({
  id: entityId,
  server_revision: z.union([z.number().int(), z.string()]).nullable(),
}).strict();
const toolErrorSchema = z.object({
  code: z.enum([
    "invalid_argument",
    "not_found",
    "conflict",
    "forbidden",
    "rate_limited",
    "internal",
  ]),
  message: z.string(),
  retry_after_seconds: z.number().int().positive().optional(),
}).strict();

function pageSchema(item: z.ZodType) {
  return z.object({
    items: z.array(item),
    nextCursor: z.string().nullable(),
  }).strict();
}

function jsonSchema(schema: z.ZodType) {
  const converted = z.toJSONSchema(schema, {
    target: "draft-7",
    io: "input",
  }) as Record<string, unknown>;
  const { $schema: _schema, ...result } = converted;
  return result;
}

function outputEnvelope(dataSchema: z.ZodType) {
  const success = z.object({
    ok: z.literal(true),
    data: dataSchema,
  }).strict();
  const failure = z.object({
    ok: z.literal(false),
    error: toolErrorSchema,
  }).strict();
  return z.object({
    ok: z.boolean(),
    data: dataSchema.optional(),
    error: toolErrorSchema.optional(),
  }).strict().superRefine((value, context) => {
    if (
      (value.ok && (!("data" in value) || value.error !== undefined)) ||
      (!value.ok && (value.error === undefined || "data" in value))
    ) {
      context.addIssue({
        code: "custom",
        message: "Invalid tool result envelope.",
      });
    }
  }).meta({ oneOf: [jsonSchema(success), jsonSchema(failure)] });
}

const outputSchemas = {
  taskPage: outputEnvelope(pageSchema(publicTaskSchema)),
  task: outputEnvelope(publicTaskSchema),
  projectPage: outputEnvelope(pageSchema(publicProjectSchema)),
  labelPage: outputEnvelope(pageSchema(publicLabelSchema)),
  kanbanBoard: outputEnvelope(kanbanBoardSchema),
  focusPage: outputEnvelope(pageSchema(focusHistorySchema)),
  productivity: outputEnvelope(productivityReportSchema),
  achievements: outputEnvelope(z.array(achievementSchema)),
  mutation: outputEnvelope(mutationResultSchema),
};
const readOutputSchemas: Record<string, z.ZodType> = {
  list_tasks: outputSchemas.taskPage,
  get_task: outputSchemas.task,
  list_projects: outputSchemas.projectPage,
  list_labels: outputSchemas.labelPage,
  get_kanban_board: outputSchemas.kanbanBoard,
  list_focus_history: outputSchemas.focusPage,
  get_productivity_report: outputSchemas.productivity,
};

const listTaskVariants = [
  z.object({ view: z.literal("inbox"), ...pagination }).strict(),
  z.object({
    view: z.literal("today"),
    time_zone: timeZone,
    ...pagination,
  }).strict(),
  z.object({
    view: z.literal("upcoming"),
    time_zone: timeZone,
    ...pagination,
  }).strict(),
  z.object({
    view: z.literal("date"),
    time_zone: timeZone,
    date,
    ...pagination,
  }).strict(),
  z.object({
    view: z.literal("project"),
    project_id: entityId,
    ...pagination,
  }).strict(),
  z.object({
    view: z.literal("search"),
    query: z.string().trim().min(1).max(500),
    ...pagination,
  }).strict(),
  z.object({ view: z.literal("all"), ...pagination }).strict(),
  z.object({ view: z.literal("completed"), ...pagination }).strict(),
] as const;
const listTasksSchema = z.object({
  view: z.enum([
    "inbox",
    "today",
    "upcoming",
    "date",
    "project",
    "search",
    "all",
    "completed",
  ]),
  time_zone: timeZone.optional(),
  date: date.optional(),
  project_id: entityId.optional(),
  query: z.string().trim().min(1).max(500).optional(),
  ...pagination,
}).strict().superRefine((value, context) => {
  const expected = new Set<string>(["view", "limit", "cursor"]);
  if (["today", "upcoming", "date"].includes(value.view)) {
    expected.add("time_zone");
    if (!value.time_zone) {
      context.addIssue({ code: "custom", message: "time_zone is required." });
    }
  }
  if (value.view === "date") {
    expected.add("date");
    if (!value.date) {
      context.addIssue({ code: "custom", message: "date is required." });
    }
  }
  if (value.view === "project") {
    expected.add("project_id");
    if (!value.project_id) {
      context.addIssue({ code: "custom", message: "project_id is required." });
    }
  }
  if (value.view === "search") {
    expected.add("query");
    if (!value.query) {
      context.addIssue({ code: "custom", message: "query is required." });
    }
  }
  for (const key of ["time_zone", "date", "project_id", "query"] as const) {
    if (value[key] !== undefined && !expected.has(key)) {
      context.addIssue({
        code: "custom",
        path: [key],
        message: `${key} is not valid for this view.`,
      });
    }
  }
}).meta({ oneOf: listTaskVariants.map(jsonSchema) });
const noArgs = z.object({}).strict();
const paged = z.object(pagination).strict();
const report = z.object({ date, time_zone: timeZone }).strict();
const createTaskSchema = z.object({
  content,
  description: description.nullable().optional(),
  priority: z.number().int().min(1).max(4).optional(),
  project_id: entityId.optional(),
  parent_id: entityId.optional(),
  label_names: z.array(name).max(100).default([]),
  estimate: z.number().int().min(1).max(999).optional(),
  schedule: schedule.optional(),
}).strict();
const updateTaskSchema = z.object({
  task_id: entityId,
  content: content.optional(),
  description: description.nullable().optional(),
  priority: z.number().int().min(1).max(4).optional(),
  project_id: entityId.optional(),
  parent_id: entityId.nullable().optional(),
  label_names: z.array(name).max(100).optional(),
  estimate: z.number().int().min(1).max(999).nullable().optional(),
  schedule: schedule.nullable().optional(),
}).strict().refine(
  (value) => Object.keys(value).some((key) => key !== "task_id"),
  "At least one changed field is required.",
);
const createProjectSchema = z.object({
  name,
  color: projectColor.optional(),
}).strict();
const updateProjectSchema = z.object({
  project_id: entityId,
  color: z.union([projectColor, z.null()]).optional(),
  is_favorite: z.boolean().optional(),
}).strict().refine(
  (value) => value.color !== undefined || value.is_favorite !== undefined,
  "At least one changed field is required.",
);
const createStatusSchema = z.object({
  name,
  color: color.nullable().optional(),
}).strict();
const updateStatusSchema = z.object({
  status_id: entityId,
  name: name.optional(),
  color: color.nullable().optional(),
  target_index: z.number().int().min(1).optional(),
}).strict().refine(
  (value) =>
    value.name !== undefined ||
    value.color !== undefined ||
    value.target_index !== undefined,
  "At least one changed field is required.",
);

export function registerPomodoistTools(
  server: McpServer,
  auth: PomodoistMcpAuth,
  dependencies: PomodoistToolDependencies,
) {
  const fetcher = dependencies.fetch ?? fetch;
  const context = {
    auth,
    config: dependencies.config,
    fetcher,
    log: dependencies.log ?? (() => {}),
  };
  const readAnnotations = {
    readOnlyHint: true,
    openWorldHint: false,
  };
  const closedAnnotations = { openWorldHint: false };
  const destructiveAnnotations = {
    destructiveHint: true,
    openWorldHint: false,
  };

  registerRead(
    server,
    "list_tasks",
    listTasksSchema,
    readAnnotations,
    context,
  );
  registerRead(
    server,
    "get_task",
    z.object({ task_id: entityId }).strict(),
    readAnnotations,
    context,
    (data) => {
      const value = record(data);
      if (value?.status !== "found") {
        throw new ToolFailure("not_found", "Task not found.");
      }
      return value.task;
    },
  );
  registerRead(server, "list_projects", paged, readAnnotations, context);
  registerRead(server, "list_labels", paged, readAnnotations, context);
  registerRead(server, "get_kanban_board", noArgs, readAnnotations, context);
  registerRead(server, "list_focus_history", paged, readAnnotations, context);
  registerRead(
    server,
    "get_productivity_report",
    report,
    readAnnotations,
    context,
    productivityReport,
  );
  server.registerTool(
    "get_achievements",
    {
      inputSchema: z.object({
        date,
        time_zone: timeZone,
        locale: z.enum(["ru", "en"]),
      }).strict(),
      outputSchema: outputSchemas.achievements,
      annotations: readAnnotations,
    },
    safe(async ({ locale, ...arguments_ }) => {
      const metrics = await readRpc(context, "get_achievements", arguments_);
      return toolSuccess(achievements(metrics, locale));
    }),
  );

  server.registerTool(
    "create_task",
    {
      inputSchema: createTaskSchema,
      outputSchema: outputSchemas.mutation,
      annotations: closedAnnotations,
    },
    safe(async (arguments_) => {
      const snapshot = await mutationSnapshot(context);
      const now = new Date().toISOString();
      const id = crypto.randomUUID();
      const projectId = arguments_.project_id ?? inboxId;
      requireProject(snapshot, projectId);
      if (arguments_.parent_id) {
        const parent = requireTask(snapshot, arguments_.parent_id);
        if (parent.projectId !== projectId) {
          throw new ToolFailure(
            "conflict",
            "Parent task belongs to another project.",
          );
        }
      }
      const operations = [
        upsert("task", id, {
          schemaVersion: 1,
          commandType: "task.create",
          id,
          userId: localUserId,
          content: arguments_.content,
          description: arguments_.description ?? null,
          projectId,
          sectionId: null,
          parentId: arguments_.parent_id ?? null,
          priority: arguments_.priority ?? 4,
          dueJson: arguments_.schedule ? dueJson(arguments_.schedule) : null,
          status: "open",
          estimatedFocusIntervals: arguments_.estimate ?? null,
          completedFocusIntervals: 0,
          totalFocusSeconds: 0,
          orderKey: orderKey(),
          dayOrder: null,
          isCollapsed: false,
          isDeleted: false,
          createdAt: now,
          updatedAt: now,
          completedAt: null,
        }, now),
        assignment(id, backlogId, now),
        ...labelAdditions(snapshot, id, arguments_.label_names, now),
      ];
      return mutate(context, operations, { id });
    }),
  );

  server.registerTool(
    "update_task",
    {
      inputSchema: updateTaskSchema,
      outputSchema: outputSchemas.mutation,
      annotations: closedAnnotations,
    },
    safe(async (arguments_) => {
      const snapshot = await mutationSnapshot(context);
      const task = requireTask(snapshot, arguments_.task_id);
      const now = new Date().toISOString();
      const projectId = arguments_.project_id ?? string(task.projectId);
      requireProject(snapshot, projectId);
      const nextParent = arguments_.parent_id === undefined
        ? nullableString(task.parentId)
        : arguments_.parent_id;
      validateParent(snapshot, string(task.id), nextParent, projectId);
      const subtree = descendants(snapshot.tasks, task.id);
      const changedTasks = arguments_.project_id === undefined
        ? [task]
        : subtree;
      const operations = changedTasks.map((row) => {
        const root = row.id === task.id;
        return upsert(
          "task",
          row.id,
          sanitizeTask({
            ...row,
            commandType: arguments_.project_id !== undefined
              ? "task.move"
              : "task.update",
            ...(root && arguments_.content !== undefined
              ? { content: arguments_.content }
              : {}),
            ...(root && arguments_.description !== undefined
              ? { description: arguments_.description }
              : {}),
            ...(root && arguments_.priority !== undefined
              ? { priority: arguments_.priority }
              : {}),
            ...(root && arguments_.estimate !== undefined
              ? { estimatedFocusIntervals: arguments_.estimate }
              : {}),
            ...(root && arguments_.schedule !== undefined
              ? {
                dueJson: arguments_.schedule === null
                  ? null
                  : dueJson(arguments_.schedule),
              }
              : {}),
            ...(arguments_.project_id !== undefined
              ? { projectId, sectionId: null }
              : {}),
            ...(root ? { parentId: nextParent } : {}),
            updatedAt: now,
          }),
          now,
        );
      });
      operations.push(
        ...labelAdditions(
          snapshot,
          string(task.id),
          arguments_.label_names ?? [],
          now,
        ),
      );
      return mutate(context, operations, { id: task.id });
    }),
  );

  registerTaskAction(
    server,
    "complete_task",
    closedAnnotations,
    context,
    completeOperations,
  );
  registerTaskAction(
    server,
    "restore_task",
    closedAnnotations,
    context,
    restoreOperations,
  );
  server.registerTool(
    "delete_task",
    {
      inputSchema: z.object({
        task_id: entityId,
        recurrence_scope: z.enum([
          "selected",
          "selected_and_following",
        ]).default("selected"),
      }).strict(),
      outputSchema: outputSchemas.mutation,
      annotations: destructiveAnnotations,
    },
    safe(async ({ task_id, recurrence_scope }) => {
      const snapshot = await mutationSnapshot(context);
      const task = requireTask(snapshot, task_id);
      const now = new Date().toISOString();
      const operations = await deleteTaskOperations(
        snapshot,
        task,
        recurrence_scope,
        now,
      );
      return mutate(context, operations, { id: task.id });
    }),
  );

  server.registerTool(
    "create_project",
    {
      inputSchema: createProjectSchema,
      outputSchema: outputSchemas.mutation,
      annotations: closedAnnotations,
    },
    safe(async (arguments_) => {
      const snapshot = await mutationSnapshot(context);
      if (
        snapshot.projects.some((project) =>
          string(project.name).toLowerCase() ===
            arguments_.name.toLowerCase()
        )
      ) {
        throw new ToolFailure("conflict", "Project name already exists.");
      }
      const now = new Date().toISOString();
      const id = crypto.randomUUID();
      const projectColor = arguments_.color ??
        nextProjectColor(snapshot.projects);
      return mutate(context, [
        upsert("project", id, {
          schemaVersion: 1,
          commandType: "project.create",
          id,
          userId: localUserId,
          name: arguments_.name,
          color: projectColor,
          parentId: null,
          viewStyle: "list",
          isFavorite: false,
          isArchived: false,
          isDeleted: false,
          orderKey: orderKey(),
          createdAt: now,
          updatedAt: now,
        }, now),
      ], { id });
    }),
  );
  server.registerTool(
    "update_project",
    {
      inputSchema: updateProjectSchema,
      outputSchema: outputSchemas.mutation,
      annotations: closedAnnotations,
    },
    safe(async (arguments_) => {
      if (arguments_.project_id === inboxId) {
        throw new ToolFailure("forbidden", "Inbox cannot be changed.");
      }
      const snapshot = await mutationSnapshot(context);
      const project = requireProject(snapshot, arguments_.project_id);
      const now = new Date().toISOString();
      return mutate(context, [
        upsert("project", project.id, {
          ...project,
          commandType: "project.update",
          ...(arguments_.color !== undefined
            ? { color: arguments_.color }
            : {}),
          ...(arguments_.is_favorite !== undefined
            ? { isFavorite: arguments_.is_favorite }
            : {}),
          updatedAt: now,
        }, now),
      ], { id: project.id });
    }),
  );
  server.registerTool(
    "delete_project",
    {
      inputSchema: z.object({ project_id: entityId }).strict(),
      outputSchema: outputSchemas.mutation,
      annotations: destructiveAnnotations,
    },
    safe(async ({ project_id }) => {
      if (project_id === inboxId) {
        throw new ToolFailure("forbidden", "Inbox cannot be deleted.");
      }
      const snapshot = await mutationSnapshot(context);
      const project = requireProject(snapshot, project_id);
      const now = new Date().toISOString();
      const operations = snapshot.tasks
        .filter((task) => task.projectId === project_id)
        .map((task) =>
          upsert(
            "task",
            task.id,
            sanitizeTask({
              ...task,
              commandType: "task.move",
              projectId: inboxId,
              sectionId: null,
              updatedAt: now,
            }),
            now,
          )
        );
      const selected = selectedProjectIds(snapshot.settings)
        .filter((id) => id !== project_id);
      if (selected.length === 0) selected.push(inboxId);
      if (
        JSON.stringify(selected) !==
          JSON.stringify(selectedProjectIds(snapshot.settings))
      ) {
        operations.push(settingsOperation(
          snapshot.settings,
          { selectedProjectIdsJson: JSON.stringify(selected) },
          now,
        ));
      }
      operations.push(remove("project", project.id, {
        commandType: "project.delete",
        id: project.id,
      }, now));
      return mutate(context, operations, { id: project.id });
    }),
  );

  server.registerTool(
    "create_label",
    {
      inputSchema: z.object({ name }).strict(),
      outputSchema: outputSchemas.mutation,
      annotations: closedAnnotations,
    },
    safe(async ({ name }) => {
      const snapshot = await mutationSnapshot(context);
      if (
        snapshot.labels.some((label) =>
          label.kind === "user" &&
          string(label.name).toLowerCase() === name.toLowerCase()
        )
      ) {
        throw new ToolFailure("conflict", "Label name already exists.");
      }
      const now = new Date().toISOString();
      const id = crypto.randomUUID();
      return mutate(context, [
        upsert("label", id, userLabel(id, name, now), now),
      ], { id });
    }),
  );
  server.registerTool(
    "delete_label",
    {
      inputSchema: z.object({ label_id: entityId }).strict(),
      outputSchema: outputSchemas.mutation,
      annotations: destructiveAnnotations,
    },
    safe(async ({ label_id }) => {
      const snapshot = await mutationSnapshot(context);
      const label = requireLabel(snapshot, label_id, "user");
      const now = new Date().toISOString();
      const operations = snapshot.taskLabels
        .filter((relation) => relation.labelId === label.id)
        .map((relation) =>
          remove("task_label", relation.entityId, {
            commandType: "task.label.delete",
            taskId: relation.taskId,
            labelId: relation.labelId,
          }, now)
        );
      operations.push(remove("label", label.id, {
        commandType: "label.delete",
        id: label.id,
      }, now));
      return mutate(context, operations, { id: label.id });
    }),
  );

  server.registerTool(
    "create_kanban_status",
    {
      inputSchema: createStatusSchema,
      outputSchema: outputSchemas.mutation,
      annotations: closedAnnotations,
    },
    safe(async ({ name, color }) => {
      const snapshot = await mutationSnapshot(context);
      ensureUniqueStatusName(snapshot, name);
      const now = new Date().toISOString();
      const id = crypto.randomUUID();
      const statuses = kanbanStatuses(snapshot);
      statuses.splice(Math.max(1, statuses.length - 1), 0, {
        id,
        userId: localUserId,
        name,
        color: color ?? null,
        kind: "kanbanStatus",
        systemKey: null,
        orderKey: "",
        isFavorite: false,
        isDeleted: false,
        createdAt: now,
        updatedAt: now,
      });
      const operations = reorderStatuses(statuses, now, id);
      return mutate(context, operations, { id });
    }),
  );
  server.registerTool(
    "update_kanban_status",
    {
      inputSchema: updateStatusSchema,
      outputSchema: outputSchemas.mutation,
      annotations: closedAnnotations,
    },
    safe(async (arguments_) => {
      const snapshot = await mutationSnapshot(context);
      const status = requireLabel(
        snapshot,
        arguments_.status_id,
        "kanbanStatus",
      );
      if (arguments_.name !== undefined) {
        ensureUniqueStatusName(snapshot, arguments_.name, string(status.id));
      }
      if (
        arguments_.target_index !== undefined &&
        (status.id === backlogId || status.id === doneId)
      ) {
        throw new ToolFailure(
          "forbidden",
          "System Kanban statuses cannot be reordered.",
        );
      }
      const now = new Date().toISOString();
      const operations: Operation[] = [];
      if (
        arguments_.name !== undefined ||
        arguments_.color !== undefined
      ) {
        operations.push(upsert("label", status.id, {
          id: status.id,
          commandType: "kanban.status.rename",
          ...(arguments_.name !== undefined ? { name: arguments_.name } : {}),
          ...(arguments_.color !== undefined
            ? { color: arguments_.color }
            : {}),
          changedAt: now,
        }, now));
      }
      if (arguments_.target_index === undefined) {
        return mutate(context, operations, {
          id: status.id,
        });
      }
      const statuses = kanbanStatuses(snapshot)
        .filter((item) => item.id !== status.id);
      statuses.splice(
        Math.min(arguments_.target_index, statuses.length - 1),
        0,
        status,
      );
      operations.push(...reorderStatuses(statuses, now));
      return mutate(context, operations, {
        id: status.id,
      });
    }),
  );
  server.registerTool(
    "delete_kanban_status",
    {
      inputSchema: z.object({ status_id: entityId }).strict(),
      outputSchema: outputSchemas.mutation,
      annotations: destructiveAnnotations,
    },
    safe(async ({ status_id }) => {
      if (status_id === backlogId || status_id === doneId) {
        throw new ToolFailure(
          "forbidden",
          "System Kanban statuses cannot be deleted.",
        );
      }
      const snapshot = await mutationSnapshot(context);
      const status = requireLabel(snapshot, status_id, "kanbanStatus");
      const now = new Date().toISOString();
      const operations = snapshot.assignments
        .filter((link) => link.labelId === status.id)
        .map((link) => assignment(link.taskId, backlogId, now));
      const settings = snapshot.settings;
      if (settings.focusStatusLabelId === status.id) {
        operations.push(settingsOperation(
          settings,
          {
            focusStatusLabelId: fallbackFocusStatus(
              snapshot,
              string(status.id),
            ),
          },
          now,
        ));
      }
      operations.push(remove("label", status.id, {
        commandType: "kanban.status.delete",
        id: status.id,
        isDeleted: true,
        changedAt: now,
      }, now));
      return mutate(context, operations, { id: status.id });
    }),
  );
  server.registerTool(
    "configure_kanban",
    {
      inputSchema: z.object({
        project_ids: z.array(entityId).min(1).max(100).optional(),
        focus_status_id: entityId.optional(),
      }).strict().refine(
        (value) =>
          value.project_ids !== undefined ||
          value.focus_status_id !== undefined,
        "At least one changed field is required.",
      ),
      outputSchema: outputSchemas.mutation,
      annotations: closedAnnotations,
    },
    safe(async ({ project_ids, focus_status_id }) => {
      const snapshot = await mutationSnapshot(context);
      const now = new Date().toISOString();
      const operations: Operation[] = [];
      if (project_ids !== undefined) {
        const unique = [...new Set(project_ids)].sort();
        for (const id of unique) requireProject(snapshot, id);
        operations.push(settingsOperation(
          snapshot.settings,
          { selectedProjectIdsJson: JSON.stringify(unique) },
          now,
        ));
      }
      if (focus_status_id !== undefined) {
        const status = requireLabel(
          snapshot,
          focus_status_id,
          "kanbanStatus",
        );
        if (status.id === doneId) {
          throw new ToolFailure(
            "conflict",
            "Done cannot be the focus status.",
          );
        }
        operations.push(settingsOperation(
          snapshot.settings,
          { focusStatusLabelId: status.id },
          now,
        ));
      }
      return mutate(context, operations, { id: settingsId });
    }),
  );
  server.registerTool(
    "move_task_on_kanban",
    {
      inputSchema: z.object({
        task_id: entityId,
        status_id: entityId,
        target_index: z.number().int().min(0).optional(),
      }).strict(),
      outputSchema: outputSchemas.mutation,
      annotations: closedAnnotations,
    },
    safe(async ({ task_id, status_id, target_index }) => {
      const snapshot = await mutationSnapshot(context);
      const task = requireTask(snapshot, task_id);
      const status = requireLabel(snapshot, status_id, "kanbanStatus");
      const now = new Date().toISOString();
      let operations: Operation[];
      if (status.id === doneId && task.status !== "completed") {
        operations = completeOperations(snapshot, task, now);
      } else if (status.id !== doneId && task.status === "completed") {
        operations = restoreOperations(
          snapshot,
          task,
          now,
          string(status.id),
        );
      } else {
        operations = [assignment(task.id, string(status.id), now)];
      }
      if (target_index !== undefined && status.id !== doneId) {
        const row = reorderedTask(
          snapshot,
          task,
          string(status.id),
          target_index,
          now,
        );
        if (row) operations.push(upsert("task", task.id, row, now));
      }
      return mutate(context, operations, { id: task.id });
    }),
  );
}

type Context = {
  auth: PomodoistMcpAuth;
  config: PomodoistMcpConfig;
  fetcher: PomodoistMcpFetch;
  log: (entry: PomodoistMcpLog) => void;
};

function registerRead(
  server: McpServer,
  operation: string,
  inputSchema: z.ZodType,
  annotations: { readOnlyHint: boolean; openWorldHint: boolean },
  context: Context,
  transform: (data: unknown) => unknown = (data) => data,
) {
  const outputSchema = readOutputSchemas[operation];
  if (!outputSchema) {
    throw new Error(`Missing output schema for ${operation}.`);
  }
  server.registerTool(
    operation,
    { inputSchema, outputSchema, annotations },
    safe(async (arguments_: unknown) =>
      toolSuccess(transform(
        await readRpc(
          context,
          operation,
          record(arguments_) ?? {},
        ),
      ))
    ),
  );
}

function registerTaskAction(
  server: McpServer,
  name: string,
  annotations: { openWorldHint: boolean },
  context: Context,
  build: (
    snapshot: Snapshot,
    task: RecordValue,
    now: string,
  ) => Operation[],
) {
  server.registerTool(
    name,
    {
      inputSchema: z.object({ task_id: entityId }).strict(),
      outputSchema: outputSchemas.mutation,
      annotations,
    },
    safe(async ({ task_id }) => {
      const snapshot = await mutationSnapshot(context);
      const task = requireTask(snapshot, task_id);
      const now = new Date().toISOString();
      return mutate(context, build(snapshot, task, now), { id: task.id });
    }),
  );
}

function safe<Args>(
  handler: (arguments_: Args) => Promise<ReturnType<typeof toolSuccess>>,
) {
  return async (arguments_: Args) => {
    try {
      return await handler(arguments_);
    } catch (error) {
      if (error instanceof ToolFailure) {
        return toolError(error.code, error.message);
      }
      if (error instanceof RpcFailure) {
        return toolError(
          error.status === 400
            ? "invalid_argument"
            : error.status === 401 || error.status === 403
            ? "forbidden"
            : error.status === 404
            ? "not_found"
            : error.status === 409
            ? "conflict"
            : "internal",
          error.status >= 500
            ? "Pomodoist service failed."
            : "Pomodoist request failed.",
        );
      }
      return toolError("internal", "Pomodoist service failed.");
    }
  };
}

async function readRpc(
  context: Context,
  operation: string,
  arguments_: RecordValue,
) {
  return await rpc(context, "read_pomodoist_mcp", {
    p_user_id: context.auth.userId,
    p_operation: operation,
    p_arguments: arguments_,
  });
}

async function rpc(
  context: Context,
  name: string,
  body: RecordValue,
) {
  const response = await context.fetcher(
    `${context.config.supabaseUrl.replace(/\/+$/, "")}/rest/v1/rpc/${name}`,
    {
      method: "POST",
      headers: {
        apikey: context.config.serviceRoleKey,
        Authorization: `Bearer ${context.config.serviceRoleKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    },
  );
  if (!response.ok) throw new RpcFailure(response.status);
  if (name === "send_pomodoist_mcp_sync_hint") return null;
  try {
    return await response.json();
  } catch {
    throw new RpcFailure(500);
  }
}

type Snapshot = {
  tasks: RecordValue[];
  projects: RecordValue[];
  labels: RecordValue[];
  taskLabels: RecordValue[];
  assignments: RecordValue[];
  completions: RecordValue[];
  settings: RecordValue;
};

async function mutationSnapshot(context: Context): Promise<Snapshot> {
  const value = record(
    await readRpc(context, "mutation_snapshot", {}),
  );
  if (!value) throw new RpcFailure(500);
  const projects = records(value.projects).filter((item) => validId(item.id));
  const labels = records(value.labels).filter((item) => validId(item.id));
  if (!projects.some((item) => item.id === inboxId)) {
    projects.push({
      id: inboxId,
      userId: localUserId,
      name: "Inbox",
      color: null,
      orderKey: "a",
      isFavorite: true,
      isArchived: false,
    });
  }
  if (!labels.some((item) => item.id === backlogId)) {
    labels.push({
      id: backlogId,
      name: "Backlog",
      kind: "kanbanStatus",
      systemKey: "backlog",
      orderKey: "00000000000000000000",
    });
  }
  if (!labels.some((item) => item.id === doneId)) {
    labels.push({
      id: doneId,
      name: "Done",
      kind: "kanbanStatus",
      systemKey: "done",
      orderKey: "00004503599627370496",
    });
  }
  return {
    tasks: records(value.tasks).filter(validTask),
    projects,
    labels,
    taskLabels: records(value.taskLabels).filter((item) =>
      validId(item.entityId) && validId(item.taskId) && validId(item.labelId)
    ),
    assignments: records(value.assignments).filter((item) =>
      validId(item.taskId) && validId(item.labelId)
    ),
    completions: records(value.completions).filter((item) =>
      validId(item.id) && validId(item.taskId)
    ),
    settings: validId(record(value.settings)?.id) ? record(value.settings)! : {
      id: settingsId,
      userId: localUserId,
      selectedProjectIdsJson: '["inbox"]',
      focusStatusLabelId: backlogId,
    },
  };
}

async function mutate(
  context: Context,
  operations: Operation[],
  result: RecordValue,
) {
  if (operations.length === 0) {
    throw new ToolFailure("conflict", "Mutation has no effect.");
  }
  const pushed = record(
    await rpc(context, "push_pomodoist_mcp_changes", {
      p_user_id: context.auth.userId,
      p_client_id: context.auth.clientId,
      p_operations: operations,
    }),
  );
  if (!pushed) throw new RpcFailure(500);
  try {
    await rpc(context, "send_pomodoist_mcp_sync_hint", {
      p_user_id: context.auth.userId,
      p_client_id: context.auth.clientId,
    });
  } catch {
    context.log({
      request_id: "",
      subject: context.auth.subject,
      client_id: context.auth.clientId,
      tool_name: "",
      outcome: "hint_failed",
      latency_ms: 0,
    });
  }
  return toolSuccess({
    ...result,
    server_revision: pushed.serverRevision ?? null,
  });
}

function completeOperations(
  snapshot: Snapshot,
  task: RecordValue,
  now: string,
) {
  const operations: Operation[] = [];
  for (const row of descendants(snapshot.tasks, task.id)) {
    if (row.status === "completed") continue;
    const completionId = crypto.randomUUID();
    const previousStatus = currentStatus(snapshot, row.id);
    operations.push(
      upsert(
        "task",
        row.id,
        sanitizeTask({
          ...row,
          commandType: "task.complete",
          status: "completed",
          completedAt: now,
          updatedAt: now,
        }),
        now,
      ),
      upsert("task_completion", completionId, {
        schemaVersion: 1,
        id: completionId,
        taskId: row.id,
        userId: localUserId,
        completedAt: now,
        snapshotJson: JSON.stringify({
          version: 1,
          kanban: { previousStatusLabelId: previousStatus },
        }),
        createdAt: now,
      }, now),
      assignment(row.id, doneId, now),
    );
  }
  return operations;
}

function restoreOperations(
  snapshot: Snapshot,
  task: RecordValue,
  now: string,
  explicitRootStatus?: string,
) {
  const operations: Operation[] = [];
  for (const row of descendants(snapshot.tasks, task.id)) {
    if (row.status !== "completed") continue;
    const status = row.id === task.id && explicitRootStatus
      ? explicitRootStatus
      : previousStatus(snapshot, string(row.id));
    operations.push(
      upsert(
        "task",
        row.id,
        sanitizeTask({
          ...row,
          commandType: "task.uncomplete",
          status: "open",
          completedAt: null,
          updatedAt: now,
        }),
        now,
      ),
      assignment(row.id, status, now),
    );
  }
  return operations;
}

async function deleteTaskOperations(
  snapshot: Snapshot,
  task: RecordValue,
  scope: "selected" | "selected_and_following",
  now: string,
) {
  const parsed = parseDue(task.dueJson);
  const seriesId = recurrenceSeriesKey(parsed);
  if (!seriesId) {
    return descendants(snapshot.tasks, task.id).map((row) =>
      remove("task", row.id, {
        commandType: "task.delete",
        id: row.id,
      }, now)
    );
  }
  if (scope === "selected_and_following") {
    const selectedStart = scheduleStart(parsed!);
    const roots = snapshot.tasks.filter((row) => {
      const due = parseDue(row.dueJson);
      return due !== null &&
        recurrenceSeriesKey(due) === seriesId &&
        scheduleStart(due) >= selectedStart;
    });
    const ids = new Set<string>();
    for (const root of roots) {
      for (const row of descendants(snapshot.tasks, root.id)) {
        ids.add(string(row.id));
      }
    }
    return [...ids].map((id) =>
      remove("task", id, { commandType: "task.delete", id }, now)
    );
  }

  if (!record(record(parsed)?.recurrence)) {
    return descendants(snapshot.tasks, task.id).map((row) =>
      remove("task", row.id, {
        commandType: "task.delete",
        id: row.id,
      }, now)
    );
  }
  const next = nextSchedule(parsed!, new Date());
  const sourceRows = descendants(snapshot.tasks, task.id);
  const delta = scheduleStart(next) - scheduleStart(parsed!);
  const ids = new Map<string, string>();
  const nextRootId = await recurringId(
    seriesId,
    scheduleOccurrenceKey(next),
    string(task.id),
  );
  if (snapshot.tasks.some((row) => row.id === nextRootId)) {
    return sourceRows.map((row) =>
      remove("task", row.id, {
        commandType: "task.delete",
        id: row.id,
      }, now)
    );
  }
  for (const row of sourceRows) {
    ids.set(
      string(row.id),
      row.id === task.id ? nextRootId : await recurringId(
        seriesId,
        scheduleOccurrenceKey(next),
        string(row.id),
      ),
    );
  }
  const operations: Operation[] = [];
  for (const row of sourceRows) {
    const isRoot = row.id === task.id;
    const id = ids.get(string(row.id))!;
    const shiftedDue = isRoot
      ? next
      : shiftChildSchedule(parseDue(row.dueJson), delta);
    operations.push(
      upsert(
        "task",
        id,
        sanitizeTask({
          ...row,
          commandType: "task.create",
          id,
          parentId: isRoot
            ? row.parentId
            : ids.get(string(row.parentId)) ?? row.parentId,
          dueJson: shiftedDue ? JSON.stringify(shiftedDue) : null,
          status: "open",
          completedAt: null,
          createdAt: now,
          updatedAt: now,
        }),
        now,
      ),
      assignment(
        id,
        row.status === "completed"
          ? previousStatus(snapshot, string(row.id))
          : currentStatus(snapshot, row.id),
        now,
      ),
    );
    for (
      const relation of snapshot.taskLabels.filter((link) =>
        link.taskId === row.id
      )
    ) {
      operations.push(upsert(
        "task_label",
        `${id}:${relation.labelId}`,
        {
          schemaVersion: 1,
          commandType: "task.label.add",
          taskId: id,
          labelId: relation.labelId,
          kind: "user",
          createdAt: now,
        },
        now,
      ));
    }
  }
  operations.push(
    ...sourceRows.map((row) =>
      remove("task", row.id, {
        commandType: "task.delete",
        id: row.id,
      }, now)
    ),
  );
  return operations;
}

function labelAdditions(
  snapshot: Snapshot,
  taskId: string,
  labelNames: string[],
  now: string,
) {
  const operations: Operation[] = [];
  const seen = new Set<string>();
  for (const rawName of labelNames) {
    const normalized = rawName.trim();
    const key = normalized.toLowerCase();
    if (!normalized || !seen.add(key)) continue;
    const existing = snapshot.labels.find((label) =>
      label.kind === "user" && string(label.name).toLowerCase() === key
    );
    const labelId = existing ? string(existing.id) : crypto.randomUUID();
    if (!existing) {
      const label = userLabel(labelId, normalized, now);
      snapshot.labels.push(label);
      operations.push(upsert("label", labelId, label, now));
    }
    if (
      !snapshot.taskLabels.some((link) =>
        link.taskId === taskId && link.labelId === labelId
      )
    ) {
      operations.push(upsert("task_label", `${taskId}:${labelId}`, {
        schemaVersion: 1,
        commandType: "task.label.add",
        taskId,
        labelId,
        kind: "user",
        createdAt: now,
      }, now));
    }
  }
  return operations;
}

function upsert(
  entityType: string,
  entityId: unknown,
  payload: RecordValue,
  now: string,
): Operation {
  return operation(entityType, entityId, "upsert", payload, now);
}

function remove(
  entityType: string,
  entityId: unknown,
  payload: RecordValue,
  now: string,
): Operation {
  return operation(entityType, entityId, "delete", payload, now);
}

function operation(
  entityType: string,
  id: unknown,
  kind: "upsert" | "delete",
  payload: RecordValue,
  now: string,
): Operation {
  const entityId = string(id);
  return {
    opId: crypto.randomUUID(),
    entityType,
    entityId,
    operation: kind,
    payload,
    clientUpdatedAt: now,
  };
}

function assignment(taskId: unknown, labelId: string, now: string) {
  const id = string(taskId);
  return upsert("task_kanban_status", id, {
    schemaVersion: 1,
    commandType: "task.kanbanStatus.set",
    taskId: id,
    labelId,
    changedAt: now,
  }, now);
}

function settingsOperation(
  _settings: RecordValue,
  patch: RecordValue,
  now: string,
) {
  return upsert("kanban_settings", settingsId, {
    commandType: patch.selectedProjectIdsJson !== undefined
      ? "kanban.settings.projects.set"
      : "kanban.settings.focus.set",
    id: settingsId,
    ...patch,
    changedAt: now,
  }, now);
}

function userLabel(id: string, labelName: string, now: string) {
  return {
    schemaVersion: 1,
    commandType: "label.create",
    id,
    userId: localUserId,
    name: labelName,
    color: null,
    kind: "user",
    systemKey: null,
    orderKey: orderKey(),
    isFavorite: false,
    isDeleted: false,
    createdAt: now,
    updatedAt: now,
  };
}

function requireTask(snapshot: Snapshot, id: string) {
  const task = snapshot.tasks.find((item) => item.id === id);
  if (!task) throw new ToolFailure("not_found", "Task not found.");
  return task;
}

function requireProject(snapshot: Snapshot, id: string) {
  const project = snapshot.projects.find((item) => item.id === id);
  if (!project) throw new ToolFailure("not_found", "Project not found.");
  return project;
}

function requireLabel(snapshot: Snapshot, id: string, kind: string) {
  const label = snapshot.labels.find((item) =>
    item.id === id && item.kind === kind
  );
  if (!label) {
    throw new ToolFailure(
      "not_found",
      kind === "user" ? "Label not found." : "Kanban status not found.",
    );
  }
  return label;
}

function descendants(tasks: RecordValue[], rootId: unknown) {
  const id = string(rootId);
  const root = tasks.find((task) => task.id === id);
  if (!root) return [];
  const result: RecordValue[] = [];
  const stack = [root];
  const seen = new Set<string>();
  while (stack.length) {
    const row = stack.pop()!;
    if (!seen.add(string(row.id))) continue;
    result.push(row);
    stack.push(
      ...tasks.filter((task) => task.parentId === row.id).reverse(),
    );
  }
  return result;
}

function validateParent(
  snapshot: Snapshot,
  taskId: string,
  parentId: string | null,
  projectId: string,
) {
  if (parentId === null) return;
  if (parentId === taskId) {
    throw new ToolFailure("conflict", "A task cannot be its own parent.");
  }
  const parent = requireTask(snapshot, parentId);
  if (parent.projectId !== projectId) {
    throw new ToolFailure(
      "conflict",
      "Parent task belongs to another project.",
    );
  }
  if (descendants(snapshot.tasks, taskId).some((row) => row.id === parentId)) {
    throw new ToolFailure("conflict", "Task parent would create a cycle.");
  }
}

function currentStatus(snapshot: Snapshot, taskId: unknown) {
  const statusId = snapshot.assignments.find((link) => link.taskId === taskId)
    ?.labelId;
  return activeNonDoneStatus(snapshot, statusId) ? string(statusId) : backlogId;
}

function previousStatus(snapshot: Snapshot, taskId: string) {
  for (
    const completion of snapshot.completions.filter((row) =>
      row.taskId === taskId
    )
  ) {
    try {
      const value = JSON.parse(string(completion.snapshotJson));
      const status = record(record(value)?.kanban)?.previousStatusLabelId;
      if (activeNonDoneStatus(snapshot, status)) return string(status);
    } catch {
      // Ignore malformed legacy snapshots.
    }
  }
  return backlogId;
}

function activeNonDoneStatus(snapshot: Snapshot, value: unknown) {
  return typeof value === "string" && value !== doneId &&
    snapshot.labels.some((label) =>
      label.id === value && label.kind === "kanbanStatus"
    );
}

function kanbanStatuses(snapshot: Snapshot) {
  return snapshot.labels.filter((label) => label.kind === "kanbanStatus")
    .sort((a, b) => {
      const rank = (row: RecordValue) =>
        row.id === backlogId ? 0 : row.id === doneId ? 2 : 1;
      return rank(a) - rank(b) ||
        string(a.orderKey).localeCompare(string(b.orderKey)) ||
        string(a.id).localeCompare(string(b.id));
    });
}

function reorderStatuses(
  statuses: RecordValue[],
  now: string,
  createdId?: string,
) {
  const step = Math.floor(maximumOrder / (statuses.length - 1));
  return statuses.flatMap((status, index) => {
    const value = index === statuses.length - 1 ? maximumOrder : step * index;
    const nextOrder = String(value).padStart(20, "0");
    if (status.orderKey === nextOrder && status.updatedAt !== now) return [];
    const created = status.id === createdId;
    return [upsert(
      "label",
      status.id,
      created
        ? {
          commandType: "kanban.status.create",
          id: status.id,
          userId: localUserId,
          name: status.name,
          color: status.color ?? null,
          kind: "kanbanStatus",
          systemKey: null,
          orderKey: nextOrder,
          isFavorite: false,
          isDeleted: false,
          createdAt: now,
          updatedAt: now,
        }
        : {
          commandType: "kanban.status.reorder",
          id: status.id,
          orderKey: nextOrder,
          changedAt: now,
        },
      now,
    )];
  });
}

function ensureUniqueStatusName(
  snapshot: Snapshot,
  statusName: string,
  exceptId?: string,
) {
  if (
    snapshot.labels.some((label) =>
      label.kind === "kanbanStatus" &&
      label.id !== exceptId &&
      string(label.name).toLowerCase() === statusName.toLowerCase()
    )
  ) {
    throw new ToolFailure("conflict", "Kanban status name already exists.");
  }
}

function fallbackFocusStatus(snapshot: Snapshot, excludedId: string) {
  return string(
    kanbanStatuses(snapshot).find((status) =>
      status.id !== excludedId &&
      status.id !== doneId &&
      status.id !== backlogId
    )?.id ?? backlogId,
  );
}

function selectedProjectIds(settings: RecordValue) {
  try {
    const value = JSON.parse(string(settings.selectedProjectIdsJson));
    return Array.isArray(value)
      ? [
        ...new Set(
          value.filter((item): item is string => typeof item === "string"),
        ),
      ].sort()
      : [inboxId];
  } catch {
    return [inboxId];
  }
}

function reorderedTask(
  snapshot: Snapshot,
  task: RecordValue,
  statusId: string,
  targetIndex: number,
  now: string,
) {
  const selected = new Set(selectedProjectIds(snapshot.settings));
  const assigned = new Map(
    snapshot.assignments.map((link) => [link.taskId, link.labelId]),
  );
  const rows = snapshot.tasks.filter((row) =>
    row.id !== task.id &&
    row.parentId == null &&
    row.status === "open" &&
    selected.has(string(row.projectId)) &&
    assigned.get(row.id) === statusId
  ).sort((a, b) =>
    string(a.orderKey).localeCompare(string(b.orderKey)) ||
    string(a.id).localeCompare(string(b.id))
  );
  const index = Math.min(targetIndex, rows.length);
  rows.splice(index, 0, task);
  const left = index === 0 ? 0 : Number(rows[index - 1].orderKey);
  const right = index === rows.length - 1
    ? maximumOrder
    : Number(rows[index + 1].orderKey);
  if (!Number.isSafeInteger(left) || !Number.isSafeInteger(right)) return null;
  const midpoint = left + Math.floor((right - left) / 2);
  if (midpoint <= left || midpoint >= right) return null;
  return {
    id: task.id,
    commandType: "task.reorder",
    orderKey: String(midpoint).padStart(20, "0"),
    changedAt: now,
  };
}

function sanitizeTask(value: RecordValue) {
  const result = { ...value };
  delete result.deadline;
  delete result.deadlineJson;
  delete result.duration;
  delete result.durationSeconds;
  return result;
}

function dueJson(value: z.infer<typeof schedule>) {
  const recurrenceValue = value.recurrence
    ? {
      interval: value.recurrence.interval,
      unit: value.recurrence.frequency,
      seriesId: crypto.randomUUID(),
    }
    : undefined;
  return JSON.stringify(
    value.type === "all_day"
      ? {
        type: "allDay",
        date: value.date,
        ...(recurrenceValue ? { recurrence: recurrenceValue } : {}),
      }
      : {
        type: "timed",
        start: new Date(value.start).toISOString(),
        end: new Date(value.end).toISOString(),
        timeZone: value.time_zone,
        ...(recurrenceValue ? { recurrence: recurrenceValue } : {}),
      },
  );
}

function parseDue(value: unknown) {
  if (typeof value !== "string") return null;
  try {
    const parsed = record(JSON.parse(value));
    if (!parsed) return null;
    const recurrence = parseRecurrence(parsed.recurrence);
    const recurrenceSeriesId = recurrence
      ? null
      : cleanSeriesId(parsed.recurrenceSeriesId);
    if (parsed.type === "timed") {
      if (
        typeof parsed.start !== "string" ||
        typeof parsed.end !== "string"
      ) {
        return null;
      }
      const start = new Date(parsed.start);
      const end = new Date(parsed.end);
      if (
        !Number.isFinite(start.getTime()) ||
        !Number.isFinite(end.getTime()) ||
        end.getTime() <= start.getTime()
      ) {
        return null;
      }
      return {
        type: "timed",
        start: start.toISOString(),
        end: end.toISOString(),
        ...(typeof parsed.timeZone === "string"
          ? { timeZone: parsed.timeZone }
          : {}),
        ...(recurrence
          ? { recurrence }
          : recurrenceSeriesId
          ? { recurrenceSeriesId }
          : {}),
      };
    }
    if (typeof parsed.date !== "string" || !validDate(parsed.date)) return null;
    return {
      type: "allDay",
      date: parsed.date,
      ...(recurrence
        ? { recurrence }
        : recurrenceSeriesId
        ? { recurrenceSeriesId }
        : {}),
    };
  } catch {
    return null;
  }
}

function parseRecurrence(value: unknown) {
  const recurrence = record(value);
  if (
    !recurrence ||
    !Number.isInteger(recurrence.interval) ||
    number(recurrence.interval) < 1 ||
    number(recurrence.interval) > 999 ||
    !["day", "week", "month"].includes(string(recurrence.unit)) ||
    typeof recurrence.seriesId !== "string" ||
    recurrence.seriesId.trim() === ""
  ) {
    return null;
  }
  return {
    interval: recurrence.interval,
    unit: recurrence.unit,
    seriesId: recurrence.seriesId,
  };
}

function cleanSeriesId(value: unknown) {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed === "" ? null : trimmed;
}

function recurrenceSeriesKey(value: RecordValue | null) {
  if (!value) return null;
  const recurrence = record(value.recurrence);
  return cleanSeriesId(recurrence?.seriesId) ??
    cleanSeriesId(value.recurrenceSeriesId);
}

function scheduleStart(value: RecordValue) {
  return value.type === "allDay"
    ? Date.parse(`${value.date}T00:00:00.000Z`)
    : Date.parse(string(value.start));
}

function scheduleOccurrenceKey(value: RecordValue) {
  return value.type === "allDay"
    ? string(value.date)
    : new Date(string(value.start)).toISOString();
}

function nextSchedule(value: RecordValue, now: Date) {
  const repeat = record(value.recurrence)!;
  const interval = number(repeat.interval);
  const unit = string(repeat.unit);
  const start = scheduleStart(value);
  if (unit === "day" || unit === "week") {
    const period = interval * (unit === "day" ? 86400000 : 604800000);
    const steps = Math.max(1, Math.floor((now.getTime() - start) / period) + 1);
    return advanceSchedule(value, unit, interval * steps);
  }
  const startDate = new Date(start);
  const monthDelta = (now.getUTCFullYear() - startDate.getUTCFullYear()) * 12 +
    now.getUTCMonth() - startDate.getUTCMonth();
  const steps = Math.max(1, Math.floor(monthDelta / interval));
  let next = advanceSchedule(value, unit, interval * steps);
  while (scheduleStart(next) <= now.getTime()) {
    next = advanceSchedule(next, unit, interval);
  }
  return next;
}

function advanceSchedule(
  value: RecordValue,
  unit: string,
  interval: number,
) {
  if (value.type === "allDay") {
    return { ...value, date: addDate(string(value.date), unit, interval) };
  }
  const start = new Date(string(value.start));
  const end = new Date(string(value.end));
  const duration = end.getTime() - start.getTime();
  const nextStart = addZonedInstant(
    start,
    unit,
    interval,
    validTimeZone(string(value.timeZone)) ? string(value.timeZone) : "UTC",
  );
  return {
    ...value,
    start: nextStart.toISOString(),
    end: new Date(nextStart.getTime() + duration).toISOString(),
  };
}

function shiftChildSchedule(value: RecordValue | null, delta: number) {
  if (!value) return null;
  const next = { ...value };
  delete next.recurrence;
  delete next.recurrenceSeriesId;
  if (next.type === "allDay") {
    next.date = new Date(
      Date.parse(`${next.date}T00:00:00.000Z`) + delta,
    ).toISOString().slice(0, 10);
  } else {
    next.start = new Date(Date.parse(string(next.start)) + delta).toISOString();
    next.end = new Date(Date.parse(string(next.end)) + delta).toISOString();
  }
  return next;
}

function addDate(value: string, unit: string, interval: number) {
  return addInstant(
    new Date(`${value}T00:00:00.000Z`),
    unit,
    interval,
  ).toISOString().slice(0, 10);
}

function addInstant(value: Date, unit: string, interval: number) {
  const next = new Date(value);
  if (unit === "day") next.setUTCDate(next.getUTCDate() + interval);
  else if (unit === "week") next.setUTCDate(next.getUTCDate() + 7 * interval);
  else {
    const day = next.getUTCDate();
    next.setUTCDate(1);
    next.setUTCMonth(next.getUTCMonth() + interval);
    const last = new Date(Date.UTC(
      next.getUTCFullYear(),
      next.getUTCMonth() + 1,
      0,
    )).getUTCDate();
    next.setUTCDate(Math.min(day, last));
  }
  return next;
}

function addZonedInstant(
  value: Date,
  unit: string,
  interval: number,
  zone: string,
) {
  const local = zonedParts(value, zone);
  const localClock = addInstant(
    new Date(Date.UTC(
      local.year,
      local.month - 1,
      local.day,
      local.hour,
      local.minute,
      local.second,
      value.getUTCMilliseconds(),
    )),
    unit,
    interval,
  );
  return instantForZonedParts({
    year: localClock.getUTCFullYear(),
    month: localClock.getUTCMonth() + 1,
    day: localClock.getUTCDate(),
    hour: localClock.getUTCHours(),
    minute: localClock.getUTCMinutes(),
    second: localClock.getUTCSeconds(),
    millisecond: localClock.getUTCMilliseconds(),
  }, zone);
}

function zonedParts(value: Date, zone: string) {
  const parts = new Intl.DateTimeFormat("en-CA-u-ca-gregory-nu-latn", {
    timeZone: zone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23",
  }).formatToParts(value);
  const result = Object.fromEntries(
    parts.filter((part) => part.type !== "literal")
      .map((part) => [part.type, Number(part.value)]),
  );
  return {
    year: result.year,
    month: result.month,
    day: result.day,
    hour: result.hour,
    minute: result.minute,
    second: result.second,
  };
}

function instantForZonedParts(
  desired: ReturnType<typeof zonedParts> & { millisecond: number },
  zone: string,
) {
  const desiredClock = Date.UTC(
    desired.year,
    desired.month - 1,
    desired.day,
    desired.hour,
    desired.minute,
    desired.second,
    desired.millisecond,
  );
  let guess = desiredClock;
  for (let attempt = 0; attempt < 4; attempt++) {
    const actual = zonedParts(new Date(guess), zone);
    const actualClock = Date.UTC(
      actual.year,
      actual.month - 1,
      actual.day,
      actual.hour,
      actual.minute,
      actual.second,
      desired.millisecond,
    );
    const correction = desiredClock - actualClock;
    if (correction === 0) return new Date(guess);
    guess += correction;
  }
  return new Date(guess);
}

async function recurringId(
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

function nextProjectColor(projects: RecordValue[]) {
  const counts = new Map(projectPalette.map((value) => [value, 0]));
  for (const project of projects) {
    if (project.id === inboxId) continue;
    const stored = typeof project.color === "string" &&
        projectPalette.includes(project.color as typeof projectPalette[number])
      ? project.color
      : projectPalette[stableHash(string(project.id)) % projectPalette.length];
    counts.set(
      stored as typeof projectPalette[number],
      (counts.get(stored as typeof projectPalette[number]) ?? 0) + 1,
    );
  }
  return projectPalette.reduce((best, value) =>
    (counts.get(value) ?? 0) < (counts.get(best) ?? 0) ? value : best
  );
}

function stableHash(value: string) {
  let hash = 0x811c9dc5;
  for (const code of new TextEncoder().encode(value)) {
    hash = Math.imul(hash ^ code, 0x01000193) & 0x7fffffff;
  }
  return hash;
}

function productivityReport(value: unknown) {
  const report = record(value) ?? {};
  return {
    reportDate: report.reportDate,
    timeZone: report.timeZone,
    daily: report.daily,
    plannedFocusIntervals: report.plannedFocusIntervals,
    openTasks: report.openTasks,
    allTime: report.allTime,
    lastSevenDays: report.lastSevenDays,
  };
}

function achievements(value: unknown, locale: "ru" | "en") {
  const inputs = record(record(value)?.achievementInputs) ?? {};
  const completedTasks = number(inputs.completedTasks);
  const completedFocus = number(inputs.completedWorkIntervals);
  const flags = record(inputs.comboFlags) ?? {};
  return achievementCatalog().map((definition) => {
    const progress = definition.group === "task"
      ? completedTasks
      : definition.group === "focus"
      ? completedFocus
      : flags["flag" in definition ? definition.flag : ""] === true
      ? 1
      : 0;
    return {
      id: definition.id,
      group: definition.group,
      presentation: definition.group === "combo"
        ? "bottomPlaque"
        : "globalBanner",
      title: definition[locale].title,
      subtitle: definition[locale].subtitle,
      progress: Math.min(progress, definition.target),
      target: definition.target,
      unlocked: progress >= definition.target,
    };
  });
}

const focusTargets = [
  1,
  5,
  10,
  25,
  50,
  100,
  250,
  500,
  1000,
  5000,
  10000,
  50000,
  100000,
  1000000,
];
const taskTargets = [...focusTargets];
function achievementCatalog() {
  return [
    ...focusTargets.map((target) => ({
      id: `focus_${target}`,
      group: "focus",
      target,
      ru: {
        title: focusTitlesRu[target],
        subtitle: `Завершить ${target} work-фокус${target === 1 ? "" : "ов"}`,
      },
      en: {
        title: focusTitlesEn[target],
        subtitle: `Complete ${target} work focus${target === 1 ? "" : "es"}`,
      },
    })),
    ...taskTargets.map((target) => ({
      id: `task_${target}`,
      group: "task",
      target,
      ru: {
        title: taskTitlesRu[target],
        subtitle: `Закрыть ${target} задач${target === 1 ? "у" : ""}`,
      },
      en: {
        title: taskTitlesEn[target],
        subtitle: `Complete ${target} task${target === 1 ? "" : "s"}`,
      },
    })),
    {
      id: "combo_day_not_wasted",
      group: "combo",
      flag: "dayNotWasted",
      target: 1,
      ru: {
        title: "День не зря",
        subtitle: "За день есть фокус и закрытая задача",
      },
      en: {
        title: "Day not wasted",
        subtitle: "Finish a focus and a task in one day",
      },
    },
    {
      id: "combo_focus_plus_check",
      group: "combo",
      flag: "focusPlusCheck",
      target: 1,
      ru: {
        title: "Фокус + галочка",
        subtitle: "За день есть 3 фокуса и 3 задачи",
      },
      en: {
        title: "Focus + check",
        subtitle: "Finish 3 focuses and 3 tasks in one day",
      },
    },
    {
      id: "combo_no_fuss",
      group: "combo",
      flag: "noFuss",
      target: 1,
      ru: { title: "Без суеты", subtitle: "5 фокусов за день без остановок" },
      en: {
        title: "No fuss",
        subtitle: "Finish 5 focuses in a day without stops",
      },
    },
    {
      id: "combo_clean_entry",
      group: "combo",
      flag: "cleanEntry",
      target: 1,
      ru: {
        title: "Чистый заход",
        subtitle: "Закрыть задачу после связанного фокуса",
      },
      en: {
        title: "Clean entry",
        subtitle: "Complete a task after its linked focus",
      },
    },
    {
      id: "combo_tomato_closed_question",
      group: "combo",
      flag: "tomatoClosed",
      target: 1,
      ru: {
        title: "Помидор закрыл вопрос",
        subtitle: "Закрыть задачу в день ее work-фокуса",
      },
      en: {
        title: "Tomato closed it",
        subtitle: "Complete a task on the day of its work focus",
      },
    },
  ];
}

const focusTitlesRu: Record<number, string> = {
  1: "Первый помидор",
  5: "Разогрев",
  10: "Фокус пойман",
  25: "Помидорная смена",
  50: "Режим включен",
  100: "Красный пояс",
  250: "Глубокая посадка",
  500: "Таймерный авторитет",
  1000: "Тысячный помидор",
  5000: "Фермер фокуса",
  10000: "Плантация внимания",
  50000: "Помидорная империя",
  100000: "Красный сверхразум",
  1000000: "Сингулярность помидора",
};
const focusTitlesEn: Record<number, string> = {
  1: "First tomato",
  5: "Warm-up",
  10: "Focus caught",
  25: "Tomato shift",
  50: "Mode on",
  100: "Red belt",
  250: "Deep roots",
  500: "Timer authority",
  1000: "Thousandth tomato",
  5000: "Focus farmer",
  10000: "Attention plantation",
  50000: "Tomato empire",
  100000: "Red supermind",
  1000000: "Tomato singularity",
};
const taskTitlesRu: Record<number, string> = {
  1: "Первая галочка",
  5: "Список дрогнул",
  10: "Чекбокс доволен",
  25: "Разбор завалов",
  50: "Мастер галочек",
  100: "Закрыватель хвостов",
  250: "Список под контролем",
  500: "Канцелярский нокаут",
  1000: "Тысяча галочек",
  5000: "Архивариус побед",
  10000: "Чекбокс-машина",
  50000: "Бюро закрытых вопросов",
  100000: "Повелитель списков",
  1000000: "Последняя галочка",
};
const taskTitlesEn: Record<number, string> = {
  1: "First check",
  5: "The list flinched",
  10: "Happy checkbox",
  25: "Clearing the pile",
  50: "Checkmark master",
  100: "Tail closer",
  250: "List under control",
  500: "Office knockout",
  1000: "Thousand checks",
  5000: "Victory archivist",
  10000: "Checkbox machine",
  50000: "Bureau of closed questions",
  100000: "List ruler",
  1000000: "Final check",
};

function validDate(value: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value) || value.startsWith("0000-")) {
    return false;
  }
  const parsed = new Date(`${value}T00:00:00.000Z`);
  return Number.isFinite(parsed.getTime()) &&
    parsed.toISOString().slice(0, 10) === value;
}

function validRfc3339(value: string) {
  const match = value.match(
    /^(\d{4}-\d{2}-\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(?:Z|[+-](\d{2}):(\d{2}))$/,
  );
  return match !== null &&
    validDate(match[1]) &&
    Number(match[2]) <= 23 &&
    Number(match[3]) <= 59 &&
    Number(match[4]) <= 59 &&
    (match[5] === undefined ||
      (Number(match[5]) <= 23 && Number(match[6]) <= 59)) &&
    Number.isFinite(Date.parse(value));
}

function validTimeZone(value: string) {
  try {
    new Intl.DateTimeFormat("en", { timeZone: value }).format();
    return true;
  } catch {
    return false;
  }
}

function validTask(value: RecordValue) {
  return validId(value.id) && typeof value.content === "string" &&
    validId(value.projectId);
}

function validId(value: unknown): value is string {
  return typeof value === "string" && entityId.safeParse(value).success;
}

function record(value: unknown): RecordValue | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? value as RecordValue
    : null;
}

function records(value: unknown) {
  return Array.isArray(value)
    ? value.map(record).filter((item): item is RecordValue => item !== null)
    : [];
}

function string(value: unknown) {
  return typeof value === "string" ? value : "";
}

function nullableString(value: unknown) {
  return typeof value === "string" ? value : null;
}

function number(value: unknown) {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

function orderKey() {
  return String(Date.now() * 1000).padStart(20, "0");
}

class ToolFailure extends Error {
  constructor(
    readonly code:
      | "invalid_argument"
      | "not_found"
      | "conflict"
      | "forbidden"
      | "rate_limited"
      | "internal",
    message: string,
  ) {
    super(message);
  }
}

class RpcFailure extends Error {
  constructor(readonly status: number) {
    super(`RPC failed with HTTP ${status}`);
  }
}

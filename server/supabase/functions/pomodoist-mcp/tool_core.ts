import { z } from "zod";
import { ActionError } from "./openclaw_actions.ts";
import {
  type PomodoistMcpAuth,
  type PomodoistMcpConfig,
  type PomodoistMcpFetch,
  type PomodoistMcpLog,
  toolError,
  toolSuccess,
} from "./pomodoist_mcp.ts";

export type RecordValue = Record<string, unknown>;
export type Operation = {
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
  webUrl?: string;
  publicUrl?: string;
};

export const localUserId = "local-user";
export const inboxId = "inbox";
export const backlogId = "kanban-status-backlog-v1";
export const doneId = "kanban-status-done-v1";
export const settingsId = "kanban-settings-primary-v1";
export const maximumOrder = 4503599627370496;
export const projectPalette = [
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
export const projectColor = z.enum(projectPalette);

export const entityId = z.string().regex(/^[A-Za-z0-9][A-Za-z0-9._:-]{0,199}$/);
export const cursor = z.string().min(1).max(4096);
export const limit = z.number().int().min(1).max(100).default(50);
export const date = z.string().refine(validDate, "Invalid calendar date.");
export const timeZone = z.string().refine(validTimeZone, "Invalid IANA time zone.");
export const name = z.string().trim().min(1).max(200);
export const content = z.string().trim().min(1).max(2000);
export const description = z.string().max(10000);
export const color = z.string().trim().toUpperCase().regex(/^#[0-9A-F]{6}$/);
export const recurrence = z.object({
  frequency: z.enum(["day", "week", "month"]),
  interval: z.number().int().min(1).max(999),
}).strict();
export const allDaySchedule = z.object({
  type: z.literal("all_day"),
  date,
  recurrence: recurrence.optional(),
}).strict();
export const timedSchedule = z.object({
  type: z.literal("timed"),
  start: z.string().refine(validRfc3339, "Invalid RFC 3339 start."),
  end: z.string().refine(validRfc3339, "Invalid RFC 3339 end."),
  time_zone: timeZone,
  recurrence: recurrence.optional(),
}).strict().refine(
  (value) => Date.parse(value.end) > Date.parse(value.start),
  "Timed schedule end must be after start.",
);
export const schedule = z.discriminatedUnion("type", [
  allDaySchedule,
  timedSchedule,
]);
export const pagination = { limit, cursor: cursor.optional() };
export const publicTaskSchema = z.object({
  id: entityId,
  createdBy: entityId.nullable().optional(),
  completedBy: entityId.nullable().optional(),
  scopeId: entityId.nullable().optional(),
  assigneeIds: z.array(entityId).optional(),
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
export const publicProjectSchema = z.object({
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
export const publicLabelSchema = z.object({
  id: entityId,
  name: z.string().nullable(),
  color: z.string().nullable(),
  orderKey: z.string().nullable(),
  isFavorite: z.boolean().nullable(),
  createdAt: z.string().nullable(),
  updatedAt: z.string().nullable(),
}).strict();
export const focusHistorySchema = z.object({
  id: entityId,
  taskId: entityId.nullable(),
  projectId: entityId.nullable(),
  startedAt: z.string(),
  completedAt: z.string(),
  actualSeconds: z.number().int().nonnegative(),
}).strict();
export const kanbanBoardSchema = z.object({
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
export const dailyMetricsSchema = z.object({
  completedTasks: z.number().int().nonnegative(),
  completedFocusIntervals: z.number().int().nonnegative(),
  totalFocusSeconds: z.number().int().nonnegative(),
}).strict();
export const productivityReportSchema = z.object({
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
export const achievementSchema = z.object({
  id: z.string().min(1),
  group: z.enum(["focus", "task", "combo"]),
  presentation: z.enum(["globalBanner", "bottomPlaque"]),
  title: z.string(),
  subtitle: z.string(),
  progress: z.number().int().nonnegative(),
  target: z.number().int().positive(),
  unlocked: z.boolean(),
}).strict();
export const mutationResultSchema = z.object({
  id: entityId,
  server_revision: z.union([z.number().int(), z.string()]).nullable(),
}).strict();
export const toolErrorSchema = z.object({
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

export function pageSchema(item: z.ZodType) {
  return z.object({
    items: z.array(item),
    nextCursor: z.string().nullable(),
  }).strict();
}

export function jsonSchema(schema: z.ZodType) {
  const converted = z.toJSONSchema(schema, {
    target: "draft-7",
    io: "input",
  }) as Record<string, unknown>;
  const { $schema: _schema, ...result } = converted;
  return result;
}

export function outputEnvelope(dataSchema: z.ZodType) {
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

export const outputSchemas = {
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
export const readOutputSchemas: Record<string, z.ZodType> = {
  list_tasks: outputSchemas.taskPage,
  get_task: outputSchemas.task,
  list_projects: outputSchemas.projectPage,
  list_labels: outputSchemas.labelPage,
  get_kanban_board: outputSchemas.kanbanBoard,
  list_focus_history: outputSchemas.focusPage,
  get_productivity_report: outputSchemas.productivity,
};

export const listTaskVariants = [
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
export const listTasksSchema = z.object({
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
export const noArgs = z.object({}).strict();
export const paged = z.object(pagination).strict();
export const report = z.object({ date, time_zone: timeZone }).strict();
export const createTaskSchema = z.object({
  content,
  description: description.nullable().optional(),
  priority: z.number().int().min(1).max(4).optional(),
  project_id: entityId.optional(),
  parent_id: entityId.optional(),
  label_names: z.array(name).max(100).default([]),
  estimate: z.number().int().min(1).max(999).optional(),
  schedule: schedule.optional(),
}).strict();
export const updateTaskSchema = z.object({
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
export const createProjectSchema = z.object({
  name,
  color: projectColor.optional(),
}).strict();
export const updateProjectSchema = z.object({
  project_id: entityId,
  color: z.union([projectColor, z.null()]).optional(),
  is_favorite: z.boolean().optional(),
}).strict().refine(
  (value) => value.color !== undefined || value.is_favorite !== undefined,
  "At least one changed field is required.",
);
export const createStatusSchema = z.object({
  name,
  color: color.nullable().optional(),
}).strict();
export const updateStatusSchema = z.object({
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

export type Context = {
  auth: PomodoistMcpAuth;
  config: PomodoistMcpConfig;
  fetcher: PomodoistMcpFetch;
  log: (entry: PomodoistMcpLog) => void;
};

export function safe<Args>(
  handler: (arguments_: Args) => Promise<ReturnType<typeof toolSuccess>>,
) {
  return async (arguments_: Args) => {
    try {
      return await handler(arguments_);
    } catch (error) {
      if (error instanceof ActionError) {
        return toolError(error.code as Parameters<typeof toolError>[0], error.message);
      }
      if (error instanceof RpcFailure) {
        return toolError(
          rpcErrorCode(error.status),
          error.status >= 500
            ? "Pomodoist service failed."
            : "Pomodoist request failed.",
        );
      }
      return toolError("internal", "Pomodoist service failed.");
    }
  };
}

export function rpcErrorCode(status: number) {
  return status === 400 ? "invalid_argument" : status === 401 || status === 403 ? "forbidden"
    : status === 404 ? "not_found" : status === 409 ? "conflict" : "internal";
}

export async function readRpc(
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

export async function rpc(
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

export function validDate(value: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value) || value.startsWith("0000-")) {
    return false;
  }
  const parsed = new Date(`${value}T00:00:00.000Z`);
  return Number.isFinite(parsed.getTime()) &&
    parsed.toISOString().slice(0, 10) === value;
}

export function validRfc3339(value: string) {
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

export function validTimeZone(value: string) {
  try {
    new Intl.DateTimeFormat("en", { timeZone: value }).format();
    return true;
  } catch {
    return false;
  }
}

export function validTask(value: RecordValue) {
  return validId(value.id) && typeof value.content === "string" &&
    validId(value.projectId);
}

export function validId(value: unknown): value is string {
  return typeof value === "string" && entityId.safeParse(value).success;
}

export function record(value: unknown): RecordValue | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? value as RecordValue
    : null;
}

export function records(value: unknown) {
  return Array.isArray(value)
    ? value.map(record).filter((item): item is RecordValue => item !== null)
    : [];
}

export function string(value: unknown) {
  return typeof value === "string" ? value : "";
}

export function nullableString(value: unknown) {
  return typeof value === "string" ? value : null;
}

export function number(value: unknown) {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

export function orderKey() {
  return String(Date.now() * 1000).padStart(20, "0");
}

export class ToolFailure extends ActionError {
  constructor(
    override readonly code:
      | "invalid_argument"
      | "not_found"
      | "conflict"
      | "forbidden"
      | "rate_limited"
      | "internal",
    message: string,
  ) {
    super(code, message);
  }
}

export class RpcFailure extends Error {
  constructor(readonly status: number) {
    super(`RPC failed with HTTP ${status}`);
  }
}

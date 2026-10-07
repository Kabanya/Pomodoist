import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import {
  mutationPlan,
  type MutationScope,
  remove,
  upsert,
} from "./mutation_helpers.ts";
import { canonicalJson } from "./openclaw_actions.ts";
import { toolSuccess } from "./pomodoist_mcp.ts";
import {
  type Context,
  date,
  entityId,
  localUserId,
  name,
  outputEnvelope,
  outputSchemas,
  pagination,
  readRpc,
  record,
  records,
  type RecordValue,
  safe,
  timeZone,
  ToolFailure,
} from "./tool_core.ts";

const periods = [
  "anytime",
  "morning",
  "afternoon",
  "evening",
  "night",
] as const;
type Period = typeof periods[number];
const period = z.enum(periods);
const selection = z.enum(["automatic", ...periods]);
const habitIcon = z.string().refine(
  (v) => v.trim().length > 0 && [...v].length <= 32,
  "Expected a nonblank habit icon of at most 32 Unicode code points.",
).nullable();
const goal = z.number().int().min(1).max(99);
const quotas = z.object({
  morning: goal.optional(),
  afternoon: goal.optional(),
  evening: goal.optional(),
  night: goal.optional(),
})
  .strict().refine(
    (v) =>
      Object.keys(v).length > 0 &&
      Object.values(v).reduce((a, b) => a + b, 0) <= 99,
    "Select at least one period; the daily total must be 1–99.",
  );
const weekdays = z.array(z.number().int().min(1).max(7)).min(1).max(7)
  .refine((v) => new Set(v).size === v.length, "Weekdays must be unique.");
const scheduleSchema = z.object({
  effectiveFrom: date,
  startDate: date,
  endDate: date.nullable(),
  weekdays,
  targetPerDay: goal,
  dayPeriod: selection.optional(),
  periodTargets: quotas.optional(),
}).strict().superRefine((v, c) => {
  if (v.endDate && v.endDate < v.startDate) {
    c.addIssue({ code: "custom", message: "End date precedes start date." });
  }
  if (
    v.periodTargets &&
    (Object.values(v.periodTargets).reduce((a, b) => a + b, 0) !==
        v.targetPerDay ||
      v.dayPeriod && v.dayPeriod !== "automatic")
  ) c.addIssue({ code: "custom", message: "Conflicting period goals." });
});
type Schedule = z.output<typeof scheduleSchema>;
type Habit = {
  id: string;
  title: string;
  icon?: string | null;
  projectId: string | null;
  reminderMinutes: number | null;
  scheduleHistory: Schedule[];
  createdAt: string;
  updatedAt: string;
};
type Mark = {
  id: string;
  habitId: string;
  day: string;
  dayPeriod?: Period;
  createdAt: string;
};
const publicHabit = z.object({
  id: z.uuid(),
  title: z.string(),
  icon: habitIcon,
  projectId: entityId.nullable(),
  reminderMinutes: z.number().int().min(0).max(1439).nullable(),
  scheduleHistory: z.array(scheduleSchema).min(1),
  createdAt: z.iso.datetime(),
  updatedAt: z.iso.datetime(),
  selectedDate: date,
  scheduled: z.boolean(),
  finished: z.boolean(),
  count: z.number().int().nonnegative(),
  target: goal,
  complete: z.boolean(),
  periods: z.array(
    z.object({ period, count: z.number().int().nonnegative(), target: goal })
      .strict(),
  ),
}).strict();
const readArgs = { time_zone: timeZone, date: date.optional() };
const fields = {
  icon: habitIcon.optional(),
  title: name.optional(),
  start_date: date.optional(),
  end_date: date.nullable().optional(),
  weekdays: weekdays.optional(),
  target_per_day: goal.optional(),
  day_period: selection.optional(),
  period_targets: quotas.nullable().optional(),
  project_id: entityId.nullable().optional(),
  reminder_minutes: z.number().int().min(0).max(1439).nullable().optional(),
};
const changed = z.object({ habit_id: z.uuid(), time_zone: timeZone, ...fields })
  .strict()
  .refine(
    (v) => Object.keys(v).some((k) => k !== "habit_id" && k !== "time_zone"),
    "At least one changed field is required.",
  );
const dated = z.object({
  habit_id: z.uuid(),
  ...readArgs,
  period: period.optional(),
}).strict();

function timestamp(v: unknown) {
  const value = typeof v === "number" ? new Date(v) : new Date(String(v));
  if (!Number.isFinite(+value)) {
    throw new ToolFailure("internal", "Invalid habit timestamp.");
  }
  return value.toISOString();
}
async function snapshot(context: Context) {
  const data = record(await readRpc(context, "habit_snapshot", {}));
  if (!data) throw new ToolFailure("internal", "Invalid habit snapshot.");
  const habits = records(data.habits).map((h) =>
    ({
      ...h,
      createdAt: timestamp(h.createdAt),
      updatedAt: timestamp(h.updatedAt),
    }) as Habit
  );
  const marks = records(data.checkIns).map((m) =>
    ({ ...m, createdAt: timestamp(m.createdAt) }) as Mark
  );
  const now = timestamp(data.serverNow);
  if (!Number.isFinite(Date.parse(now))) {
    throw new ToolFailure("internal", "Invalid server time.");
  }
  return { habits, marks, projects: records(data.projects), now };
}
type Snapshot = Awaited<ReturnType<typeof snapshot>>;
function today(now: string, zone: string) {
  const parts = new Intl.DateTimeFormat("en", {
    timeZone: zone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(new Date(now));
  const value = (kind: string) => parts.find((p) => p.type === kind)!.value;
  return `${value("year")}-${value("month")}-${value("day")}`;
}
function requireHabit(s: Snapshot, id: string) {
  const h = s.habits.find((h) => h.id === id);
  if (!h) throw new ToolFailure("not_found", "Habit not found.");
  return h;
}
function scheduleFor(h: Habit, day: string) {
  return h.scheduleHistory.filter((v) => v.effectiveFrom <= day).at(-1);
}
function scheduled(h: Habit, day: string) {
  const v = scheduleFor(h, day);
  const weekday = new Date(`${day}T12:00:00Z`).getUTCDay() || 7;
  return Boolean(
    v && day >= v.startDate && (!v.endDate || day <= v.endDate) &&
      v.weekdays.includes(weekday),
  );
}
function targets(h: Habit, v: Schedule): Partial<Record<Period, number>> {
  if (v.periodTargets) return v.periodTargets;
  let p = v.dayPeriod ?? "automatic";
  if (p === "automatic") {
    const minutes = h.reminderMinutes ?? null;
    p = v.targetPerDay > 1 || minutes === null
      ? "anytime"
      : minutes < 300
      ? "night"
      : minutes < 720
      ? "morning"
      : minutes < 1080
      ? "afternoon"
      : "evening";
  }
  return { [p]: v.targetPerDay };
}
function progress(s: Snapshot, h: Habit, day: string) {
  const v = scheduleFor(h, day);
  const goals = v ? targets(h, v) : {};
  const selected = periods.filter((p) => goals[p] !== undefined);
  const counts = Object.fromEntries(selected.map((p) => [p, 0])) as Partial<
    Record<Period, number>
  >;
  const marks = s.marks.filter((m) => m.habitId === h.id && m.day === day)
    .sort((a, b) =>
      a.createdAt.localeCompare(b.createdAt) || a.id.localeCompare(b.id)
    );
  const assigned = new Map<string, Period>();
  for (const m of marks) {
    if (m.dayPeriod && goals[m.dayPeriod] !== undefined) {
      assigned.set(m.id, m.dayPeriod);
      counts[m.dayPeriod]!++;
    }
  }
  for (const m of marks) {
    if (!assigned.has(m.id) && selected.length) {
      const p = selected.find((p) => counts[p]! < goals[p]!) ?? selected[0];
      assigned.set(m.id, p);
      counts[p]!++;
    }
  }
  const rows = selected.map((p) => ({
    period: p,
    count: Math.min(counts[p]!, goals[p]!),
    target: goals[p]!,
  }));
  return {
    marks,
    assigned,
    periods: rows,
    count: rows.reduce((sum, p) => sum + p.count, 0),
    target: v?.targetPerDay ?? h.scheduleHistory.at(-1)!.targetPerDay,
  };
}
function view(s: Snapshot, h: Habit, day: string, current: string) {
  const p = progress(s, h, day);
  const latest = h.scheduleHistory.at(-1)!;
  return {
    id: h.id,
    title: h.title,
    icon: h.icon ?? null,
    projectId: h.projectId ?? null,
    reminderMinutes: h.reminderMinutes ?? null,
    scheduleHistory: h.scheduleHistory,
    createdAt: h.createdAt,
    updatedAt: h.updatedAt,
    selectedDate: day,
    scheduled: scheduled(h, day),
    finished: Boolean(latest.endDate && latest.endDate < current),
    count: p.count,
    target: p.target,
    complete: scheduled(h, day) && p.count >= p.target,
    periods: p.periods,
  };
}
function project(s: Snapshot, id: string | null | undefined) {
  if (
    id != null &&
    !s.projects.some((p) => p.id === id && !p.scopeId && p.isArchived !== true)
  ) {
    throw new ToolFailure(
      "invalid_argument",
      "Select an active personal project.",
    );
  }
}
function buildSchedule(
  args: z.output<typeof changed> | RecordValue,
  current: string,
  old?: Schedule,
): Schedule {
  const q = args.period_targets !== undefined
    ? args.period_targets
    : args.day_period !== undefined || args.target_per_day !== undefined
    ? undefined
    : old?.periodTargets;
  if (
    q && args.target_per_day !== undefined &&
    args.target_per_day !==
      Object.values(q as Record<string, number>).reduce((a, b) => a + b, 0)
  ) {
    throw new ToolFailure(
      "invalid_argument",
      "Daily target must equal the sum of period goals.",
    );
  }
  if (q && args.day_period && args.day_period !== "automatic") {
    throw new ToolFailure(
      "invalid_argument",
      "Period goals cannot be combined with a single day period.",
    );
  }
  const value = {
    effectiveFrom: old ? current : args.start_date ?? current,
    startDate: args.start_date ?? old?.startDate ?? current,
    endDate: args.end_date !== undefined ? args.end_date : old?.endDate ?? null,
    weekdays: args.weekdays ?? old?.weekdays ?? [1, 2, 3, 4, 5, 6, 7],
    targetPerDay: q
      ? Object.values(q as Record<string, number>).reduce((a, b) => a + b, 0)
      : args.target_per_day ?? old?.targetPerDay ?? 1,
    ...(q
      ? { periodTargets: q }
      : { dayPeriod: args.day_period ?? old?.dayPeriod ?? "automatic" }),
  };
  const parsed = scheduleSchema.safeParse(value);
  if (!parsed.success) {
    throw new ToolFailure("invalid_argument", parsed.error.issues[0].message);
  }
  return parsed.data;
}
function edited(s: Snapshot, h: Habit, args: z.output<typeof changed>) {
  project(s, args.project_id);
  const current = today(s.now, args.time_zone);
  const latest = h.scheduleHistory.at(-1)!;
  const next = buildSchedule(args, current, latest);
  const comparable = (v: Schedule) => ({
    ...v,
    effectiveFrom: current,
    dayPeriod: v.dayPeriod ?? "automatic",
    weekdays: [...v.weekdays].sort(),
  });
  const same =
    canonicalJson(comparable(latest)) === canonicalJson(comparable(next));
  return {
    ...h,
    userId: localUserId,
    isDeleted: false,
    title: args.title ?? h.title,
    icon: args.icon !== undefined ? args.icon : h.icon ?? null,
    projectId: args.project_id !== undefined
      ? args.project_id
      : h.projectId ?? null,
    reminderMinutes: args.reminder_minutes !== undefined
      ? args.reminder_minutes
      : h.reminderMinutes ?? null,
    scheduleHistory: same
      ? h.scheduleHistory
      : [...h.scheduleHistory.filter((v) => v.effectiveFrom < current), next],
    updatedAt: s.now,
  };
}

export function registerHabitReads(server: McpServer, context: Context) {
  const annotations = { readOnlyHint: true, openWorldHint: false };
  server.registerTool(
    "list_habits",
    {
      description:
        "List personal habits with scheduled-date progress and per-period goals, including night. Calendar dates use time_zone.",
      inputSchema: z.object({
        ...readArgs,
        ...pagination,
        view: z.enum(["all", "active", "finished"]).default("active"),
      }).strict(),
      outputSchema: outputEnvelope(
        z.object({
          items: z.array(publicHabit),
          nextCursor: z.string().nullable(),
        }).strict(),
      ),
      annotations,
    },
    safe(async (args) => {
      const s = await snapshot(context),
        current = today(s.now, args.time_zone),
        day = args.date ?? current;
      const rows = s.habits.map((h) => view(s, h, day, current)).filter((h) =>
        args.view === "all" ||
        (args.view === "finished" ? h.finished : !h.finished && h.scheduled)
      )
        .sort((a, b) =>
          a.createdAt.localeCompare(b.createdAt) || a.id.localeCompare(b.id)
        );
      let offset = 0;
      if (args.cursor) {
        try {
          const c = JSON.parse(atob(args.cursor));
          if (
            c.date !== day || c.view !== args.view ||
            !Number.isInteger(c.offset) || c.offset < 0
          ) throw Error();
          offset = c.offset;
        } catch {
          throw new ToolFailure("invalid_argument", "Invalid habit cursor.");
        }
      }
      const end = offset + args.limit;
      return toolSuccess({
        items: rows.slice(offset, end),
        nextCursor: end < rows.length
          ? btoa(JSON.stringify({ date: day, view: args.view, offset: end }))
          : null,
      });
    }),
  );
  server.registerTool(
    "get_habit",
    {
      inputSchema: z.object({ habit_id: z.uuid(), ...readArgs }).strict(),
      outputSchema: outputEnvelope(publicHabit),
      annotations,
      description:
        "Read one personal habit, historical schedule and progress for a calendar date.",
    },
    safe(async (args) => {
      const s = await snapshot(context), current = today(s.now, args.time_zone);
      return toolSuccess(
        view(s, requireHabit(s, args.habit_id), args.date ?? current, current),
      );
    }),
  );
}

export function habitMutations(
  { define, context, annotations }: MutationScope,
) {
  define("create_habit", {
    description:
      "Create a personal habit. time_zone sets the calendar date. period_targets assigns separate morning, afternoon, evening and night goals; their sum is the daily target. One reminder_minutes value schedules one daily reminder.",
    inputSchema: z.object({ ...fields, title: name, time_zone: timeZone })
      .strict(),
    outputSchema: outputSchemas.mutation,
    annotations: annotations.closed,
  }, async (args) => {
    const s = await snapshot(context);
    project(s, args.project_id);
    const id = crypto.randomUUID(), current = today(s.now, args.time_zone);
    const h = {
      id,
      userId: localUserId,
      title: args.title,
      icon: args.icon ?? null,
      projectId: args.project_id ?? null,
      reminderMinutes: args.reminder_minutes ?? null,
      scheduleHistory: [buildSchedule(args, current)],
      createdAt: s.now,
      updatedAt: s.now,
      isDeleted: false,
    };
    return mutationPlan([upsert("habit", id, h, s.now)], { id });
  });
  define("update_habit", {
    description:
      "Edit a habit; schedule changes take effect today in time_zone and retain historical goals. period_targets replaces period quotas; day_period or target_per_day switches to one daily goal; null clears quotas or nullable fields.",
    inputSchema: changed,
    outputSchema: outputSchemas.mutation,
    annotations: annotations.closed,
  }, async (args) => {
    const s = await snapshot(context), h = requireHabit(s, args.habit_id);
    return mutationPlan([upsert("habit", h.id, edited(s, h, args), s.now)], {
      id: h.id,
    });
  });
  for (
    const action of [
      "add_habit_check_in",
      "complete_habit",
      "undo_habit_check_in",
    ] as const
  ) {
    define(action, {
      description: action === "complete_habit"
        ? "Fill all remaining check-ins for the selected calendar date, or only the specified period. This completes the daily goal; it does not end the habit schedule. Future dates are read-only."
        : action === "add_habit_check_in"
        ? "Add one check-in on the selected calendar date. Specify period when multiple parts of day have goals. Night belongs to that same date; press time never selects a period."
        : "Undo the most recent check-in on the selected calendar date, optionally restricted to one period. Past check-ins can be corrected. Future dates are read-only.",
      inputSchema: dated,
      outputSchema: outputSchemas.mutation,
      annotations: annotations.closed,
    }, async (args) => {
      const s = await snapshot(context),
        h = requireHabit(s, args.habit_id),
        current = today(s.now, args.time_zone),
        day = args.date ?? current;
      if (day > current) {
        throw new ToolFailure(
          "invalid_argument",
          "Future habit dates are read-only.",
        );
      }
      const p = progress(s, h, day);
      if (args.period && !p.periods.some((p) => p.period === args.period)) {
        throw new ToolFailure(
          "invalid_argument",
          "Period is not scheduled on this date.",
        );
      }
      if (action === "undo_habit_check_in") {
        const m = p.marks.filter((m) =>
          !args.period || p.assigned.get(m.id) === args.period
        ).at(-1);
        if (!m) throw new ToolFailure("conflict", "No check-in to undo.");
        return mutationPlan([remove("habit_check_in", m.id, {}, s.now)], {
          id: h.id,
        });
      }
      if (!scheduled(h, day)) {
        throw new ToolFailure(
          "invalid_argument",
          "Habit is not scheduled on this date.",
        );
      }
      if (
        action === "add_habit_check_in" && !args.period && p.periods.length > 1
      ) {
        throw new ToolFailure(
          "invalid_argument",
          "Choose a part of day for this check-in.",
        );
      }
      const chosen = p.periods.filter((p) =>
        !args.period || p.period === args.period
      );
      const marks = chosen.flatMap((p) =>
        Array.from({
          length: action === "complete_habit"
            ? p.target - p.count
            : p.count < p.target
            ? 1
            : 0,
        }, () => {
          const id = crypto.randomUUID();
          return upsert("habit_check_in", id, {
            id,
            userId: localUserId,
            habitId: h.id,
            day,
            dayPeriod: p.period,
            createdAt: s.now,
            updatedAt: s.now,
            isDeleted: false,
          }, s.now);
        })
      );
      if (!marks.length) {
        throw new ToolFailure(
          "conflict",
          "Selected habit goal is already complete.",
        );
      }
      return mutationPlan(marks, { id: h.id });
    });
  }
  for (const action of ["finish_habit", "reopen_habit"] as const) {
    define(action, {
      description: action === "finish_habit"
        ? "End the habit schedule on end_date (inclusive), defaulting to today in time_zone. Keep its past marks and goals; this does not complete the daily goal."
        : "Remove the habit end date from today in time_zone, preserving previous schedule versions and check-ins.",
      inputSchema: z.object({
        habit_id: z.uuid(),
        time_zone: timeZone,
        ...(action === "finish_habit" ? { end_date: date.optional() } : {}),
      }).strict(),
      outputSchema: outputSchemas.mutation,
      annotations: annotations.closed,
    }, async (args) => {
      const s = await snapshot(context),
        h = requireHabit(s, args.habit_id),
        current = today(s.now, args.time_zone);
      const end = action === "finish_habit"
        ? (args as { end_date?: string }).end_date ?? current
        : null;
      return mutationPlan([
        upsert(
          "habit",
          h.id,
          edited(s, h, {
            habit_id: h.id,
            time_zone: args.time_zone,
            end_date: end,
          }),
          s.now,
        ),
      ], { id: h.id });
    });
  }
  define("delete_habit", {
    description:
      "Delete a personal habit through sync tombstones. Use finish_habit to end its schedule while keeping visible history.",
    inputSchema: z.object({ habit_id: z.uuid() }).strict(),
    outputSchema: outputSchemas.mutation,
    annotations: annotations.destructive,
  }, async (args) => {
    const s = await snapshot(context), h = requireHabit(s, args.habit_id);
    return mutationPlan([remove("habit", h.id, {}, s.now)], { id: h.id });
  });
}

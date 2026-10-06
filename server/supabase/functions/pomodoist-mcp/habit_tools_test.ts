import { assert, assertEquals } from "@std/assert";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { registerPomodoistTools } from "./tools.ts";

const id = "11111111-1111-4111-8111-111111111111";
const otherId = "22222222-2222-4222-8222-222222222222";
const now = "2026-10-03T21:30:00Z";
const baseSchedule = {
  effectiveFrom: "2026-10-01",
  startDate: "2026-10-01",
  endDate: null,
  weekdays: [1, 2, 3, 4, 5, 6, 7],
  targetPerDay: 7,
  periodTargets: { morning: 2, afternoon: 2, evening: 2, night: 1 },
};
const habit = {
  id,
  userId: "local-user",
  title: "Water",
  projectId: null,
  reminderMinutes: null,
  scheduleHistory: [baseSchedule],
  createdAt: now,
  updatedAt: now,
  isDeleted: false,
};
type Row = Record<string, unknown>;
type Tool = {
  schema: z.ZodType;
  output: z.ZodType;
  run: (args: unknown) => Promise<Row>;
};
function fixture(
  habits: Row[] = [structuredClone(habit)],
  checkIns: Row[] = [],
  serverNow = now,
  projects: Row[] = [],
) {
  const calls: { name: string; args: Row }[] = [];
  const tools = new Map<string, Tool>();
  const server = {
    registerTool(
      name: string,
      config: { inputSchema: z.ZodType; outputSchema: z.ZodType },
      run: Tool["run"],
    ) {
      tools.set(name, {
        schema: config.inputSchema,
        output: config.outputSchema,
        run,
      });
    },
  } as unknown as McpServer;
  registerPomodoistTools(server, {
    subject: otherId,
    userId: otherId,
    sessionId: otherId,
    clientId: id,
  }, {
    config: {
      issuer: "https://example.com/auth/v1",
      resourceUrl: "https://example.com/mcp",
      allowedOrigins: [],
      supabaseUrl: "https://example.com",
      serviceRoleKey: "test",
    },
    fetch: async (input, init) => {
      const name = String(input).split("/").at(-1)!;
      const args = JSON.parse(String(init?.body));
      calls.push({ name, args });
      if (name === "read_pomodoist_mcp") {
        assertEquals(args.p_user_id, otherId);
        assertEquals(args.p_operation, "habit_snapshot");
        return Response.json({ habits, checkIns, serverNow, projects });
      }
      if (name === "push_pomodoist_mcp_changes") {
        assertEquals(args.p_user_id, otherId);
        for (const op of args.p_operations) {
          const rows = op.entityType === "habit" ? habits : checkIns;
          const i = rows.findIndex((r) => r.id === op.entityId);
          if (op.operation === "delete") { if (i >= 0) rows.splice(i, 1); }
          else if (i >= 0) rows[i] = op.payload;
          else rows.push(op.payload);
        }
        return Response.json({ serverRevision: "42" });
      }
      if (name === "send_pomodoist_mcp_sync_hint") return Response.json(null);
      throw Error(`Unexpected RPC ${name}`);
    },
  });
  async function run(name: string, args: Row) {
    const t = tools.get(name)!;
    const result = await t.run(t.schema.parse(args));
    t.output.parse(result.structuredContent);
    return result.structuredContent as {
      ok: boolean;
      data: Row;
      error: { code: string };
    };
  }
  const args = { habit_id: id, time_zone: "UTC", date: "2026-10-03" };
  const writes = () =>
    calls.filter((c) => c.name === "push_pomodoist_mcp_changes");
  return { tools, calls, habits, checkIns, run, args, writes };
}
function mark(
  markId: string,
  dayPeriod?: string,
  createdAt = now,
  day = "2026-10-03",
) {
  return {
    id: markId,
    habitId: id,
    day,
    ...(dayPeriod ? { dayPeriod } : {}),
    createdAt,
    updatedAt: createdAt,
    isDeleted: false,
  };
}

Deno.test("habit create derives seven daily repetitions including night and emits sync payload", async () => {
  const f = fixture([]);
  const result = await f.run("create_habit", {
    title: "Water",
    time_zone: "Europe/Moscow",
    period_targets: baseSchedule.periodTargets,
    reminder_minutes: 540,
  });
  assert(result.ok);
  assertEquals(result.data.server_revision, "42");
  assertEquals((f.habits[0].scheduleHistory as Row[])[0], {
    ...baseSchedule,
    effectiveFrom: "2026-10-04",
    startDate: "2026-10-04",
  });
  assertEquals(f.habits[0].userId, "local-user");
  assertEquals(f.habits[0].reminderMinutes, 540);
  assertEquals(f.calls.at(-1)!.name, "send_pomodoist_mcp_sync_hint");
});
Deno.test("habit schemas reject invalid dates, timezones, quota shapes and caller identities before reading", () => {
  const f = fixture();
  const schema = f.tools.get("create_habit")!.schema;
  for (
    const extra of [
      { time_zone: "bad/zone" },
      { start_date: "2026-02-29" },
      { period_targets: {} },
      { period_targets: { anytime: 2 } },
      { period_targets: { night: 0 } },
      { period_targets: { morning: 99, night: 1 } },
      { period_targets: { night: 1.5 } },
      { user_id: otherId },
    ]
  ) {
    assert(
      !schema.safeParse({ title: "Water", time_zone: "UTC", ...extra }).success,
    );
  }
  assert(
    !f.tools.get("update_habit")!.schema.safeParse({
      habit_id: id,
      time_zone: "UTC",
    }).success,
  );
  assertEquals(f.calls.length, 0);
});
Deno.test("habit create rejects contradictory total, single group and cross-account/shared project", async () => {
  const f = fixture([], [], now, [{ id: "shared", scopeId: id }]);
  for (
    const extra of [
      { target_per_day: 7, period_targets: { night: 2 } },
      { day_period: "morning", period_targets: { night: 2 } },
      { project_id: "shared" },
      { project_id: "missing" },
    ]
  ) {
    const result = await f.run("create_habit", {
      title: "Water",
      time_zone: "UTC",
      ...extra,
    });
    assertEquals(result.error.code, "invalid_argument");
  }
  assertEquals(f.writes().length, 0);
});
Deno.test("habit list reads legacy epoch timestamps as ISO, paginates and hides private identity", async () => {
  const f = fixture([{
    ...habit,
    createdAt: Date.parse(now),
    updatedAt: Date.parse(now),
  }, { ...habit, id: otherId }]);
  const first = await f.run("list_habits", { time_zone: "UTC", limit: 1 });
  const rows = first.data.items as Row[];
  assertEquals(rows.length, 1);
  assertEquals(rows[0].createdAt, new Date(now).toISOString());
  assert(!("userId" in rows[0]));
  assert(first.data.nextCursor);
  const next = await f.run("list_habits", {
    time_zone: "UTC",
    limit: 1,
    cursor: first.data.nextCursor,
  });
  assertEquals((next.data.items as Row[])[0].id, otherId);
  assertEquals(next.data.nextCursor, null);
  const wrong = await f.run("list_habits", {
    time_zone: "UTC",
    date: "2026-10-02",
    cursor: first.data.nextCursor,
  });
  assertEquals(wrong.error.code, "invalid_argument");
});
Deno.test("automatic habit grouping observes 00,05,12,18 boundaries and legacy/manual/multiple-goal priorities", async () => {
  for (
    const [reminderMinutes, dayPeriod, targetPerDay, expected] of [
      [0, undefined, 1, "night"],
      [299, undefined, 1, "night"],
      [300, undefined, 1, "morning"],
      [719, undefined, 1, "morning"],
      [720, undefined, 1, "afternoon"],
      [1079, undefined, 1, "afternoon"],
      [1080, undefined, 1, "evening"],
      [1439, undefined, 1, "evening"],
      [null, undefined, 1, "anytime"],
      [undefined, undefined, 1, "anytime"],
      [0, undefined, 7, "anytime"],
      [800, "night", 7, "night"],
    ] as const
  ) {
    const f = fixture([{
      ...habit,
      reminderMinutes,
      scheduleHistory: [{
        ...baseSchedule,
        periodTargets: undefined,
        dayPeriod,
        targetPerDay,
      }],
    }]);
    const result = await f.run("get_habit", f.args);
    assertEquals((result.data.periods as Row[])[0].period, expected);
  }
});
Deno.test("night check-ins belong to selected calendar date; future dates are read-only in caller timezone", async () => {
  const f = fixture();
  assert(
    (await f.run("add_habit_check_in", { ...f.args, period: "night" })).ok,
  );
  assertEquals(f.checkIns[0].day, "2026-10-03");
  assertEquals(f.checkIns[0].dayPeriod, "night");
  assertEquals(
    (await f.run("add_habit_check_in", {
      ...f.args,
      date: "2026-10-04",
      period: "morning",
    })).error.code,
    "invalid_argument",
  );
  assert(
    (await f.run("add_habit_check_in", {
      ...f.args,
      time_zone: "Europe/Moscow",
      date: "2026-10-04",
      period: "night",
    })).ok,
  );
  assertEquals(f.checkIns[1].day, "2026-10-04");
  const future = await f.run("get_habit", { ...f.args, date: "2026-10-05" });
  assert(future.ok);
});
Deno.test("multi-period single check-in requires a group and never spills a full group into night", async () => {
  const f = fixture();
  assertEquals(
    (await f.run("add_habit_check_in", f.args)).error.code,
    "invalid_argument",
  );
  assertEquals(
    (await f.run("add_habit_check_in", { ...f.args, period: "anytime" })).error
      .code,
    "invalid_argument",
  );
  for (let i = 0; i < 2; i++) {
    assert(
      (await f.run("add_habit_check_in", { ...f.args, period: "morning" })).ok,
    );
  }
  assertEquals(
    (await f.run("add_habit_check_in", { ...f.args, period: "morning" })).error
      .code,
    "conflict",
  );
  assertEquals(f.checkIns.length, 2);
  const read = await f.run("get_habit", f.args);
  assertEquals(read.data.complete, false);
  assertEquals(read.data.count, 2);
});
Deno.test("complete fills missing period goals exactly once; scoped undo makes daily habit incomplete", async () => {
  const f = fixture();
  assert((await f.run("complete_habit", { ...f.args, period: "night" })).ok);
  assertEquals(f.checkIns.length, 1);
  assert((await f.run("complete_habit", f.args)).ok);
  assertEquals(f.checkIns.length, 7);
  assertEquals((await f.run("get_habit", f.args)).data.complete, true);
  assertEquals((await f.run("complete_habit", f.args)).error.code, "conflict");
  assert(
    (await f.run("undo_habit_check_in", { ...f.args, period: "night" })).ok,
  );
  const read = await f.run("get_habit", f.args);
  assertEquals(read.data.count, 6);
  assertEquals(read.data.complete, false);
  assertEquals(f.checkIns.filter((m) => m.dayPeriod === "morning").length, 2);
});
Deno.test("legacy marks fill available goals after explicit marks; scoped undo uses latest deterministic attribution", async () => {
  const f = fixture(undefined, [
    mark("a", undefined, "2026-10-03T10:00:00Z"),
    mark("b", "morning", "2026-10-03T09:00:00Z"),
    mark("c", "evening"),
    mark("d", "evening"),
    mark("e", "evening"),
    mark("f", "anytime"),
  ]);
  const read = await f.run("get_habit", f.args);
  assertEquals(read.data.count, 5);
  assertEquals(read.data.periods, [
    { period: "morning", count: 2, target: 2 },
    { period: "afternoon", count: 1, target: 2 },
    { period: "evening", count: 2, target: 2 },
    { period: "night", count: 0, target: 1 },
  ]);
  await f.run("undo_habit_check_in", { ...f.args, period: "morning" });
  const op = (f.writes().at(-1)!.args.p_operations as Row[])[0];
  assertEquals(op.entityId, "a");
  assertEquals(op.operation, "delete");
});
Deno.test("schedule edits preserve historical period goals; title-only edit does not add a version", async () => {
  const f = fixture();
  await f.run("update_habit", {
    habit_id: id,
    time_zone: "UTC",
    title: "Drink water",
  });
  assertEquals((f.habits[0].scheduleHistory as Row[]).length, 1);
  await f.run("update_habit", {
    habit_id: id,
    time_zone: "UTC",
    period_targets: { night: 3 },
  });
  const history = f.habits[0].scheduleHistory as Row[];
  assertEquals(history.length, 2);
  assertEquals(history[0], baseSchedule);
  assertEquals(history[1].effectiveFrom, "2026-10-03");
  assertEquals(history[1].targetPerDay, 3);
  const past = await f.run("get_habit", { ...f.args, date: "2026-10-02" });
  assertEquals(past.data.target, 7);
  assertEquals((await f.run("get_habit", f.args)).data.periods, [{
    period: "night",
    count: 0,
    target: 3,
  }]);
  await f.run("update_habit", {
    habit_id: id,
    time_zone: "UTC",
    day_period: "morning",
    target_per_day: 7,
  });
  const current = (f.habits[0].scheduleHistory as Row[]).at(-1)!;
  assertEquals(current.dayPeriod, "morning");
  assert(!("periodTargets" in current));
});
Deno.test("finish/reopen keep previous goals and marks; finished past dates remain correctable; delete uses a tombstone", async () => {
  const f = fixture(undefined, [mark("a", "night", now, "2026-10-01")]);
  await f.run("finish_habit", {
    habit_id: id,
    time_zone: "UTC",
    end_date: "2026-10-02",
  });
  assertEquals(f.checkIns.length, 1);
  assertEquals((await f.run("get_habit", f.args)).data.finished, true);
  assertEquals(
    ((await f.run("list_habits", { time_zone: "UTC", view: "finished" })).data
      .items as Row[]).length,
    1,
  );
  assertEquals(
    (await f.run("add_habit_check_in", { ...f.args, period: "night" })).error
      .code,
    "invalid_argument",
  );
  assert(
    (await f.run("undo_habit_check_in", {
      ...f.args,
      date: "2026-10-01",
      period: "night",
    })).ok,
  );
  assertEquals(f.checkIns.length, 0);
  await f.run("reopen_habit", { habit_id: id, time_zone: "UTC" });
  assertEquals((await f.run("get_habit", f.args)).data.finished, false);
  await f.run("delete_habit", { habit_id: id });
  assertEquals(
    (f.writes().at(-1)!.args.p_operations as Row[])[0].operation,
    "delete",
  );
  assertEquals((await f.run("get_habit", f.args)).error.code, "not_found");
});
Deno.test("unscheduled weekday rejects new marks but permits historical undo", async () => {
  const f = fixture([{
    ...habit,
    scheduleHistory: [{ ...baseSchedule, weekdays: [1] }],
  }], [mark("a", "night")]);
  assertEquals(
    (await f.run("complete_habit", f.args)).error.code,
    "invalid_argument",
  );
  assert((await f.run("undo_habit_check_in", f.args)).ok);
});

Deno.test("habit undo compares timestamps as instants across UTC offsets", async () => {
  const f = fixture(undefined, [
    mark("earlier", "night", "2026-10-03T14:00:00+03:00"),
    mark("later", "night", "2026-10-03T12:00:00Z"),
  ]);
  assert(
    (await f.run("undo_habit_check_in", { ...f.args, period: "night" })).ok,
  );
  assertEquals(
    (f.writes().at(-1)!.args.p_operations as Row[])[0].entityId,
    "later",
  );
});

Deno.test("habit signs survive create, edit, reset and read", async () => {
  const f = fixture();
  await f.run("create_habit", { title: "Read", time_zone: "UTC", icon: "📚" });
  assertEquals(f.habits.at(-1)!.icon, "📚");
  await f.run("update_habit", {
    habit_id: id,
    time_zone: "UTC",
    icon: "bookOpen",
  });
  const read = await f.run("get_habit", f.args);
  assertEquals(read.data.icon, "bookOpen");
  await f.run("update_habit", {
    habit_id: id,
    time_zone: "UTC",
    title: "Water again",
  });
  assertEquals(f.habits[0].icon, "bookOpen");
  await f.run("update_habit", { habit_id: id, time_zone: "UTC", icon: null });
  assertEquals(f.habits[0].icon, null);
  for (const icon of ["", " ", 1, false, {}, "😀".repeat(33)]) {
    assert(
      !f.tools.get("create_habit")!.schema.safeParse({
        title: "Read",
        time_zone: "UTC",
        icon,
      }).success,
    );
    assert(
      !f.tools.get("update_habit")!.schema.safeParse({
        habit_id: id,
        time_zone: "UTC",
        icon,
      }).success,
    );
  }
  assert(
    f.tools.get("create_habit")!.schema.safeParse({
      title: "Read",
      time_zone: "UTC",
      icon: "😀".repeat(32),
    }).success,
  );
});

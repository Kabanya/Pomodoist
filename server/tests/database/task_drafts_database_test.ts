import { assertEquals } from "jsr:@std/assert";
import { commitDraftOps } from "../../supabase/functions/_shared/pomodoist_task_commands.ts";
import { pomodoistState } from "../../supabase/functions/_shared/pomodoist_state.ts";

// Run explicitly against the disposable local database after applying migrations:
// POMODOIST_TEST_DB=pomodoist-selfhost-refactor-db deno test --allow-env --allow-run tests/database/task_drafts_database_test.ts
Deno.test("draft planners persist atomically with real durable SQL receipts", async () => {
  const container = Deno.env.get("POMODOIST_TEST_DB");
  if (!container?.startsWith("pomodoist-selfhost-")) {
    throw new Error("Explicit disposable local database required");
  }
  const user = { id: "95000000-0000-4000-8000-000000000001" };
  const command = {
    id: "draft-regression-command",
    tasks: [
      { quickAdd: "First @shared" },
      { quickAdd: "Second @shared" },
    ],
  };
  const now = new Date("2026-09-13T10:00:00Z");
  const operations = await commitDraftOps(
    pomodoistState([]),
    command,
    user,
    now,
    () => crypto.randomUUID(),
  );
  const changedState = pomodoistState(
    operations.map((op) => ({ ...op, data: op.payload })),
  );
  const retry = await commitDraftOps(
    changedState,
    command,
    user,
    new Date(+now + 60000),
    () => crypto.randomUUID(),
  );
  assertEquals(
    retry.filter((op) => op.entityType === "task").map((op) => op.entityId),
    operations.filter((op) => op.entityType === "task").map((op) =>
      op.entityId
    ),
  );
  const legacyCommand = { ...command, id: "legacy-regression-command" };
  const legacyRetry = await commitDraftOps(
    pomodoistState([]),
    legacyCommand,
    user,
    now,
    () => crypto.randomUUID(),
  );
  const legacy = operations.filter((op) => op.entityType === "task").map((
    op,
    i,
  ) => ({
    ...op,
    opId: legacyCommand.id,
    entityId: `legacy-task-${i}`,
    payload: { ...op.payload, id: `legacy-task-${i}` },
  }));
  const invalidBatch = [{
    ...operations[0],
    opId: "rollback-command",
    entityId: "rollback-task",
  }, { ...operations[1], opId: "rollback-invalid", entityId: null }];
  const json = (value: unknown) =>
    `'${JSON.stringify(value).replaceAll("'", "''")}'::jsonb`;
  const sql = `begin;
insert into auth.users(id,email,aud,role,created_at,updated_at) values
('${user.id}','draft-regression@example.com','authenticated','authenticated',now(),now());
select set_config('request.jwt.claim.sub','${user.id}',true);
select private.push_changes_for_user('${user.id}','pomodoist','legacy',${
    json(legacy)
  });
set local role authenticated;
select public.push_pomodoist_draft_changes('watch','${command.id}',${
    json(operations)
  });
select public.push_pomodoist_draft_changes('watch','${command.id}',${
    json(retry)
  });
select public.push_pomodoist_draft_changes('watch','${legacyCommand.id}',${
    json(legacyRetry)
  });
reset role;
do $$ begin
  begin
    perform public.push_pomodoist_draft_changes('watch','rollback-command',${
    json(invalidBatch)
  });
    raise exception 'Expected invalid operation failure';
  exception when others then
    if sqlerrm = 'Expected invalid operation failure' then raise; end if;
  end;
  if exists (select 1 from public.sync_operation_receipts where user_id='${user.id}' and op_id='rollback-command')
    or exists (select 1 from public.sync_entities where user_id='${user.id}' and entity_id='rollback-task') then
    raise exception 'Partial batch escaped rollback'; end if;
  if (select count(*) from public.sync_entities where user_id='${user.id}' and entity_type='task') <> 3 then
    raise exception 'Batch or legacy retry created missing/duplicate tasks'; end if;
  if exists (select 1 from public.sync_entities l where l.user_id='${user.id}' and l.entity_type='task_label'
    and (not exists (select 1 from public.sync_entities t where t.user_id=l.user_id and t.entity_type='task' and t.entity_id=l.data->>'taskId')
      or not exists (select 1 from public.sync_entities t where t.user_id=l.user_id and t.entity_type='label' and t.entity_id=l.data->>'labelId')))
    then raise exception 'Dangling task label'; end if;
  if (select count(*) from public.sync_entities where user_id='${user.id}' and entity_type='label') <> 1 then
    raise exception 'Shared label duplicated'; end if;
  if (select count(*) from public.sync_entities where user_id='${user.id}' and entity_type='task_label') <> 2 then
    raise exception 'Task label missing'; end if;
  if exists (select 1 from public.sync_entities where user_id='${user.id}' and entity_type='task' and data->>'updatedAt' <> '${now.toISOString()}') then
    raise exception 'Lost-response retry overwrote accepted entities'; end if;
end $$;
rollback;`;
  const process = new Deno.Command("docker", {
    args: [
      "exec",
      "-i",
      container,
      "psql",
      "-X",
      "-U",
      "postgres",
      "-d",
      "postgres",
      "-v",
      "ON_ERROR_STOP=1",
    ],
    stdin: "piped",
    stdout: "piped",
    stderr: "piped",
  }).spawn();
  const writer = process.stdin.getWriter();
  await writer.write(new TextEncoder().encode(sql));
  await writer.close();
  const result = await process.output();
  assertEquals(result.code, 0, new TextDecoder().decode(result.stderr));
});

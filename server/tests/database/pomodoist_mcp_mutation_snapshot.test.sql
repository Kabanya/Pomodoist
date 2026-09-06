begin;
\ir hosted-mode.inc

select to_regprocedure(
  'private.read_pomodoist_mcp_v1(uuid,text,jsonb)'
) is not null as function_exists \gset

\if :function_exists

select plan(7);

insert into auth.users (id, email, aud, role, created_at, updated_at)
values
  ('82000000-0000-4000-8000-000000000001','mcp-snapshot-a@example.com','authenticated','authenticated',now(),now()),
  ('82000000-0000-4000-8000-000000000002','mcp-snapshot-b@example.com','authenticated','authenticated',now(),now());

insert into public.sync_entities (
  user_id, app_id, entity_type, entity_id, server_revision,
  client_updated_at, deleted_at, data, field_clock
)
values
  (
    '82000000-0000-4000-8000-000000000001','pomodoist','task','root',
    nextval('public.sync_revision_seq'),now(),null,
    '{"id":"root","userId":"local-user","content":"Root","projectId":"project-a","parentId":null,"status":"open","orderKey":"1"}',
    '{}'::jsonb
  ),
  (
    '82000000-0000-4000-8000-000000000001','pomodoist','task','child',
    nextval('public.sync_revision_seq'),now(),null,
    '{"id":"child","userId":"local-user","content":"Child","projectId":"project-a","parentId":"root","status":"completed","orderKey":"2"}',
    '{}'::jsonb
  ),
  (
    '82000000-0000-4000-8000-000000000001','pomodoist','task_label','root:label-a',
    nextval('public.sync_revision_seq'),now(),null,
    '{"taskId":"root","labelId":"label-a","kind":"user"}',
    '{}'::jsonb
  ),
  (
    '82000000-0000-4000-8000-000000000001','pomodoist','task_kanban_status','root',
    nextval('public.sync_revision_seq'),now(),null,
    '{"taskId":"root","labelId":"kanban-status-backlog-v1"}',
    '{}'::jsonb
  ),
  (
    '82000000-0000-4000-8000-000000000001','pomodoist','task_completion','completion-a',
    nextval('public.sync_revision_seq'),now(),null,
    '{"id":"completion-a","taskId":"root","snapshotJson":"{\"version\":1,\"kanban\":{\"previousStatusLabelId\":\"kanban-status-backlog-v1\"}}","completedAt":"2026-07-30T10:00:00Z"}',
    '{}'::jsonb
  ),
  (
    '82000000-0000-4000-8000-000000000002','pomodoist','task','foreign',
    nextval('public.sync_revision_seq'),now(),null,
    '{"id":"foreign","content":"Foreign"}',
    '{}'::jsonb
  ),
  (
    '82000000-0000-4000-8000-000000000001','pomodoist','task','deleted',
    nextval('public.sync_revision_seq'),now(),now(),
    '{"id":"deleted","content":"Deleted"}',
    '{}'::jsonb
  ),
  (
    '82000000-0000-4000-8000-000000000001','pomodoist','task','malformed',
    nextval('public.sync_revision_seq'),now(),null,
    '"legacy-scalar"',
    '{}'::jsonb
  );

set local role service_role;
create temporary table snapshot_result on commit drop as
select public.read_pomodoist_mcp(
  '82000000-0000-4000-8000-000000000001',
  'mutation_snapshot',
  '{}'::jsonb
) as value;
reset role;

select is(
  (select jsonb_array_length(value -> 'tasks') from snapshot_result),
  2,
  'snapshot returns all active owned tasks including completed descendants'
);
select is(
  (select value #>> '{taskLabels,0,labelId}' from snapshot_result),
  'label-a',
  'snapshot exposes user-label relationship IDs for cascades'
);
select is(
  (select value #>> '{assignments,0,labelId}' from snapshot_result),
  'kanban-status-backlog-v1',
  'snapshot exposes Kanban assignments'
);
select is(
  (select value #>> '{completions,0,id}' from snapshot_result),
  'completion-a',
  'snapshot exposes completion history needed for restore status'
);
select ok(
  not ((select value from snapshot_result)::text like '%foreign%')
  and not ((select value from snapshot_result)::text like '%deleted%'),
  'snapshot never crosses ownership and omits tombstones'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.read_pomodoist_mcp(uuid,text,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'pomodoist_mcp',
    'public.read_pomodoist_mcp(uuid,text,jsonb)',
    'EXECUTE'
  )
  and has_function_privilege(
    'service_role',
    'public.read_pomodoist_mcp(uuid,text,jsonb)',
    'EXECUTE'
  ),
  'the unchanged read dispatcher remains service-role-only'
);
select is(
  to_regprocedure('public.read_pomodoist_mcp_mutation_snapshot(uuid)'),
  null::regprocedure,
  'mutation snapshots add no second public RPC'
);

\else

select plan(1);
select fail('the MCP read dispatcher has a private V1 delegate');

\endif

select * from finish();
rollback;

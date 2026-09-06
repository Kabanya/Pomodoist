begin;
\ir hosted-mode.inc

select plan(30);

insert into auth.users (id, email, aud, role, created_at, updated_at)
values
  (
    '11111111-1111-4111-8111-111111111111',
    'mcp-sync-a@example.com',
    'authenticated',
    'authenticated',
    now(),
    now()
  ),
  (
    '66666666-6666-4666-8666-666666666666',
    'mcp-sync-b@example.com',
    'authenticated',
    'authenticated',
    now(),
    now()
  ),
  (
    '77777777-7777-4777-8777-777777777777',
    'mcp-sync-c@example.com',
    'authenticated',
    'authenticated',
    now(),
    now()
  );

create function pg_temp.sync_op(
  p_op_id text,
  p_entity_type text,
  p_entity_id text,
  p_operation text default 'upsert',
  p_payload jsonb default '{"schemaVersion":1}'::jsonb,
  p_updated_at text default '2026-07-30T10:00:00.000Z'
)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'opId', p_op_id,
    'entityType', p_entity_type,
    'entityId', p_entity_id,
    'operation', p_operation,
    'payload', p_payload,
    'clientUpdatedAt', p_updated_at
  );
$$;

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '66666666-6666-4666-8666-666666666666',
  true
);

create temporary table flutter_push_result on commit drop as
select public.push_changes(
  'pomodoist',
  'flutter-device',
  jsonb_build_array(
    pg_temp.sync_op(
      'flutter-op-1',
      'task',
      'flutter-task-1',
      'upsert',
      '{"schemaVersion":1,"content":"wire-compatible"}'::jsonb
    )
  )
) as value;

reset role;

select ok(
  (select (value ->> 'serverRevision')::bigint > 0
   and jsonb_array_length(value -> 'applied') = 1
   and value #>> '{applied,0,entityType}' = 'task'
   and value #>> '{applied,0,entityId}' = 'flutter-task-1'
   from flutter_push_result),
  'authenticated push_changes keeps its camel-case wire result'
);

select ok(
  exists(
    select 1
    from public.sync_entities
    where user_id = '66666666-6666-4666-8666-666666666666'
      and app_id = 'pomodoist'
      and entity_type = 'task'
      and entity_id = 'flutter-task-1'
      and data ->> 'content' = 'wire-compatible'
  )
  and exists(
    select 1
    from public.sync_operation_receipts
    where user_id = '66666666-6666-4666-8666-666666666666'
      and op_id = 'flutter-op-1'
  ),
  'authenticated push_changes still owns entities and receipts by auth.uid()'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.push_changes(text,text,jsonb)',
    'EXECUTE'
  )
  and has_function_privilege(
    'anon',
    'public.push_changes(text,text,jsonb)',
    'EXECUTE'
  ),
  'existing push_changes grants remain wire-compatible'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.push_pomodoist_mcp_changes(uuid,uuid,jsonb)',
    'EXECUTE'
  )
  and has_function_privilege(
    'service_role',
    'public.send_pomodoist_mcp_sync_hint(uuid,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.push_pomodoist_mcp_changes(uuid,uuid,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.push_pomodoist_mcp_changes(uuid,uuid,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'pomodoist_mcp',
    'public.push_pomodoist_mcp_changes(uuid,uuid,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.send_pomodoist_mcp_sync_hint(uuid,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.send_pomodoist_mcp_sync_hint(uuid,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'pomodoist_mcp',
    'public.send_pomodoist_mcp_sync_hint(uuid,uuid)',
    'EXECUTE'
  ),
  'MCP write and hint RPCs are service-role-only'
);

select ok(
  not has_function_privilege(
    'service_role',
    'private.push_changes_for_user(uuid,text,text,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'private.push_changes_for_user(uuid,text,text,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'pomodoist_mcp',
    'private.push_changes_for_user(uuid,text,text,jsonb)',
    'EXECUTE'
  ),
  'shared sync core remains private'
);

select public.push_pomodoist_mcp_changes(
  '11111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222222',
  jsonb_build_array(
    pg_temp.sync_op(
      'mcp-explicit-owner',
      'task',
      'mcp-owned-task',
      'upsert',
      '{"schemaVersion":1,"content":"owned by explicit user","userId":"local-user"}'::jsonb
    )
  )
);

select ok(
  exists(
    select 1
    from public.sync_entities
    where user_id = '11111111-1111-4111-8111-111111111111'
      and app_id = 'pomodoist'
      and entity_type = 'task'
      and entity_id = 'mcp-owned-task'
  )
  and not exists(
    select 1
    from public.sync_entities
    where user_id = '66666666-6666-4666-8666-666666666666'
      and app_id = 'pomodoist'
      and entity_id = 'mcp-owned-task'
  ),
  'MCP writes use the explicit real user and ignore ambient JWT ownership'
);

select throws_ok(
  $query$
    select public.push_pomodoist_mcp_changes(
      '11111111-1111-4111-8111-111111111111',
      '22222222-2222-4222-8222-222222222222',
      '{"operations":[]}'::jsonb
    )
  $query$,
  '22023',
  'Invalid Pomodoist MCP sync batch',
  'MCP rejects a non-array batch envelope'
);

select throws_ok(
  $query$
    select public.push_pomodoist_mcp_changes(
      '11111111-1111-4111-8111-111111111111',
      '22222222-2222-4222-8222-222222222222',
      '[{"opId":"bad-payload","entityType":"task","entityId":"bad-payload","operation":"upsert","payload":[],"clientUpdatedAt":"2026-07-30T10:00:00.000Z"}]'::jsonb
    )
  $query$,
  '22023',
  'Invalid Pomodoist MCP sync operation',
  'MCP rejects a non-object payload'
);

select throws_ok(
  $query$
    select public.push_pomodoist_mcp_changes(
      '11111111-1111-4111-8111-111111111111',
      '22222222-2222-4222-8222-222222222222',
      '[{"opId":7,"entityType":"task","entityId":8,"operation":"upsert","payload":{},"clientUpdatedAt":"2026-07-30T10:00:00.000Z"}]'::jsonb
    )
  $query$,
  '22023',
  'Invalid Pomodoist MCP sync operation',
  'MCP rejects non-string operation and entity identifiers'
);

select throws_ok(
  $query$
    select public.push_pomodoist_mcp_changes(
      '11111111-1111-4111-8111-111111111111',
      '22222222-2222-4222-8222-222222222222',
      '[{"opId":"foreign-kind","entityType":"focus_preset","entityId":"foreign-kind","operation":"upsert","payload":{},"clientUpdatedAt":"2026-07-30T10:00:00.000Z"}]'::jsonb
    )
  $query$,
  '22023',
  'Invalid Pomodoist MCP sync operation',
  'MCP rejects excluded focus, Calendar, and other foreign entity kinds'
);

select throws_ok(
  $query$
    select public.push_pomodoist_mcp_changes(
      '11111111-1111-4111-8111-111111111111',
      '22222222-2222-4222-8222-222222222222',
      '[{"opId":"foreign-owner","entityType":"task","entityId":"foreign-owner","operation":"upsert","payload":{"userId":"someone-else"},"clientUpdatedAt":"2026-07-30T10:00:00.000Z"}]'::jsonb
    )
  $query$,
  '22023',
  'Invalid Pomodoist MCP sync operation',
  'MCP rejects a foreign app-local owner in an entity payload'
);

select throws_ok(
  $query$
    select public.push_pomodoist_mcp_changes(
      '11111111-1111-4111-8111-111111111111',
      '22222222-2222-4222-8222-222222222222',
      '[{"opId":"foreign-anchor-kind","entityType":"task","entityId":"inbox","operation":"upsert","payload":{},"clientUpdatedAt":"2026-07-30T10:00:00.000Z"}]'::jsonb
    )
  $query$,
  '22023',
  'Invalid Pomodoist MCP sync operation',
  'MCP rejects a protected entity ID under a foreign entity kind'
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '66666666-6666-4666-8666-666666666666',
  true
);

select throws_ok(
  $query$
    select public.push_changes(
      'pomodoist',
      'atomic-device',
      '[
        {"opId":"atomic-first","entityType":"task","entityId":"atomic-first","operation":"upsert","payload":{"schemaVersion":1},"clientUpdatedAt":"2026-07-30T10:00:00.000Z"},
        {"opId":"atomic-protected","entityType":"project","entityId":"inbox","operation":"delete","payload":{"schemaVersion":1},"clientUpdatedAt":"2026-07-30T10:00:01.000Z"}
      ]'::jsonb
    )
  $query$,
  '22023',
  'Protected Pomodoist system anchor cannot be deleted: project/inbox',
  'shared core aborts an entire batch when a later operation is rejected'
);

reset role;

select ok(
  not exists(
    select 1
    from public.sync_entities
    where user_id = '66666666-6666-4666-8666-666666666666'
      and entity_id = 'atomic-first'
  )
  and not exists(
    select 1
    from public.sync_operation_receipts
    where user_id = '66666666-6666-4666-8666-666666666666'
      and op_id = 'atomic-first'
  ),
  'failed shared-core batches roll back prior entities and receipts atomically'
);

select public.push_pomodoist_mcp_changes(
  '77777777-7777-4777-8777-777777777777',
  '22222222-2222-4222-8222-222222222222',
  jsonb_build_array(
    pg_temp.sync_op('kind-project', 'project', 'kind-project'),
    pg_temp.sync_op('kind-task', 'task', 'kind-task'),
    pg_temp.sync_op('kind-task-completion', 'task_completion', 'kind-task-completion'),
    pg_temp.sync_op('kind-label', 'label', 'kind-label'),
    pg_temp.sync_op('kind-task-label', 'task_label', 'kind-task-label'),
    pg_temp.sync_op('kind-task-kanban', 'task_kanban_status', 'kind-task-kanban'),
    pg_temp.sync_op('kind-settings', 'kanban_settings', 'kanban-settings-primary-v1')
  )
);

select is(
  (
    select count(*)::integer
    from public.sync_operation_receipts
    where user_id = '77777777-7777-4777-8777-777777777777'
      and op_id like 'kind-%'
  ),
  7,
  'MCP accepts exactly the seven Pomodoist V1 mutation sync entity kinds'
);

select is(
  (
    select count(*)::integer
    from public.sync_entities
    where user_id = '11111111-1111-4111-8111-111111111111'
      and app_id = 'pomodoist'
      and (
        (entity_type = 'project' and entity_id = 'inbox')
        or (entity_type = 'label' and entity_id in (
          'kanban-status-backlog-v1',
          'kanban-status-done-v1'
        ))
        or (
          entity_type = 'kanban_settings'
          and entity_id = 'kanban-settings-primary-v1'
        )
      )
  ),
  4,
  'first MCP write ensures Inbox, Backlog, Done, and Kanban settings'
);

select ok(
  (
    select data @> '{
      "schemaVersion":1,
      "id":"inbox",
      "userId":"local-user",
      "name":"Inbox",
      "viewStyle":"list",
      "isFavorite":true,
      "isArchived":false,
      "isDeleted":false,
      "orderKey":"a"
    }'::jsonb
    from public.sync_entities
    where user_id = '11111111-1111-4111-8111-111111111111'
      and app_id = 'pomodoist'
      and entity_type = 'project'
      and entity_id = 'inbox'
  )
  and (
    select data @> '{
      "schemaVersion":1,
      "id":"kanban-settings-primary-v1",
      "userId":"local-user",
      "selectedProjectIdsJson":"[\"inbox\"]",
      "focusStatusLabelId":"kanban-status-backlog-v1"
    }'::jsonb
    from public.sync_entities
    where user_id = '11111111-1111-4111-8111-111111111111'
      and app_id = 'pomodoist'
      and entity_type = 'kanban_settings'
      and entity_id = 'kanban-settings-primary-v1'
  )
  and exists (
    select 1
    from public.sync_entities settings
    join public.sync_entities status
      on status.user_id = settings.user_id
      and status.app_id = settings.app_id
      and status.entity_type = 'label'
      and status.entity_id = settings.data ->> 'focusStatusLabelId'
      and status.deleted_at is null
      and status.data ->> 'kind' = 'kanbanStatus'
      and coalesce(status.data ->> 'isDeleted', 'false') <> 'true'
    where settings.user_id = '11111111-1111-4111-8111-111111111111'
      and settings.app_id = 'pomodoist'
      and settings.entity_type = 'kanban_settings'
      and settings.entity_id = 'kanban-settings-primary-v1'
  ),
  'MCP anchors use Flutter-compatible payloads with an active focus status'
);

create temporary table anchor_revisions on commit drop as
select entity_type, entity_id, server_revision
from public.sync_entities
where user_id = '11111111-1111-4111-8111-111111111111'
  and app_id = 'pomodoist'
  and entity_id in (
    'inbox',
    'kanban-status-backlog-v1',
    'kanban-status-done-v1',
    'kanban-settings-primary-v1'
  );

select public.push_pomodoist_mcp_changes(
  '11111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222222',
  jsonb_build_array(
    pg_temp.sync_op(
      'mcp-second-call',
      'task',
      'mcp-second-task',
      'upsert',
      '{"schemaVersion":1,"content":"second"}'::jsonb
    )
  )
);

select is(
  (
    select count(*)::integer
    from public.sync_entities current
    join anchor_revisions original using (entity_type, entity_id, server_revision)
    where current.user_id = '11111111-1111-4111-8111-111111111111'
      and current.app_id = 'pomodoist'
  ),
  4,
  'system anchors are idempotent across MCP calls'
);

select is(
  (
    select count(*)::integer
    from public.sync_operation_receipts
    where user_id = '11111111-1111-4111-8111-111111111111'
      and op_id like 'pomodoist-mcp-system:%'
  ),
  4,
  'idempotent anchors keep one compact receipt each'
);

delete from public.sync_entities
where user_id = '11111111-1111-4111-8111-111111111111'
  and app_id = 'pomodoist'
  and entity_type = 'kanban_settings'
  and entity_id = 'kanban-settings-primary-v1';

update public.sync_entities
set deleted_at = '2026-07-30T10:00:00.000Z'
where user_id = '11111111-1111-4111-8111-111111111111'
  and app_id = 'pomodoist'
  and entity_type = 'label'
  and entity_id = 'kanban-status-backlog-v1';

select public.push_pomodoist_mcp_changes(
  '11111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222222',
  jsonb_build_array(
    pg_temp.sync_op(
      'mcp-anchor-recovery',
      'task',
      'mcp-anchor-recovery',
      'upsert',
      '{"schemaVersion":1,"content":"recover anchors"}'::jsonb
    )
  )
);

select ok(
  exists(
    select 1
    from public.sync_entities
    where user_id = '11111111-1111-4111-8111-111111111111'
      and app_id = 'pomodoist'
      and entity_type = 'kanban_settings'
      and entity_id = 'kanban-settings-primary-v1'
      and deleted_at is null
  )
  and (
    select count(*) = 2
    from public.sync_operation_receipts
    where user_id = '11111111-1111-4111-8111-111111111111'
      and op_id like 'pomodoist-mcp-system:kanban-settings:v1:%'
  ),
  'MCP restores a missing anchor even while its prior receipt remains'
);

select ok(
  (
    select deleted_at is null
    from public.sync_entities
    where user_id = '11111111-1111-4111-8111-111111111111'
      and app_id = 'pomodoist'
      and entity_type = 'label'
      and entity_id = 'kanban-status-backlog-v1'
  ),
  'MCP repairs a historical protected-anchor tombstone'
);

select public.push_pomodoist_mcp_changes(
  '11111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222222',
  jsonb_build_array(
    pg_temp.sync_op(
      'delete-win-create',
      'label',
      'delete-win-label',
      'upsert',
      '{"schemaVersion":1,"name":"Original"}'::jsonb,
      '2026-07-30T10:01:00.000Z'
    ),
    pg_temp.sync_op(
      'delete-win-delete',
      'label',
      'delete-win-label',
      'delete',
      '{"schemaVersion":1}'::jsonb,
      '2026-07-30T10:02:00.000Z'
    ),
    pg_temp.sync_op(
      'delete-win-resurrect',
      'label',
      'delete-win-label',
      'upsert',
      '{"schemaVersion":1,"name":"Resurrected"}'::jsonb,
      '2026-07-30T10:03:00.000Z'
    )
  )
);

select ok(
  (
    select deleted_at = '2026-07-30T10:02:00.000Z'::timestamptz
    from public.sync_entities
    where user_id = '11111111-1111-4111-8111-111111111111'
      and app_id = 'pomodoist'
      and entity_type = 'label'
      and entity_id = 'delete-win-label'
  ),
  'MCP batches preserve tombstones'
);

select is(
  (
    select data ->> 'name'
    from public.sync_entities
    where user_id = '11111111-1111-4111-8111-111111111111'
      and app_id = 'pomodoist'
      and entity_type = 'label'
      and entity_id = 'delete-win-label'
  ),
  'Original',
  'shared core preserves deletion-wins against newer upserts'
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '66666666-6666-4666-8666-666666666666',
  true
);

select throws_ok(
  $query$
    select public.push_changes(
      'pomodoist',
      'protected-device',
      jsonb_build_array(pg_temp.sync_op('delete-inbox', 'project', 'inbox', 'delete'))
    )
  $query$,
  '22023',
  'Protected Pomodoist system anchor cannot be deleted: project/inbox',
  'shared core rejects Inbox tombstones'
);

select throws_ok(
  $query$
    select public.push_changes(
      'pomodoist',
      'protected-device',
      jsonb_build_array(pg_temp.sync_op(
        'delete-backlog',
        'label',
        'kanban-status-backlog-v1',
        'delete'
      ))
    )
  $query$,
  '22023',
  'Protected Pomodoist system anchor cannot be deleted: label/kanban-status-backlog-v1',
  'shared core rejects Backlog tombstones'
);

select throws_ok(
  $query$
    select public.push_changes(
      'pomodoist',
      'protected-device',
      jsonb_build_array(pg_temp.sync_op(
        'delete-done',
        'label',
        'kanban-status-done-v1',
        'delete'
      ))
    )
  $query$,
  '22023',
  'Protected Pomodoist system anchor cannot be deleted: label/kanban-status-done-v1',
  'shared core rejects Done tombstones'
);

select throws_ok(
  $query$
    select public.push_changes(
      'pomodoist',
      'protected-device',
      jsonb_build_array(pg_temp.sync_op(
        'delete-settings',
        'kanban_settings',
        'kanban-settings-primary-v1',
        'delete'
      ))
    )
  $query$,
  '22023',
  'Protected Pomodoist system anchor cannot be deleted: kanban_settings/kanban-settings-primary-v1',
  'shared core rejects Kanban settings tombstones'
);

reset role;

select public.send_pomodoist_mcp_sync_hint(
  '11111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222222'
);

select ok(
  (
    select topic = 'sync:11111111-1111-4111-8111-111111111111:pomodoist'
      and event = 'changed'
      and private
      and extension = 'broadcast'
    from realtime.messages
    where topic = 'sync:11111111-1111-4111-8111-111111111111:pomodoist'
    order by inserted_at desc
    limit 1
  ),
  'sync hint uses the exact private Flutter topic and event'
);

select is(
  (
    select payload - 'id' - 'sentAt'
    from realtime.messages
    where topic = 'sync:11111111-1111-4111-8111-111111111111:pomodoist'
    order by inserted_at desc
    limit 1
  ),
  '{
    "appId":"pomodoist",
    "deviceId":"mcp:22222222-2222-4222-8222-222222222222"
  }'::jsonb,
  'sync hint payload identifies Pomodoist and the MCP OAuth client device'
);

select ok(
  (
    select (
        select count(*) = 3
        from jsonb_object_keys(message.payload - 'id')
      )
      and (message.payload ->> 'sentAt')
        ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$'
    from realtime.messages as message
    where message.topic = 'sync:11111111-1111-4111-8111-111111111111:pomodoist'
    order by message.inserted_at desc
    limit 1
  ),
  'sync hint payload has exactly the three Flutter keys and a UTC ISO-8601 sentAt'
);

select * from finish();
rollback;

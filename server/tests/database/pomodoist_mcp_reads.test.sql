begin;
\ir hosted-mode.inc

select to_regprocedure(
  'public.read_pomodoist_mcp(uuid,text,jsonb)'
) is not null as function_exists \gset

\if :function_exists

select plan(37);

insert into auth.users (id, email, aud, role, created_at, updated_at)
values
  ('80000000-0000-4000-8000-000000000001','mcp-read-a@example.com','authenticated','authenticated',now(),now()),
  ('80000000-0000-4000-8000-000000000002','mcp-read-b@example.com','authenticated','authenticated',now(),now()),
  ('81000000-0000-4000-8000-000000000001','parity-utc@example.com','authenticated','authenticated',now(),now()),
  ('81000000-0000-4000-8000-000000000002','parity-moscow@example.com','authenticated','authenticated',now(),now()),
  ('81000000-0000-4000-8000-000000000003','parity-new-york@example.com','authenticated','authenticated',now(),now());

create function pg_temp.put_entity(
  p_user_id uuid,
  p_type text,
  p_id text,
  p_data jsonb,
  p_deleted boolean default false
)
returns void
language sql
as $$
  insert into public.sync_entities (
    user_id, app_id, entity_type, entity_id, server_revision,
    client_updated_at, deleted_at, data, field_clock
  )
  values (
    p_user_id, 'pomodoist', p_type, p_id,
    nextval('public.sync_revision_seq'), '2026-07-30T12:00:00Z',
    case when p_deleted then '2026-07-30T12:00:00Z'::timestamptz end,
    p_data, '{}'::jsonb
  );
$$;

create function pg_temp.task_data(
  p_id text,
  p_content text,
  p_project_id text default 'inbox',
  p_status text default 'open',
  p_due_json text default null,
  p_description text default null,
  p_order_key text default 'a',
  p_day_order integer default null
)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'id', p_id,
    'userId', 'local-user',
    'content', p_content,
    'description', p_description,
    'projectId', p_project_id,
    'parentId', null,
    'priority', 4,
    'dueJson', p_due_json,
    'status', p_status,
    'estimatedFocusIntervals', 1,
    'completedFocusIntervals', 0,
    'totalFocusSeconds', 0,
    'orderKey', p_order_key,
    'dayOrder', p_day_order,
    'isDeleted', false,
    'createdAt', '2026-07-30T10:00:00Z',
    'updatedAt', '2026-07-30T10:00:00Z',
    'completedAt', case when p_status = 'completed' then '2026-07-30T10:00:00Z' end
  );
$$;

select pg_temp.put_entity(
  '80000000-0000-4000-8000-000000000001','project','inbox',
  '{"id":"inbox","userId":"local-user","name":"Inbox","color":null,"parentId":null,"viewStyle":"list","isFavorite":true,"isArchived":false,"isDeleted":false,"orderKey":"0","createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"}'
);
select pg_temp.put_entity(
  '80000000-0000-4000-8000-000000000001','project','project-a',
  '{"id":"project-a","userId":"local-user","name":"Alpha","color":"blue","parentId":null,"viewStyle":"list","isFavorite":false,"isArchived":false,"isDeleted":false,"orderKey":"1","createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"}'
);
select pg_temp.put_entity(
  '80000000-0000-4000-8000-000000000001','project','project-deleted',
  '{"id":"project-deleted","userId":"local-user","name":"Deleted","isDeleted":true,"orderKey":"2"}',
  true
);

select pg_temp.put_entity(
  '80000000-0000-4000-8000-000000000001','task','task-inbox',
  pg_temp.task_data('task-inbox','Inbox task')
);
select pg_temp.put_entity(
  '80000000-0000-4000-8000-000000000001','task','task-overdue',
  pg_temp.task_data(
    'task-overdue',
    'Overdue task',
    'inbox',
    'open',
    jsonb_build_object(
      'type',
      'allDay',
      'date',
      to_char(
        (now() at time zone 'Europe/Moscow')::date - 1,
        'YYYY-MM-DD'
      )
    )::text
  )
);
select pg_temp.put_entity(
  '80000000-0000-4000-8000-000000000001','task','task-today',
  pg_temp.task_data(
    'task-today',
    'Today task',
    'inbox',
    'open',
    jsonb_build_object(
      'type',
      'timed',
      'start',
      (
        (
          (now() at time zone 'Europe/Moscow')::date
          + time '12:00'
        ) at time zone 'Europe/Moscow'
      ),
      'end',
      (
        (
          (now() at time zone 'Europe/Moscow')::date
          + time '13:00'
        ) at time zone 'Europe/Moscow'
      ),
      'timeZone',
      'Europe/Moscow'
    )::text
  )
);
select pg_temp.put_entity(
  '80000000-0000-4000-8000-000000000001','task','task-future',
  pg_temp.task_data(
    'task-future',
    'Future task',
    'inbox',
    'open',
    jsonb_build_object(
      'type',
      'allDay',
      'date',
      to_char(
        (now() at time zone 'Europe/Moscow')::date + 1,
        'YYYY-MM-DD'
      )
    )::text
  )
);
select pg_temp.put_entity(
  '80000000-0000-4000-8000-000000000001','task','task-project',
  pg_temp.task_data('task-project','Project task','project-a')
);
select pg_temp.put_entity(
  '80000000-0000-4000-8000-000000000001','task','task-search-content',
  pg_temp.task_data('task-search-content','Find the needle','project-a')
);
select pg_temp.put_entity(
  '80000000-0000-4000-8000-000000000001','task','task-search-description',
  pg_temp.task_data('task-search-description','Ordinary','project-a','open',null,'Needle in details')
);
select pg_temp.put_entity(
  '80000000-0000-4000-8000-000000000001','task','task-completed',
  pg_temp.task_data(
    'task-completed','Completed task','project-a','completed',
    null,null,'000'
  )
);
select pg_temp.put_entity(
  '80000000-0000-4000-8000-000000000001','task','task-timed-no-end',
  pg_temp.task_data(
    'task-timed-no-end',
    'Malformed timed task without end',
    'inbox',
    'open',
    jsonb_build_object(
      'type','timed',
      'start',(
        (
          (now() at time zone 'Europe/Moscow')::date + time '14:00'
        ) at time zone 'Europe/Moscow'
      ),
      'timeZone','Europe/Moscow'
    )::text
  )
);
select pg_temp.put_entity(
  '80000000-0000-4000-8000-000000000001','task','task-timed-reversed',
  pg_temp.task_data(
    'task-timed-reversed',
    'Malformed reversed timed task',
    'inbox',
    'open',
    jsonb_build_object(
      'type','timed',
      'start',(
        (
          (now() at time zone 'Europe/Moscow')::date + time '16:00'
        ) at time zone 'Europe/Moscow'
      ),
      'end',(
        (
          (now() at time zone 'Europe/Moscow')::date + time '15:00'
        ) at time zone 'Europe/Moscow'
      ),
      'timeZone','Europe/Moscow'
    )::text
  )
);
select pg_temp.put_entity(
  '80000000-0000-4000-8000-000000000001','task','task-timed-infinity',
  pg_temp.task_data(
    'task-timed-infinity',
    'Malformed non-finite timed task',
    'inbox',
    'open',
    '{"type":"timed","start":"-infinity","end":"infinity","timeZone":"Europe/Moscow"}'
  )
);
select pg_temp.put_entity(
  '80000000-0000-4000-8000-000000000001','task','task-tombstone',
  pg_temp.task_data('task-tombstone','Deleted task'),
  true
);
select pg_temp.put_entity(
  '80000000-0000-4000-8000-000000000002','task','task-other-user',
  pg_temp.task_data('task-other-user','Other user task')
);

select pg_temp.put_entity(
  '80000000-0000-4000-8000-000000000001','label','kanban-status-backlog-v1',
  '{"id":"kanban-status-backlog-v1","userId":"local-user","name":"Backlog","color":null,"kind":"kanbanStatus","systemKey":"backlog","orderKey":"0000","isFavorite":false,"isDeleted":false,"createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"}'
);
select pg_temp.put_entity(
  '80000000-0000-4000-8000-000000000001','label','kanban-status-doing',
  '{"id":"kanban-status-doing","userId":"local-user","name":"Doing","color":"blue","kind":"kanbanStatus","systemKey":null,"orderKey":"1000","isFavorite":false,"isDeleted":false,"createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"}'
);
select pg_temp.put_entity(
  '80000000-0000-4000-8000-000000000001','label','kanban-status-done-v1',
  '{"id":"kanban-status-done-v1","userId":"local-user","name":"Done","color":null,"kind":"kanbanStatus","systemKey":"done","orderKey":"9999","isFavorite":false,"isDeleted":false,"createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"}'
);
select pg_temp.put_entity(
  '80000000-0000-4000-8000-000000000001','label','label-user',
  '{"id":"label-user","userId":"local-user","name":"User label","color":"red","kind":"user","systemKey":null,"orderKey":"2000","isFavorite":true,"isDeleted":false,"createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"}'
);
select pg_temp.put_entity(
  '80000000-0000-4000-8000-000000000001','label','label-deleted',
  '{"id":"label-deleted","userId":"local-user","name":"Deleted label","kind":"user","orderKey":"3000","isDeleted":true}',
  true
);
select pg_temp.put_entity(
  '80000000-0000-4000-8000-000000000001','kanban_settings','kanban-settings-primary-v1',
  '{"id":"kanban-settings-primary-v1","userId":"local-user","selectedProjectIdsJson":"[\"inbox\",\"project-a\"]","focusStatusLabelId":"kanban-status-doing","createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"}'
);
select pg_temp.put_entity(
  '80000000-0000-4000-8000-000000000001','task_kanban_status','task-project',
  '{"taskId":"task-project","labelId":"kanban-status-doing","changedAt":"2026-07-30T10:00:00Z"}'
);

select pg_temp.put_entity(
  '80000000-0000-4000-8000-000000000001','focus_interval','focus-completed',
  '{"id":"focus-completed","runId":"run-terminal","taskId":"task-project","projectId":"project-a","type":"work","status":"completed","plannedSeconds":1500,"startedAt":"2026-07-30T08:00:00Z","pausedAt":null,"pausedTotalSeconds":60,"completedAt":"2026-07-30T08:25:00Z","stoppedAt":null,"sequenceNumber":1,"createdAt":"2026-07-30T08:00:00Z","updatedAt":"2026-07-30T08:25:00Z","isDeleted":false}'
);
select pg_temp.put_entity(
  '80000000-0000-4000-8000-000000000001','focus_interval','focus-break',
  '{"id":"focus-break","runId":"run-terminal","taskId":null,"projectId":"project-a","type":"shortBreak","status":"completed","startedAt":"2026-07-30T08:25:00Z","completedAt":"2026-07-30T08:30:00Z","pausedTotalSeconds":0,"sequenceNumber":2,"isDeleted":false}'
);
select pg_temp.put_entity(
  '80000000-0000-4000-8000-000000000001','focus_interval','focus-running',
  '{"id":"focus-running","runId":"run-active","taskId":null,"projectId":null,"type":"work","status":"running","startedAt":"2026-07-30T09:00:00Z","completedAt":null,"pausedTotalSeconds":0,"sequenceNumber":1,"isDeleted":false}'
);
select pg_temp.put_entity(
  '80000000-0000-4000-8000-000000000001','focus_interval','focus-stopped',
  '{"id":"focus-stopped","runId":"run-terminal","taskId":null,"projectId":null,"type":"work","status":"stopped","startedAt":"2026-07-30T09:00:00Z","completedAt":null,"stoppedAt":"2026-07-30T09:05:00Z","pausedTotalSeconds":0,"sequenceNumber":1,"isDeleted":false}'
);
select pg_temp.put_entity(
  '80000000-0000-4000-8000-000000000001','focus_interval','focus-legacy-completed',
  '{"id":"focus-legacy-completed","runId":"run-terminal","taskId":null,"projectId":null,"type":"work","status":"completed","startedAt":"2026-07-30T07:00:00Z","completedAt":null,"stoppedAt":"2026-07-30T07:10:00Z","pausedTotalSeconds":60,"sequenceNumber":1,"isDeleted":false}'
);
select pg_temp.put_entity(
  '80000000-0000-4000-8000-000000000001','focus_interval','focus-century',
  '{"id":"focus-century","runId":"run-terminal","taskId":null,"projectId":null,"type":"work","status":"completed","startedAt":"2000-01-01T00:00:00Z","completedAt":"2100-01-01T00:00:00Z","stoppedAt":null,"pausedTotalSeconds":0,"sequenceNumber":1,"isDeleted":false}'
);
select pg_temp.put_entity(
  '80000000-0000-4000-8000-000000000001','focus_interval','focus-infinity',
  '{"id":"focus-infinity","runId":"run-terminal","taskId":null,"projectId":null,"type":"work","status":"completed","startedAt":"-infinity","completedAt":"infinity","stoppedAt":null,"pausedTotalSeconds":0,"sequenceNumber":1,"isDeleted":false}'
);
select pg_temp.put_entity(
  '80000000-0000-4000-8000-000000000001','focus_interval','focus-deleted',
  '{"id":"focus-deleted","runId":"run-terminal","taskId":null,"projectId":null,"type":"work","status":"completed","startedAt":"2026-07-30T09:00:00Z","completedAt":"2026-07-30T09:20:00Z","pausedTotalSeconds":0,"sequenceNumber":1,"isDeleted":true}',
  true
);

insert into public.sync_entities (
  user_id, app_id, entity_type, entity_id, server_revision,
  client_updated_at, deleted_at, data, field_clock
)
select
  '80000000-0000-4000-8000-000000000001',
  'pomodoist',
  'task',
  'page-' || lpad(n::text,3,'0'),
  nextval('public.sync_revision_seq'),
  '2026-07-30T12:00:00Z',
  null,
  pg_temp.task_data(
    'page-' || lpad(n::text,3,'0'),
    'Page task ' || n,
    'page-project',
    'open',
    null,
    null,
    lpad(n::text,3,'0')
  ),
  '{}'::jsonb
from generate_series(1,105) n;

\ir pomodoist_productivity_parity.inc

insert into public.sync_entities (
  user_id, app_id, entity_type, entity_id, server_revision,
  client_updated_at, deleted_at, data, field_clock
)
select
  (case_row.value ->> 'userId')::uuid,
  'pomodoist',
  'task',
  task.value ->> 'id',
  nextval('public.sync_revision_seq'),
  '2026-01-01T00:00:00Z',
  null,
  jsonb_build_object(
    'id', task.value ->> 'id',
    'userId', 'local-user',
    'content', task.value ->> 'content',
    'projectId', task.value ->> 'projectId',
    'status', task.value ->> 'status',
    'estimatedFocusIntervals', task.value -> 'estimatedFocusIntervals',
    'dueJson', task.value -> 'dueJson',
    'isDeleted', false,
    'orderKey', task.value ->> 'id',
    'createdAt', '2026-01-01T00:00:00Z',
    'updatedAt', '2026-01-01T00:00:00Z'
  ),
  '{}'::jsonb
from productivity_cases case_row
cross join lateral jsonb_array_elements(case_row.value -> 'tasks') task(value);

insert into public.sync_entities (
  user_id, app_id, entity_type, entity_id, server_revision,
  client_updated_at, deleted_at, data, field_clock
)
select
  (case_row.value ->> 'userId')::uuid,
  'pomodoist',
  'task_completion',
  completion.value ->> 'id',
  nextval('public.sync_revision_seq'),
  (completion.value ->> 'completedAt')::timestamptz,
  null,
  completion.value || jsonb_build_object(
    'userId', 'local-user',
    'createdAt', completion.value ->> 'completedAt'
  ),
  '{}'::jsonb
from productivity_cases case_row
cross join lateral jsonb_array_elements(case_row.value -> 'taskCompletions') completion(value);

insert into public.sync_entities (
  user_id, app_id, entity_type, entity_id, server_revision,
  client_updated_at, deleted_at, data, field_clock
)
select
  (case_row.value ->> 'userId')::uuid,
  'pomodoist',
  'focus_interval',
  interval_row.value ->> 'id',
  nextval('public.sync_revision_seq'),
  (interval_row.value ->> 'startedAt')::timestamptz,
  null,
  interval_row.value || jsonb_build_object(
    'runId', 'fixture-run',
    'projectId', null,
    'sequenceNumber', 1,
    'createdAt', interval_row.value ->> 'startedAt',
    'updatedAt', coalesce(
      interval_row.value ->> 'completedAt',
      interval_row.value ->> 'stoppedAt',
      interval_row.value ->> 'startedAt'
    )
  ),
  '{}'::jsonb
from productivity_cases case_row
cross join lateral jsonb_array_elements(case_row.value -> 'focusIntervals') interval_row(value);

select ok(
  has_function_privilege(
    'service_role',
    'public.read_pomodoist_mcp(uuid,text,jsonb)',
    'EXECUTE'
  ),
  'service_role can execute the MCP read dispatcher'
);

select ok(
  not has_function_privilege('public','public.read_pomodoist_mcp(uuid,text,jsonb)','EXECUTE')
  and not has_function_privilege('anon','public.read_pomodoist_mcp(uuid,text,jsonb)','EXECUTE')
  and not has_function_privilege('authenticated','public.read_pomodoist_mcp(uuid,text,jsonb)','EXECUTE')
  and not has_function_privilege('pomodoist_mcp','public.read_pomodoist_mcp(uuid,text,jsonb)','EXECUTE'),
  'the MCP read dispatcher is service-role-only'
);

select ok(
  not has_table_privilege('pomodoist_mcp','public.sync_entities','SELECT')
  and (
    select coalesce(relacl::text, '') not like '%pomodoist_mcp%'
    from pg_class
    where oid = 'public.sync_entities'::regclass
  ),
  'the MCP bearer role receives no direct sync table grant'
);

select throws_ok(
  $$select public.read_pomodoist_mcp(null,'list_projects','{}')$$,
  '22023','Invalid Pomodoist MCP read request',
  'a real user UUID is required'
);

select throws_ok(
  $$select public.read_pomodoist_mcp('80000000-0000-4000-8000-000000000001','unknown','{}')$$,
  '22023','Invalid Pomodoist MCP read request',
  'unknown operations are rejected'
);

select throws_ok(
  $$select public.read_pomodoist_mcp('80000000-0000-4000-8000-000000000001','list_projects','{"query":"ignored"}')$$,
  '22023','Invalid Pomodoist MCP read request',
  'unrelated filters are rejected'
);

select throws_ok(
  $$select public.read_pomodoist_mcp('80000000-0000-4000-8000-000000000001','list_tasks','{"view":"today","time_zone":"Not/AZone"}')$$,
  '22023','Invalid Pomodoist MCP read request',
  'invalid IANA zones are rejected'
);

select throws_ok(
  $$select public.read_pomodoist_mcp('80000000-0000-4000-8000-000000000001','list_tasks','{"view":"date","time_zone":"UTC","date":"2026-02-30"}')$$,
  '22023','Invalid Pomodoist MCP read request',
  'invalid calendar dates are rejected'
);

select throws_ok(
  $$select public.read_pomodoist_mcp('80000000-0000-4000-8000-000000000001','list_tasks','{"view":"search","query":"  "}')$$,
  '22023','Invalid Pomodoist MCP read request',
  'blank task searches are rejected'
);

select is(
  (select jsonb_agg(item ->> 'id' order by item ->> 'id')
   from jsonb_array_elements(public.read_pomodoist_mcp(
     '80000000-0000-4000-8000-000000000001','list_tasks',
     '{"view":"inbox","limit":100}'
   ) -> 'items') item),
  '["task-inbox","task-timed-infinity","task-timed-no-end","task-timed-reversed"]'::jsonb,
  'inbox treats malformed timed schedules as unscheduled'
);

select is(
  (select jsonb_agg(item ->> 'id' order by item ->> 'id')
   from jsonb_array_elements(public.read_pomodoist_mcp(
     '80000000-0000-4000-8000-000000000001','list_tasks',
     '{"view":"today","time_zone":"Europe/Moscow","limit":100}'
   ) -> 'items') item),
  '["task-overdue","task-today"]'::jsonb,
  'today includes overdue and local-today tasks'
);

select is(
  (select jsonb_agg(item ->> 'id' order by item ->> 'id')
   from jsonb_array_elements(public.read_pomodoist_mcp(
     '80000000-0000-4000-8000-000000000001','list_tasks',
     '{"view":"upcoming","time_zone":"Europe/Moscow","limit":100}'
   ) -> 'items') item),
  '["task-future"]'::jsonb,
  'upcoming returns tasks after the local report day'
);

select is(
  (select jsonb_agg(item ->> 'id' order by item ->> 'id')
   from jsonb_array_elements(public.read_pomodoist_mcp(
     '80000000-0000-4000-8000-000000000001','list_tasks',
     jsonb_build_object(
       'view','date',
       'time_zone','Europe/Moscow',
       'date',to_char(
         (now() at time zone 'Europe/Moscow')::date + 1,
         'YYYY-MM-DD'
       ),
       'limit',100
     )
   ) -> 'items') item),
  '["task-future"]'::jsonb,
  'date returns tasks on the requested local calendar date'
);

select is(
  (select jsonb_agg(item ->> 'id' order by item ->> 'id')
   from jsonb_array_elements(public.read_pomodoist_mcp(
     '80000000-0000-4000-8000-000000000001','list_tasks',
     '{"view":"project","project_id":"project-a","limit":100}'
   ) -> 'items') item
   where item ->> 'id' not like 'page-%'),
  '["task-project","task-search-content","task-search-description"]'::jsonb,
  'project returns open tasks in the requested project'
);

select is(
  (select jsonb_agg(item ->> 'id' order by item ->> 'id')
   from jsonb_array_elements(public.read_pomodoist_mcp(
     '80000000-0000-4000-8000-000000000001','list_tasks',
     '{"view":"search","query":" NeEdLe ","limit":100}'
   ) -> 'items') item),
  '["task-search-content","task-search-description"]'::jsonb,
  'search follows case-insensitive content and description semantics'
);

select ok(
  (
    with first_page as (
      select public.read_pomodoist_mcp(
        '80000000-0000-4000-8000-000000000001','list_tasks',
        '{"view":"all","limit":100}'
      ) value
    ),
    both_pages as (
      select value -> 'items' items from first_page
      union all
      select public.read_pomodoist_mcp(
        '80000000-0000-4000-8000-000000000001','list_tasks',
        jsonb_build_object(
          'view','all',
          'limit',100,
          'cursor',(select value ->> 'nextCursor' from first_page)
        )
      ) -> 'items'
    )
    select count(*) = 115
      and count(*) filter (where item ->> 'id' = 'task-completed') = 0
    from both_pages
    cross join lateral jsonb_array_elements(items) item
  ),
  'all excludes an early-sorting completed task across every cursor page'
);

select is(
  public.read_pomodoist_mcp(
    '80000000-0000-4000-8000-000000000001','list_tasks',
    '{"view":"completed","limit":100}'
  ) #>> '{items,0,id}',
  'task-completed',
  'completed returns completed tasks only'
);

select is(
  public.read_pomodoist_mcp(
    '80000000-0000-4000-8000-000000000001','get_task',
    '{"task_id":"task-inbox"}'
  ) ->> 'status',
  'found',
  'get_task finds a current task owned by the explicit user'
);

select is(
  public.read_pomodoist_mcp(
    '80000000-0000-4000-8000-000000000001','get_task',
    '{"task_id":"task-tombstone"}'
  ) ->> 'status',
  'tombstoned',
  'get_task distinguishes tombstoned tasks'
);

select is(
  public.read_pomodoist_mcp(
    '80000000-0000-4000-8000-000000000001','get_task',
    '{"task_id":"task-other-user"}'
  ) ->> 'status',
  'missing',
  'get_task does not cross explicit-user ownership'
);

select throws_ok(
  $$select public.read_pomodoist_mcp(
    '80000000-0000-4000-8000-000000000001','list_tasks',
    '{"view":"all","cursor":"not base64"}'
  )$$,
  '22023','Invalid Pomodoist MCP read request',
  'malformed cursors are rejected'
);

create temporary table first_page as
select public.read_pomodoist_mcp(
  '80000000-0000-4000-8000-000000000001','list_tasks',
  '{"view":"all","limit":50}'
) value;

select is(
  (select jsonb_array_length(value -> 'items') from first_page),
  50,
  'list pagination defaults to 50'
);

select ok(
  (
    select convert_from(decode(value ->> 'nextCursor','base64'),'UTF8')
      not like '%80000000-0000-4000-8000-000000000001%'
    from first_page
  ),
  'opaque cursors do not disclose the real Auth user UUID'
);

select throws_ok(
  format(
    'select public.read_pomodoist_mcp(%L,%L,%L::jsonb)',
    '80000000-0000-4000-8000-000000000002','list_tasks',
    jsonb_build_object('view','all','cursor',(select value ->> 'nextCursor' from first_page))::text
  ),
  '22023','Invalid Pomodoist MCP read request',
  'cursors are bound to the real user'
);

select throws_ok(
  format(
    'select public.read_pomodoist_mcp(%L,%L,%L::jsonb)',
    '80000000-0000-4000-8000-000000000001','list_projects',
    jsonb_build_object('cursor',(select value ->> 'nextCursor' from first_page))::text
  ),
  '22023','Invalid Pomodoist MCP read request',
  'cursors are bound to the operation'
);

select throws_ok(
  format(
    'select public.read_pomodoist_mcp(%L,%L,%L::jsonb)',
    '80000000-0000-4000-8000-000000000001','list_tasks',
    jsonb_build_object('view','project','project_id','project-a','cursor',(select value ->> 'nextCursor' from first_page))::text
  ),
  '22023','Invalid Pomodoist MCP read request',
  'cursors are bound to normalized filters'
);

create temporary table max_page as
select public.read_pomodoist_mcp(
  '80000000-0000-4000-8000-000000000001','list_tasks',
  '{"view":"all","limit":100}'
) value;

select is(
  (select jsonb_array_length(value -> 'items') from max_page),
  100,
  'list pagination accepts the maximum limit of 100'
);

select ok(
  (select value ->> 'nextCursor' is not null from max_page)
  and not exists (
    select 1
    from jsonb_array_elements((select value -> 'items' from max_page)) first_item
    join jsonb_array_elements(public.read_pomodoist_mcp(
      '80000000-0000-4000-8000-000000000001','list_tasks',
      jsonb_build_object(
        'view','all',
        'limit',100,
        'cursor',(select value ->> 'nextCursor' from max_page)
      )
    ) -> 'items') second_item
      on first_item ->> 'id' = second_item ->> 'id'
  ),
  'deterministic cursor pages contain no duplicate tasks'
);

select is(
  (select jsonb_agg(item ->> 'id' order by item ->> 'id')
   from jsonb_array_elements(public.read_pomodoist_mcp(
     '80000000-0000-4000-8000-000000000001','list_projects','{}'
   ) -> 'items') item),
  '["inbox","project-a"]'::jsonb,
  'projects omit tombstones'
);

select is(
  (select jsonb_agg(item ->> 'id')
   from jsonb_array_elements(public.read_pomodoist_mcp(
     '80000000-0000-4000-8000-000000000001','list_labels','{}'
   ) -> 'items') item),
  '["label-user"]'::jsonb,
  'labels omit tombstones and Kanban statuses'
);

select ok(
  public.read_pomodoist_mcp(
    '80000000-0000-4000-8000-000000000001','get_kanban_board','{}'
  ) #> '{settings,selectedProjectIds}' = '["inbox","project-a"]'::jsonb
  and public.read_pomodoist_mcp(
    '80000000-0000-4000-8000-000000000001','get_kanban_board','{}'
  ) #> '{statuses}' @> '[{"id":"kanban-status-doing"}]'::jsonb
  and public.read_pomodoist_mcp(
    '80000000-0000-4000-8000-000000000001','get_kanban_board','{}'
  ) #>> '{statuses,0,id}' = 'kanban-status-backlog-v1'
  and public.read_pomodoist_mcp(
    '80000000-0000-4000-8000-000000000001','get_kanban_board','{}'
  ) #>> '{statuses,2,id}' = 'kanban-status-done-v1'
  and public.read_pomodoist_mcp(
    '80000000-0000-4000-8000-000000000001','get_kanban_board','{}'
  ) #> '{assignments}' @> '[{"taskId":"task-project","statusId":"kanban-status-doing"}]'::jsonb,
  'Kanban board returns stable settings, ordered statuses, and task assignments'
);

select is(
  public.read_pomodoist_mcp(
    '80000000-0000-4000-8000-000000000001','list_focus_history','{}'
  ) -> 'items',
  '[{"id":"focus-completed","taskId":"task-project","projectId":"project-a","startedAt":"2026-07-30T08:00:00+00:00","completedAt":"2026-07-30T08:25:00+00:00","actualSeconds":1440},{"id":"focus-legacy-completed","taskId":null,"projectId":null,"startedAt":"2026-07-30T07:00:00+00:00","completedAt":"2026-07-30T07:10:00+00:00","actualSeconds":540},{"id":"focus-century","taskId":null,"projectId":null,"startedAt":"2000-01-01T00:00:00+00:00","completedAt":"2100-01-01T00:00:00+00:00","actualSeconds":3155760000}]'::jsonb,
  'focus history uses a finite legacy terminal end and omits non-terminal rows'
);

select is(
  public.read_pomodoist_mcp(
    '80000000-0000-4000-8000-000000000001','list_focus_history','{}'
  ) #>> '{items,2,actualSeconds}',
  '3155760000',
  'focus history computes durations beyond int32 without overflow'
);

select ok(
  not public.read_pomodoist_mcp(
    '80000000-0000-4000-8000-000000000001','list_focus_history','{}'
  ) #> '{items}' @> '[{"id":"focus-infinity"}]'::jsonb,
  'focus history rejects non-finite timestamps'
);

select ok(
  (
    with metrics as (
      select public.read_pomodoist_mcp(
        '80000000-0000-4000-8000-000000000001',
        'get_achievements',
        '{"date":"2026-07-30","time_zone":"UTC"}'
      ) value
    )
    select value #>> '{daily,completedFocusIntervals}' = '2'
      and value #>> '{daily,totalFocusSeconds}' = '1980'
      and value #>> '{allTime,completedFocusIntervals}' = '3'
      and value #>> '{achievementInputs,completedWorkIntervals}' = '3'
    from metrics
  ),
  'productivity aggregation rejects infinity and keeps bigint work finite'
);

select results_eq(
  $$
    select
      case_row.value ->> 'name',
      public.read_pomodoist_mcp(
        (case_row.value ->> 'userId')::uuid,
        'get_productivity_report',
        jsonb_build_object(
          'date', case_row.value ->> 'reportDate',
          'time_zone', case_row.value ->> 'timeZone'
        )
      )
    from productivity_cases case_row
    order by case_row.value ->> 'name'
  $$,
  $$
    select
      case_row.value ->> 'name',
      case_row.value -> 'expected'
    from productivity_cases case_row
    order by case_row.value ->> 'name'
  $$,
  'productivity metrics match the shared UTC, Moscow, and DST fixture'
);

select results_eq(
  $$
    select
      case_row.value ->> 'name',
      public.read_pomodoist_mcp(
        (case_row.value ->> 'userId')::uuid,
        'get_achievements',
        jsonb_build_object(
          'date', case_row.value ->> 'reportDate',
          'time_zone', case_row.value ->> 'timeZone'
        )
      )
    from productivity_cases case_row
    order by case_row.value ->> 'name'
  $$,
  $$
    select
      case_row.value ->> 'name',
      case_row.value -> 'expected'
    from productivity_cases case_row
    order by case_row.value ->> 'name'
  $$,
  'achievement reads use the same untranslated metric and combo inputs'
);

select * from finish();

\else

select plan(1);
select has_function(
  'public',
  'read_pomodoist_mcp',
  array['uuid','text','jsonb'],
  'the MCP read dispatcher exists'
);
select * from finish();

\endif

rollback;

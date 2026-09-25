-- Unit regressions for the shared mutation function; every fixture rolls back.
begin;
select no_plan();

insert into auth.users(id,email,aud,role,created_at,updated_at)
values ('c2500000-0000-4000-8000-000000000001','kanban-unit@example.test','authenticated','authenticated',now(),now());
insert into private.pomodoist_scopes(id,root_project_id,owner_id)
values ('c2500000-0000-4000-8000-000000000002','project','c2500000-0000-4000-8000-000000000001');

create function pg_temp.put(typ text,id text,data jsonb,deleted timestamptz default null) returns jsonb language sql as $$
  select private.pomodoist_shared_put('c2500000-0000-4000-8000-000000000002',typ,id,data,deleted);
$$;
create function pg_temp.apply(typ text,id text,data jsonb,base bigint default null,op text default 'upsert') returns jsonb language sql as $$
  select private.pomodoist_shared_apply(
    'c2500000-0000-4000-8000-000000000002','c2500000-0000-4000-8000-000000000001','member',
    jsonb_build_object('opId',gen_random_uuid(),'entityType',typ,'entityId',id,'operation',op,
      'payload',data,'baseRevision',coalesce(base,(select revision from private.pomodoist_scopes
        where id='c2500000-0000-4000-8000-000000000002')),'clientUpdatedAt',now()));
$$;
create function pg_temp.entity(typ text,id text) returns jsonb language sql as $$
  select data from private.pomodoist_shared_entities where scope_id='c2500000-0000-4000-8000-000000000002'
    and entity_type=typ and entity_id=id;
$$;

select pg_temp.put('project','project','{"id":"project","name":"Project"}');
select pg_temp.put('label','backlog','{"name":"Backlog","kind":"kanbanStatus","systemKey":"backlog"}');
select pg_temp.put('label','done','{"name":"Done","kind":"kanbanStatus","systemKey":"done"}');
select pg_temp.put('label','review','{"name":"Review","kind":"kanbanStatus"}');
select pg_temp.put('task','task','{"id":"task","content":"Task","projectId":"project","status":"open"}');
select pg_temp.put('task','completed','{"content":"Completed","projectId":"project","status":"completed"}');
select pg_temp.put('task_kanban_status','task','{"taskId":"task","labelId":"review","changedAt":"2026-09-14T00:00:00Z"}');
select pg_temp.put('task_kanban_status','completed','{"taskId":"completed","labelId":"review"}');

select is(pg_temp.apply('label','review','{"name":"QA","changedAt":"2026-09-15T00:00:00Z"}')->>'status',
  'applied','legacy rename metadata is accepted');
select is(pg_temp.apply('label','review','{"orderKey":"b","changedAt":"2026-09-15T00:00:00Z"}')->>'status',
  'applied','legacy column ordering metadata is accepted');
select is(pg_temp.apply('task','task','{"orderKey":"b","changedAt":"2026-09-15T00:00:00Z"}')->>'status',
  'applied','legacy task ordering metadata is accepted');
select ok(not (pg_temp.entity('label','review') ? 'changedAt') and not (pg_temp.entity('task','task') ? 'changedAt'),
  'local ordering clocks are not stored on tasks or columns');
select throws_ok($$select pg_temp.apply('label','review','{"unknownField":true}')$$,
  '22023','Unsupported shared field: unknownField','other unsupported fields remain rejected');

select is(pg_temp.apply('task_kanban_status','task',
  '{"taskId":"task","labelId":"review","changedAt":"2026-09-15T00:00:00Z"}',0)->>'status',
  'applied','same status with a different clock does not conflict');
select is(pg_temp.apply('task_kanban_status','task','{"taskId":"task","labelId":"backlog"}',0)->>'status',
  'conflict','a stale change to a different status still conflicts');

select is(pg_temp.apply('task','task','{"status":"completed"}')->>'status','applied','complete task');
select is(pg_temp.apply('task_completion','completion','{"taskId":"task","snapshotJson":{"kanban":{"previousStatusLabelId":"forged"}}}')->>'status',
  'applied','record completion with server-owned history');
select is(pg_temp.entity('task_completion','completion')#>>'{snapshotJson,kanban,previousStatusLabelId}',
  'review','completion captures the canonical status before Done');
select is(pg_temp.entity('task_completion','completion')#>>'{snapshotJson,version}','1','workflow snapshot is versioned');
select is(pg_temp.entity('task_completion','completion')#>>'{snapshotJson,content}','Task','canonical task snapshot is retained');
select is(pg_temp.apply('task','task','{"status":"open"}')->>'status','applied','restore task for deletion regression');

select is(pg_temp.apply('label','review','{}',null,'delete')->>'status','applied','delete custom column');
select is(pg_temp.entity('task_kanban_status','task')->>'labelId','backlog','open task moves to Backlog');
select is(pg_temp.entity('task_kanban_status','completed')->>'labelId','done','completed task moves to Done');
select is((select count(*) from private.pomodoist_shared_entities
  where scope_id='c2500000-0000-4000-8000-000000000002' and entity_type='task_kanban_status' and deleted_at is null),
  2::bigint,'column deletion leaves both assignments live');
select is(pg_temp.apply('task_kanban_status','task','{"taskId":"task","labelId":"done"}')->>'status',
  'applied','a task can change column after its previous column was deleted');

-- Reproduce a tombstone left by the old label deletion implementation.
select pg_temp.put('task_kanban_status','task',pg_temp.entity('task_kanban_status','task'),now());
select is(pg_temp.apply('task_kanban_status','task','{"taskId":"task","labelId":"backlog"}',0)->>'code',
  'deleted','an assignment from before the tombstone remains rejected');
select is(pg_temp.apply('task_kanban_status','task','{"taskId":"task","labelId":"backlog"}')->>'status',
  'applied','a fresh assignment can restore a legacy tombstone');

select pg_temp.put('task_kanban_status','task',pg_temp.entity('task_kanban_status','task'),now());
select throws_ok($$select pg_temp.apply('task_kanban_status','task','{"taskId":"task","labelId":"review"}')$$,
  '22023','Label must belong to the shared scope','revival cannot reference a deleted column');
select pg_temp.put('task','task',pg_temp.entity('task','task'),now());
select throws_ok($$select pg_temp.apply('task_kanban_status','task','{"taskId":"task","labelId":"backlog"}')$$,
  '22023','Task is inaccessible','revival cannot reference a deleted task');
select is(pg_temp.apply('task','task','{"content":"Resurrect"}')->>'code','deleted','task deletion still wins');

select * from finish();
rollback;

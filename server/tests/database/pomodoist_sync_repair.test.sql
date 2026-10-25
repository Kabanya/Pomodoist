-- Exercise the final installed writer, including replacements by later migrations.
begin;
select no_plan();
insert into auth.users(id,email,aud,role,created_at,updated_at)
values('ac115000-0000-4000-8000-000000000001','sync-repair@example.test','authenticated','authenticated',now(),now());
create function pg_temp.repair_push(id text, action text, stamp text, typ text default 'task_label', eid text default 'task:label', payload jsonb default '{"taskId":"task","labelId":"label"}') returns jsonb language sql as $$
  select private.push_changes_for_user('ac115000-0000-4000-8000-000000000001','pomodoist','repair-test',jsonb_build_array(
    jsonb_build_object('opId',id,'entityType',typ,'entityId',eid,'operation',action,'clientUpdatedAt',stamp,'payload',payload)));
$$;
create function pg_temp.relation_deleted() returns boolean language sql as $$
  select deleted_at is not null from public.sync_entities where user_id='ac115000-0000-4000-8000-000000000001'
    and app_id='pomodoist' and entity_type='task_label' and entity_id='task:label';
$$;
select pg_temp.repair_push('add','upsert','2026-10-01T10:00:00Z');
select ok(not pg_temp.relation_deleted(),'first add is live');
select pg_temp.repair_push('remove','delete','2026-10-01T10:01:00Z');
select ok(pg_temp.relation_deleted(),'remove tombstones the relation');
select pg_temp.repair_push('readd','upsert','2026-10-01T10:02:00Z');
select ok(not pg_temp.relation_deleted(),'later add restores the same relation ID');
select pg_temp.repair_push('old-remove','delete','2026-10-01T10:01:30Z');
select ok(not pg_temp.relation_deleted(),'delayed delete cannot remove a newer add');
select pg_temp.repair_push('new-remove','delete','2026-10-01T10:03:00Z');
select pg_temp.repair_push('older-add','upsert','2026-10-01T10:02:30Z');
select ok(pg_temp.relation_deleted(),'delayed add cannot undo a newer deletion');
select pg_temp.repair_push('equal-add','upsert','2026-10-01T10:03:00Z');
select ok(pg_temp.relation_deleted(),'equal-time add loses to deletion');
select pg_temp.repair_push('fresh-add','upsert','2026-10-01T10:04:00Z');
select pg_temp.repair_push('equal-delete','delete','2026-10-01T10:04:00Z');
select ok(pg_temp.relation_deleted(),'equal-time deletion wins in either arrival order');
select pg_temp.repair_push('last-add','upsert','2026-10-01T10:05:00Z');
select is(jsonb_array_length(pg_temp.repair_push('last-add','upsert','2026-10-01T10:05:00Z')->'applied'),0,'receipt retry is idempotent');
-- Simulate a pre-fix tombstone without the new membership clock.
update public.sync_entities set field_clock=field_clock-'_membership',deleted_at='2026-10-01T10:06:00Z',client_updated_at='2026-10-01T10:00:00Z'
where user_id='ac115000-0000-4000-8000-000000000001' and entity_type='task_label';
select pg_temp.repair_push('legacy-stale','upsert','2026-10-01T10:05:30Z');
select ok(pg_temp.relation_deleted(),'legacy deletion clock survives regressed client_updated_at');
select pg_temp.repair_push('legacy-fresh','upsert','2026-10-01T10:07:00Z');
select ok(not pg_temp.relation_deleted(),'legacy tombstone can be restored by a newer add');
select pg_temp.repair_push('task-delete','delete','2026-10-01T10:08:00Z','task','task','{}');
select throws_ok($$select pg_temp.repair_push('deleted-task-add','upsert','2026-10-01T10:09:00Z')$$,
  '22023','Task label references a deleted entity','relation cannot resurrect a deleted task');
select throws_ok($$select pg_temp.repair_push('attachment','upsert','2026-10-01T10:10:00Z','attachment','file','{"id":"file"}')$$,
  '42501','Attachment metadata is server-authored','final writer blocks forged attachment metadata');
select throws_ok($$select pg_temp.repair_push('attachment-delete','delete','2026-10-01T10:10:00Z','attachment','file','{}')$$,
  '42501','Attachment metadata is server-authored','final writer blocks client attachment deletion');
select ok(strpos(pg_get_functiondef('private.push_changes_for_user(uuid,text,text,jsonb)'::regprocedure),'pomodoist-file-lifecycle')
  < strpos(pg_get_functiondef('private.push_changes_for_user(uuid,text,text,jsonb)'::regprocedure),'pomodoist-google-calendar:'),
  'file lifecycle lock precedes the calendar lock');
select throws_ok($$select pg_temp.repair_push('invalid-manual','upsert','2026-10-01T10:10:00Z','task','estimate','{"isFocusEstimateManual":"true"}')$$,
  '22023','Invalid Pomodoist manual focus estimate','manual estimate validation remains installed');
select pg_temp.repair_push('cloud-new','upsert','2026-10-01T12:00:00Z','task','merge-task','{"content":"Cloud content"}');
select pg_temp.repair_push('archive-old','upsert','2026-10-01T11:00:00Z','task','merge-task','{"content":"Old content","description":"Recovered missing field"}');
select is((select data->>'content' from public.sync_entities where user_id='ac115000-0000-4000-8000-000000000001' and entity_id='merge-task'),
  'Cloud content','archive cannot overwrite newer cloud fields');
select is((select data->>'description' from public.sync_entities where user_id='ac115000-0000-4000-8000-000000000001' and entity_id='merge-task'),
  'Recovered missing field','archive can fill a cloud field without a clock');
select pg_temp.repair_push('cloud-tombstone','delete','2026-10-01T13:00:00Z','task','merge-task','{}');
select pg_temp.repair_push('archive-new','upsert','2026-10-01T14:00:00Z','task','merge-task','{"content":"Cannot revive"}');
select ok((select deleted_at is not null from public.sync_entities where user_id='ac115000-0000-4000-8000-000000000001' and entity_id='merge-task'),
  'confirmed task deletions survive even a newer archive snapshot');
select pg_temp.repair_push('label-tombstone','delete','2026-10-01T13:00:00Z','label','removed-label','{}');
select throws_ok($$select pg_temp.repair_push('deleted-label-add','upsert','2026-10-01T14:00:00Z','task_label','another-task:removed-label','{"taskId":"another-task","labelId":"removed-label"}')$$,
  '22023','Task label references a deleted entity','relation cannot resurrect a deleted label');
select pg_temp.repair_push('soft-label','upsert','2026-10-01T13:00:00Z','label','soft-label','{"isDeleted":true}');
select throws_ok($$select pg_temp.repair_push('soft-label-add','upsert','2026-10-01T14:00:00Z','task_label','another-task:soft-label','{"taskId":"another-task","labelId":"soft-label"}')$$,
  '22023','Task label references a deleted entity','relation cannot reference a soft-deleted label');
select ok(strpos(pg_get_functiondef('private.calendar_service(text,uuid,text,jsonb)'::regprocedure),'pomodoist-file-lifecycle') > 0
  and strpos(pg_get_functiondef('private.calendar_service(text,uuid,text,jsonb)'::regprocedure),'pomodoist-file-lifecycle')
    < strpos(pg_get_functiondef('private.calendar_service(text,uuid,text,jsonb)'::regprocedure),'pomodoist-google-calendar:'),
  'generic calendar service takes the lifecycle lock before its calendar or row locks');
select * from finish();
rollback;

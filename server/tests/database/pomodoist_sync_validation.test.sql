begin;
select no_plan();
insert into auth.users(id,email,aud,role,created_at,updated_at)
values('ac000000-0000-4000-8000-000000000001','sync-validation@example.test','authenticated','authenticated',now(),now());
set local request.jwt.claim.sub='ac000000-0000-4000-8000-000000000001';
set local request.jwt.claims='{"sub":"ac000000-0000-4000-8000-000000000001","role":"authenticated"}';

create function pg_temp.sync_op(p_id text) returns jsonb language sql as $$
  select jsonb_build_object('opId',p_id,'entityType','task','entityId',p_id,
    'operation','upsert','payload',jsonb_build_object('content','Private task text'),
    'clientUpdatedAt','2026-09-14T00:00:00Z');
$$;

select throws_ok($$select public.push_changes('pomodoist','invalid','{}')$$,
  '22023','Invalid sync batch: expected an array','object batch rejected');
select throws_ok($$select public.push_changes('pomodoist','invalid','null')$$,
  '22023','Invalid sync batch: expected an array','JSON null batch rejected');
select throws_ok($$select public.push_changes('pomodoist','invalid','[null]')$$,
  '22023','Invalid sync operation: expected an object','null operation rejected');
select throws_ok($$select public.push_changes('pomodoist','invalid',jsonb_build_array(
  pg_temp.sync_op('valid-first'),pg_temp.sync_op('invalid-last') || '{"operation":"deleet"}'))$$,
  '22023','Invalid sync operation: expected upsert or delete','unknown operation rejects the whole batch');
select is((select count(*) from public.sync_entities where user_id=auth.uid()),0::bigint,'no partial entity writes');
select is((select count(*) from public.sync_operation_receipts where user_id=auth.uid()),0::bigint,'no partial receipts');
select is((select count(*) from public.sync_devices where user_id=auth.uid()),0::bigint,'validation precedes device writes');
select throws_ok($$select public.push_changes('pomodoist','invalid',jsonb_build_array(pg_temp.sync_op('x') || '{"opId":12}'))$$,
  '22023','Invalid sync identifier: opId','numeric identifier rejected');
select throws_ok($$select public.push_changes('pomodoist','invalid',jsonb_build_array(pg_temp.sync_op('x') || '{"entityType":" "}'))$$,
  '22023','Invalid sync identifier: entityType','blank entity type rejected');
select throws_ok($$select public.push_changes('pomodoist','invalid',jsonb_build_array(pg_temp.sync_op('x') - 'entityId'))$$,
  '22023','Invalid sync identifier: entityId','missing identifier rejected');
select throws_ok($$select public.push_changes('pomodoist','invalid',jsonb_build_array(pg_temp.sync_op('x') || '{"payload":null}'))$$,
  '22023','Invalid sync payload: expected an object','null payload rejected');
select throws_ok($$select public.push_changes('pomodoist','invalid',jsonb_build_array(pg_temp.sync_op('x') || '{"payload":[]}'))$$,
  '22023','Invalid sync payload: expected an object','array payload rejected');

select is(jsonb_array_length(public.push_changes('pomodoist','valid',jsonb_build_array(pg_temp.sync_op('task-a')))->'applied'),1,'valid upsert accepted');
select is(jsonb_array_length(public.push_changes('pomodoist','valid',jsonb_build_array(pg_temp.sync_op('task-a')))->'applied'),0,'receipt retry remains idempotent');
select lives_ok($$select public.push_changes('pomodoist','valid',jsonb_build_array(pg_temp.sync_op('default') - 'operation' - 'payload'))$$,'missing operation and payload retain legacy defaults');
select lives_ok($$select public.push_changes('pomodoist','valid',jsonb_build_array(pg_temp.sync_op('null-op') || '{"operation":null}'))$$,'null operation retains legacy upsert default');
select lives_ok($$select public.push_changes('pomodoist','valid','[{"op_id":"snake","entity_type":"task","entity_id":"snake"}]')$$,'snake_case aliases remain supported');
select lives_ok($$select public.push_changes('pomodoist','valid','[{"opId":null,"op_id":"alias","entityType":null,"entity_type":"task","entityId":null,"entity_id":"alias"}]')$$,'null camelCase falls back to snake_case');
select lives_ok($$select public.push_changes('pomodoist','valid',null)$$,'SQL null batch remains supported');
select lives_ok($$select public.push_changes('pomodoist','valid','[]')$$,'empty batch remains supported');
select public.push_changes('pomodoist','valid',jsonb_build_array(pg_temp.sync_op('delete-task-a') || '{"entityId":"task-a","operation":"delete"}'));
select ok((select deleted_at is not null from public.sync_entities where user_id=auth.uid() and entity_id='task-a'),'delete still produces a tombstone');
select throws_ok($$select public.push_changes('pomodoist','valid','[{"opId":"delete-inbox","entityType":"project","entityId":"inbox","operation":"delete"}]')$$,
  '22023','Protected Pomodoist system anchor cannot be deleted: project/inbox','protected anchors remain protected');

select throws_ok($$insert into public.usage_periods(user_id,app_id,quota_key,period_start,period_end,limit_value)
  values(auth.uid(),'pomodoist','llm_requests','2026-10-01Z','2026-09-01Z',1000)$$,
  '23514',null,'inverted quota period rejected');
select throws_ok($$insert into public.usage_periods(user_id,app_id,quota_key,period_start,period_end,limit_value)
  values(auth.uid(),'pomodoist','llm_requests','2026-10-01Z','2026-10-01Z',1000)$$,
  '23514',null,'zero-length quota period rejected');
select throws_ok($$insert into public.usage_periods(user_id,app_id,quota_key,period_start,period_end,limit_value)
  values(auth.uid(),'pomodoist','llm_requets','2026-10-01Z','2026-11-01Z',1000)$$,
  '23503',null,'unknown quota rejected');
insert into public.apps(id,display_name) values('quota-test-app','Quota test');
insert into public.quota_definitions(app_id,quota_key,limit_value) values('quota-test-app','other_app_quota',1000);
select throws_ok($$insert into public.usage_periods(user_id,app_id,quota_key,period_start,period_end,limit_value)
  values(auth.uid(),'pomodoist','other_app_quota','2026-10-01Z','2026-11-01Z',1000)$$,
  '23503',null,'quota definition must belong to the same app');
insert into public.usage_periods(user_id,app_id,quota_key,period_start,period_end,used,limit_value)
values(auth.uid(),'pomodoist','llm_requests','2026-10-01Z','2026-11-01Z',1001,1000);
select is((select used from public.usage_periods where user_id=auth.uid()),1001,'lowering a limit does not erase previous usage');
select throws_ok($$delete from public.quota_definitions where app_id='pomodoist' and quota_key='llm_requests'$$,
  '23503',null,'cannot delete a quota definition with history');

select * from finish();
rollback;

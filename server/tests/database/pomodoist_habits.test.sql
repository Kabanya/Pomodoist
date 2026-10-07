begin;
select no_plan();
insert into auth.users(id,email,aud,role,created_at,updated_at) values
 ('ab900000-0000-4000-8000-000000000001','habits-a@example.test','authenticated','authenticated',now(),now()),
 ('ab900000-0000-4000-8000-000000000002','habits-b@example.test','authenticated','authenticated',now(),now());
set local request.jwt.claim.sub='ab900000-0000-4000-8000-000000000001';
set local request.jwt.claims='{"sub":"ab900000-0000-4000-8000-000000000001","role":"authenticated"}';
create function pg_temp.habit_data(p_id text) returns jsonb language sql as $$
 select jsonb_build_object('id',p_id,'userId','local-user','title','Read','projectId',null,'reminderMinutes',1200,
 'scheduleHistory',jsonb_build_array(jsonb_build_object('effectiveFrom','2026-09-30','startDate','2026-09-30','endDate',null,'weekdays',jsonb_build_array(1,2,3,4,5,6,7),'targetPerDay',2)),
 'createdAt','2026-09-30T12:00:00Z','updatedAt','2026-09-30T12:00:00Z','isDeleted',false);
$$;
create function pg_temp.check_data(p_id text,p_habit text) returns jsonb language sql as $$
 select jsonb_build_object('id',p_id,'userId','local-user','habitId',p_habit,'day','2026-09-30',
 'createdAt','2026-09-30T12:00:00Z','updatedAt','2026-09-30T12:00:00Z','isDeleted',false);
$$;
create function pg_temp.habit_op(p_op text,p_type text,p_id text,p_data jsonb,p_action text default 'upsert') returns jsonb language sql as $$
 select jsonb_build_object('opId',p_op,'entityType',p_type,'entityId',p_id,'operation',p_action,
   'payload',jsonb_build_object('schemaVersion',1,'commandType',p_type || case p_action when 'delete' then '.delete' else '.create' end) || p_data,
   'clientUpdatedAt','2026-09-30T12:00:00Z');
$$;
select lives_ok($$select public.push_changes('pomodoist','habits',jsonb_build_array(pg_temp.habit_op('mixed-task','task','metadata-task','{"content":"Synced with habit"}'),pg_temp.habit_op('create','habit','ab900000-0000-4000-8000-000000000010',pg_temp.habit_data('ab900000-0000-4000-8000-000000000010'))))$$,'task and SDK habit metadata sync in one batch');
select is((select count(*) from public.sync_entities where user_id=auth.uid() and entity_type='task' and entity_id='metadata-task'),1::bigint,'habit metadata does not block task delivery');
select lives_ok($$select public.push_changes('pomodoist','habits',jsonb_build_array(pg_temp.habit_op('check1','habit_check_in','ab900000-0000-4000-8000-000000000011',pg_temp.check_data('ab900000-0000-4000-8000-000000000011','ab900000-0000-4000-8000-000000000010'))))$$,'first independent check-in');
select lives_ok($$select public.push_changes('pomodoist','other-device',jsonb_build_array(pg_temp.habit_op('check2','habit_check_in','ab900000-0000-4000-8000-000000000012',pg_temp.check_data('ab900000-0000-4000-8000-000000000012','ab900000-0000-4000-8000-000000000010'))))$$,'second independent check-in');
select public.push_changes('pomodoist','habits',jsonb_build_array(pg_temp.habit_op('check1','habit_check_in','ab900000-0000-4000-8000-000000000011',pg_temp.check_data('ab900000-0000-4000-8000-000000000011','ab900000-0000-4000-8000-000000000010'))));
select is((select count(*) from public.sync_entities where user_id=auth.uid() and entity_type='habit_check_in'),2::bigint,'retry does not duplicate completions');
select throws_ok($$select public.push_changes('pomodoist','invalid',jsonb_build_array(pg_temp.habit_op('bad-title','habit','ab900000-0000-4000-8000-000000000010',pg_temp.habit_data('ab900000-0000-4000-8000-000000000010') || '{"title":" "}')))$$,'22023','Invalid habit title','blank title rejected');
select throws_ok($$select public.push_changes('pomodoist','invalid',jsonb_build_array(pg_temp.habit_op('bad-id','habit','ab900000-0000-4000-8000-000000000010',pg_temp.habit_data('ab900000-0000-4000-8000-000000000010') || '{"id":"other"}')))$$,'22023','Invalid habit identity','payload identity cannot disagree');
select throws_ok($$select public.push_changes('pomodoist','invalid',jsonb_build_array(pg_temp.habit_op('bad-owner','habit','ab900000-0000-4000-8000-000000000010',pg_temp.habit_data('ab900000-0000-4000-8000-000000000010') || '{"userId":"ab900000-0000-4000-8000-000000000002"}')))$$,'22023','Invalid habit identity','payload owner cannot impersonate another account');
select throws_ok($$select public.push_changes('pomodoist','invalid',jsonb_build_array(pg_temp.habit_op('bad-reminder','habit','ab900000-0000-4000-8000-000000000010',pg_temp.habit_data('ab900000-0000-4000-8000-000000000010') || '{"reminderMinutes":1440}')))$$,'22023','Invalid habit reminder','reminder bounds');
select throws_ok($$select public.push_changes('pomodoist','invalid',jsonb_build_array(pg_temp.habit_op('bad-goal','habit','ab900000-0000-4000-8000-000000000010',jsonb_set(pg_temp.habit_data('ab900000-0000-4000-8000-000000000010'),'{scheduleHistory,0,targetPerDay}','100'))))$$,'22023','Invalid habit schedule','goal bounds');
select throws_ok($$select public.push_changes('pomodoist','invalid',jsonb_build_array(pg_temp.habit_op('bad-date','habit','ab900000-0000-4000-8000-000000000010',jsonb_set(pg_temp.habit_data('ab900000-0000-4000-8000-000000000010'),'{scheduleHistory,0,startDate}','"2026-02-30"'))))$$,'22023','Invalid habit date','invalid calendar date');
select throws_ok($$select public.push_changes('pomodoist','invalid',jsonb_build_array(pg_temp.habit_op('bad-days','habit','ab900000-0000-4000-8000-000000000010',jsonb_set(pg_temp.habit_data('ab900000-0000-4000-8000-000000000010'),'{scheduleHistory,0,weekdays}','[1,1]'))))$$,'22023','Invalid habit weekdays','duplicate weekdays');
select throws_ok($$select public.push_changes('pomodoist','invalid',jsonb_build_array(pg_temp.habit_op('bad-check-date','habit_check_in','ab900000-0000-4000-8000-000000000011',pg_temp.check_data('ab900000-0000-4000-8000-000000000011','ab900000-0000-4000-8000-000000000010') || '{"day":"2026-09-31"}')))$$,'22023','Invalid habit date','invalid completion date');
select throws_ok($$select public.push_changes('pomodoist','invalid',jsonb_build_array(pg_temp.habit_op('move-check','habit_check_in','ab900000-0000-4000-8000-000000000011',pg_temp.check_data('ab900000-0000-4000-8000-000000000011','ab900000-0000-4000-8000-000000000010') || '{"day":"2026-09-29"}')))$$,'22023','Check-in identity is immutable','existing completion cannot move dates');
select throws_ok($$select public.push_changes('pomodoist','invalid',jsonb_build_array(pg_temp.habit_op('unknown-project','habit','ab900000-0000-4000-8000-000000000010',pg_temp.habit_data('ab900000-0000-4000-8000-000000000010') || '{"projectId":"missing"}')))$$,'22023','Habit project must belong to the same account and be personal','unknown project rejected');
-- A valid existing type followed by an invalid habit must roll back everything.
select throws_ok($$select public.push_changes('pomodoist','atomic',jsonb_build_array(pg_temp.habit_op('atomic-task','task','atomic-task','{"content":"Must roll back"}'),pg_temp.habit_op('atomic-habit','habit','ab900000-0000-4000-8000-000000000010',pg_temp.habit_data('ab900000-0000-4000-8000-000000000010') || '{"title":""}')))$$,'22023','Invalid habit title','mixed batch rollback');
select is((select count(*) from public.sync_entities where entity_id='atomic-task'),0::bigint,'no partial entities');
select is((select count(*) from public.sync_operation_receipts where user_id=auth.uid() and op_id='atomic-task'),0::bigint,'no partial receipts');
set local request.jwt.claim.sub='ab900000-0000-4000-8000-000000000002';
set local request.jwt.claims='{"sub":"ab900000-0000-4000-8000-000000000002","role":"authenticated"}';
select throws_ok($$select public.push_changes('pomodoist','foreign',jsonb_build_array(pg_temp.habit_op('foreign-check','habit_check_in','ab900000-0000-4000-8000-000000000013',pg_temp.check_data('ab900000-0000-4000-8000-000000000013','ab900000-0000-4000-8000-000000000010'))))$$,'22023','Check-in habit must belong to the same account','foreign habit inaccessible');
set local role authenticated;
select is((select count(*) from public.sync_entities where entity_type in ('habit','habit_check_in')),0::bigint,'RLS isolates habit reads');
reset role;
set local request.jwt.claim.sub='ab900000-0000-4000-8000-000000000001';
set local request.jwt.claims='{"sub":"ab900000-0000-4000-8000-000000000001","role":"authenticated"}';
select public.push_changes('pomodoist','habits',jsonb_build_array(pg_temp.habit_op('undo','habit_check_in','ab900000-0000-4000-8000-000000000011','{}','delete')));
select ok((select deleted_at is not null from public.sync_entities where user_id=auth.uid() and entity_id='ab900000-0000-4000-8000-000000000011'),'undo is a tombstone');
select public.push_changes('pomodoist','habits',jsonb_build_array(pg_temp.habit_op('delete','habit','ab900000-0000-4000-8000-000000000010','{}','delete')));
select lives_ok($$select public.push_changes('pomodoist','late',jsonb_build_array(pg_temp.habit_op('late-check','habit_check_in','ab900000-0000-4000-8000-000000000014',pg_temp.check_data('ab900000-0000-4000-8000-000000000014','ab900000-0000-4000-8000-000000000010'))))$$,'late delivery accepted without reviving parent');
select ok((select deleted_at is not null from public.sync_entities where user_id=auth.uid() and entity_id='ab900000-0000-4000-8000-000000000014'),'late check-in stays deleted');
select public.push_changes('pomodoist','late',jsonb_build_array(pg_temp.habit_op('late-habit','habit','ab900000-0000-4000-8000-000000000010',pg_temp.habit_data('ab900000-0000-4000-8000-000000000010'))));
select ok((select deleted_at is not null from public.sync_entities where user_id=auth.uid() and entity_id='ab900000-0000-4000-8000-000000000010'),'deleted habit never resurrects');
select lives_ok($$select public.push_changes('pomodoist','legacy',jsonb_build_array(pg_temp.habit_op('legacy-task','task','legacy-task','{"content":"Legacy works"}')))$$,'existing entity protocol unchanged');
-- Personal project references remain account-scoped, including stale patches.
select public.push_changes('pomodoist','projects',jsonb_build_array(pg_temp.habit_op('personal-project','project','habits-personal','{"id":"habits-personal","name":"Personal","scopeId":null}')));
select lives_ok($$select public.push_changes('pomodoist','projects',jsonb_build_array(pg_temp.habit_op('personal-habit','habit','ab900000-0000-4000-8000-000000000020',pg_temp.habit_data('ab900000-0000-4000-8000-000000000020') || '{"projectId":"habits-personal"}')))$$,'own personal project accepted');
select public.push_changes('pomodoist','projects',jsonb_build_array(pg_temp.habit_op('archived-project','project','habits-personal','{"isArchived":true}')));
select lives_ok($$select public.push_changes('pomodoist','projects',jsonb_build_array(pg_temp.habit_op('archived-habit-edit','habit','ab900000-0000-4000-8000-000000000020','{"title":"Read again"}')))$$,'archived project does not erase the habit');
select throws_ok($$select public.push_changes('pomodoist','old',jsonb_build_array(pg_temp.habit_op('stale-invalid','habit','ab900000-0000-4000-8000-000000000020','{"title":""}') || '{"clientUpdatedAt":"2000-01-01T00:00:00Z"}'))$$,'22023','Invalid habit title','invalid stale patch is rejected before field-clock merge');
select throws_ok($$select public.push_changes('pomodoist','old',jsonb_build_array(pg_temp.habit_op('unknown-field','habit','ab900000-0000-4000-8000-000000000020','{"unexpected":true}')))$$,'22023','Invalid habit field','unknown new-entity fields rejected');
select throws_ok($$select public.push_changes('pomodoist','history',jsonb_build_array(pg_temp.habit_op('bad-history-order','habit','ab900000-0000-4000-8000-000000000020',jsonb_set(pg_temp.habit_data('ab900000-0000-4000-8000-000000000020'),'{scheduleHistory}',(pg_temp.habit_data('ab900000-0000-4000-8000-000000000020')->'scheduleHistory') || (pg_temp.habit_data('ab900000-0000-4000-8000-000000000020')->'scheduleHistory')))))$$,'22023','Invalid habit schedule','schedule versions cannot repeat effective dates');
set local request.jwt.claim.sub='ab900000-0000-4000-8000-000000000002';
set local request.jwt.claims='{"sub":"ab900000-0000-4000-8000-000000000002","role":"authenticated"}';
select throws_ok($$select public.push_changes('pomodoist','foreign-project',jsonb_build_array(pg_temp.habit_op('foreign-project-habit','habit','ab900000-0000-4000-8000-000000000021',pg_temp.habit_data('ab900000-0000-4000-8000-000000000021') || '{"projectId":"habits-personal"}')))$$,'22023','Habit project must belong to the same account and be personal','foreign project is rejected');
select * from finish();
rollback;

-- Whole-run offline adoption must preserve history before retiring local outbox rows.
begin;
\ir hosted-mode.inc
select no_plan();
create function pg_temp.check(value boolean,label text) returns text language sql as $$select ok(value,label)$$;
create function pg_temp.rejected(command jsonb,label text) returns text language plpgsql as $$begin perform public.pomodoist_focus(command); return ok(false,label||' accepted'); exception when sqlstate '22023' then return ok(true,label); end$$;
create function pg_temp.adoption(p_run text,p_task text,p_project text default 'inbox') returns jsonb language plpgsql as $$
declare t timestamptz:=clock_timestamp(); base jsonb; first_work jsonb; first_break jsonb; current_work jsonb; run jsonb;
begin
 base:=jsonb_build_object('runId',p_run,'taskId',p_task,'projectId',p_project,'pausedAt',null,'pausedTotalSeconds',0,'stoppedAt',null,'isDeleted',false);
 first_work:=base||jsonb_build_object('id',p_run||'-work-1','type','work','status','completed','plannedSeconds',60,'sequenceNumber',1,'startedAt',t-interval '400 seconds','completedAt',t-interval '340 seconds','createdAt',t-interval '400 seconds','updatedAt',t-interval '340 seconds');
 first_break:=base||jsonb_build_object('id',p_run||'-break-1','type','shortBreak','status','completed','plannedSeconds',60,'sequenceNumber',2,'startedAt',t-interval '340 seconds','completedAt',t-interval '280 seconds','createdAt',t-interval '340 seconds','updatedAt',t-interval '280 seconds');
 current_work:=base||jsonb_build_object('id',p_run||'-work-2','type','work','status','running','plannedSeconds',60,'sequenceNumber',3,'startedAt',t-interval '30 seconds','completedAt',null,'createdAt',t-interval '280 seconds','updatedAt',t-interval '30 seconds');
 run:=jsonb_build_object('id',p_run,'userId','local-user','taskId',p_task,'projectId',p_project,'presetId','classic','status','active','startedAt',t-interval '400 seconds','endedAt',null,'targetWorkIntervals',3,'completedWorkIntervals',1,'createdAt',t-interval '400 seconds','updatedAt',t-interval '30 seconds','isDeleted',false);
 return jsonb_build_object('action','start','deviceId','adoption-desktop','requestId',p_run,'expectedRevision',0,'payload',jsonb_build_object('preset',jsonb_build_object('id','classic','workSeconds',60,'shortBreakSeconds',60,'longBreakSeconds',120,'intervalsBeforeLongBreak',2,'strictMode',false),'adopt',jsonb_build_object('run',run,'interval',current_work,'intervals',jsonb_build_array(first_work,first_break),'events',jsonb_build_array(
  jsonb_build_object('id',p_run||'-event-1','runId',p_run,'intervalId',first_work->>'id','type','runStarted','occurredAt',t-interval '400 seconds','payloadJson',jsonb_build_object('taskId',p_task,'projectId',p_project)::text,'createdAt',t-interval '400 seconds'),
  jsonb_build_object('id',p_run||'-event-2','runId',p_run,'intervalId',first_work->>'id','type','intervalCompleted','occurredAt',t-interval '340 seconds','payloadJson','{"type":"work"}','createdAt',t-interval '340 seconds'),
  jsonb_build_object('id',p_run||'-event-3','runId',p_run,'intervalId',current_work->>'id','type','intervalStarted','occurredAt',t-interval '30 seconds','payloadJson','{"type":"work"}','createdAt',t-interval '30 seconds')))));
end$$;
insert into auth.users(id,email,aud,role,created_at,updated_at) values
 ('fb000000-0000-4000-8000-000000000001','adopt-1@example.test','authenticated','authenticated',now(),now()),
 ('fb000000-0000-4000-8000-000000000002','adopt-2@example.test','authenticated','authenticated',now(),now()),
 ('fb000000-0000-4000-8000-000000000003','adopt-3@example.test','authenticated','authenticated',now(),now()),
 ('fb000000-0000-4000-8000-000000000004','adopt-4@example.test','authenticated','authenticated',now(),now());
insert into auth.sessions(id,user_id,created_at,updated_at) values
 ('fb000000-0000-4000-8000-000000000011','fb000000-0000-4000-8000-000000000001',now(),now()),
 ('fb000000-0000-4000-8000-000000000012','fb000000-0000-4000-8000-000000000002',now(),now()),
 ('fb000000-0000-4000-8000-000000000013','fb000000-0000-4000-8000-000000000003',now(),now()),
 ('fb000000-0000-4000-8000-000000000014','fb000000-0000-4000-8000-000000000004',now(),now());
select private.pomodoist_focus_project('fb000000-0000-4000-8000-000000000001','task','adopt-task','{"id":"adopt-task","content":"Task","projectId":"inbox","status":"open","completedFocusIntervals":0,"totalFocusSeconds":0}');
create temp table adoption_fixture as select pg_temp.adoption('offline-history','adopt-task') command;
grant select on adoption_fixture to authenticated;
set local role authenticated;
set local request.jwt.claims='{"sub":"fb000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"fb000000-0000-4000-8000-000000000011"}';
set local request.jwt.claim.sub='fb000000-0000-4000-8000-000000000001';
create temp table adoption_response as select public.pomodoist_focus(command) response from adoption_fixture;
select pg_temp.check((select count(*)=3 from public.sync_entities where user_id=auth.uid() and entity_type='focus_interval' and data->>'runId'='offline-history'),'adoption preserves completed work, break, and current interval');
select pg_temp.check((select count(*)=3 from public.sync_entities where user_id=auth.uid() and entity_type='focus_event' and data->>'runId'='offline-history'),'adoption preserves every offline event');
select pg_temp.check((select data->>'totalFocusSeconds'='60' and data->>'completedFocusIntervals'='1' from public.sync_entities where user_id=auth.uid() and entity_type='task' and entity_id='adopt-task'),'prior adopted work credits personal task exactly once');
select pg_temp.check((select response->'session'->'run'->>'completedWorkIntervals'='1' and response->'session'->'interval'->>'id'='offline-history-work-2' from adoption_response),'adoption preserves validated run progress and current identity');
select pg_temp.check((select public.pomodoist_focus(command)=(select response from adoption_response) from adoption_fixture),'adoption request replay is exact');
reset role;
update private.pomodoist_focus_accounts set deadline=clock_timestamp()-interval '1 second',session=jsonb_set(session,'{interval,startedAt}',to_jsonb(clock_timestamp()-interval '61 seconds')) where user_id='fb000000-0000-4000-8000-000000000001';
set local role authenticated;
select public.pomodoist_focus('{"action":"read","deviceId":"adoption-desktop"}');
select public.pomodoist_focus('{"action":"read","deviceId":"adoption-desktop"}');
select pg_temp.check((select data->>'totalFocusSeconds'='120' and data->>'completedFocusIntervals'='2' from public.sync_entities where user_id=auth.uid() and entity_type='task' and entity_id='adopt-task'),'subsequent live completion retains prior adopted personal contribution');
reset role;
-- A second account exercises rejection paths before it has a live session.
select private.pomodoist_focus_project('fb000000-0000-4000-8000-000000000002','task','adopt-task','{"id":"adopt-task","content":"Task","projectId":"inbox","status":"open"}');
set local role authenticated;
set local request.jwt.claims='{"sub":"fb000000-0000-4000-8000-000000000002","role":"authenticated","session_id":"fb000000-0000-4000-8000-000000000012"}';
set local request.jwt.claim.sub='fb000000-0000-4000-8000-000000000002';
select pg_temp.rejected(jsonb_set(command,'{payload,adopt,intervals}','[]'),'missing prior history is rejected') from adoption_fixture;
select pg_temp.rejected(jsonb_set(command,'{payload,adopt,run,completedWorkIntervals}','2'),'invented progress is rejected') from adoption_fixture;
select pg_temp.rejected(jsonb_set(command,'{payload,adopt,intervals,0,taskId}','"another-task"'),'history cannot switch task ownership') from adoption_fixture;
select pg_temp.rejected(jsonb_set(command,'{payload,adopt,intervals,0,id}',command#>'{payload,adopt,interval,id}'),'current interval cannot also appear in history') from adoption_fixture;
select pg_temp.rejected(jsonb_set(command,'{payload,adopt,intervals,1,sequenceNumber}','1'),'duplicate interval sequence is rejected') from adoption_fixture;
select pg_temp.rejected(jsonb_set(command,'{payload,adopt,intervals,1,startedAt}',command#>'{payload,adopt,intervals,0,startedAt}'),'overlapping intervals are rejected') from adoption_fixture;
select pg_temp.rejected(jsonb_set(command,'{payload,adopt,intervals,0,pausedTotalSeconds}','999'),'impossible paused duration is rejected') from adoption_fixture;
select pg_temp.rejected(jsonb_set(command,'{payload,adopt,intervals,0,plannedSeconds}','59'),'history duration remains bounded') from adoption_fixture;
select pg_temp.rejected(jsonb_set(command,'{payload,adopt,events}',(select jsonb_agg('{}'::jsonb) from generate_series(1,5001))),'event adoption is bounded') from adoption_fixture;
select pg_temp.rejected(jsonb_set(command,'{payload,adopt,intervals}',(select jsonb_agg('{}'::jsonb) from generate_series(1,1001))),'interval adoption is bounded') from adoption_fixture;
select pg_temp.rejected(jsonb_set(command,'{payload,adopt,intervals,1,type}','"work"'),'history cannot contain consecutive work phases') from adoption_fixture;
select pg_temp.rejected(jsonb_set(command,'{payload,note}',to_jsonb(repeat('x',2097152))),'adoption request size is bounded') from adoption_fixture;
select pg_temp.rejected(jsonb_set(command,'{payload,adopt,run,userId}','"someone-else"'),'foreign run owner is rejected') from adoption_fixture;
select pg_temp.rejected(jsonb_set(command,'{payload,adopt,events,0,intervalId}','"unrelated-interval"'),'event cannot refer to another interval') from adoption_fixture;
select pg_temp.rejected(jsonb_set(command,'{payload,adopt,events,1,id}',command#>'{payload,adopt,events,0,id}'),'duplicate event identity is rejected') from adoption_fixture;
select pg_temp.rejected(jsonb_set(command,'{payload,adopt,events,1,payloadJson}','"not json"'),'invalid event payload is rejected') from adoption_fixture;
reset role;
select pg_temp.check(not exists(select 1 from private.pomodoist_focus_owned_runs where user_id='fb000000-0000-4000-8000-000000000002') and not exists(select 1 from public.sync_entities where user_id='fb000000-0000-4000-8000-000000000002' and entity_type in ('focus_run','focus_interval','focus_event')),'failed adoption rolls back authority and all history');
select private.pomodoist_focus_project('fb000000-0000-4000-8000-000000000002','focus_interval','offline-history-work-1','{"id":"offline-history-work-1","runId":"unrelated-run","status":"completed"}');
set local role authenticated;
select pg_temp.rejected(command,'colliding existing interval identity is rejected') from adoption_fixture;
reset role;
delete from public.sync_entities where user_id='fb000000-0000-4000-8000-000000000002' and entity_type='focus_interval';
-- A previously synchronized identical interval is included, rather than omitted.
select private.pomodoist_focus_project('fb000000-0000-4000-8000-000000000002','focus_interval','offline-history-work-1',command#>'{payload,adopt,intervals,0}') from adoption_fixture;
set local role authenticated;
select public.pomodoist_focus(command) from adoption_fixture;
select pg_temp.check((select data->>'totalFocusSeconds'='60' and data->>'completedFocusIntervals'='1' from public.sync_entities where user_id=auth.uid() and entity_type='task' and entity_id='adopt-task'),'already synced history does not double count on adoption');
reset role;
create function pg_temp.immutable_event() returns text language plpgsql as $$begin update public.sync_entities set data=jsonb_set(data,'{runId}','"unrelated-run"') where user_id='fb000000-0000-4000-8000-000000000002' and entity_type='focus_event' and entity_id='offline-history-event-1'; return ok(false,'owned event mutated'); exception when insufficient_privilege then return ok(true,'adopted event cannot escape ownership by changing runId'); end$$;
select pg_temp.immutable_event();
set local role authenticated;
select public.pomodoist_focus('{"action":"requestStop","deviceId":"adoption-desktop","requestId":"stop-before-final-break","expectedRevision":1}');
create temp table final_break_fixture as with source as (select pg_temp.adoption('final-break','adopt-task') c)
select (c||'{"expectedRevision":2}')||jsonb_build_object('payload',(c->'payload')||jsonb_build_object('adopt',(c#>'{payload,adopt}')||jsonb_build_object(
 'run',(c#>'{payload,adopt,run}')||'{"targetWorkIntervals":1}', 'interval',(c#>'{payload,adopt,interval}')||'{"type":"shortBreak","sequenceNumber":2}',
 'intervals',jsonb_build_array(c#>'{payload,adopt,intervals,0}'),'events','[]'::jsonb))) command from source;
select pg_temp.check((public.pomodoist_focus(command)->'session'->'interval'->>'type')='shortBreak','final break may be adopted after target work count is reached') from final_break_fixture;
reset role;
insert into private.pomodoist_scopes(id,root_project_id,owner_id) values('fb000000-0000-4000-8000-000000000023','shared-project','fb000000-0000-4000-8000-000000000003');
insert into private.pomodoist_members(scope_id,user_id,role) values('fb000000-0000-4000-8000-000000000023','fb000000-0000-4000-8000-000000000003','administrator');
select private.pomodoist_shared_put('fb000000-0000-4000-8000-000000000023','project','shared-project','{"id":"shared-project","name":"Shared"}');
select private.pomodoist_shared_put('fb000000-0000-4000-8000-000000000023','task','shared-adopt-task','{"id":"shared-adopt-task","content":"Shared task","status":"open","projectId":"shared-project"}');
create temp table shared_adoption_fixture as select pg_temp.adoption('shared-history','shared-adopt-task','shared-project') command;
grant select on shared_adoption_fixture to authenticated;
-- Simulate work that reached collaboration sync before the live adoption.
select private.pomodoist_shared_apply('fb000000-0000-4000-8000-000000000023','fb000000-0000-4000-8000-000000000003','member',jsonb_build_object('entityType','focus_interval','entityId','shared-history-work-1','operation','upsert','opId','already-offline-work','baseRevision',(select revision from private.pomodoist_scopes where id='fb000000-0000-4000-8000-000000000023'),'clientUpdatedAt',command#>'{payload,adopt,intervals,0,completedAt}','payload',(command#>'{payload,adopt,intervals,0}')||'{"durationSeconds":60}')) from shared_adoption_fixture;
set local role authenticated;
set local request.jwt.claims='{"sub":"fb000000-0000-4000-8000-000000000003","role":"authenticated","session_id":"fb000000-0000-4000-8000-000000000013"}';
set local request.jwt.claim.sub='fb000000-0000-4000-8000-000000000003';
select public.pomodoist_focus(command) from shared_adoption_fixture;
select public.pomodoist_focus(command) from shared_adoption_fixture;
reset role;
select pg_temp.check((select data->>'totalFocusSeconds'='60' and data->>'completedFocusIntervals'='1' from private.pomodoist_shared_entities where scope_id='fb000000-0000-4000-8000-000000000023' and entity_type='task' and entity_id='shared-adopt-task'),'adoption credits preexisting shared work once');
select pg_temp.check((select count(*)=1 from private.pomodoist_shared_entities where scope_id='fb000000-0000-4000-8000-000000000023' and entity_type='focus_interval'),'adoption replay does not duplicate shared contribution');
update private.pomodoist_focus_accounts set deadline=clock_timestamp()-interval '1 second',session=jsonb_set(session,'{interval,startedAt}',to_jsonb(clock_timestamp()-interval '61 seconds')) where user_id='fb000000-0000-4000-8000-000000000003';
set local role authenticated;
select public.pomodoist_focus('{"action":"read","deviceId":"adoption-desktop"}');
select public.pomodoist_focus('{"action":"read","deviceId":"adoption-desktop"}');
reset role;
select pg_temp.check((select data->>'totalFocusSeconds'='120' and data->>'completedFocusIntervals'='2' from private.pomodoist_shared_entities where scope_id='fb000000-0000-4000-8000-000000000023' and entity_type='task' and entity_id='shared-adopt-task'),'live completion adds to adopted shared history once');
select pg_temp.check((select count(*)=3 from public.sync_entities where user_id='fb000000-0000-4000-8000-000000000003' and entity_type='focus_event' and data->>'runId'='shared-history'),'shared adoption also retains personal event history');
select pg_temp.check(not has_function_privilege('authenticated','private.pomodoist_focus_adopt_history(uuid,uuid,jsonb,jsonb,jsonb,jsonb,timestamp with time zone)','EXECUTE'),'history ingestion helper is not directly callable');
-- Presets can change during an ordinary offline run. The existing interval
-- retains its old duration; earlier completions retain their original policy.
select private.pomodoist_focus_project('fb000000-0000-4000-8000-000000000004','task','variable-task','{"id":"variable-task","content":"Variable presets","status":"open","projectId":"inbox"}');
set local role authenticated;
set local request.jwt.claims='{"sub":"fb000000-0000-4000-8000-000000000004","role":"authenticated","session_id":"fb000000-0000-4000-8000-000000000014"}';
set local request.jwt.claim.sub='fb000000-0000-4000-8000-000000000004';
create temp table variable_adoption_fixture as with source as (select clock_timestamp() t), base as (
 select t,jsonb_build_object('runId','variable-run','taskId','variable-task','projectId','inbox','pausedAt',null,'pausedTotalSeconds',0,'stoppedAt',null,'isDeleted',false) b from source
), history as (
 select t,b,jsonb_build_array(
  b||jsonb_build_object('id','variable-work-1','type','work','status','completed','plannedSeconds',120,'pausedTotalSeconds',10,'sequenceNumber',1,'startedAt',t-interval '3000 seconds','completedAt',t-interval '2960 seconds','createdAt',t-interval '3000 seconds','updatedAt',t-interval '2960 seconds'),
  b||jsonb_build_object('id','variable-break-1','type','shortBreak','status','completed','plannedSeconds',300,'sequenceNumber',2,'startedAt',t-interval '2960 seconds','completedAt',t-interval '2940 seconds','createdAt',t-interval '2960 seconds','updatedAt',t-interval '2940 seconds'),
  b||jsonb_build_object('id','variable-work-2','type','work','status','completed','plannedSeconds',900,'sequenceNumber',3,'startedAt',t-interval '2940 seconds','completedAt',t-interval '2880 seconds','createdAt',t-interval '2940 seconds','updatedAt',t-interval '2880 seconds'),
  b||jsonb_build_object('id','variable-break-2','type','longBreak','status','completed','plannedSeconds',600,'sequenceNumber',4,'startedAt',t-interval '2880 seconds','completedAt',t-interval '2840 seconds','createdAt',t-interval '2880 seconds','updatedAt',t-interval '2840 seconds')) intervals from base
)
select jsonb_build_object('action','start','deviceId','variable-desktop','requestId','variable-adoption','expectedRevision',0,'payload',jsonb_build_object(
 'preset',jsonb_build_object('id','strict-new','workSeconds',2700,'shortBreakSeconds',300,'longBreakSeconds',900,'intervalsBeforeLongBreak',3,'strictMode',true,'allowPause',false),
 'adopt',jsonb_build_object(
  'run',jsonb_build_object('id','variable-run','userId','local-user','taskId','variable-task','projectId','inbox','presetId','strict-new','status','active','startedAt',t-interval '3000 seconds','targetWorkIntervals',4,'completedWorkIntervals',2,'createdAt',t-interval '3000 seconds','updatedAt',t-interval '300 seconds','isDeleted',false),
  'interval',b||jsonb_build_object('id','variable-current','type','work','status','running','plannedSeconds',1500,'sequenceNumber',5,'startedAt',t-interval '300 seconds','completedAt',null,'createdAt',t-interval '2840 seconds','updatedAt',t-interval '300 seconds'),
  'intervals',intervals,'events','[]'::jsonb))) command from history;
create temp table variable_adoption_response as select public.pomodoist_focus(command) response from variable_adoption_fixture;
select pg_temp.check(response#>>'{session,interval,plannedSeconds}'='1500' and response#>>'{session,preset,workSeconds}'='2700','preset adoption preserves current interval duration from its earlier preset') from variable_adoption_response;
select pg_temp.check((response#>>'{session,protectionExpiresAt}')::timestamptz between clock_timestamp()+interval '1199 seconds' and clock_timestamp()+interval '1201 seconds','preset adoption preserves elapsed time instead of restarting current work') from variable_adoption_response;
select pg_temp.check((select count(*)=4 from public.sync_entities where user_id=auth.uid() and entity_type='focus_interval' and data->>'runId'='variable-run' and data->>'status'='completed'),'all historical durations and short or long break choices survive preset changes');
select pg_temp.check((select data->>'totalFocusSeconds'='90' and data->>'completedFocusIntervals'='2' from public.sync_entities where user_id=auth.uid() and entity_type='task' and entity_id='variable-task'),'earlier ordinary completions retain actual duration and pause accounting after switching to strict');
select pg_temp.check(public.pomodoist_focus('{"action":"complete","requestId":"variable-early-complete","deviceId":"variable-desktop","expectedRevision":1}')->>'code'='strict_exit_required','new strict policy still protects ongoing adopted work');
reset role;
update private.pomodoist_focus_accounts set deadline=clock_timestamp()-interval '1 second',session=jsonb_set(session,'{interval,startedAt}',to_jsonb(clock_timestamp()-interval '1501 seconds')) where user_id='fb000000-0000-4000-8000-000000000004';
set local role authenticated;
update variable_adoption_response set response=public.pomodoist_focus('{"action":"read","deviceId":"variable-desktop"}');
select pg_temp.check(response#>>'{session,interval,type}'='longBreak' and response#>>'{session,interval,plannedSeconds}'='900','next interval uses the newly selected preset duration and cadence') from variable_adoption_response;
select pg_temp.check((select data->>'totalFocusSeconds'='1590' and data->>'completedFocusIntervals'='3' from public.sync_entities where user_id=auth.uid() and entity_type='task' and entity_id='variable-task'),'live completion credits the original 1500-second interval once');
select * from finish();
rollback;

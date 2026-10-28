begin;
\ir hosted-mode.inc
select no_plan();
insert into auth.users(id,email,aud,role,created_at,updated_at) values
 ('fb000000-0000-4000-8000-000000000001','focus-pause@example.test','authenticated','authenticated',now(),now());
insert into auth.sessions(id,user_id,created_at,updated_at) values
 ('fb000000-0000-4000-8000-000000000011','fb000000-0000-4000-8000-000000000001',now(),now());
insert into private.pomodoist_scopes(id,root_project_id,owner_id) values
 ('fb000000-0000-4000-8000-000000000021','pause-project','fb000000-0000-4000-8000-000000000001');
insert into private.pomodoist_members(scope_id,user_id,role) values
 ('fb000000-0000-4000-8000-000000000021','fb000000-0000-4000-8000-000000000001','administrator');
select private.pomodoist_shared_put('fb000000-0000-4000-8000-000000000021','project','pause-project','{"id":"pause-project","name":"Pause project"}');
set local request.jwt.claims='{"sub":"fb000000-0000-4000-8000-000000000001","session_id":"fb000000-0000-4000-8000-000000000011","role":"authenticated"}';

create function pg_temp.pause_case(label text,action text,shared boolean,strict boolean default false) returns setof text language plpgsql as $$
declare actor uuid:=auth.uid(); scope uuid:='fb000000-0000-4000-8000-000000000021'; result jsonb; terminal jsonb; interval_id text; paused_at timestamptz; ended_at timestamptz; credited integer; rev bigint; fixture_time timestamptz;
begin
 if shared then
  perform private.pomodoist_shared_put(scope,'task',label,jsonb_build_object('id',label,'content',label,'status','open','projectId','pause-project'));
 else
  perform private.pomodoist_focus_project(actor,'task',label,jsonb_build_object('id',label,'content',label,'status','open','completedFocusIntervals',0,'totalFocusSeconds',0));
 end if;
 select coalesce(revision,0) into rev from private.pomodoist_focus_accounts where user_id=actor;
 result:=public.pomodoist_focus(jsonb_build_object('action','start','deviceId','pause-test','requestId',label||'-start','expectedRevision',coalesce(rev,0),'payload',jsonb_build_object('taskId',label,'strictExitSeconds',60,'preset',jsonb_build_object('id','classic','workSeconds',1500,'shortBreakSeconds',60,'longBreakSeconds',120,'intervalsBeforeLongBreak',2,'strictMode',strict,'allowPause',true))));
 interval_id:=result->'session'->'interval'->>'id';
 result:=public.pomodoist_focus(jsonb_build_object('action','pause','deviceId','pause-test','requestId',label||'-pause','expectedRevision',(result->'session'->>'revision')::bigint));
 fixture_time:=clock_timestamp(); paused_at:=fixture_time-interval '600 seconds';
 update private.pomodoist_focus_accounts set session=jsonb_set(jsonb_set(jsonb_set(session,'{interval,startedAt}',to_jsonb(fixture_time-interval '990 seconds')),'{interval,pausedAt}',to_jsonb(paused_at)),'{interval,pausedTotalSeconds}','90') where user_id=actor;
 result:=public.pomodoist_focus(jsonb_build_object('action',action,'deviceId','pause-test','requestId',label||'-finish','expectedRevision',(result->'session'->>'revision')::bigint));
 if strict then
  update private.pomodoist_focus_accounts set session=jsonb_set(session,'{exitRequestedAt}',to_jsonb(fixture_time-interval '61 seconds')) where user_id=actor;
  result:=public.pomodoist_focus('{"action":"read","deviceId":"pause-test"}');
 end if;
 select data into terminal from public.sync_entities where user_id=actor and entity_type='focus_interval' and entity_id=interval_id;
 ended_at:=coalesce(terminal->>'completedAt',terminal->>'stoppedAt')::timestamptz;
 return next is(terminal->>'status',case action when 'complete' then 'completed' when 'skip' then 'skipped' else 'stopped' end,label||': terminal status');
 return next is(terminal->'pausedAt','null'::jsonb,label||': terminal history has no open pause');
 return next is((terminal->>'pausedTotalSeconds')::integer,90+greatest(0,floor(extract(epoch from (ended_at-paused_at))))::integer,label||': existing and open pauses are counted once');
 if shared then
  select (data->>'totalFocusSeconds')::integer into credited from private.pomodoist_shared_entities where scope_id=scope and entity_type='task' and entity_id=label;
 else
  select (data->>'totalFocusSeconds')::integer into credited from public.sync_entities where user_id=actor and entity_type='task' and entity_id=label;
 end if;
 return next is(coalesce(credited,0),case action when 'complete' then 300 else 0 end,label||': task credit excludes all pause time');
 if action='complete' and shared then
  return next is((select (data->>'durationSeconds')::integer from private.pomodoist_shared_entities where scope_id=scope and entity_type='focus_interval' and entity_id=interval_id),300,label||': shared contribution excludes pause time');
 end if;
 if action in ('complete','skip') then
  perform public.pomodoist_focus(jsonb_build_object('action','requestStop','deviceId','pause-test','requestId',label||'-cleanup','expectedRevision',(result->'session'->>'revision')::bigint));
 end if;
end $$;
select * from pg_temp.pause_case('personal-complete','complete',false);
select * from pg_temp.pause_case('shared-complete','complete',true);
select * from pg_temp.pause_case('personal-skip','skip',false);
select * from pg_temp.pause_case('personal-stop','requestStop',false);
select * from pg_temp.pause_case('strict-stop','requestStop',false,true);
select * from finish();
rollback;

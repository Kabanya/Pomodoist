begin;
\ir hosted-mode.inc
select no_plan();
insert into auth.users(id,email,aud,role,created_at,updated_at) values
 ('fc000000-0000-4000-8000-000000000001','focus-ready@example.test','authenticated','authenticated',now(),now());
insert into auth.sessions(id,user_id,created_at,updated_at) values
 ('fc000000-0000-4000-8000-000000000011','fc000000-0000-4000-8000-000000000001',now(),now());
select private.pomodoist_focus_project('fc000000-0000-4000-8000-000000000001','task','ready-task','{"id":"ready-task","content":"Ready task","status":"open","projectId":"inbox"}');
set local role authenticated;
set local request.jwt.claims='{"sub":"fc000000-0000-4000-8000-000000000001","session_id":"fc000000-0000-4000-8000-000000000011","role":"authenticated"}';
select public.pomodoist_focus('{"action":"start","requestId":"start","deviceId":"desktop","expectedRevision":0,"payload":{"taskId":"ready-task","preset":{"id":"classic","workSeconds":1500,"shortBreakSeconds":60,"longBreakSeconds":120,"intervalsBeforeLongBreak":2,"strictMode":false},"targetWorkIntervals":2}}');
select public.pomodoist_focus('{"action":"complete","requestId":"first-work","deviceId":"desktop","expectedRevision":1}');
select is(public.pomodoist_focus('{"action":"complete","requestId":"unstarted-break","deviceId":"desktop","expectedRevision":2}')->>'code','invalid_focus_transition','an unstarted break cannot be completed');
select public.pomodoist_focus('{"action":"skip","requestId":"skip-break","deviceId":"desktop","expectedRevision":2}');
reset role;
update private.pomodoist_focus_accounts set session=jsonb_set(session,'{interval,startedAt}',to_jsonb(clock_timestamp()-interval '10 minutes')) where user_id='fc000000-0000-4000-8000-000000000001';
create temp table before_ready as select session,revision from private.pomodoist_focus_accounts where user_id='fc000000-0000-4000-8000-000000000001';
create temp table before_history as select jsonb_agg(to_jsonb(e) order by entity_type,entity_id) data from public.sync_entities e where user_id='fc000000-0000-4000-8000-000000000001';
set local role authenticated;
select is(public.pomodoist_focus('{"action":"complete","requestId":"unstarted-work","deviceId":"desktop","expectedRevision":3}')->>'code','invalid_focus_transition','waiting for ten minutes cannot count as work');
reset role;
select is(a.session,b.session,'rejected completion preserves the ready interval and progress') from private.pomodoist_focus_accounts a,before_ready b where a.user_id='fc000000-0000-4000-8000-000000000001';
select is(a.revision,b.revision,'rejected completion preserves the revision') from private.pomodoist_focus_accounts a,before_ready b where a.user_id='fc000000-0000-4000-8000-000000000001';
select is((select jsonb_agg(to_jsonb(e) order by entity_type,entity_id) from public.sync_entities e where user_id='fc000000-0000-4000-8000-000000000001'),data,'rejected completion preserves history and task totals') from before_history;
set local role authenticated;
select is(public.pomodoist_focus('{"action":"startReady","requestId":"start-ready","deviceId":"desktop","expectedRevision":3}')->'session'->'interval'->>'status','running','the ready interval can still be started');
reset role;
update private.pomodoist_focus_accounts set session=jsonb_set(session,'{interval,startedAt}',to_jsonb(clock_timestamp()-interval '120 seconds')) where user_id='fc000000-0000-4000-8000-000000000001';
set local role authenticated;
select public.pomodoist_focus('{"action":"complete","requestId":"started-work","deviceId":"desktop","expectedRevision":4}');
select is((select data->>'totalFocusSeconds' from public.sync_entities where user_id=auth.uid() and entity_type='task' and entity_id='ready-task'),'120','only time after startReady is credited');
select * from finish();
rollback;

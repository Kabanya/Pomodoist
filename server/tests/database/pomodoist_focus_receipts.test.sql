begin;
\ir hosted-mode.inc
select no_plan();

insert into auth.users(id,email,aud,role,created_at,updated_at)
values ('fd000000-0000-4000-8000-000000000001','focus-receipts@example.test','authenticated','authenticated',now(),now());
insert into auth.sessions(id,user_id,created_at,updated_at)
values ('fd000000-0000-4000-8000-000000000011','fd000000-0000-4000-8000-000000000001',now(),now());
set local role authenticated;
set local request.jwt.claims='{"sub":"fd000000-0000-4000-8000-000000000001","session_id":"fd000000-0000-4000-8000-000000000011","role":"authenticated"}';
select public.pomodoist_focus('{"action":"read","deviceId":"desktop"}');
select public.pomodoist_focus('{"action":"registerDevice","deviceId":"desktop","requestId":"heartbeat","payload":{"platform":"macos"}}');
reset role;
select is((select count(*) from private.pomodoist_focus_requests where user_id='fd000000-0000-4000-8000-000000000001'),0::bigint,'heartbeats never create replay receipts');
select ok(exists(select 1 from private.pomodoist_focus_devices where user_id='fd000000-0000-4000-8000-000000000001' and device_id='desktop' and platform='macos'),'heartbeat still updates device metadata');

set local role authenticated;
select public.pomodoist_focus('{"action":"start","deviceId":"desktop","requestId":"start","expectedRevision":0,"payload":{"preset":{"id":"classic","workSeconds":1500,"shortBreakSeconds":60,"longBreakSeconds":120,"intervalsBeforeLongBreak":2}}}');
-- A second device must not lose its replay window to activity on the first.
select public.pomodoist_focus('{"action":"pause","deviceId":"browser","requestId":"browser-pause","expectedRevision":1}');
select public.pomodoist_focus('{"action":"resume","deviceId":"desktop","requestId":"resume","expectedRevision":2}');
select public.pomodoist_focus(jsonb_build_object('action','profileUpsert','deviceId','desktop','requestId','profile-'||n,'expectedSettingsRevision',n,'payload',jsonb_build_object('profile',jsonb_build_object('id','custom','name','Profile '||n,'blockedCategories','[]'::jsonb,'overrides','[]'::jsonb)))) from generate_series(1,8) n;
reset role;
select is((select count(*) from private.pomodoist_focus_requests where user_id='fd000000-0000-4000-8000-000000000001' and command->>'deviceId'='desktop'),5::bigint,'only five responses remain for an active device');
select ok(not exists(select 1 from private.pomodoist_focus_requests where user_id='fd000000-0000-4000-8000-000000000001' and request_id in ('start','resume','profile-1','profile-2','profile-3')),'the oldest responses are evicted first');
select is((select count(*) from private.pomodoist_focus_requests where user_id='fd000000-0000-4000-8000-000000000001' and command->>'deviceId'='browser'),1::bigint,'another device retains its own replay window');
set local role authenticated;
select is(public.pomodoist_focus('{"action":"pause","deviceId":"browser","requestId":"browser-pause","expectedRevision":1}')->'session'->>'revision','2','another device can replay its original response');
select is(public.pomodoist_focus('{"action":"start","deviceId":"desktop","requestId":"start","expectedRevision":0,"payload":{"preset":{"id":"classic","workSeconds":1500,"shortBreakSeconds":60,"longBreakSeconds":120,"intervalsBeforeLongBreak":2}}}')->>'code','revision_conflict','an evicted timer command cannot execute again');
select is(public.pomodoist_focus('{"action":"profileUpsert","deviceId":"desktop","requestId":"profile-1","expectedSettingsRevision":1,"payload":{"profile":{"id":"custom","name":"Profile 1","blockedCategories":[],"overrides":[]}}}')->>'code','revision_conflict','an evicted settings command cannot overwrite newer settings');
select is((select p->>'name' from jsonb_array_elements(public.pomodoist_focus('{"action":"read","deviceId":"desktop"}')->'profiles') p where p->>'id'='custom'),'Profile 8','stale replay preserves the newest profile');
select is(public.pomodoist_focus('{"action":"profileUpsert","deviceId":"desktop","requestId":"legacy-settings","payload":{"profile":{"id":"custom","name":"Legacy overwrite","blockedCategories":[],"overrides":[]}}}')->>'code','revision_conflict','unversioned legacy settings cannot bypass replay protection');
reset role;

-- The newest surviving success still returns its original response exactly.
create temp table last_receipt as select command,response from private.pomodoist_focus_requests where user_id='fd000000-0000-4000-8000-000000000001' and request_id='profile-8';
grant select on last_receipt to authenticated;
set local role authenticated;
select is(public.pomodoist_focus(command),response,'a retained settings command replays exactly') from last_receipt;
select is(public.pomodoist_focus('{"action":"read","deviceId":"desktop"}')->>'settingsRevision','9','replay never increments the settings revision');
reset role;
select is((select count(*) from private.pomodoist_focus_requests where user_id='fd000000-0000-4000-8000-000000000001' and command->>'deviceId'='desktop'),5::bigint,'conflicts also respect the five-response bound');
select * from finish();
rollback;

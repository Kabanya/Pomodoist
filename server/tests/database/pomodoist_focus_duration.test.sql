begin;
\ir hosted-mode.inc
select no_plan();
insert into auth.users(id,email,aud,role,created_at,updated_at) values
 ('fd000000-0000-4000-8000-000000000001','focus-duration@example.test','authenticated','authenticated',now(),now());
insert into auth.sessions(id,user_id,created_at,updated_at) values
 ('fd000000-0000-4000-8000-000000000011','fd000000-0000-4000-8000-000000000001',now(),now());

set local role authenticated;
set local request.jwt.claims='{"sub":"fd000000-0000-4000-8000-000000000001","session_id":"fd000000-0000-4000-8000-000000000011","role":"authenticated"}';
create temp table original as
select public.pomodoist_focus('{"action":"start","requestId":"start","deviceId":"desktop","expectedRevision":0,"payload":{"preset":{"id":"classic","workSeconds":1500,"shortBreakSeconds":300,"longBreakSeconds":900,"intervalsBeforeLongBreak":4,"strictMode":false,"allowPause":true}}}')->'session' as s;
create function pg_temp.adjust(request text, revision int, delta int, interval_id text)
returns jsonb language sql as $$
 select public.pomodoist_focus(jsonb_build_object('action','adjustDuration','requestId',request,
   'deviceId','desktop','expectedRevision',revision,
   'payload',jsonb_build_object('intervalId',interval_id,'deltaSeconds',delta)))
$$;
create temp table adjusted as
select pg_temp.adjust('extend',1,300,s#>>'{interval,id}')->'session' as s from original;
select is(a.s#>>'{interval,plannedSeconds}','1800','extension updates the current plan') from adjusted a;
select is(a.s#>>'{interval,startedAt}',o.s#>>'{interval,startedAt}','extension keeps the original start') from adjusted a,original o;
select is((a.s->>'protectionExpiresAt')::timestamptz-(o.s->>'protectionExpiresAt')::timestamptz,
 interval '5 minutes','the running deadline shifts by five minutes') from adjusted a,original o;
select is(a.s->'preset',o.s->'preset','future intervals keep the original preset') from adjusted a,original o;
select is(pg_temp.adjust('extend',1,300,o.s#>>'{interval,id}')->'session',a.s,'retried requests do not add time twice') from adjusted a,original o;
select is(pg_temp.adjust('stale',2,-300,'old-interval')->>'code','revision_conflict','a stale interval cannot change the current plan');
select is(pg_temp.adjust('invalid',2,301,s#>>'{interval,id}')->>'code','invalid_focus_duration','only five-minute adjustments are accepted') from original;
select is((select data->>'plannedSeconds' from public.sync_entities
 where user_id=auth.uid() and entity_type='focus_interval' and entity_id=s#>>'{interval,id}'),
 '1800','adjusted interval is projected to sync') from original;

select public.pomodoist_focus('{"action":"pause","requestId":"pause","deviceId":"desktop","expectedRevision":2}');
select is(pg_temp.adjust('shorten-paused',3,-300,s#>>'{interval,id}')#>>'{session,interval,status}',
 'paused','shortening preserves pause') from original;
select is(public.pomodoist_focus('{"action":"resume","requestId":"resume","deviceId":"desktop","expectedRevision":4}')#>>'{session,interval,plannedSeconds}',
 '1500','resume uses the shortened plan');

select public.pomodoist_focus('{"action":"changePreset","requestId":"strict","deviceId":"desktop","expectedRevision":5,"payload":{"preset":{"id":"strict","workSeconds":1500,"shortBreakSeconds":300,"longBreakSeconds":900,"intervalsBeforeLongBreak":4,"strictMode":true}}}');
select is(pg_temp.adjust('strict-shortening',6,-300,s#>>'{interval,id}')->>'code',
 'strict_exit_required','strict mode cannot be shortened') from original;
select is(pg_temp.adjust('strict-extension',6,300,s#>>'{interval,id}')#>>'{session,interval,plannedSeconds}',
 '1800','strict mode can be extended') from original;
select * from finish();
rollback;

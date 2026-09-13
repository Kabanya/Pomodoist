begin;
select no_plan();

insert into auth.users (id, email, aud, role, created_at, updated_at)
values ('af000000-0000-4000-8000-000000000001', 'voice-quota@example.test', 'authenticated', 'authenticated', now(), now());
update public.quota_definitions set limit_value = 1
where app_id = 'pomodoist' and quota_key = 'voice_transcriptions';

select is(public.pomodoist_voice_quota('af000000-0000-4000-8000-000000000001', 'af000000-0000-4000-8000-000000000011', 'reserve')->>'allowed', 'true', 'first request reserves the last slot');
select is(public.pomodoist_voice_quota('af000000-0000-4000-8000-000000000001', 'af000000-0000-4000-8000-000000000011', 'reserve')->>'allowed', 'true', 'reservation retry uses the same slot');
select is(public.pomodoist_voice_quota('af000000-0000-4000-8000-000000000001', 'af000000-0000-4000-8000-000000000012', 'reserve')->>'allowed', 'false', 'in-flight requests count toward the limit');
select is((select used from public.usage_periods where user_id='af000000-0000-4000-8000-000000000001'), 0, 'reservation does not charge a failed attempt');
select public.pomodoist_voice_quota('af000000-0000-4000-8000-000000000001', 'af000000-0000-4000-8000-000000000011', 'release');
select is(public.pomodoist_voice_quota('af000000-0000-4000-8000-000000000001', 'af000000-0000-4000-8000-000000000012', 'reserve')->>'allowed', 'true', 'provider failure frees the slot');
select public.pomodoist_voice_quota('af000000-0000-4000-8000-000000000001', 'af000000-0000-4000-8000-000000000012', 'complete');
select public.pomodoist_voice_quota('af000000-0000-4000-8000-000000000001', 'af000000-0000-4000-8000-000000000012', 'complete');
select public.pomodoist_voice_quota('af000000-0000-4000-8000-000000000001', 'af000000-0000-4000-8000-000000000012', 'release');
select is((select used from public.usage_periods where user_id='af000000-0000-4000-8000-000000000001'), 1, 'completion is idempotent and release cannot refund success');
select is(public.pomodoist_voice_quota('af000000-0000-4000-8000-000000000001', 'af000000-0000-4000-8000-000000000013', 'reserve')->>'allowed', 'false', 'successful recognition consumes the monthly slot');

update public.usage_periods set used=0 where user_id='af000000-0000-4000-8000-000000000001';
select public.pomodoist_voice_quota('af000000-0000-4000-8000-000000000001', 'af000000-0000-4000-8000-000000000014', 'reserve');
update private.pomodoist_voice_requests set expires_at=now()-interval '1 second' where request_id='af000000-0000-4000-8000-000000000014';
select is(public.pomodoist_voice_quota('af000000-0000-4000-8000-000000000001', 'af000000-0000-4000-8000-000000000015', 'reserve')->>'allowed', 'true', 'crashed requests expire without charging quota');
select is((select period_start from public.usage_periods where user_id='af000000-0000-4000-8000-000000000001'), date_trunc('month', now(), 'UTC'), 'period comes from the server UTC calendar');

select ok(not has_function_privilege('anon', 'public.pomodoist_voice_quota(uuid,uuid,text)', 'EXECUTE') and not has_function_privilege('authenticated', 'public.pomodoist_voice_quota(uuid,uuid,text)', 'EXECUTE'), 'only the backend can reserve or settle voice quota');
select ok(not has_table_privilege('authenticated', 'private.pomodoist_voice_requests', 'SELECT'), 'request receipts are private');
set local role authenticated;
set local request.jwt.claims = '{"sub":"af000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local request.jwt.claim.sub = 'af000000-0000-4000-8000-000000000001';
select throws_ok($$select public.consume_quota('pomodoist','voice_transcriptions',1,now()+interval '1 day',now()+interval '2 days')$$, '42501', 'Voice quota is managed by the transcription endpoint', 'client-supplied periods cannot create a separate voice counter');
reset role;

-- The retained generic SDK contract also rejects invented billing periods.
insert into public.quota_definitions(app_id,quota_key,limit_value) values ('pomodoist','quota_test',2);
set local role authenticated;
select is(public.consume_quota('pomodoist','quota_test',1,now()+interval '1 day',now()+interval '2 days')->>'used', '1', 'first generic charge uses server month');
select is(public.consume_quota('pomodoist','quota_test',1,now()+interval '3 days',now()+interval '4 days')->>'used', '2', 'changing dates uses the same counter');
select is(public.consume_quota('pomodoist','quota_test',1)->>'allowed', 'false', 'generic quota stops at its limit');
select throws_ok($$select public.consume_quota('pomodoist','quota_test',0)$$, '22023', 'Quota units must be positive', 'zero units are rejected');
reset role;
select throws_ok($$select public.pomodoist_voice_quota(null,'af000000-0000-4000-8000-000000000015','complete')$$, '22023', 'Invalid voice quota request', 'missing identity is rejected');
select throws_ok($$select public.pomodoist_voice_quota('af000000-0000-4000-8000-000000000002','af000000-0000-4000-8000-000000000015','complete')$$, '22023', 'Voice reservation expired or missing', 'a receipt cannot be completed for another user');

-- Completion belongs to the reservation month, even across UTC rollover.
update public.usage_periods set period_start=period_start-interval '1 month', period_end=period_start
where user_id='af000000-0000-4000-8000-000000000001' and quota_key='voice_transcriptions';
select public.pomodoist_voice_quota('af000000-0000-4000-8000-000000000001','af000000-0000-4000-8000-000000000015','complete');
select is((select used from public.usage_periods where user_id='af000000-0000-4000-8000-000000000001' and quota_key='voice_transcriptions'), 1, 'rollover completes the original period');
select is(public.pomodoist_voice_quota('af000000-0000-4000-8000-000000000001','af000000-0000-4000-8000-000000000016','reserve')->>'allowed', 'true', 'new month has a fresh allowance');

select * from finish();
rollback;

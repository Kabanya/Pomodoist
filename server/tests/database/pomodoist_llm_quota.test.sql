begin;
select no_plan();

insert into auth.users (id,email,aud,role,created_at,updated_at)
values ('ae000000-0000-4000-8000-000000000001','llm-quota@example.test','authenticated','authenticated',now(),now());
select is((select limit_value from public.quota_definitions where app_id='pomodoist' and quota_key='voice_transcriptions'),1000,'STT default is 1000');
select is((select limit_value from public.quota_definitions where app_id='pomodoist' and quota_key='llm_requests'),1000,'LLM default is 1000');
select public.pomodoist_llm_quota('ae000000-0000-4000-8000-000000000001',null,'ae000000-0000-4000-8000-000000000011','reserve');
select public.pomodoist_llm_quota('ae000000-0000-4000-8000-000000000001',null,'ae000000-0000-4000-8000-000000000011','release');
update public.usage_periods set used=999 where user_id='ae000000-0000-4000-8000-000000000001' and quota_key='llm_requests';
select is(public.pomodoist_llm_quota('ae000000-0000-4000-8000-000000000001',null,'ae000000-0000-4000-8000-000000000011','reserve')->>'allowed','true','1000th analysis can reserve');
select is(public.pomodoist_llm_quota('ae000000-0000-4000-8000-000000000001',null,'ae000000-0000-4000-8000-000000000011','reserve')->>'allowed','true','reservation retries are idempotent');
select is(public.pomodoist_llm_quota('ae000000-0000-4000-8000-000000000001',null,'ae000000-0000-4000-8000-000000000012','reserve')->>'allowed','false','pending 1000th slot blocks another request');
select public.pomodoist_llm_quota('ae000000-0000-4000-8000-000000000001',null,'ae000000-0000-4000-8000-000000000011','complete');
select public.pomodoist_llm_quota('ae000000-0000-4000-8000-000000000001',null,'ae000000-0000-4000-8000-000000000011','complete');
select public.pomodoist_llm_quota('ae000000-0000-4000-8000-000000000001',null,'ae000000-0000-4000-8000-000000000011','release');
select is((select used from public.usage_periods where user_id='ae000000-0000-4000-8000-000000000001' and quota_key='llm_requests'),1000,'completion charges once and cannot be refunded');
select is(public.pomodoist_llm_quota('ae000000-0000-4000-8000-000000000001',null,'ae000000-0000-4000-8000-000000000012','reserve')->>'allowed','false','1001st analysis is blocked');
select is(public.pomodoist_voice_quota('ae000000-0000-4000-8000-000000000001','ae000000-0000-4000-8000-000000000013','reserve')->>'allowed','true','STT counter is independent');

select public.pomodoist_llm_quota(null,'apple:Production:quota-test-original','ae000000-0000-4000-8000-000000000021','reserve');
select public.pomodoist_llm_quota(null,'apple:Production:quota-test-original','ae000000-0000-4000-8000-000000000021','release');
update public.usage_periods set used=999 where purchase_subject='apple:Production:quota-test-original';
select is(public.pomodoist_llm_quota(null,'apple:Production:quota-test-original','ae000000-0000-4000-8000-000000000022','reserve')->>'allowed','true','guest purchase can reserve its last slot');
select is(public.pomodoist_llm_quota(null,'apple:Production:quota-test-original','ae000000-0000-4000-8000-000000000023','reserve')->>'allowed','false','same purchase on another device shares the limit');
update private.pomodoist_voice_requests set expires_at=now()-interval '1 second' where request_id='ae000000-0000-4000-8000-000000000022';
select is(public.pomodoist_llm_quota(null,'apple:Production:quota-test-original','ae000000-0000-4000-8000-000000000023','reserve')->>'allowed','true','expired reservation frees the slot');
select throws_ok($$select public.pomodoist_llm_quota(null,'apple:Production:other','ae000000-0000-4000-8000-000000000023','complete')$$,'22023','LLM reservation expired or missing','another purchase cannot complete a receipt');
select throws_ok($$select public.pomodoist_llm_quota(null,null,gen_random_uuid(),'reserve')$$,'22023','Invalid LLM quota request','missing identity rejected');
select throws_ok($$select public.pomodoist_llm_quota('ae000000-0000-4000-8000-000000000001','apple:Production:other',gen_random_uuid(),'reserve')$$,'22023','Invalid LLM quota request','ambiguous identity rejected');
select throws_ok($$select public.pomodoist_llm_quota(null,'arbitrary-device-id',gen_random_uuid(),'reserve')$$,'22023','Invalid LLM quota request','invalid purchase identity rejected');

select ok(not has_function_privilege('anon','public.pomodoist_llm_quota(uuid,text,uuid,text)','EXECUTE') and not has_function_privilege('authenticated','public.pomodoist_llm_quota(uuid,text,uuid,text)','EXECUTE'),'LLM accounting is service-only');
set local role authenticated;
set local request.jwt.claims='{"sub":"ae000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local request.jwt.claim.sub='ae000000-0000-4000-8000-000000000001';
select is((select count(*) from public.usage_periods where purchase_subject is not null),0::bigint,'RLS hides guest purchase rows');
select throws_ok($$select public.consume_quota('pomodoist','llm_requests',1)$$,'42501','LLM quota is managed by the task analysis endpoint','legacy SDK cannot charge LLM');
reset role;

update public.usage_periods set period_start=period_start-interval '1 month',period_end=period_start where purchase_subject='apple:Production:quota-test-original';
select public.pomodoist_llm_quota(null,'apple:Production:quota-test-original','ae000000-0000-4000-8000-000000000023','complete');
select is((select used from public.usage_periods where purchase_subject='apple:Production:quota-test-original'),1000,'completion across month rollover charges the original month');
select is(public.pomodoist_llm_quota(null,'apple:Production:quota-test-original','ae000000-0000-4000-8000-000000000024','reserve')->>'allowed','true','new UTC month gets a fresh limit');
select is((select count(*) from public.usage_periods where purchase_subject='apple:Production:quota-test-original'),2::bigint,'month history remains available');

select * from finish();
rollback;

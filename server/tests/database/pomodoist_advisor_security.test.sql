begin;
select no_plan();

select is(count(*), 7::bigint, 'all seven public RPCs are invokers with authenticated/service access only')
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in
  ('ensure_profile','get_account_overview','get_apple_app_account_token','get_usage_period','consume_quota','push_changes','pull_changes')
  and not p.prosecdef and not has_function_privilege('anon',p.oid,'EXECUTE')
  and has_function_privilege('authenticated',p.oid,'EXECUTE')
  and has_function_privilege('service_role',p.oid,'EXECUTE');
select is(count(*), 7::bigint, 'only seven private RPCs are executable by authenticated')
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='private' and has_function_privilege('authenticated',p.oid,'EXECUTE');
select ok(not exists (
  select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='private' and c.relkind='r'
    and (has_table_privilege('authenticated',c.oid,'SELECT,INSERT,UPDATE,DELETE')
      or has_table_privilege('anon',c.oid,'SELECT,INSERT,UPDATE,DELETE'))
), 'private tables remain inaccessible');
select ok(not has_schema_privilege('anon','private','USAGE'), 'anon cannot resolve private objects');
select is(count(*), 8::bigint, 'private RPCs and timestamp trigger have fixed empty search paths')
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where ((n.nspname='private' and p.proname in
  ('ensure_profile','get_account_overview','get_apple_app_account_token','get_usage_period','consume_quota','push_changes','pull_changes'))
  or (n.nspname='public' and p.proname='touch_updated_at'))
  and p.proconfig @> array['search_path=""'];
select is(count(*), 11::bigint, 'all affected RLS policies evaluate uid through a SELECT')
from pg_policies where schemaname='public'
  and tablename in ('profiles','user_app_installs','user_entitlements','usage_periods','sync_devices','sync_entities')
  and (qual is null or qual like '%SELECT auth.uid()%')
  and (with_check is null or with_check like '%SELECT auth.uid()%');

update private.pomodoist_instance_settings set selfhost_features_enabled=true;
insert into auth.users(id,email,aud,role,created_at,updated_at) values
  ('b0000000-0000-4000-8000-000000000001','advisor-alice@example.test','authenticated','authenticated',now(),now()),
  ('b0000000-0000-4000-8000-000000000002','advisor-bob@example.test','authenticated','authenticated',now(),now());
insert into public.usage_periods(user_id,app_id,quota_key,period_start,period_end,used,limit_value,unit)
values ('b0000000-0000-4000-8000-000000000001','pomodoist','llm_requests',date_trunc('month',now(),'UTC'),
  date_trunc('month',now(),'UTC')+interval '1 month',2,1000,'request');

set local role authenticated;
set local request.jwt.claims='{"sub":"b0000000-0000-4000-8000-000000000001","role":"authenticated"}';
select is(private.ensure_profile(),auth.uid(),'direct private profile entry remains bound to caller');
select is(public.ensure_profile(),auth.uid(),'public profile entry remains compatible');
select is(private.get_account_overview() #>> '{profile,id}',auth.uid()::text,'private overview belongs to caller');
select is(public.get_apple_app_account_token(),private.get_apple_app_account_token(),'Apple token wrapper preserves value');
select is(public.get_usage_period('pomodoist','llm_requests')->>'used','2','public usage wrapper preserves counter');
select is(private.get_usage_period('pomodoist','llm_requests')->>'used','2','private usage belongs to caller');
select throws_ok($$select private.consume_quota('pomodoist','llm_requests',1)$$,
  '42501','LLM quota is managed by the task analysis endpoint','private entry cannot bypass managed quota');
insert into public.user_app_installs(user_id,app_id,device_id,platform,app_version,updated_at)
values(auth.uid(),'pomodoist','advisor-a','ios','1.0.5','2000-01-01');
update public.user_app_installs set app_version='1.0.6' where user_id=auth.uid();
select ok((select updated_at > '2000-01-01'::timestamptz from public.user_app_installs where device_id='advisor-a'),
  'timestamp trigger still runs on direct client updates');
select throws_ok($$update public.user_app_installs set user_id='b0000000-0000-4000-8000-000000000002' where device_id='advisor-a'$$,
  '42501','new row violates row-level security policy for table "user_app_installs"','install ownership cannot be reassigned');
select lives_ok($$select private.push_changes('pomodoist','advisor-a','[{"opId":"advisor-create","entityType":"task","entityId":"advisor-task","payload":{"title":"Private"}}]')$$,
  'private push derives owner from auth.uid');
select is(jsonb_array_length(public.pull_changes('pomodoist','advisor-a')->'changes'),1,'public pull reads private push');
select is(jsonb_array_length(public.push_changes('pomodoist','advisor-a','[{"opId":"advisor-create","entityType":"task","entityId":"advisor-task","payload":{"title":"Retry"}}]')->'applied'),0,'wrapper preserves idempotence');
select throws_ok($$select private.push_changes_for_user('b0000000-0000-4000-8000-000000000002','pomodoist','forged','[]')$$,
  '42501','permission denied for function push_changes_for_user','arbitrary-owner writer stays forbidden');
select throws_ok($$select private.grant_pomodoist_selfhost_access(auth.uid())$$,
  '42501','permission denied for function grant_pomodoist_selfhost_access','schema USAGE does not grant privileged helpers');

set local request.jwt.claims='{"sub":"b0000000-0000-4000-8000-000000000002","role":"authenticated"}';
select is(private.get_account_overview() #>> '{profile,id}',auth.uid()::text,'private overview switches to second account');
select is(private.get_usage_period('pomodoist','llm_requests')->>'used','0','private reader does not expose another account usage');
select is(jsonb_array_length(private.pull_changes('pomodoist','advisor-b')->'changes'),0,'private pull cannot see another account tasks');
select is((select count(*) from public.user_app_installs),0::bigint,'RLS hides other installs');
select is((select count(*) from public.usage_periods),0::bigint,'RLS hides other usage');
select is((select count(*) from public.sync_entities),0::bigint,'RLS hides other entities');
select is((select count(*) from public.sync_devices where user_id<>auth.uid()),0::bigint,'RLS hides other sync devices');
select is((select count(*) from public.profiles),1::bigint,'RLS exposes only own profile');
select is((select count(*) from public.user_entitlements where user_id<>auth.uid()),0::bigint,'RLS hides other entitlements');
select throws_ok($$insert into public.sync_devices(user_id,app_id,device_id) values('b0000000-0000-4000-8000-000000000001','pomodoist','forged')$$,
  '42501','new row violates row-level security policy for table "sync_devices"','sync device insert enforces ownership');
select throws_ok($$update public.sync_devices set user_id='b0000000-0000-4000-8000-000000000001' where device_id='advisor-b'$$,
  '42501','new row violates row-level security policy for table "sync_devices"','sync device update enforces ownership');

set local request.jwt.claims='{"role":"authenticated"}';
select throws_ok($$select private.ensure_profile()$$,'P0001','Authentication required','private account entry rejects missing subject');
select throws_ok($$select private.push_changes('pomodoist','none','[]')$$,'P0001','Authentication required','private push rejects missing subject');
select throws_ok($$select private.pull_changes('pomodoist','none')$$,'P0001','Authentication required','private pull rejects missing subject');
set local role anon;
select throws_ok($$select public.push_changes('pomodoist','none','[]')$$,'42501','permission denied for function push_changes','anon cannot execute public push');
select throws_ok($$select public.pull_changes('pomodoist','none')$$,'42501','permission denied for function pull_changes','anon cannot execute public pull');
select throws_ok($$select private.ensure_profile()$$,'42501','permission denied for schema private','anon cannot call private entry');
reset role;
select * from finish();
rollback;

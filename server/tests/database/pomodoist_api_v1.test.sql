begin;
select no_plan();
select has_schema('api_v1');
select is((select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='api_v1'),7::bigint,'exactly seven versioned RPCs');
select ok(not has_schema_privilege('anon','api_v1','USAGE'),'anonymous role cannot access v1');
select ok(not p.prosecdef,'v1 wrapper is an invoker: '||p.proname)
from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='api_v1';
select ok(not has_function_privilege('anon',p.oid,'EXECUTE'),'anonymous execute denied: '||p.proname)
from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='api_v1';
select ok(has_function_privilege('authenticated',p.oid,'EXECUTE'),'authenticated execute granted: '||p.proname)
from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='api_v1';

insert into public.apps(id,display_name) values ('pomodoist','Pomodoist') on conflict do nothing;
insert into auth.users(id,email,aud,role,created_at,updated_at) values
('b1000000-0000-4000-8000-000000000001','api-v1-a@example.test','authenticated','authenticated',now(),now()),
('b1000000-0000-4000-8000-000000000002','api-v1-b@example.test','authenticated','authenticated',now(),now());
set local role authenticated;
set local request.jwt.claims='{"sub":"b1000000-0000-4000-8000-000000000001","role":"authenticated"}';
select is(api_v1.ensure_profile(),public.ensure_profile(),'profile identity unchanged');
select is(api_v1.get_account_overview(),public.get_account_overview(),'overview unchanged');
select is(api_v1.get_apple_app_account_token(),public.get_apple_app_account_token(),'Apple identity unchanged');
select is(api_v1.get_usage_period('pomodoist','llm_requests'),public.get_usage_period('pomodoist','llm_requests'),'quota reader defaults unchanged');
select throws_ok($$select api_v1.consume_quota('pomodoist','llm_requests',1)$$,'42501','LLM quota is managed by the task analysis endpoint','versioning cannot bypass quota authority');
select is(jsonb_array_length(api_v1.push_changes('pomodoist','v1-test','[{"opId":"v1-create","entityType":"task","entityId":"v1-task","payload":{"title":"Kept"}}]')->'applied'),1,'v1 writes one operation');
select is(jsonb_array_length(public.push_changes('pomodoist','v1-test','[{"opId":"v1-create","entityType":"task","entityId":"v1-task","payload":{"title":"Duplicate"}}]')->'applied'),0,'v0 retry deduplicates v1 receipt');
select is(jsonb_array_length(public.push_changes('pomodoist','v1-test','[{"opId":"v0-create","entityType":"task","entityId":"v0-task","payload":{"title":"Kept"}}]')->'applied'),1,'v0 still writes');
select is(jsonb_array_length(api_v1.push_changes('pomodoist','v1-test','[{"opId":"v0-create","entityType":"task","entityId":"v0-task","payload":{"title":"Duplicate"}}]')->'applied'),0,'v1 retry deduplicates v0 receipt');
select is(api_v1.pull_changes('pomodoist','v1-test'),public.pull_changes('pomodoist','v1-test'),'pull envelope and defaults unchanged');
select throws_ok($$select api_v1.push_changes('pomodoist','v1-test','{}')$$,'22023','Invalid sync batch: expected an array','invalid input still rejected');
set local request.jwt.claims='{"sub":"b1000000-0000-4000-8000-000000000002","role":"authenticated"}';
select is(jsonb_array_length(api_v1.pull_changes('pomodoist','v1-other')->'changes'),0,'other users cannot read these tasks');
select throws_ok($$select private.push_changes_for_user('b1000000-0000-4000-8000-000000000001','pomodoist','forged','[]')$$,'42501','permission denied for function push_changes_for_user','actor override remains forbidden');
reset role;
select * from finish();
rollback;

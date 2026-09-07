begin;
\ir hosted-mode.inc
select no_plan();

insert into auth.users (id,email,aud,role,created_at,updated_at) values
('11111111-1111-4111-8111-111111111111','openclaw-a@example.com','authenticated','authenticated',now(),now()),
('66666666-6666-4666-8666-666666666666','openclaw-b@example.com','authenticated','authenticated',now(),now());
insert into auth.oauth_clients (id,registration_type,redirect_uris,grant_types,client_name,client_type,token_endpoint_auth_method)
values ('22222222-2222-4222-8222-222222222222','dynamic','["http://localhost:4000/callback"]',
  '["authorization_code","refresh_token"]','OpenClaw integration test','public','none');
insert into auth.sessions (id,user_id,created_at,updated_at,not_after,oauth_client_id,scopes)
values ('33333333-3333-4333-8333-333333333333','11111111-1111-4111-8111-111111111111',now(),now(),now()+interval '1 hour',
  '22222222-2222-4222-8222-222222222222','email');

create function pg_temp.subject() returns uuid language sql as $$
select private.pomodoist_mcp_subject('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222');
$$;
create function pg_temp.action(p_id uuid, p_ops jsonb default null, p_revision bigint default null,
  p_hash text default repeat('a',64), p_name text default 'create_task') returns jsonb language sql as $$
select public.pomodoist_openclaw_action(pg_temp.subject(), '33333333-3333-4333-8333-333333333333',
  '22222222-2222-4222-8222-222222222222', p_id, p_name, p_hash, p_revision, p_ops, '{"id":"original"}');
$$;
create function pg_temp.op(p_id text, p_entity text default 'task', p_status text default 'open') returns jsonb language sql as $$
select jsonb_build_object('opId',p_id,'entityType',p_entity,'entityId',p_id,'operation','upsert',
 'payload',jsonb_build_object('schemaVersion',1,'id',p_id,'userId','local-user','content',p_id,'status',p_status),
 'clientUpdatedAt','2026-09-07T10:00:00Z');
$$;
create function pg_temp.snapshot(p_task text default null) returns jsonb language sql as $$
select public.read_pomodoist_openclaw_state(pg_temp.subject(),'33333333-3333-4333-8333-333333333333',
 '22222222-2222-4222-8222-222222222222',p_task);
$$;

select ok(has_function_privilege('service_role','public.pomodoist_openclaw_action(uuid,uuid,uuid,uuid,text,text,bigint,jsonb,jsonb)','execute')
 and not has_function_privilege('authenticated','public.pomodoist_openclaw_action(uuid,uuid,uuid,uuid,text,text,bigint,jsonb,jsonb)','execute')
 and not has_function_privilege('pomodoist_mcp','public.pomodoist_openclaw_action(uuid,uuid,uuid,uuid,text,text,bigint,jsonb,jsonb)','execute')
 and not has_function_privilege('anon','public.read_pomodoist_openclaw_state(uuid,uuid,uuid,text)','execute'), 'only service RPCs expose guarded operations');
select ok((select relrowsecurity from pg_class where oid='private.pomodoist_openclaw_receipts'::regclass), 'receipt table has RLS');
select ok(not has_table_privilege('authenticated','private.pomodoist_openclaw_receipts','select')
 and not has_table_privilege('service_role','private.pomodoist_openclaw_receipts','insert'), 'receipts cannot be forged directly by API roles');
select ok(position('pg_advisory_xact_lock' in pg_get_functiondef('private.push_changes_for_user(uuid,text,text,jsonb)'::regprocedure))
 < position('insert into public.sync_devices' in pg_get_functiondef('private.push_changes_for_user(uuid,text,text,jsonb)'::regprocedure)),
 'shared push takes account lock before any row locks');

create temporary table first_prepare as select pg_temp.action('44444444-4444-4444-8444-444444444444') as value;
select is((select value ->> 'revision' from first_prepare),'0','empty account prepare returns a lossless revision');
create temporary table first_result as select pg_temp.action('44444444-4444-4444-8444-444444444444',
 jsonb_build_array(pg_temp.op('original')), (select (value ->> 'revision')::bigint from first_prepare)) as value;
select is((select value ->> 'id' from first_result),'original','commit returns stable result');
select is((select count(*) from private.pomodoist_openclaw_receipts),1::bigint,'commit stores one durable receipt');
select is(pg_temp.action('44444444-4444-4444-8444-444444444444',jsonb_build_array(pg_temp.op('duplicate')),0),
 (select value from first_result),'concurrent/retried commit returns original result before checking stale revision');
select ok(not exists(select 1 from public.sync_entities where entity_id='duplicate'), 'replay does not create another task');
select is(pg_temp.action('44444444-4444-4444-8444-444444444444') -> 'result', (select value from first_result),
 'prepare after a lost response also returns original result');
select throws_ok($$select pg_temp.action('44444444-4444-4444-8444-444444444444',null,null,repeat('b',64))$$,
 '22023','OpenClaw request_id was reused','same ID with different arguments is rejected');

create temporary table stale_prepare as select pg_temp.action('55555555-5555-4555-8555-555555555555') as value;
set local role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
select public.push_changes('pomodoist','flutter-device',jsonb_build_array(pg_temp.op('from-device')));
reset role;
select throws_ok($$select pg_temp.action('55555555-5555-4555-8555-555555555555',jsonb_build_array(pg_temp.op('stale')),
 (select (value ->> 'revision')::bigint from stale_prepare))$$,'40001','OpenClaw snapshot changed','device changes invalidate action snapshot');
select ok(not exists(select 1 from public.sync_entities where entity_id='stale')
 and not exists(select 1 from private.pomodoist_openclaw_receipts where request_id='55555555-5555-4555-8555-555555555555'),
 'conflicting action writes neither entity nor receipt');

select throws_ok($$select pg_temp.action('77777777-7777-4777-8777-777777777777',
 jsonb_build_array(pg_temp.op('focus-a','focus_run','active'),pg_temp.op('focus-b','focus_run','active')),
 (select (pg_temp.action('77777777-7777-4777-8777-777777777777',null,null,repeat('a',64),'focus') ->> 'revision')::bigint),repeat('a',64),'focus')$$,
 '23505','Pomodoist Focus already active','shared trigger rejects two Focus runs in one atomic action');
select ok(not exists(select 1 from public.sync_entities where entity_id in ('focus-a','focus-b'))
 and not exists(select 1 from private.pomodoist_openclaw_receipts where request_id='77777777-7777-4777-8777-777777777777'),
 'mid-batch failure rolls back every operation and receipt');

select public.push_pomodoist_mcp_changes('66666666-6666-4666-8666-666666666666','22222222-2222-4222-8222-222222222222',
 jsonb_build_array(pg_temp.op('foreign-task')));
select is(jsonb_array_length(pg_temp.snapshot('foreign-task')->'entities'),0,'snapshot cannot read another account task');
select is(pg_temp.snapshot('original') #>> '{entities,0,data,id}','original','authorized task details are visible');
select throws_ok($$select public.read_pomodoist_openclaw_state('66666666-6666-4666-8666-666666666666',
 '33333333-3333-4333-8333-333333333333','22222222-2222-4222-8222-222222222222','original')$$,
 '42501','OpenClaw authorization revoked','spoofed OAuth subject is rejected');

delete from auth.sessions where id='33333333-3333-4333-8333-333333333333';
select throws_ok($$select pg_temp.action('44444444-4444-4444-8444-444444444444')$$,
 '42501','OpenClaw authorization revoked','revoked sessions cannot replay previous successes');
select throws_ok($$select pg_temp.snapshot('original')$$,'42501','OpenClaw authorization revoked','revoked sessions cannot read');
select * from finish();
rollback;

begin;
select no_plan();

select is((select count(*) from public.apps), 1::bigint, 'fresh catalog contains only Pomodoist');
select ok(not exists (
  select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname in ('public', 'private') and c.relkind = 'r' and not c.relrowsecurity
), 'all application tables have RLS');
select ok(
  not has_table_privilege('authenticated', 'private.pomodoist_instance_settings', 'UPDATE')
  and not has_function_privilege('authenticated', 'private.grant_pomodoist_selfhost_access(uuid)', 'EXECUTE'),
  'clients cannot change instance mode or grant their own access'
);

update private.pomodoist_instance_settings set selfhost_features_enabled = true;
insert into auth.users (id, email, aud, role, created_at, updated_at)
values
  ('a0000000-0000-4000-8000-000000000001', 'selfhost-alice@example.test', 'authenticated', 'authenticated', now(), now()),
  ('a0000000-0000-4000-8000-000000000002', 'selfhost-bob@example.test', 'authenticated', 'authenticated', now(), now());
select is((select count(*) from public.profiles where pomodoist_is_pro and id in ('a0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000002')), 2::bigint,
  'new independent-server accounts receive full local feature access');
select is((select count(*) from public.user_entitlements where source = 'selfhosted' and user_id in ('a0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000002')
  and status = 'active' and purchase_type = 'lifetime' and valid_until is null), 2::bigint,
  'local access is independent of purchase records and expiration');
select is((select count(*) from public.pomodoist_purchase_claims where linked_user_id in ('a0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000002')), 0::bigint,
  'local feature access creates no official purchase claim');

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}';
select is(public.ensure_profile(), 'a0000000-0000-4000-8000-000000000001'::uuid,
  'the public account SDK ensure_profile contract works');
select is(public.ensure_profile(), 'a0000000-0000-4000-8000-000000000001'::uuid,
  'repeated profile setup is idempotent');
select is(public.get_account_overview() #>> '{profile,pomodoistIsPro}', 'true',
  'account overview reports local Pro access');
select is(public.get_account_overview() #>> '{apps,0,entitlements,0,source}', 'selfhosted',
  'account overview exposes the independent entitlement source');

-- AccountClient.registerInstall directly upserts this table.
insert into public.user_app_installs (user_id, app_id, device_id, platform, app_version)
values (auth.uid(), 'pomodoist', 'desktop-a', 'linux', 'selfhost-test')
on conflict (user_id, app_id, device_id) do update set app_version = excluded.app_version;
select is(public.get_account_overview() #>> '{apps,0,installed}', 'true',
  'the direct install upsert is accepted through RLS');
select throws_ok($$insert into public.user_app_installs (user_id, app_id, device_id)
  values ('a0000000-0000-4000-8000-000000000002', 'pomodoist', 'forged')$$,
  '42501', 'new row violates row-level security policy for table "user_app_installs"',
  'an account cannot register a device for another account');
select throws_ok($$update public.profiles set pomodoist_is_pro = false where id = auth.uid()$$,
  '42501', 'permission denied for table profiles', 'clients cannot edit the entitlement projection');

select is(jsonb_array_length(public.push_changes('pomodoist', 'desktop-a', '[
  {"opId":"selfhost-create","entityType":"task","entityId":"task-a","operation":"upsert",
   "clientUpdatedAt":"2026-09-06T10:00:00Z","payload":{"title":"First title","status":"pending"}}
]'::jsonb)->'applied'), 1, 'first device uploads a task');
select is(public.pull_changes('pomodoist', 'phone-a', 0, 500) #>> '{changes,0,data,title}',
  'First title', 'second device downloads the task');
select is(jsonb_array_length(public.push_changes('pomodoist', 'desktop-a', '[
  {"opId":"selfhost-create","entityType":"task","entityId":"task-a","operation":"upsert",
   "clientUpdatedAt":"2026-09-06T11:00:00Z","payload":{"title":"Replayed title"}}
]'::jsonb)->'applied'), 0, 'retry with the same operation id is deduplicated');
select is(public.pull_changes('pomodoist', 'phone-a', 0, 500) #>> '{changes,0,data,title}',
  'First title', 'a duplicate does not mutate the task');

select public.push_changes('pomodoist', 'phone-a', '[
  {"opId":"selfhost-update","entityType":"task","entityId":"task-a","operation":"upsert",
   "clientUpdatedAt":"2026-09-06T11:00:00Z","payload":{"title":"Edited on phone"}},
  {"opId":"selfhost-create-b","entityType":"task","entityId":"task-b","operation":"upsert",
   "clientUpdatedAt":"2026-09-06T11:00:00Z","payload":{"title":"Second task"}}
]'::jsonb);
select is(public.pull_changes('pomodoist', 'desktop-a', 0, 1)->>'hasMore', 'true',
  'the public pull RPC paginates changes');
select is(public.pull_changes('pomodoist', 'desktop-a', 0, 500) #>> '{changes,0,data,title}',
  'Edited on phone', 'updates return to the first device');

select public.push_changes('pomodoist', 'phone-a', '[
  {"opId":"selfhost-delete","entityType":"task","entityId":"task-a","operation":"delete",
   "clientUpdatedAt":"2026-09-06T12:00:00Z","payload":{}},
  {"opId":"selfhost-stale-edit","entityType":"task","entityId":"task-a","operation":"upsert",
   "clientUpdatedAt":"2026-09-06T10:30:00Z","payload":{"title":"Stale offline edit"}}
]'::jsonb);
select ok((select deleted_at is not null from public.sync_entities where entity_id = 'task-a'),
  'a stale offline upsert cannot resurrect a tombstone');
select is((select data->>'title' from public.sync_entities where entity_id = 'task-a'),
  'Edited on phone', 'deletion preserves the last accepted task data');
select ok(exists (
  select 1 from jsonb_array_elements(public.pull_changes('pomodoist', 'desktop-a', 0, 500)->'changes') c
  where c->>'entityId' = 'task-a' and c->>'deletedAt' is not null
), 'the other device receives the deletion');

set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated"}';
select is(jsonb_array_length(public.pull_changes('pomodoist', 'desktop-b', 0, 500)->'changes'),
  0, 'another tenant cannot pull the first tenant data');
select is((select count(*) from public.sync_entities), 0::bigint,
  'direct entity reads respect tenant RLS');
select is((select count(*) from public.profiles), 1::bigint,
  'profile reads reveal only the current account');
select is((select count(*) from public.user_entitlements), 1::bigint,
  'entitlement reads reveal only the current account');
select throws_ok($$select public.pomodoist_google_calendar_service('get_account',
  'a0000000-0000-4000-8000-000000000001', '{}'::jsonb)$$,
  '42501', 'permission denied for function pomodoist_google_calendar_service',
  'integration service RPCs still require service credentials');

set local role anon;
set local request.jwt.claims = '{"role":"anon"}';
select throws_ok($$select public.push_changes('pomodoist', 'unauthenticated', '[]'::jsonb)$$,
  'P0001', 'Authentication required', 'selfhost mode does not allow anonymous sync');
select throws_ok($$select public.pull_changes('pomodoist', 'unauthenticated', 0, 500)$$,
  'P0001', 'Authentication required', 'selfhost mode does not allow anonymous pulls');
reset role;
select is((select count(*) from public.user_entitlements where source = 'selfhosted' and user_id in ('a0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000002')),
  2::bigint, 'profile retries did not duplicate local entitlements');
select * from finish();
rollback;

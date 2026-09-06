begin;
\ir hosted-mode.inc

select plan(24);

insert into auth.users (id, email, aud, role, created_at, updated_at)
values
  ('10000000-0000-4000-8000-000000000001', 'tg-guest-1@telegram.invalid', 'authenticated', 'authenticated', now(), now()),
  ('10000000-0000-4000-8000-000000000002', 'target-1@example.com', 'authenticated', 'authenticated', now(), now()),
  ('10000000-0000-4000-8000-000000000003', 'tg-guest-2@telegram.invalid', 'authenticated', 'authenticated', now(), now()),
  ('10000000-0000-4000-8000-000000000004', 'target-2@example.com', 'authenticated', 'authenticated', now(), now()),
  ('10000000-0000-4000-8000-000000000005', 'tg-guest-3@telegram.invalid', 'authenticated', 'authenticated', now(), now()),
  ('10000000-0000-4000-8000-000000000006', 'target-3@example.com', 'authenticated', 'authenticated', now(), now()),
  ('10000000-0000-4000-8000-000000000007', 'tg-guest-4@telegram.invalid', 'authenticated', 'authenticated', now(), now()),
  ('10000000-0000-4000-8000-000000000008', 'target-4@example.com', 'authenticated', 'authenticated', now(), now()),
  ('10000000-0000-4000-8000-000000000009', 'target-5@example.com', 'authenticated', 'authenticated', now(), now());

select ok(
  not has_table_privilege('anon', 'public.pomodoist_telegram_accounts', 'SELECT')
  and not has_table_privilege('authenticated', 'public.pomodoist_telegram_accounts', 'SELECT')
  and not has_table_privilege('anon', 'public.pomodoist_telegram_link_attempts', 'SELECT')
  and not has_table_privilege('authenticated', 'public.pomodoist_telegram_link_attempts', 'SELECT'),
  'Telegram identity and link tables are closed to browser roles'
);

select ok(
  has_function_privilege('service_role', 'public.bootstrap_pomodoist_telegram(bigint,uuid,uuid)', 'EXECUTE')
  and has_function_privilege('service_role', 'public.push_pomodoist_telegram_changes(bigint,uuid,uuid,jsonb)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.bootstrap_pomodoist_telegram(bigint,uuid,uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.complete_pomodoist_telegram_link(bytea,uuid)', 'EXECUTE'),
  'only service role can execute Telegram identity RPCs'
);

create temporary table first_bootstrap on commit drop as
select public.bootstrap_pomodoist_telegram(
  42,
  '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001'
) as value;

select is(
  (select value ->> 'userId' from first_bootstrap),
  '10000000-0000-4000-8000-000000000001',
  'first bootstrap claims the supplied guest user'
);

select is(
  public.bootstrap_pomodoist_telegram(
    42,
    '10000000-0000-4000-8000-000000000003',
    '20000000-0000-4000-8000-000000000002'
  ) ->> 'userId',
  '10000000-0000-4000-8000-000000000001',
  'parallel bootstrap loser receives the existing identity'
);

select public.begin_pomodoist_telegram_link(
  42,
  decode(repeat('11', 32), 'hex'),
  now() + interval '15 minutes'
);

insert into public.sync_entities (
  user_id, app_id, entity_type, entity_id, server_revision,
  client_updated_at, data, field_clock
)
values
  ('10000000-0000-4000-8000-000000000001', 'pomodoist', 'task', 'guest-task', nextval('public.sync_revision_seq'), now(), '{"id":"guest-task","content":"Guest","projectId":"inbox","status":"open"}', '{}'),
  ('10000000-0000-4000-8000-000000000001', 'pomodoist', 'task_completion', 'guest-completion', nextval('public.sync_revision_seq'), now(), '{"id":"guest-completion","taskId":"guest-task"}', '{}'),
  ('10000000-0000-4000-8000-000000000001', 'pomodoist', 'focus_interval', 'guest-interval', nextval('public.sync_revision_seq'), now(), '{"id":"guest-interval","runId":"guest-run","status":"completed"}', '{}'),
  ('10000000-0000-4000-8000-000000000002', 'pomodoist', 'task', 'target-task', nextval('public.sync_revision_seq'), now(), '{"id":"target-task","content":"Keep","projectId":"inbox","status":"open"}', '{}');

select lives_ok(
  $$select public.complete_pomodoist_telegram_link(decode(repeat('11', 32), 'hex'), '10000000-0000-4000-8000-000000000002')$$,
  'valid token atomically links the Telegram identity'
);

select ok(
  (select user_id = '10000000-0000-4000-8000-000000000002'
     and guest_user_id = '10000000-0000-4000-8000-000000000001'
   from public.pomodoist_telegram_accounts where telegram_user_id = 42),
  'mapping points to the target while retaining cleanup identity'
);

select ok(
  exists(select 1 from public.sync_entities where user_id = '10000000-0000-4000-8000-000000000002' and entity_id = 'guest-task')
  and exists(select 1 from public.sync_entities where user_id = '10000000-0000-4000-8000-000000000002' and entity_id = 'guest-completion')
  and exists(select 1 from public.sync_entities where user_id = '10000000-0000-4000-8000-000000000002' and entity_id = 'guest-interval'),
  'guest task, completion, and focus entities move to the target'
);

select ok(
  exists(select 1 from public.sync_entities where user_id = '10000000-0000-4000-8000-000000000002' and entity_id = 'target-task'),
  'existing target data is preserved'
);

select throws_ok(
  $$select public.complete_pomodoist_telegram_link(decode(repeat('11', 32), 'hex'), '10000000-0000-4000-8000-000000000002')$$,
  '22023',
  'Invalid or expired Telegram link token',
  'link token is one-time'
);

select public.bootstrap_pomodoist_telegram(
  43,
  '10000000-0000-4000-8000-000000000003',
  '20000000-0000-4000-8000-000000000003'
);
insert into public.pomodoist_telegram_link_attempts (
  token_hash,
  telegram_user_id,
  expires_at
) values (
  decode(repeat('22', 32), 'hex'),
  43,
  now() - interval '1 second'
);

select throws_ok(
  $$select public.complete_pomodoist_telegram_link(decode(repeat('22', 32), 'hex'), '10000000-0000-4000-8000-000000000004')$$,
  '22023',
  'Invalid or expired Telegram link token',
  'expired link token is rejected'
);

select public.begin_pomodoist_telegram_link(
  43,
  decode(repeat('33', 32), 'hex'),
  now() + interval '15 minutes'
);
insert into public.sync_entities (
  user_id, app_id, entity_type, entity_id, server_revision,
  client_updated_at, data, field_clock
)
values
  ('10000000-0000-4000-8000-000000000003', 'pomodoist', 'task', 'collision', nextval('public.sync_revision_seq'), now(), '{"id":"collision"}', '{}'),
  ('10000000-0000-4000-8000-000000000004', 'pomodoist', 'task', 'collision', nextval('public.sync_revision_seq'), now(), '{"id":"collision"}', '{}');

select throws_ok(
  $$select public.complete_pomodoist_telegram_link(decode(repeat('33', 32), 'hex'), '10000000-0000-4000-8000-000000000004')$$,
  '23505',
  'Telegram account merge conflict',
  'entity ID collision aborts the link'
);

select ok(
  (select user_id = '10000000-0000-4000-8000-000000000003'
   from public.pomodoist_telegram_accounts where telegram_user_id = 43)
  and exists(select 1 from public.sync_entities where user_id = '10000000-0000-4000-8000-000000000003' and entity_id = 'collision'),
  'failed merge rolls back mapping and guest entities'
);

select public.bootstrap_pomodoist_telegram(
  44,
  '10000000-0000-4000-8000-000000000005',
  '20000000-0000-4000-8000-000000000004'
);
select public.begin_pomodoist_telegram_link(
  44,
  decode(repeat('44', 32), 'hex'),
  now() + interval '15 minutes'
);
insert into public.sync_entities (
  user_id, app_id, entity_type, entity_id, server_revision,
  client_updated_at, data, field_clock
)
values
  ('10000000-0000-4000-8000-000000000005', 'pomodoist', 'focus_run', 'guest-active', nextval('public.sync_revision_seq'), now(), '{"id":"guest-active","status":"active"}', '{}'),
  ('10000000-0000-4000-8000-000000000006', 'pomodoist', 'focus_run', 'target-active', nextval('public.sync_revision_seq'), now(), '{"id":"target-active","status":"paused"}', '{}');

select throws_ok(
  $$select public.complete_pomodoist_telegram_link(decode(repeat('44', 32), 'hex'), '10000000-0000-4000-8000-000000000006')$$,
  '23505',
  'Telegram account merge conflict',
  'simultaneous active Focus runs abort the link'
);

select lives_ok(
  $$select public.push_pomodoist_telegram_changes(
    42,
    '10000000-0000-4000-8000-000000000002',
    '20000000-0000-4000-8000-000000000001',
    '[{"opId":"telegram-focus","entityType":"focus_event","entityId":"telegram-focus","operation":"upsert","payload":{"id":"telegram-focus","runId":"run","type":"runStarted","occurredAt":"2026-08-03T12:00:00Z","createdAt":"2026-08-03T12:00:00Z"},"clientUpdatedAt":"2026-08-03T12:00:00Z"}]'
  )$$,
  'service push accepts the shared focus entity format'
);

select throws_ok(
  $$select public.push_pomodoist_telegram_changes(
    42,
    '10000000-0000-4000-8000-000000000002',
    '20000000-0000-4000-8000-000000000001',
    '[{"opId":"telegram-project","entityType":"project","entityId":"project","operation":"upsert","payload":{},"clientUpdatedAt":"2026-08-03T12:00:00Z"}]'
  )$$,
  '22023',
  'Invalid Telegram sync operation',
  'service push rejects entity types outside the Mini App boundary'
);

select public.bootstrap_pomodoist_telegram(
  45,
  '10000000-0000-4000-8000-000000000007',
  '20000000-0000-4000-8000-000000000005'
);
select public.begin_pomodoist_telegram_link(
  45,
  decode(repeat('55', 32), 'hex'),
  now() + interval '15 minutes'
);
insert into public.pomodoist_telegram_link_attempts (
  token_hash,
  telegram_user_id,
  expires_at
) values (
  decode(repeat('56', 32), 'hex'),
  45,
  now() + interval '15 minutes'
);
insert into public.sync_entities (
  user_id, app_id, entity_type, entity_id, server_revision,
  client_updated_at, data, field_clock
) values
  ('10000000-0000-4000-8000-000000000007', 'pomodoist', 'task', 'guest-four-task', nextval('public.sync_revision_seq'), now(), '{"id":"guest-four-task","status":"open"}', '{}'),
  ('10000000-0000-4000-8000-000000000008', 'pomodoist', 'task', 'target-four-task', nextval('public.sync_revision_seq'), now(), '{"id":"target-four-task","status":"open"}', '{}');

select lives_ok(
  $$select public.complete_pomodoist_telegram_link(decode(repeat('55', 32), 'hex'), '10000000-0000-4000-8000-000000000008')$$,
  'first valid sibling token links the guest account'
);

select throws_ok(
  $$select public.complete_pomodoist_telegram_link(decode(repeat('56', 32), 'hex'), '10000000-0000-4000-8000-000000000009')$$,
  '22023',
  'Invalid or expired Telegram link token',
  'successful linking invalidates every sibling token'
);

select ok(
  exists(select 1 from public.sync_entities where user_id = '10000000-0000-4000-8000-000000000008' and entity_id = 'guest-four-task')
  and exists(select 1 from public.sync_entities where user_id = '10000000-0000-4000-8000-000000000008' and entity_id = 'target-four-task')
  and not exists(select 1 from public.sync_entities where user_id = '10000000-0000-4000-8000-000000000009' and entity_id in ('guest-four-task', 'target-four-task')),
  'stale link token cannot move the linked account data'
);

select throws_ok(
  $$select public.begin_pomodoist_telegram_link(45, decode(repeat('57', 32), 'hex'), now() + interval '15 minutes')$$,
  '22023',
  'Telegram account already linked',
  'linked Telegram identity cannot issue another link token'
);

select throws_ok(
  $$select public.push_pomodoist_telegram_changes(
    45,
    '10000000-0000-4000-8000-000000000007',
    '20000000-0000-4000-8000-000000000005',
    '[{"opId":"stale-command","entityType":"task","entityId":"stale-command","operation":"upsert","payload":{"id":"stale-command","status":"open"},"clientUpdatedAt":"2026-08-03T12:00:00Z"}]'
  )$$,
  '40001',
  'Telegram mapping changed',
  'command cannot write through a stale guest mapping after linking'
);

select lives_ok(
  $$select public.push_pomodoist_telegram_changes(
    45,
    '10000000-0000-4000-8000-000000000008',
    '20000000-0000-4000-8000-000000000005',
    '[{"opId":"focus-one","entityType":"focus_run","entityId":"focus-one","operation":"upsert","payload":{"id":"focus-one","status":"active"},"clientUpdatedAt":"2026-08-03T12:00:00Z"}]'
  )$$,
  'first Telegram Focus starts'
);

select throws_ok(
  $$select public.push_pomodoist_telegram_changes(
    45,
    '10000000-0000-4000-8000-000000000008',
    '20000000-0000-4000-8000-000000000005',
    '[{"opId":"focus-two","entityType":"focus_run","entityId":"focus-two","operation":"upsert","payload":{"id":"focus-two","status":"active"},"clientUpdatedAt":"2026-08-03T12:00:00Z"}]'
  )$$,
  '23505',
  'Telegram Focus already active',
  'serialized Telegram commands cannot create a second active Focus'
);

select throws_ok(
  $$select private.push_changes_for_user(
    '10000000-0000-4000-8000-000000000008',
    'pomodoist',
    'flutter-race-test',
    '[{"opId":"focus-three","entityType":"focus_run","entityId":"focus-three","operation":"upsert","payload":{"id":"focus-three","status":"active"},"clientUpdatedAt":"2026-08-03T12:00:00Z"}]'
  )$$,
  '23505',
  'Pomodoist Focus already active',
  'ordinary sync cannot race Telegram into a second active Focus'
);

select lives_ok(
  $$select private.push_changes_for_user(
    '10000000-0000-4000-8000-000000000008',
    'pomodoist',
    'flutter-race-test',
    '[{"opId":"focus-one-pause","entityType":"focus_run","entityId":"focus-one","operation":"upsert","payload":{"id":"focus-one","status":"paused"},"clientUpdatedAt":"2026-08-03T12:01:00Z"}]'
  )$$,
  'upsert can pause the current active Focus itself'
);

select * from finish();
rollback;

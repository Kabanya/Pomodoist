begin;
\ir hosted-mode.inc

select plan(30);

select has_table('private', 'pomodoist_google_calendar_accounts', 'calendar account table exists');
select has_table('private', 'pomodoist_google_calendar_oauth_states', 'OAuth state table exists');
select has_table('private', 'pomodoist_google_calendar_jobs', 'calendar job table exists');
select has_table('private', 'pomodoist_google_calendar_links', 'calendar link table exists');

select ok(
  not has_table_privilege('anon', 'private.pomodoist_google_calendar_accounts', 'SELECT')
  and not has_table_privilege('authenticated', 'private.pomodoist_google_calendar_oauth_states', 'SELECT')
  and not has_table_privilege('service_role', 'private.pomodoist_google_calendar_links', 'SELECT'),
  'calendar credentials and state are private behind the service RPC'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.pomodoist_google_calendar_service(text,uuid,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.pomodoist_google_calendar_service(text,uuid,jsonb)',
    'EXECUTE'
  ),
  'only service role can call the calendar service RPC'
);

insert into auth.users (id, email, aud, role, created_at, updated_at)
values (
  '11111111-1111-4111-8111-111111111111',
  'calendar-test@example.com',
  'authenticated',
  'authenticated',
  '2026-08-26 10:00:00+00',
  '2026-08-26 10:00:00+00'
);

delete from net.http_request_queue;

select public.pomodoist_google_calendar_service(
  'configure_worker', null,
  jsonb_build_object(
    'functionUrl', 'https://functions.test/pomodoist-google-calendar',
    'workerSecret', repeat('w', 32)
  )
);
select public.pomodoist_google_calendar_service(
  'configure_worker', null,
  jsonb_build_object(
    'functionUrl', 'https://functions.test/pomodoist-google-calendar',
    'workerSecret', repeat('w', 32)
  )
);

select is(
  (
    select count(*)
    from vault.decrypted_secrets
    where name in (
      'pomodoist-google-calendar-worker-url',
      'pomodoist-google-calendar-worker-secret'
    )
  ),
  2::bigint,
  'worker configuration is stored idempotently in Vault'
);

select is(
  (
    select decrypted_secret
    from vault.decrypted_secrets
    where name = 'pomodoist-google-calendar-worker-url'
  ),
  'https://functions.test/pomodoist-google-calendar',
  'worker URL is stored for pg_net dispatch'
);

select public.pomodoist_google_calendar_service(
  'store_oauth_state',
  '11111111-1111-4111-8111-111111111111',
  jsonb_build_object(
    'stateHash', repeat('s', 64),
    'codeVerifier', repeat('v', 43),
    'expiresAt', '2099-01-01T00:00:00Z'
  )
);

select is(
  public.pomodoist_google_calendar_service(
    'consume_oauth_state', null, jsonb_build_object('stateHash', repeat('s', 64))
  )->>'codeVerifier',
  repeat('v', 43),
  'OAuth state is consumed once'
);

select is(
  public.pomodoist_google_calendar_service(
    'consume_oauth_state', null, jsonb_build_object('stateHash', repeat('s', 64))
  ),
  null,
  'replayed OAuth state is rejected'
);

select public.pomodoist_google_calendar_service(
  'connect',
  '11111111-1111-4111-8111-111111111111',
  '{"refreshToken":"refresh-secret"}'
);

select is(
  (
    select data ->> 'status'
    from public.sync_entities
    where user_id = '11111111-1111-4111-8111-111111111111'
      and app_id = 'pomodoist'
      and entity_type = 'google_calendar_connection'
      and entity_id = 'primary'
  ),
  'connecting',
  'connection state is projected through account sync'
);

select is(
  (
    select data ->> 'ownerDeviceId'
    from public.sync_entities
    where user_id = '11111111-1111-4111-8111-111111111111'
      and app_id = 'pomodoist'
      and entity_type = 'google_calendar_connection'
      and entity_id = 'primary'
  ),
  'google-calendar-server',
  'server connection reserves ownership from legacy clients'
);

do $$
begin
  for i in 1..10000 loop
    perform public.pomodoist_google_calendar_service(
      'queue', '11111111-1111-4111-8111-111111111111', '{}'
    );
  end loop;
end;
$$;

select is(
  (
    select count(*)
    from private.pomodoist_google_calendar_jobs
    where user_id = '11111111-1111-4111-8111-111111111111'
  ),
  1::bigint,
  'ten thousand queue requests coalesce into one pending job'
);

select is(
  (select count(*) from net.http_request_queue),
  1::bigint,
  'ten thousand queue requests emit only one worker wake'
);

insert into public.sync_entities (
  user_id, app_id, entity_type, entity_id, server_revision,
  client_updated_at, data, field_clock
) values (
  '11111111-1111-4111-8111-111111111111',
  'pomodoist', 'task', 'task-1', nextval('public.sync_revision_seq'),
  '2026-08-26 11:00:00+00',
  '{"id":"task-1","content":"Breakfast","dueJson":"{\"date\":\"2026-08-27\"}","updatedAt":"2026-08-26T11:00:00.000Z"}',
  '{}'
);

select is(
  (
    select local_schedule_updated_at
    from private.pomodoist_google_calendar_task_state
    where user_id = '11111111-1111-4111-8111-111111111111'
      and task_id = 'task-1'
  ),
  '2026-08-26 11:00:00+00'::timestamptz,
  'task insert records the independent schedule timestamp'
);

update public.sync_entities
set data = jsonb_set(data, '{content}', '"New title"'),
    client_updated_at = '2026-08-26 12:00:00+00'
where user_id = '11111111-1111-4111-8111-111111111111'
  and entity_type = 'task' and entity_id = 'task-1';

select is(
  (
    select local_schedule_updated_at
    from private.pomodoist_google_calendar_task_state
    where user_id = '11111111-1111-4111-8111-111111111111'
      and task_id = 'task-1'
  ),
  '2026-08-26 11:00:00+00'::timestamptz,
  'title changes do not overwrite the schedule conflict clock'
);

create temp table calendar_claim_result (payload jsonb);
insert into calendar_claim_result
select public.pomodoist_google_calendar_service('claim', null, '{"limit":10}');

select is(
  jsonb_array_length((select payload from calendar_claim_result)),
  1,
  'claim returns one due account'
);

select is(
  ((select payload from calendar_claim_result) -> 0 ->> 'claimedGeneration')::bigint,
  (
    select claimed_generation
    from private.pomodoist_google_calendar_jobs
    where user_id = '11111111-1111-4111-8111-111111111111'
  ),
  'claim returns the leased generation to the worker'
);

select ok(
  (
    select status = 'processing' and lease_until > now()
    from private.pomodoist_google_calendar_jobs
    where user_id = '11111111-1111-4111-8111-111111111111'
  ),
  'claim leases one account atomically'
);

select public.pomodoist_google_calendar_service(
  'queue', '11111111-1111-4111-8111-111111111111', '{}'
);
select ok(
  (
    select status = 'processing' and lease_until > now()
    from private.pomodoist_google_calendar_jobs
    where user_id = '11111111-1111-4111-8111-111111111111'
  ),
  'queueing during a lease preserves the single active worker'
);
select public.pomodoist_google_calendar_service(
  'complete',
  '11111111-1111-4111-8111-111111111111',
  '{"account":{},"links":[],"removedTaskIds":[],"operations":[]}'
);
select ok(
  (
    select status = 'pending' and due_at <= now()
    from private.pomodoist_google_calendar_jobs
    where user_id = '11111111-1111-4111-8111-111111111111'
  ),
  'completion of a leased generation preserves a newer queued change'
);

select is(
  (select count(*) from net.http_request_queue),
  2::bigint,
  'completion wakes exactly once when a newer generation arrived during the lease'
);

select public.pomodoist_google_calendar_service('claim', null, '{"limit":10}');

select public.pomodoist_google_calendar_service(
  'complete',
  '11111111-1111-4111-8111-111111111111',
  '{"account":{},"links":[],"removedTaskIds":[],"operations":[]}'
);

select ok(
  (
    select status = 'pending'
      and due_at between now() + interval '23 hours 59 minutes'
                     and now() + interval '24 hours 1 minute'
    from private.pomodoist_google_calendar_jobs
    where user_id = '11111111-1111-4111-8111-111111111111'
  ),
  'clean completion schedules one daily safety pull instead of a minute loop'
);

select is(
  private.invoke_pomodoist_google_calendar_worker(),
  null::bigint,
  'idle cron dispatch does not invoke the Edge Function'
);

update public.sync_entities
set data = jsonb_set(data, '{ownerDeviceId}', '"legacy-device"'),
    client_updated_at = now() + interval '1 hour',
    field_clock = jsonb_set(
      field_clock,
      '{ownerDeviceId}',
      to_jsonb(now() + interval '1 hour')
    )
where user_id = '11111111-1111-4111-8111-111111111111'
  and app_id = 'pomodoist'
  and entity_type = 'google_calendar_connection'
  and entity_id = 'primary';

select is(
  (
    select data ->> 'ownerDeviceId'
    from public.sync_entities
    where user_id = '11111111-1111-4111-8111-111111111111'
      and app_id = 'pomodoist'
      and entity_type = 'google_calendar_connection'
      and entity_id = 'primary'
  ),
  'google-calendar-server',
  'legacy connection updates cannot reclaim server ownership'
);

update private.pomodoist_google_calendar_jobs
set due_at = now(), status = 'pending'
where user_id = '11111111-1111-4111-8111-111111111111';

select public.pomodoist_google_calendar_service('claim', null, '{"limit":10}');

select public.pomodoist_google_calendar_service(
  'fail',
  '11111111-1111-4111-8111-111111111111',
  '{"error":"temporary","retrySeconds":30}'
);

select ok(
  (
    select status = 'pending' and attempts = 1 and due_at > now()
    from private.pomodoist_google_calendar_jobs
    where user_id = '11111111-1111-4111-8111-111111111111'
  ),
  'failed jobs are retained with retry backoff'
);

update private.pomodoist_google_calendar_accounts
set sync_token = 'baseline-token', status = 'connected', last_error = null
where user_id = '11111111-1111-4111-8111-111111111111';
update private.pomodoist_google_calendar_jobs
set due_at = now(), status = 'pending', attempts = 0, last_error = null
where user_id = '11111111-1111-4111-8111-111111111111';
select public.pomodoist_google_calendar_service('claim', null, '{"limit":10}');
select public.pomodoist_google_calendar_service(
  'queue', '11111111-1111-4111-8111-111111111111', '{}'
);
select public.pomodoist_google_calendar_service(
  'complete',
  '11111111-1111-4111-8111-111111111111',
  jsonb_build_object(
    'claimedGeneration', (
      select claimed_generation
      from private.pomodoist_google_calendar_jobs
      where user_id = '11111111-1111-4111-8111-111111111111'
    ),
    'account', '{"syncToken":"stale-token"}'::jsonb,
    'links', '[{"taskId":"task-1","calendarId":"calendar-1","eventId":"stale-event","localScheduleUpdatedAt":"2026-08-26T13:00:00Z"}]'::jsonb,
    'removedTaskIds', '[]'::jsonb,
    'operations', '[{"opId":"stale-calendar-op","entityType":"task","entityId":"task-1","operation":"upsert","payload":{"commandType":"task.update","dueJson":"{\"type\":\"allDay\",\"date\":\"2026-08-30\"}","durationSeconds":null},"clientUpdatedAt":"2026-08-26T13:00:00Z"}]'::jsonb
  )
);

select ok(
  (
    select data ->> 'dueJson' = '{"date":"2026-08-27"}'
    from public.sync_entities
    where user_id = '11111111-1111-4111-8111-111111111111'
      and entity_type = 'task' and entity_id = 'task-1'
  )
  and not exists (
    select 1 from private.pomodoist_google_calendar_links
    where user_id = '11111111-1111-4111-8111-111111111111'
      and event_id = 'stale-event'
  )
  and (
    select sync_token = 'baseline-token' and status = 'connecting'
      and last_error is null
    from private.pomodoist_google_calendar_accounts
    where user_id = '11111111-1111-4111-8111-111111111111'
  )
  and (
    select status = 'pending' and due_at <= now() and attempts = 0
    from private.pomodoist_google_calendar_jobs
    where user_id = '11111111-1111-4111-8111-111111111111'
  ),
  'stale completion cannot apply task, link, token, or status changes and requeues immediately'
);

select public.pomodoist_google_calendar_service('claim', null, '{"limit":10}');
select public.pomodoist_google_calendar_service(
  'complete',
  '11111111-1111-4111-8111-111111111111',
  jsonb_build_object(
    'claimedGeneration', (
      select claimed_generation
      from private.pomodoist_google_calendar_jobs
      where user_id = '11111111-1111-4111-8111-111111111111'
    ),
    'account', '{"syncToken":"fresh-token"}'::jsonb,
    'links', '[{"taskId":"task-1","calendarId":"calendar-1","eventId":"fresh-event","localScheduleUpdatedAt":"2026-08-26T14:00:00Z"}]'::jsonb,
    'removedTaskIds', '[]'::jsonb,
    'operations', '[{"opId":"fresh-calendar-op","entityType":"task","entityId":"task-1","operation":"upsert","payload":{"commandType":"task.update","dueJson":"{\"type\":\"allDay\",\"date\":\"2026-08-29\"}","durationSeconds":null},"clientUpdatedAt":"2026-08-26T14:00:00Z"}]'::jsonb
  )
);

select ok(
  (
    select data ->> 'dueJson' = '{"type":"allDay","date":"2026-08-29"}'
    from public.sync_entities
    where user_id = '11111111-1111-4111-8111-111111111111'
      and entity_type = 'task' and entity_id = 'task-1'
  )
  and exists (
    select 1 from private.pomodoist_google_calendar_links
    where user_id = '11111111-1111-4111-8111-111111111111'
      and event_id = 'fresh-event'
  )
  and (
    select sync_token = 'fresh-token' and status = 'connected'
    from private.pomodoist_google_calendar_accounts
    where user_id = '11111111-1111-4111-8111-111111111111'
  ),
  'the current claimed generation applies task, link, token, and status changes'
);

update private.pomodoist_google_calendar_jobs
set due_at = now(), status = 'pending', attempts = 0, last_error = null
where user_id = '11111111-1111-4111-8111-111111111111';
select public.pomodoist_google_calendar_service('claim', null, '{"limit":10}');
select public.pomodoist_google_calendar_service(
  'queue', '11111111-1111-4111-8111-111111111111', '{}'
);
select public.pomodoist_google_calendar_service(
  'fail',
  '11111111-1111-4111-8111-111111111111',
  jsonb_build_object(
    'claimedGeneration', (
      select claimed_generation
      from private.pomodoist_google_calendar_jobs
      where user_id = '11111111-1111-4111-8111-111111111111'
    ),
    'error', 'stale failure',
    'retrySeconds', 3600
  )
);

select ok(
  (
    select status = 'pending' and due_at <= now() and attempts = 0
      and last_error is null
    from private.pomodoist_google_calendar_jobs
    where user_id = '11111111-1111-4111-8111-111111111111'
  )
  and (
    select status = 'connecting' and last_error is null
    from private.pomodoist_google_calendar_accounts
    where user_id = '11111111-1111-4111-8111-111111111111'
  ),
  'stale failure does not record an error or backoff and requeues immediately'
);

select public.pomodoist_google_calendar_service('claim', null, '{"limit":10}');
select public.pomodoist_google_calendar_service(
  'fail',
  '11111111-1111-4111-8111-111111111111',
  jsonb_build_object(
    'claimedGeneration', (
      select claimed_generation
      from private.pomodoist_google_calendar_jobs
      where user_id = '11111111-1111-4111-8111-111111111111'
    ),
    'error', 'Precondition',
    'retrySeconds', 5,
    'transientConflict', true
  )
);

select ok(
  (
    select status = 'pending' and due_at <= now() and attempts = 0
      and last_error is null
    from private.pomodoist_google_calendar_jobs
    where user_id = '11111111-1111-4111-8111-111111111111'
  )
  and (
    select status = 'connecting' and last_error is null
    from private.pomodoist_google_calendar_accounts
    where user_id = '11111111-1111-4111-8111-111111111111'
  ),
  'a fresh 412 conflict retries immediately without a persistent error or backoff'
);

select * from finish();
rollback;

begin;
select no_plan();

-- Exercise the real function bodies with a controlled clock. All clones, data,
-- and the temporary receipt default disappear on rollback; cron never runs.
create function pg_temp.quota_now() returns timestamptz language sql as $$
  select current_setting('test.quota_now')::timestamptz;
$$;
do $$
declare
  v_name text;
  v_schema text;
  v_source text;
begin
  foreach v_name in array array['pomodoist_voice_quota', 'pomodoist_llm_quota',
                              'get_usage_period', 'get_account_overview'] loop
    v_schema := case when v_name in ('get_usage_period', 'get_account_overview') then 'private' else 'public' end;
    select pg_get_functiondef(p.oid) into strict v_source
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = v_schema and p.proname = v_name;
    assert position('now()' in v_source) > 0, 'Test clock must replace the production clock';
    execute replace(replace(v_source, 'FUNCTION ' || v_schema || '.' || v_name || '(',
                            'FUNCTION pg_temp.' || v_name || '('),
                    'now()', 'pg_temp.quota_now()');
  end loop;
end;
$$;
alter table private.pomodoist_voice_requests
  alter column expires_at set default pg_temp.quota_now() + interval '10 minutes';

create function pg_temp.quota_call(p_mode text, p_user uuid, p_request uuid, p_action text)
returns jsonb language plpgsql as $$
begin
  if p_mode = 'voice' then
    return pg_temp.pomodoist_voice_quota(p_user, p_request, p_action);
  end if;
  return pg_temp.pomodoist_llm_quota(
    case when p_mode = 'account_llm' then p_user end,
    case when p_mode = 'guest_llm' then 'apple:Production:reset-' || p_user::text end,
    p_request, p_action);
end;
$$;

create function pg_temp.check_quota_reset(p_boundary timestamptz, p_timezone text, p_mode text)
returns void language plpgsql as $$
declare
  v_user uuid := gen_random_uuid();
  v_old_request uuid := gen_random_uuid();
  v_new_request uuid := gen_random_uuid();
  v_old_period uuid;
  v_new_period uuid;
  v_next_end timestamptz := (p_boundary at time zone 'UTC' + interval '1 month') at time zone 'UTC';
  v_key text := case when p_mode = 'voice' then 'voice_transcriptions' else 'llm_requests' end;
  v_result jsonb;
begin
  perform set_config('TimeZone', p_timezone, true);
  perform set_config('test.quota_now', (p_boundary - interval '1 second')::text, true);
  insert into auth.users (id,email,aud,role,created_at,updated_at)
  values (v_user, v_user::text || '@example.test', 'authenticated', 'authenticated', now(), now());
  perform set_config('request.jwt.claim.sub', v_user::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_user, 'role', 'authenticated')::text, true);

  v_result := pg_temp.quota_call(p_mode, v_user, v_old_request, 'reserve');
  assert v_result->>'allowed' = 'true', 'Old month reservation must succeed';
  assert (v_result->>'resetsAt')::timestamptz = p_boundary, 'Reset must be UTC month start';
  select usage_period_id into strict v_old_period
  from private.pomodoist_voice_requests where request_id = v_old_request;
  update public.usage_periods set used = 999 where id = v_old_period;
  assert pg_temp.quota_call(p_mode, v_user, gen_random_uuid(), 'reserve')->>'allowed' = 'false',
    'Used and pending requests must exhaust the old month';
  if p_mode <> 'guest_llm' then
    assert pg_temp.get_usage_period('pomodoist', v_key)->>'used' = '999',
      'Reader must find the current UTC counter in every session timezone';
    assert jsonb_array_length(pg_temp.get_account_overview() #> '{apps,0,usage}') = 1,
      'Overview must include the old month until UTC midnight';
  end if;

  perform set_config('test.quota_now', p_boundary::text, true);
  if p_mode <> 'guest_llm' then
    v_result := pg_temp.get_usage_period('pomodoist', v_key);
    assert v_result->>'used' = '0' and v_result->>'remaining' = '1000',
      'An unused new month must report the full allowance';
    assert (v_result->>'resetsAt')::timestamptz = v_next_end,
      'Empty-month reset timestamp must ignore session timezone and DST';
    assert jsonb_array_length(pg_temp.get_account_overview() #> '{apps,0,usage}') = 0,
      'Overview must exclude the expired month at UTC midnight';
  end if;
  v_result := pg_temp.quota_call(p_mode, v_user, v_old_request, 'reserve');
  assert v_result->>'allowed' = 'true' and (v_result->>'resetsAt')::timestamptz = p_boundary,
    'Retry across midnight must retain the original reservation';
  v_result := pg_temp.quota_call(p_mode, v_user, v_new_request, 'reserve');
  assert v_result->>'allowed' = 'true' and (v_result->>'resetsAt')::timestamptz = v_next_end,
    'New month must open without pruning old receipts';
  select usage_period_id into strict v_new_period
  from private.pomodoist_voice_requests where request_id = v_new_request;
  assert v_new_period <> v_old_period, 'Each UTC month must have its own ledger row';
  assert (select used = 0 and limit_value = 1000 and period_start = p_boundary
          from public.usage_periods where id = v_new_period), 'New month must start at zero';

  perform set_config('test.quota_now', (p_boundary + interval '1 second')::text, true);
  perform pg_temp.quota_call(p_mode, v_user, v_old_request, 'complete');
  perform pg_temp.quota_call(p_mode, v_user, v_old_request, 'complete');
  assert (select used = 1000 from public.usage_periods where id = v_old_period),
    'Late completion and retry must charge the old month exactly once';
  assert (select used = 0 from public.usage_periods where id = v_new_period),
    'Late completion must not spend the new allowance';
  perform pg_temp.quota_call(p_mode, v_user, v_new_request, 'complete');
  if p_mode <> 'guest_llm' then
    assert pg_temp.get_usage_period('pomodoist', v_key)->>'used' = '1',
      'Reader must switch to the new counter';
    assert jsonb_array_length(pg_temp.get_account_overview() #> '{apps,0,usage}') = 1,
      'Overview must expose only the current month';
  end if;
  assert current_setting('TimeZone') = p_timezone, 'Readers must preserve the caller timezone';
end;
$$;

select lives_ok(
  format('select pg_temp.check_quota_reset(%L::timestamptz, %L, %L)', boundary, zone, mode),
  format('%s rollover: %s, %s', mode, boundary, zone))
from unnest(array['2027-02-01 00:00:00+00', '2027-03-01 00:00:00+00',
                  '2028-03-01 00:00:00+00', '2027-04-01 00:00:00+00',
                  '2027-05-01 00:00:00+00', '2028-01-01 00:00:00+00']) as boundary
cross join unnest(array['UTC', 'Europe/Moscow', 'America/Los_Angeles', 'Pacific/Kiritimati']) as zone
cross join unnest(array['voice', 'account_llm', 'guest_llm']) as mode;

select * from finish();
rollback;

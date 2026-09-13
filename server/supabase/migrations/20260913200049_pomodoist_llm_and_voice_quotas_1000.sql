begin;

insert into public.quota_definitions (app_id, quota_key, limit_value, unit, period)
values ('pomodoist', 'llm_requests', 1000, 'request', 'monthly')
on conflict (app_id, quota_key) do update set limit_value = 1000;
update public.quota_definitions set limit_value = 1000
where app_id = 'pomodoist' and quota_key = 'voice_transcriptions';
update public.usage_periods set limit_value = 1000
where app_id = 'pomodoist' and quota_key in ('voice_transcriptions', 'llm_requests')
  and period_start <= now() and period_end > now();

-- StoreKit-only callers have no profile. Keep their verified purchase counter in
-- the same ledger; the existing ownership RLS policy exposes no guest rows.
alter table public.usage_periods alter column user_id drop not null;
alter table public.usage_periods add column purchase_subject text;
alter table public.usage_periods add constraint usage_periods_owner_check check (
  (user_id is not null and purchase_subject is null) or
  (user_id is null and app_id = 'pomodoist' and quota_key = 'llm_requests'
   and purchase_subject is not null
   and purchase_subject ~ '^apple:(Production|Sandbox):[^:]{1,128}$')
);
create unique index usage_periods_purchase_period_idx
  on public.usage_periods (purchase_subject, app_id, quota_key, period_start)
  where purchase_subject is not null;
comment on column public.usage_periods.purchase_subject is
  'StoreKit-only LLM identity: apple:<environment>:<verified originalTransactionId>. Never supplied directly by a client.';

-- Reuse the voice request reservations and their ten-minute cleanup job. The
-- quota key on usage_periods separates STT and LLM counters and receipts.
create function public.pomodoist_llm_quota(p_user_id uuid, p_purchase_subject text, p_request_id uuid, p_action text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_period public.usage_periods%rowtype;
  v_request private.pomodoist_voice_requests%rowtype;
  v_start timestamptz := pg_catalog.date_trunc('month', now(), 'UTC');
  v_end timestamptz := (v_start at time zone 'UTC' + interval '1 month') at time zone 'UTC';
  v_limit integer;
  v_unit text;
  v_pending integer;
begin
  if pg_catalog.num_nonnulls(p_user_id, p_purchase_subject) <> 1
     or (p_purchase_subject is not null and p_purchase_subject !~ '^apple:(Production|Sandbox):[^:]{1,128}$')
     or p_request_id is null or p_action is null
     or p_action not in ('reserve', 'complete', 'release') then
    raise exception using errcode = '22023', message = 'Invalid LLM quota request';
  end if;

  select u.* into v_period
  from public.usage_periods u
  join private.pomodoist_voice_requests r on r.usage_period_id = u.id
  where r.request_id = p_request_id and u.app_id = 'pomodoist' and u.quota_key = 'llm_requests'
    and u.user_id is not distinct from p_user_id
    and u.purchase_subject is not distinct from p_purchase_subject
  for update of u;

  if not found then
    if p_action = 'release' then return jsonb_build_object('allowed', true); end if;
    if p_action = 'complete' then
      raise exception using errcode = '22023', message = 'LLM reservation expired or missing';
    end if;
    select limit_value, unit into v_limit, v_unit from public.quota_definitions
    where app_id = 'pomodoist' and quota_key = 'llm_requests' and period = 'monthly';
    if not found then raise exception 'LLM quota is not configured'; end if;
    if p_user_id is not null then
    insert into public.usage_periods (user_id, app_id, quota_key, period_start, period_end, used, limit_value, unit)
    values (p_user_id, 'pomodoist', 'llm_requests', v_start, v_end, 0, v_limit, v_unit)
    on conflict (user_id, app_id, quota_key, period_start) do update
    set limit_value = excluded.limit_value, period_end = excluded.period_end, unit = excluded.unit
    returning * into v_period;
    else
    insert into public.usage_periods (purchase_subject, app_id, quota_key, period_start, period_end, used, limit_value, unit)
    values (p_purchase_subject, 'pomodoist', 'llm_requests', v_start, v_end, 0, v_limit, v_unit)
    on conflict (purchase_subject, app_id, quota_key, period_start) where purchase_subject is not null do update
    set limit_value = excluded.limit_value, period_end = excluded.period_end, unit = excluded.unit
    returning * into v_period;
    end if;
  end if;

  select * into v_request from private.pomodoist_voice_requests
  where request_id = p_request_id and usage_period_id = v_period.id for update;

  if p_action = 'reserve' then
    if v_request.request_id is not null then
      return jsonb_build_object('allowed', not v_request.completed and v_request.expires_at > now(), 'resetsAt', v_period.period_end);
    end if;
    select count(*) into v_pending from private.pomodoist_voice_requests
    where usage_period_id = v_period.id and not completed and expires_at > now();
    if v_period.used::bigint + v_pending >= v_period.limit_value then
      return jsonb_build_object('allowed', false, 'resetsAt', v_period.period_end);
    end if;
    insert into private.pomodoist_voice_requests (request_id, usage_period_id)
    values (p_request_id, v_period.id);
  elsif p_action = 'complete' then
    if v_request.request_id is null or v_request.expires_at <= now() then
      raise exception using errcode = '22023', message = 'LLM reservation expired or missing';
    end if;
    if not v_request.completed then
      update public.usage_periods set used = used + 1 where id = v_period.id;
      update private.pomodoist_voice_requests set completed = true where request_id = p_request_id;
    end if;
  elsif not coalesce(v_request.completed, false) then
    delete from private.pomodoist_voice_requests where request_id = p_request_id and usage_period_id = v_period.id;
  end if;
  return jsonb_build_object('allowed', true, 'resetsAt', v_period.period_end);
end;
$$;
revoke all on function public.pomodoist_llm_quota(uuid,text,uuid,text) from public, anon, authenticated;
grant execute on function public.pomodoist_llm_quota(uuid,text,uuid,text) to service_role;

create or replace function public.consume_quota(
  p_app_id text, p_quota_key text, p_units integer,
  p_period_start timestamptz default null, p_period_end timestamptz default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_user_id uuid;
  v_definition public.quota_definitions%rowtype;
  v_row public.usage_periods%rowtype;
  v_start timestamptz := pg_catalog.date_trunc('month', now(), 'UTC');
  v_end timestamptz := (v_start at time zone 'UTC' + interval '1 month') at time zone 'UTC';
  v_allowed boolean;
begin
  if p_app_id = 'pomodoist' and p_quota_key = 'voice_transcriptions' then
    raise exception using errcode = '42501', message = 'Voice quota is managed by the transcription endpoint';
  end if;
  if p_app_id = 'pomodoist' and p_quota_key = 'llm_requests' then
    raise exception using errcode = '42501', message = 'LLM quota is managed by the task analysis endpoint';
  end if;
  if p_units is null or p_units <= 0 then
    raise exception using errcode = '22023', message = 'Quota units must be positive';
  end if;
  v_user_id := public.ensure_profile();
  select * into v_definition from public.quota_definitions
  where app_id = p_app_id and quota_key = p_quota_key;
  if not found then raise exception 'Unknown quota definition: %.%', p_app_id, p_quota_key; end if;
  insert into public.usage_periods (user_id, app_id, quota_key, period_start, period_end, used, limit_value, unit)
  values (v_user_id, p_app_id, p_quota_key, v_start, v_end, 0, v_definition.limit_value, v_definition.unit)
  on conflict (user_id, app_id, quota_key, period_start) do update
  set period_end = excluded.period_end, limit_value = excluded.limit_value, unit = excluded.unit
  returning * into v_row;
  v_allowed := v_row.used <= v_row.limit_value - p_units;
  if v_allowed then
    update public.usage_periods set used = used + p_units where id = v_row.id returning * into v_row;
  end if;
  return jsonb_build_object('allowed', v_allowed, 'appId', p_app_id, 'quotaKey', p_quota_key,
    'used', v_row.used, 'limit', v_row.limit_value, 'remaining', greatest(v_row.limit_value - v_row.used, 0),
    'unit', v_row.unit, 'resetsAt', v_row.period_end);
end;
$$;
revoke all on function public.consume_quota(text,text,integer,timestamptz,timestamptz) from public, anon;

notify pgrst, 'reload schema';
commit;

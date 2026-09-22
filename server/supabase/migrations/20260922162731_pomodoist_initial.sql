-- Pomodoist fresh-install baseline, extracted from a synthetic local schema.
-- No hosted database, user records or historical migration files were exported.
-- Squashed after all 17 legacy migrations; synthetic local database only.
-- IMMUTABLE after release. Existing hosted deployments MUST skip this baseline;
-- only later shared migrations are applied to both hosted and independent servers.
-- Requires migrated Supabase Auth and Realtime, Vault, pg_cron and pg_net.
-- The migration runner supplies the transaction; objects belong to postgres.
do $$
begin
  if to_regclass('public.profiles') is not null
     or to_regclass('public.sync_entities') is not null
     or to_regclass('private.pomodoist_instance_settings') is not null then
    raise exception 'Pomodoist initial schema is for empty databases only';
  end if;
  if to_regclass('auth.oauth_clients') is null
     or to_regclass('realtime.messages') is null then
    raise exception 'Run Supabase Auth and Realtime migrations first';
  end if;
end;
$$;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists "uuid-ossp" with schema extensions;
create extension if not exists supabase_vault with schema vault;
create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;
set local role postgres;
set local check_function_bodies = false;

do $$
begin
  if not exists (
    select 1
    from pg_roles
    where rolname = 'pomodoist_mcp'
  ) then
    create role pomodoist_mcp
      nologin
      noinherit
      nosuperuser
      nocreatedb
      nocreaterole
      noreplication
      nobypassrls;
  elsif exists (
    select 1
    from pg_roles
    where rolname = 'pomodoist_mcp'
      and (
        rolcanlogin
        or rolinherit
        or rolsuper
        or rolcreatedb
        or rolcreaterole
        or rolreplication
        or rolbypassrls
      )
  ) then
    raise exception 'Existing pomodoist_mcp role has unsafe attributes';
  end if;
end;
$$;

alter role pomodoist_mcp set search_path = pg_catalog;
grant pomodoist_mcp to authenticator;

--
-- PostgreSQL database dump
--


-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: private; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA private;


ALTER SCHEMA private OWNER TO postgres;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: pg_database_owner
--

CREATE SCHEMA IF NOT EXISTS public;


ALTER SCHEMA public OWNER TO pg_database_owner;

--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: pg_database_owner
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: additional_account_overview(uuid, text); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.additional_account_overview(p_user_id uuid, p_app_id text) RETURNS jsonb
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
      select '{}'::jsonb;
      $$;


ALTER FUNCTION private.additional_account_overview(p_user_id uuid, p_app_id text) OWNER TO postgres;

--
-- Name: capture_pomodoist_return_offer(); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.capture_pomodoist_return_offer() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $_$
begin
  if new.environment in ('Production', 'Sandbox')
    and new.raw_claims ->> 'appTransactionId' ~ '^[0-9]{1,128}$'
    and new.raw_claims ->> 'offerIdentifier' in ('return_monthly_2026_v1', 'return_annual_2026_v1') then
    insert into private.pomodoist_subscription_offers(environment, app_transaction_id, campaign_id, redeemed)
    values(new.environment, new.raw_claims ->> 'appTransactionId', 'return-2026-v1', true)
    on conflict (environment, app_transaction_id, campaign_id) do update set redeemed = true;
  end if;
  return new;
end;
$_$;


ALTER FUNCTION private.capture_pomodoist_return_offer() OWNER TO postgres;

--
-- Name: consume_quota(text, text, integer, timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.consume_quota(p_app_id text, p_quota_key text, p_units integer, p_period_start timestamp with time zone DEFAULT NULL::timestamp with time zone, p_period_end timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
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


ALTER FUNCTION private.consume_quota(p_app_id text, p_quota_key text, p_units integer, p_period_start timestamp with time zone, p_period_end timestamp with time zone) OWNER TO postgres;

--
-- Name: enforce_single_active_pomodoist_focus(); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.enforce_single_active_pomodoist_focus() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_new_lock bigint := pg_catalog.hashtextextended(
    new.user_id::text || ':pomodoist:focus',
    0
  );
  v_old_lock bigint;
begin
  if tg_op = 'UPDATE' and old.user_id is distinct from new.user_id then
    v_old_lock := pg_catalog.hashtextextended(
      old.user_id::text || ':pomodoist:focus',
      0
    );
    perform pg_catalog.pg_advisory_xact_lock(
      least(v_old_lock, v_new_lock)
    );
    perform pg_catalog.pg_advisory_xact_lock(
      greatest(v_old_lock, v_new_lock)
    );
  else
    perform pg_catalog.pg_advisory_xact_lock(v_new_lock);
  end if;

  if new.deleted_at is null and new.data ->> 'status' in ('active', 'paused') then
    if tg_op = 'INSERT' then
      if exists (
        select 1
        from public.sync_entities
        where user_id = new.user_id
          and app_id = 'pomodoist'
          and entity_type = 'focus_run'
          and deleted_at is null
          and data ->> 'status' in ('active', 'paused')
          and not (
            user_id = new.user_id
            and app_id = new.app_id
            and entity_type = new.entity_type
            and entity_id = new.entity_id
          )
      ) then
        raise exception using errcode = '23505', message = 'Pomodoist Focus already active';
      end if;
    elsif exists (
      select 1
      from public.sync_entities
      where user_id = new.user_id
        and app_id = 'pomodoist'
        and entity_type = 'focus_run'
        and deleted_at is null
        and data ->> 'status' in ('active', 'paused')
        and not (
          user_id = old.user_id
          and app_id = old.app_id
          and entity_type = old.entity_type
          and entity_id = old.entity_id
        )
    ) then
      raise exception using errcode = '23505', message = 'Pomodoist Focus already active';
    end if;
  end if;
  return new;
end;
$$;


ALTER FUNCTION private.enforce_single_active_pomodoist_focus() OWNER TO postgres;

--
-- Name: ensure_profile(); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.ensure_profile() RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_user_id uuid := auth.uid();
  v_email text;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  select email into v_email from auth.users where id = v_user_id;

  insert into public.profiles (id, email, revenuecat_app_user_id)
  values (v_user_id, v_email, v_user_id::text)
  on conflict (id) do nothing;

  perform private.grant_pomodoist_selfhost_access(v_user_id);

  return v_user_id;
end;
$$;


ALTER FUNCTION private.ensure_profile() OWNER TO postgres;

--
-- Name: get_account_overview(); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.get_account_overview() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    SET "TimeZone" TO 'UTC'
    AS $$
declare
  v_user_id uuid := public.ensure_profile();
  v_profile jsonb;
  v_apps jsonb;
begin
  select jsonb_build_object(
    'id', p.id,
    'email', p.email,
    'displayName', p.display_name,
    'avatarUrl', p.avatar_url,
    'revenueCatAppUserId', p.revenuecat_app_user_id,
    'appleAppAccountToken', p.apple_app_account_token,
    'pomodoistIsPro', p.pomodoist_is_pro
  )
  into v_profile
  from public.profiles p
  where p.id = v_user_id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', a.id,
        'displayName', a.display_name,
        'installed', exists (
          select 1
          from public.user_app_installs i
          where i.user_id = v_user_id
            and i.app_id = a.id
        ),
        'entitlements', coalesce((
          select jsonb_agg(jsonb_build_object(
            'appId', e.app_id,
            'entitlementId', e.entitlement_id,
            'status', e.status,
            'purchaseType', e.purchase_type,
            'source', e.source,
            'productId', e.product_id,
            'store', e.store,
            'validUntil', e.valid_until,
            'renewsAt', e.renews_at
          ) order by e.updated_at desc)
          from public.user_entitlements e
          where e.user_id = v_user_id
            and e.app_id = a.id
        ), '[]'::jsonb),
        'usage', coalesce((
          select jsonb_agg(jsonb_build_object(
            'appId', u.app_id,
            'quotaKey', u.quota_key,
            'used', u.used,
            'limit', u.limit_value,
            'unit', u.unit,
            'periodEnd', u.period_end
          ) order by u.period_end desc)
          from public.usage_periods u
          where u.user_id = v_user_id
            and u.app_id = a.id
            and u.period_end > timezone('utc', now())
        ), '[]'::jsonb),
        'purchaseBinding', null,
        'storage', null
      )
      order by case when a.id = 'pomodoist' then 1 else 2 end, a.id
    ),
    '[]'::jsonb
  )
  into v_apps
  from public.apps a;

  return jsonb_build_object(
    'profile', v_profile,
    'apps', v_apps,
    'generatedAt', timezone('utc', now())
  );
end;
$$;


ALTER FUNCTION private.get_account_overview() OWNER TO postgres;

--
-- Name: get_apple_app_account_token(); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.get_apple_app_account_token() RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_user_id uuid := public.ensure_profile();
  v_token uuid;
begin
  select p.apple_app_account_token
  into v_token
  from public.profiles p
  where p.id = v_user_id;

  return v_token;
end;
$$;


ALTER FUNCTION private.get_apple_app_account_token() OWNER TO postgres;

--
-- Name: get_usage_period(text, text, timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.get_usage_period(p_app_id text, p_quota_key text, p_period_start timestamp with time zone DEFAULT NULL::timestamp with time zone, p_period_end timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    SET "TimeZone" TO 'UTC'
    AS $$
declare
  v_user_id uuid := public.ensure_profile();
  v_definition public.quota_definitions%rowtype;
  v_start timestamptz := coalesce(
    p_period_start,
    date_trunc('month', timezone('utc', now()))::timestamptz
  );
  v_end timestamptz := coalesce(p_period_end, v_start + interval '1 month');
  v_row public.usage_periods%rowtype;
begin
  select *
  into v_definition
  from public.quota_definitions
  where app_id = p_app_id
    and quota_key = p_quota_key;

  if not found then
    raise exception 'Unknown quota definition: %.%', p_app_id, p_quota_key;
  end if;

  select *
  into v_row
  from public.usage_periods
  where user_id = v_user_id
    and app_id = p_app_id
    and quota_key = p_quota_key
    and period_start = v_start;

  return jsonb_build_object(
    'appId', p_app_id,
    'quotaKey', p_quota_key,
    'used', coalesce(v_row.used, 0),
    'limit', coalesce(v_row.limit_value, v_definition.limit_value),
    'remaining', greatest(
      coalesce(v_row.limit_value, v_definition.limit_value) -
      coalesce(v_row.used, 0),
      0
    ),
    'unit', coalesce(v_row.unit, v_definition.unit),
    'periodEnd', coalesce(v_row.period_end, v_end),
    'resetsAt', coalesce(v_row.period_end, v_end)
  );
end;
$$;


ALTER FUNCTION private.get_usage_period(p_app_id text, p_quota_key text, p_period_start timestamp with time zone, p_period_end timestamp with time zone) OWNER TO postgres;

--
-- Name: grant_pomodoist_selfhost_access(uuid); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.grant_pomodoist_selfhost_access(p_user_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not exists (
    select 1 from private.pomodoist_instance_settings
    where singleton and selfhost_features_enabled
  ) then
    return;
  end if;
  insert into public.user_entitlements (
    user_id, app_id, entitlement_id, source, purchase_type, status, valid_from
  ) values (
    p_user_id, 'pomodoist', 'pomodoist_selfhost', 'selfhosted',
    'lifetime', 'active', now()
  ) on conflict (user_id, app_id, entitlement_id) do nothing;
end;
$$;


ALTER FUNCTION private.grant_pomodoist_selfhost_access(p_user_id uuid) OWNER TO postgres;

--
-- Name: initialize_additional_account(uuid); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.initialize_additional_account(p_user_id uuid) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
      begin return; end;
      $$;


ALTER FUNCTION private.initialize_additional_account(p_user_id uuid) OWNER TO postgres;

--
-- Name: invoke_pomodoist_google_calendar_worker(); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.invoke_pomodoist_google_calendar_worker() RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_url text;
  v_secret text;
  v_request_id bigint;
begin
  if not exists (
    select 1
    from private.pomodoist_google_calendar_jobs job
    where (job.status = 'pending'
        and job.due_at <= pg_catalog.timezone('utc', pg_catalog.now()))
       or (job.status = 'processing'
        and job.lease_until <= pg_catalog.timezone('utc', pg_catalog.now()))
  ) then
    return null;
  end if;
  select decrypted_secret into v_url
  from vault.decrypted_secrets
  where name = 'pomodoist-google-calendar-worker-url'
  order by updated_at desc limit 1;
  select decrypted_secret into v_secret
  from vault.decrypted_secrets
  where name = 'pomodoist-google-calendar-worker-secret'
  order by updated_at desc limit 1;
  if coalesce(v_url, '') = '' or coalesce(v_secret, '') = '' then
    return null;
  end if;
  select net.http_post(
    url := v_url,
    body := '{}'::jsonb,
    headers := pg_catalog.jsonb_build_object(
      'Content-Type', 'application/json',
      'X-Pomodoist-Worker-Secret', v_secret
    ),
    timeout_milliseconds := 55000
  ) into v_request_id;
  return v_request_id;
end;
$$;


ALTER FUNCTION private.invoke_pomodoist_google_calendar_worker() OWNER TO postgres;

--
-- Name: on_pomodoist_task_calendar_change(); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.on_pomodoist_task_calendar_change() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_user_id uuid;
  v_task_id text;
  v_updated_at timestamptz;
begin
  if tg_op = 'DELETE' then
    if old.app_id <> 'pomodoist' or old.entity_type <> 'task' then return old; end if;
    v_user_id := old.user_id;
    v_task_id := old.entity_id;
    v_updated_at := old.client_updated_at;
  else
    if new.app_id = 'pomodoist'
      and new.entity_type = 'google_calendar_connection'
      and new.entity_id = 'primary'
      and coalesce(new.data ->> 'ownerDeviceId', '') <> 'google-calendar-server'
      and exists (
        select 1
        from private.pomodoist_google_calendar_accounts account
        where account.user_id = new.user_id and account.status <> 'disconnected'
    )
    then
      update private.pomodoist_google_calendar_accounts account
      set updated_at = greatest(
        account.updated_at,
        new.client_updated_at + interval '1 microsecond',
        pg_catalog.now()
      )
      where account.user_id = new.user_id;
      perform private.project_pomodoist_google_calendar_connection(new.user_id);
      return new;
    end if;
    if new.app_id <> 'pomodoist' or new.entity_type <> 'task' then return new; end if;
    v_user_id := new.user_id;
    v_task_id := new.entity_id;
    v_updated_at := new.client_updated_at;
  end if;
  if tg_op = 'INSERT'
    or tg_op = 'DELETE'
    or old.data -> 'dueJson' is distinct from new.data -> 'dueJson'
    or old.deleted_at is distinct from new.deleted_at
  then
    insert into private.pomodoist_google_calendar_task_state (
      user_id, task_id, local_schedule_updated_at
    ) values (v_user_id, v_task_id, v_updated_at)
    on conflict (user_id, task_id) do update
    set local_schedule_updated_at = excluded.local_schedule_updated_at;
  end if;
  perform private.queue_pomodoist_google_calendar(v_user_id);
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;


ALTER FUNCTION private.on_pomodoist_task_calendar_change() OWNER TO postgres;

--
-- Name: pomodoist_account_deletion_check(uuid); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.pomodoist_account_deletion_check(p_user_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode='42501',message='Service role required'; end if;
  return jsonb_build_object('ownedScopes',coalesce((select jsonb_agg(jsonb_build_object('scopeId',id,'rootProjectId',root_project_id))
    from private.pomodoist_scopes where owner_id=p_user_id),'[]'));
end $$;


ALTER FUNCTION private.pomodoist_account_deletion_check(p_user_id uuid) OWNER TO postgres;

--
-- Name: pomodoist_collaboration(jsonb); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.pomodoist_collaboration(p_request jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    SET "TimeZone" TO 'UTC'
    AS $_$
declare
  actor uuid:=auth.uid(); action text:=p_request->>'action'; scope uuid; role_name text;
  s private.pomodoist_scopes%rowtype; invitation private.pomodoist_invitations%rowtype;
  upload private.pomodoist_uploads%rowtype; rec record; result jsonb; d jsonb; rows jsonb;
  applied jsonb:='[]'; conflicts jsonb:='[]'; rejected jsonb:='[]'; operation jsonb; receipt record;
  target uuid; ids text[]; task_ids text[]; token text; since bigint; cursor_value bigint; more boolean;
  paid boolean; amount bigint; held bigint; used_month bigint; used_year bigint; month_start date; yr integer; object_size bigint;
begin
  if octet_length(p_request::text)>1000000 then raise exception using errcode='22023',message='Request is too large'; end if;
  if jsonb_typeof(p_request) is distinct from 'object' then raise exception using errcode='22023',message='Expected request object'; end if;
  if action='publicRead' then
    select * into s from private.pomodoist_scopes where public_token=p_request->>'token' and length(p_request->>'token')=64;
    if not found then raise exception using errcode='42501',message='Public link is unavailable'; end if;
    select coalesce(jsonb_agg(jsonb_build_object('id',entity_id,'entityType',entity_type,
      'data',(select coalesce(jsonb_object_agg(k,v),'{}') from jsonb_each(e.data) a(k,v)
        where k in ('name','content','description','parentId','projectId','taskId','body','dueJson','deadlineJson','status','priority','orderKey','createdAt','updatedAt','completedAt'))
        ||jsonb_build_object('creatorName',coalesce((select display_name from public.profiles where id::text=e.data->>'createdBy'),'Member'),
          'assigneeNames',coalesce((select jsonb_agg(coalesce(p.display_name,'Member')) from public.profiles p
            where p.id::text in(select jsonb_array_elements_text(coalesce(e.data->'assigneeIds','[]')))),'[]')))
      order by e.server_revision),'[]') into rows from private.pomodoist_shared_entities e
      where scope_id=s.id and entity_type in ('project','task','comment') and deleted_at is null
      and (entity_type<>'comment' or exists(select 1 from private.pomodoist_shared_entities t where t.scope_id=s.id
        and t.entity_type='task' and t.entity_id=e.data->>'taskId' and t.deleted_at is null));
    return jsonb_build_object('scopeId',s.id,'rootProjectId',s.root_project_id,'entities',rows);
  end if;
  -- Deleted users and revoked sessions must not retain access through unexpired JWTs.
  if actor is null or not exists(select 1 from auth.users where id=actor and not coalesce(is_anonymous,false))
    or not exists(select 1 from auth.sessions where user_id=actor and id::text=auth.jwt()->>'session_id'
      and (not_after is null or not_after>now())) then
    raise exception using errcode='42501',message='An active authenticated session is required';
  end if;
  if action in ('state','notifications') then
    for rec in select scope_id from private.pomodoist_members where user_id=actor loop
      perform private.pomodoist_history_refresh(rec.scope_id);
    end loop;
    perform private.pomodoist_history_refresh(null,actor);
    select coalesce(jsonb_agg(jsonb_build_object('id',id,'scopeId',scope_id,'kind',kind,'data',data,'readAt',read_at,'createdAt',created_at)
      order by created_at desc),'[]') into rows from (select * from private.pomodoist_notifications where user_id=actor order by created_at desc limit 200) n;
    if action='notifications' then return jsonb_build_object('notifications',rows); end if;
    return jsonb_build_object('userId',actor,'scopes',coalesce((select jsonb_agg(private.pomodoist_scope_json(scope_id,actor))
      from private.pomodoist_members where user_id=actor),'[]'),'notifications',rows,
      'preferences',private.pomodoist_preferences_json(actor),
      'invitations',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'scopeId',i.scope_id,'role',i.role,'token',i.token,'expiresAt',i.expires_at))
        from private.pomodoist_invitations i join auth.users u on lower(u.email)=i.email where u.id=actor
        and u.email_confirmed_at is not null and i.revoked_at is null and i.accepted_at is null and i.expires_at>now()),'[]'),
      'personalHistory',(select jsonb_build_object('historyUnlimited',history_unlimited,'graceEndsAt',grace_ends_at)
        from private.pomodoist_personal_history where user_id=actor),
      'personalRevision',coalesce((select max(server_revision) from public.sync_entities where user_id=actor and app_id='pomodoist'),0));
  elsif action='readNotification' then
    update private.pomodoist_notifications set read_at=coalesce(read_at,now()) where id=(p_request->>'notificationId')::uuid and user_id=actor;
    return jsonb_build_object('ok',true);
  elsif action='share' then
    perform pg_advisory_xact_lock(hashtextextended('pomodoist-google-calendar:'||actor::text,0));
    if p_request->>'rootProjectId'='inbox' then raise exception using errcode='22023',message='Inbox cannot be shared'; end if;
    select coalesce(max(server_revision),0) into cursor_value from public.sync_entities where user_id=actor and app_id='pomodoist';
    if p_request->>'expectedRevision' is null or (p_request->>'expectedRevision')::bigint<>cursor_value then
      raise exception using errcode='22023',message='Complete personal sync before sharing'; end if;
    if not exists(select 1 from public.sync_entities where user_id=actor and app_id='pomodoist' and entity_type='project'
      and entity_id=p_request->>'rootProjectId' and deleted_at is null) then raise exception using errcode='22023',message='Personal project not found'; end if;
    with recursive tree as (
      select entity_id from public.sync_entities where user_id=actor and app_id='pomodoist' and entity_type='project' and entity_id=p_request->>'rootProjectId' and deleted_at is null
      union select e.entity_id from public.sync_entities e join tree t on e.data->>'parentId'=t.entity_id
        where e.user_id=actor and e.app_id='pomodoist' and e.entity_type='project' and e.deleted_at is null)
    select array_agg(entity_id) into ids from tree;
    if exists(select 1 from public.sync_entities e join private.pomodoist_transferred_entities t on t.user_id=e.user_id
      and t.entity_type=e.entity_type and t.entity_id=e.entity_id where e.user_id=actor and e.app_id='pomodoist'
      and e.entity_type='project' and e.data->>'parentId'=any(ids)) then
      raise exception using errcode='22023',message='A shared root cannot contain another shared root'; end if;
    select array_agg(entity_id) into task_ids from public.sync_entities where user_id=actor and app_id='pomodoist'
      and entity_type='task' and data->>'projectId'=any(ids);
    insert into private.pomodoist_scopes(root_project_id,owner_id) values(p_request->>'rootProjectId',actor) returning * into s;
    insert into private.pomodoist_members(scope_id,user_id,role) values(s.id,actor,'administrator');
    insert into private.pomodoist_shared_preferences(scope_id,user_id,entity_type,entity_id,data)
      select s.id,actor,'scope',s.id::text,jsonb_build_object('rootParentId',data->'parentId') from public.sync_entities
      where user_id=actor and app_id='pomodoist' and entity_type='project' and entity_id=s.root_project_id;
    for rec in select * from public.sync_entities where user_id=actor and app_id='pomodoist'
      and ((entity_type='project' and entity_id=any(ids)) or (entity_type='task' and entity_id=any(task_ids))) loop
      insert into private.pomodoist_shared_preferences(scope_id,user_id,entity_type,entity_id,data)
        values(s.id,actor,rec.entity_type,case when rec.entity_type='label' then s.id::text||':'||rec.entity_id else rec.entity_id end,
          (select coalesce(jsonb_object_agg(key,value),'{}') from jsonb_each(rec.data) where key in ('isFavorite','isCollapsed','dayOrder','viewStyle','viewPreferences','reminders')))
        on conflict(scope_id,user_id,entity_type,entity_id) do nothing;
      d:=(rec.data-array['userId','dayOrder','isCollapsed','isFavorite','reminderJson','reminders','viewPreferences','viewStyle','completedFocusIntervals','totalFocusSeconds'])
        ||jsonb_build_object('scopeId',s.id,'createdBy',coalesce(rec.data->>'createdBy',actor::text));
      if rec.entity_type='project' and rec.entity_id=s.root_project_id then d:=d||jsonb_build_object('parentId',null); end if;
      if rec.entity_type='task' then
        d:=d||jsonb_build_object('assigneeIds','[]'::jsonb,'completedBy',case when d->>'status'='completed' then actor else null end);
        if d->>'parentId' is not null and not(d->>'parentId'=any(coalesce(task_ids,array[]::text[]))) then d:=d||jsonb_build_object('parentId',null); end if;
      end if;
      perform private.pomodoist_shared_put(s.id,rec.entity_type,rec.entity_id,d,rec.deleted_at);
      update public.sync_entities set deleted_at=coalesce(deleted_at,now()),server_revision=nextval('public.sync_revision_seq'),updated_at=now()
        where user_id=actor and app_id='pomodoist' and entity_type=rec.entity_type and entity_id=rec.entity_id;
      insert into private.pomodoist_transferred_entities values(actor,rec.entity_type,rec.entity_id,s.id);
    end loop;
    for rec in select * from public.sync_entities where user_id=actor and app_id='pomodoist' and deleted_at is null
      and ((entity_type='section' and data->>'projectId'=any(ids))
        or (entity_type in ('task_label','task_kanban_status','task_completion') and data->>'taskId'=any(task_ids))
        or (entity_type='focus_interval' and data->>'taskId'=any(task_ids) and data->>'type'='work' and data->>'status'='completed')
        or (entity_type='label' and entity_id in(select data->>'labelId' from public.sync_entities where user_id=actor
          and app_id='pomodoist' and entity_type in ('task_label','task_kanban_status') and data->>'taskId'=any(task_ids))) or (entity_type='label' and data->>'kind'='kanbanStatus')) loop
      insert into private.pomodoist_shared_preferences(scope_id,user_id,entity_type,entity_id,data)
        values(s.id,actor,rec.entity_type,case when rec.entity_type='label' then s.id::text||':'||rec.entity_id else rec.entity_id end,
          (select coalesce(jsonb_object_agg(key,value),'{}') from jsonb_each(rec.data) where key in ('isFavorite','isCollapsed','dayOrder','viewStyle','viewPreferences','reminders')))
        on conflict(scope_id,user_id,entity_type,entity_id) do nothing;
      d:=(rec.data-array['userId','dayOrder','isCollapsed','isFavorite'])||jsonb_build_object('scopeId',s.id,'createdBy',actor);
      if rec.entity_type in ('task_completion','focus_interval') then d:=d||jsonb_build_object('userId',actor); end if;
      if rec.entity_type='focus_interval' then
        d:=d||jsonb_build_object('durationSeconds',coalesce((d->>'durationSeconds')::integer,(d->>'plannedSeconds')::integer));
      end if;
      if rec.entity_type='label' then
        d:=d||jsonb_build_object('id',s.id::text||':'||rec.entity_id);
        perform private.pomodoist_shared_put(s.id,'label',s.id::text||':'||rec.entity_id,d);
      elsif rec.entity_type in ('task_label','task_kanban_status') then
        d:=d||jsonb_build_object('labelId',s.id::text||':'||(rec.data->>'labelId'));
        d:=d||jsonb_build_object('id',case when rec.entity_type='task_label'
          then (d->>'taskId')||':'||(d->>'labelId') else rec.entity_id end);
        perform private.pomodoist_shared_put(s.id,rec.entity_type,
          case when rec.entity_type='task_label' then (d->>'taskId')||':'||(d->>'labelId') else rec.entity_id end,d);
      else perform private.pomodoist_shared_put(s.id,rec.entity_type,rec.entity_id,d); end if;
      if rec.entity_type not in ('label','focus_interval') then
        update public.sync_entities set deleted_at=now(),server_revision=nextval('public.sync_revision_seq'),updated_at=now()
          where user_id=actor and app_id='pomodoist' and entity_type=rec.entity_type and entity_id=rec.entity_id;
        insert into private.pomodoist_transferred_entities values(actor,rec.entity_type,rec.entity_id,s.id);
      end if;
    end loop;
    for rec in select * from private.pomodoist_shared_entities where scope_id=s.id and entity_type='task' loop
      select jsonb_build_object('totalFocusSeconds',coalesce(sum(coalesce((data->>'durationSeconds')::bigint,(data->>'plannedSeconds')::bigint)),0),
        'completedFocusIntervals',count(*)) into d from private.pomodoist_shared_entities where scope_id=s.id and entity_type='focus_interval'
        and data->>'taskId'=rec.entity_id and deleted_at is null and data->>'type'='work' and data->>'status'='completed';
      perform private.pomodoist_shared_put(s.id,'task',rec.entity_id,rec.data||d,rec.deleted_at);
    end loop;
    perform private.pomodoist_history_refresh(s.id);
    perform private.pomodoist_collaboration_event(s.id,actor,'shared',s.root_project_id);
    return jsonb_build_object('scope',private.pomodoist_scope_json(s.id,actor));
  elsif action='accept' then
    select i.scope_id into scope from private.pomodoist_invitations i where i.token=p_request->>'token';
  else scope:=(p_request->>'scopeId')::uuid;
  end if;
  select * into s from private.pomodoist_scopes where id=scope for update;
  if not found then raise exception using errcode='42501',message='Shared scope is inaccessible'; end if;
  if action='accept' then
    select i.* into invitation from private.pomodoist_invitations i where i.token=p_request->>'token' and i.scope_id=scope for update;
    if invitation.revoked_at is not null or invitation.expires_at<=now() or
      (invitation.email is not null and not exists(select 1 from auth.users where id=actor and lower(email)=invitation.email and email_confirmed_at is not null))
      or (invitation.accepted_by is not null and invitation.accepted_by<>actor) then
      raise exception using errcode='42501',message='Invitation is unavailable for this account'; end if;
    if exists(select 1 from private.pomodoist_members where scope_id=scope and user_id=actor) then
      return jsonb_build_object('scope',private.pomodoist_scope_json(scope,actor)); end if;
    insert into private.pomodoist_members(scope_id,user_id,role) values(scope,actor,invitation.role) on conflict do nothing;
    if invitation.email is not null then update private.pomodoist_invitations set accepted_by=actor,accepted_at=coalesce(accepted_at,now()) where id=invitation.id; end if;
    perform private.pomodoist_history_refresh(scope);
    perform private.pomodoist_collaboration_event(scope,actor,'member.joined',actor::text);
    return jsonb_build_object('scope',private.pomodoist_scope_json(scope,actor));
  end if;
  select role into role_name from private.pomodoist_members where scope_id=scope and user_id=actor;
  if role_name is null then raise exception using errcode='42501',message='Shared scope is inaccessible'; end if;
  perform private.pomodoist_history_refresh(scope);
  if action='preferences' then
    if coalesce(p_request->>'entityType','') not in ('scope','project','task','label','section')
      or coalesce(p_request->>'entityId','')='' or jsonb_typeof(p_request->'data') is distinct from 'object'
      or exists(select 1 from jsonb_object_keys(p_request->'data') k where k not in ('isFavorite','isCollapsed','dayOrder','reminders','viewStyle','viewPreferences','rootParentId')) then
      raise exception using errcode='22023',message='Invalid private preferences'; end if;
    if p_request->>'entityType'='scope' then
      if p_request->>'entityId'<>scope::text then raise exception using errcode='22023',message='Invalid scope preference identity'; end if;
    elsif not exists(select 1 from private.pomodoist_shared_entities where scope_id=scope and entity_type=p_request->>'entityType'
      and entity_id=p_request->>'entityId' and deleted_at is null) then raise exception using errcode='42501',message='Preference entity is inaccessible'; end if;
    if p_request->'data' ? 'rootParentId' then
      if p_request->>'entityType'<>'scope' then raise exception using errcode='22023',message='Root placement is a scope preference'; end if;
      if p_request->'data'->>'rootParentId' is not null and not exists(select 1 from public.sync_entities where user_id=actor and app_id='pomodoist'
        and entity_type='project' and entity_id=p_request->'data'->>'rootParentId' and deleted_at is null) then
        raise exception using errcode='22023',message='Root parent must be an accessible personal project'; end if;
    end if;
    insert into private.pomodoist_shared_preferences(scope_id,user_id,entity_type,entity_id,data)
      values(scope,actor,p_request->>'entityType',p_request->>'entityId',p_request->'data')
      on conflict(scope_id,user_id,entity_type,entity_id) do update
      set data=private.pomodoist_shared_preferences.data||excluded.data,updated_at=now();
    perform private.pomodoist_collaboration_hint(null,actor);
    return jsonb_build_object('preferences',private.pomodoist_preferences_json(actor,scope));
  end if;
  if action='members' then return jsonb_build_object('members',private.pomodoist_members_json(scope),
    'invitations',case when role_name='administrator' then coalesce((select jsonb_agg(jsonb_build_object('id',id,'email',email,'role',role,'expiresAt',expires_at,'revokedAt',revoked_at,'acceptedAt',accepted_at))
      from private.pomodoist_invitations where scope_id=scope),'[]') else '[]'::jsonb end);
  elsif action in ('pull','export') then
    since:=coalesce((p_request->>'sinceRevision')::bigint,0);
    if since<0 then raise exception using errcode='22023',message='Invalid cursor'; end if;
    with page as (select * from private.pomodoist_shared_entities where scope_id=scope and server_revision>since order by server_revision limit 501),
      limited as (select * from page order by server_revision limit 500)
    select coalesce(jsonb_agg(jsonb_build_object('entityType',entity_type,'entityId',entity_id,'data',data,'serverRevision',server_revision,
      'deletedAt',deleted_at,'updatedAt',updated_at) order by server_revision),'[]'),coalesce(max(server_revision),s.revision),
      (select count(*)>500 from page) into rows,cursor_value,more from limited;
    return jsonb_build_object('changes',rows,'nextCursor',cursor_value,'hasMore',more,'members',private.pomodoist_members_json(scope),
      'scope',private.pomodoist_scope_json(scope,actor),'preferences',private.pomodoist_preferences_json(actor,scope));
  elsif action='push' then
    if jsonb_typeof(p_request->'operations') is distinct from 'array' or jsonb_array_length(p_request->'operations')>200 then
      raise exception using errcode='22023',message='Expected at most 200 operations'; end if;
    for operation in select value from jsonb_array_elements(p_request->'operations') loop
      begin
        select stored.request,stored.result into receipt from private.pomodoist_shared_receipts stored
          where stored.scope_id=scope and stored.user_id=actor and stored.op_id=operation->>'opId';
        if found then
          if receipt.request<>operation then raise exception using errcode='22023',message='Operation ID was reused with different content'; end if;
          result:=receipt.result;
        else
          result:=private.pomodoist_shared_apply(scope,actor,role_name,operation);
          insert into private.pomodoist_shared_receipts values(scope,actor,operation->>'opId',operation,result);
        end if;
      exception when others then result:=jsonb_build_object('opId',operation->>'opId','status','rejected','code',sqlstate,'error',sqlerrm);
      end;
      if result->>'status'='applied' then applied:=applied||jsonb_build_array(result);
      elsif result->>'status'='conflict' then conflicts:=conflicts||jsonb_build_array(result);
      else rejected:=rejected||jsonb_build_array(result); end if;
    end loop;
    return jsonb_build_object('applied',applied,'conflicts',conflicts,'rejected',rejected);
  elsif action='unshare' and actor<>s.owner_id then
    raise exception using errcode='42501',message='Only the owner may make the project private';
  elsif action in ('invite','role','remove','transfer','delete','publicLink') and role_name<>'administrator' then
    raise exception using errcode='42501',message='Administrator role required';
  end if;
  if action='invite' then
    if p_request->>'invitationId' is not null and p_request->>'revoke'='true' then
      update private.pomodoist_invitations set revoked_at=coalesce(revoked_at,now()) where scope_id=scope and id=(p_request->>'invitationId')::uuid;
      return jsonb_build_object('ok',true);
    end if;
    if coalesce(p_request->>'role','member') not in ('member','observer') then raise exception using errcode='22023',message='Invitation role must be member or observer'; end if;
    if p_request->>'email' is not null and (length(p_request->>'email')>254 or (p_request->>'email')!~'^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$') then
      raise exception using errcode='22023',message='Invalid invitation email'; end if;
    if (select count(*) from private.pomodoist_invitations where scope_id=scope and created_at>now()-interval '1 hour')>=50 then
      raise exception using errcode='54000',message='Invitation rate limit exceeded'; end if;
    insert into private.pomodoist_invitations(scope_id,email,role,created_by)
      values(scope,lower(p_request->>'email'),coalesce(p_request->>'role','member'),actor) returning * into invitation;
    insert into private.pomodoist_notifications(user_id,scope_id,kind,data) select id,scope,'invitation',jsonb_build_object('invitationId',invitation.id)
      from auth.users where lower(email)=invitation.email;
    perform private.pomodoist_collaboration_event(scope,actor,'invitation.created',invitation.id::text);
    return jsonb_build_object('id',invitation.id,'token',invitation.token,'email',invitation.email,'role',invitation.role,'expiresAt',invitation.expires_at);
  elsif action in ('role','remove','leave','transfer') then
    target:=case when action='leave' then actor else (p_request->>'userId')::uuid end;
    if not exists(select 1 from private.pomodoist_members where scope_id=scope and user_id=target) then raise exception using errcode='22023',message='Member not found'; end if;
    if action='transfer' then
      if actor<>s.owner_id then raise exception using errcode='42501',message='Only the owner may transfer ownership'; end if;
      update private.pomodoist_members set role='administrator' where scope_id=scope and user_id=target;
      update private.pomodoist_scopes set owner_id=target where id=scope;
    else
      if target=s.owner_id then raise exception using errcode='42501',message='Owner must transfer ownership or delete the shared root'; end if;
      if action='role' then
        if coalesce(p_request->>'role','') not in ('administrator','member','observer') then raise exception using errcode='22023',message='Invalid role'; end if;
        update private.pomodoist_members set role=p_request->>'role' where scope_id=scope and user_id=target;
      else
        delete from private.pomodoist_members where scope_id=scope and user_id=target;
        delete from private.pomodoist_notifications where scope_id=scope and user_id=target;
      end if;
      if action<>'role' or p_request->>'role'='observer' then
        for rec in select * from private.pomodoist_shared_entities where scope_id=scope and entity_type='task' and data->'assigneeIds' ? target::text loop
          perform private.pomodoist_shared_put(scope,'task',rec.entity_id,rec.data||jsonb_build_object('assigneeIds',(rec.data->'assigneeIds')-target::text),rec.deleted_at);
        end loop;
      end if;
    end if;
    perform private.pomodoist_history_refresh(scope);
    perform private.pomodoist_collaboration_hint(scope,target);
    perform private.pomodoist_collaboration_event(scope,actor,'access.'||action,target::text);
    return jsonb_build_object('ok',true,'members',case when action='leave' then '[]'::jsonb else private.pomodoist_members_json(scope) end);
  elsif action='delete' then
    if actor<>s.owner_id then raise exception using errcode='42501',message='Only the owner may delete the shared root'; end if;
    for rec in select * from private.pomodoist_uploads where scope_id=scope and deleted_at is null loop
      if rec.finished_at is not null then
        update private.pomodoist_upload_years set bytes=bytes-rec.bytes where user_id=rec.user_id and year=extract(year from rec.finished_at at time zone 'UTC')::integer;
      end if;
      insert into private.pomodoist_storage_deletions(object_path) values(rec.object_path) on conflict do nothing;
    end loop;
    perform private.pomodoist_collaboration_hint(scope);
    delete from private.pomodoist_scopes where id=scope;
    return jsonb_build_object('ok',true);
  elsif action='unshare' then
    select coalesce(jsonb_agg(jsonb_build_object('entityType',c.entity_type,'entityId',c.entity_id,'data',
      (c.personal||(c.shared-array['scopeId','assigneeIds','completedBy','totalFocusSeconds','completedFocusIntervals']))
        ||jsonb_build_object('id',c.entity_id,'userId',actor::text,'assigneeIds',coalesce(c.personal->'assigneeIds','[]'::jsonb))
        ||case c.entity_type when 'task' then jsonb_build_object('completedBy',case when c.shared->>'status'='completed' then actor::text end)
          when 'task_label' then jsonb_build_object('labelId',c.personal->>'labelId')
          when 'task_kanban_status' then jsonb_build_object('labelId',c.personal->>'labelId')
          when 'project' then case when c.entity_id=s.root_project_id then jsonb_build_object('parentId',c.personal->'parentId') else '{}'::jsonb end
          else '{}'::jsonb end)),'[]') into rows
      from (select e.entity_type,e.entity_id,e.data personal,x.data shared from public.sync_entities e
        join private.pomodoist_transferred_entities t on t.user_id=e.user_id and t.entity_type=e.entity_type
          and t.entity_id=e.entity_id and t.scope_id=scope
        join private.pomodoist_shared_entities x on x.scope_id=scope and x.entity_type=e.entity_type and x.deleted_at is null
          and x.entity_id=case when e.entity_type='task_label'
            then e.data->>'taskId'||':'||scope::text||':'||(e.data->>'labelId') else e.entity_id end
        where e.user_id=actor and e.app_id='pomodoist' and e.deleted_at is not null) c;
    delete from private.pomodoist_transferred_entities where scope_id=scope;
    insert into public.sync_entities(user_id,app_id,entity_type,entity_id,server_revision,client_updated_at,deleted_at,data,created_at,updated_at)
      select actor,'pomodoist',v->>'entityType',v->>'entityId',nextval('public.sync_revision_seq'),now(),null,v->'data',now(),now()
      from jsonb_array_elements(rows) v
      on conflict (user_id,app_id,entity_type,entity_id) do update set deleted_at=null,server_revision=excluded.server_revision,
        updated_at=now(),data=excluded.data;
    insert into private.pomodoist_notifications(user_id,scope_id,kind,data)
      select user_id,null,'access.unshare',jsonb_build_object('scopeId',scope) from private.pomodoist_members
      where scope_id=scope and user_id<>actor;
    perform private.pomodoist_collaboration_hint(scope);
    for rec in select * from private.pomodoist_uploads where scope_id=scope and deleted_at is null loop
      if rec.finished_at is not null then
        update private.pomodoist_upload_years set bytes=bytes-rec.bytes where user_id=rec.user_id and year=extract(year from rec.finished_at at time zone 'UTC')::integer;
      end if;
      insert into private.pomodoist_storage_deletions(object_path) values(rec.object_path) on conflict do nothing;
    end loop;
    delete from private.pomodoist_scopes where id=scope;
    return jsonb_build_object('ok',true,'restored',jsonb_array_length(rows),'rootProjectId',s.root_project_id);
  elsif action='publicLink' then
    if jsonb_typeof(p_request->'enabled') is distinct from 'boolean' then raise exception using errcode='22023',message='Expected enabled boolean'; end if;
    token:=case when (p_request->>'enabled')::boolean then encode(extensions.gen_random_bytes(32),'hex') else null end;
    update private.pomodoist_scopes set public_token=token where id=scope;
    return jsonb_build_object('token',token);
  end if;
  if action='reserveUpload' then
    if role_name='observer' or not public.has_active_pomodoist_paid_entitlement(actor) then raise exception using errcode='42501',message='Pro editor required to upload'; end if;
    amount:=(p_request->>'bytes')::bigint;
    if amount is null or amount not between 1 and 20000000 or length(coalesce(p_request->>'name','')) not between 1 and 255
      or length(coalesce(p_request->>'contentType','')) not between 1 and 200 then raise exception using errcode='22023',message='Invalid attachment'; end if;
    if not exists(select 1 from private.pomodoist_shared_entities where scope_id=scope and entity_type='task'
      and entity_id=p_request->>'taskId' and deleted_at is null) then raise exception using errcode='42501',message='Task is inaccessible'; end if;
    perform pg_advisory_xact_lock(hashtextextended('pomodoist-uploads:'||actor::text,0));
    select * into upload from private.pomodoist_uploads where id=(p_request->>'uploadId')::uuid;
    if found then
      if upload.user_id<>actor or upload.scope_id<>scope or upload.task_id<>p_request->>'taskId' or upload.bytes<>amount
        or upload.name<>p_request->>'name' or upload.content_type<>p_request->>'contentType' or upload.deleted_at is not null
        or (upload.finished_at is null and upload.expires_at<=now()) then
        raise exception using errcode='22023',message='Upload ID is unavailable'; end if;
    else
      month_start:=date_trunc('month',now() at time zone 'UTC')::date; yr:=extract(year from now() at time zone 'UTC');
      select coalesce(sum(bytes),0) into held from private.pomodoist_uploads where user_id=actor and finished_at is null and deleted_at is null and expires_at>now();
      select coalesce((select bytes from private.pomodoist_upload_months where user_id=actor and month=month_start),0) into used_month;
      select coalesce((select bytes from private.pomodoist_upload_years where user_id=actor and year=yr),0) into used_year;
      if used_month+held+amount>1000000000 or used_year+held+amount>5000000000 then raise exception using errcode='54000',message='Attachment quota exceeded'; end if;
      insert into private.pomodoist_uploads(id,scope_id,task_id,user_id,name,content_type,bytes,object_path)
        values((p_request->>'uploadId')::uuid,scope,p_request->>'taskId',actor,p_request->>'name',p_request->>'contentType',amount,
          scope::text||'/'||actor::text||'/'||(p_request->>'uploadId')) returning * into upload;
    end if;
    return jsonb_build_object('uploadId',upload.id,'objectPath',upload.object_path,'expiresAt',upload.expires_at,'finished',upload.finished_at is not null);
  elsif action in ('finishUpload','download','deleteAttachment') then
    select * into upload from private.pomodoist_uploads where scope_id=scope
      and id=coalesce(p_request->>'uploadId',p_request->>'attachmentId')::uuid for update;
    if not found or upload.deleted_at is not null then raise exception using errcode='42501',message='Attachment is inaccessible'; end if;
    if not exists(select 1 from private.pomodoist_shared_entities where scope_id=scope and entity_type='task'
      and entity_id=upload.task_id and (deleted_at is null or (action in ('download','deleteAttachment') and data<>'{}'::jsonb))) then raise exception using errcode='42501',message='Task is inaccessible'; end if;
    if action='download' then
      if upload.finished_at is null then raise exception using errcode='42501',message='Attachment is unfinished'; end if;
      return jsonb_build_object('objectPath',upload.object_path,'name',upload.name,'attachmentId',upload.id);
    end if;
    if action='finishUpload' and upload.finished_at is not null and upload.user_id=actor then
      select data into d from private.pomodoist_shared_entities where scope_id=scope and entity_type='attachment' and entity_id=upload.id::text;
      return jsonb_build_object('attachment',d);
    end if;
    if role_name='observer' then raise exception using errcode='42501',message='Editor role required'; end if;
    perform pg_advisory_xact_lock(hashtextextended('pomodoist-uploads:'||upload.user_id::text,0));
    if action='deleteAttachment' then
      if upload.finished_at is not null then
        update private.pomodoist_upload_years set bytes=bytes-upload.bytes where user_id=upload.user_id
          and year=extract(year from upload.finished_at at time zone 'UTC')::integer;
      end if;
      update private.pomodoist_uploads set deleted_at=now() where id=upload.id;
      insert into private.pomodoist_storage_deletions(object_path) values(upload.object_path) on conflict do nothing;
      select data into d from private.pomodoist_shared_entities where scope_id=scope and entity_type='attachment' and entity_id=upload.id::text;
      if d is not null then perform private.pomodoist_shared_put(scope,'attachment',upload.id::text,d,now()); end if;
      return jsonb_build_object('ok',true,'objectPath',upload.object_path);
    end if;
    if upload.user_id<>actor or not public.has_active_pomodoist_paid_entitlement(actor) then raise exception using errcode='42501',message='Pro uploader required'; end if;
    if upload.finished_at is null then
      if upload.expires_at<=now() then raise exception using errcode='22023',message='Upload reservation expired'; end if;
      select (metadata->>'size')::bigint into object_size from storage.objects where bucket_id='pomodoist-shared' and name=upload.object_path and metadata->>'mimetype'=upload.content_type;
      if object_size is null or object_size<>upload.bytes or object_size>20000000 then raise exception using errcode='22023',message='Uploaded object size does not match reservation'; end if;
      month_start:=date_trunc('month',now() at time zone 'UTC')::date; yr:=extract(year from now() at time zone 'UTC');
      select coalesce(sum(bytes),0) into held from private.pomodoist_uploads where user_id=actor and id<>upload.id
        and finished_at is null and deleted_at is null and expires_at>now();
      insert into private.pomodoist_upload_months(user_id,month) values(actor,month_start) on conflict do nothing;
      insert into private.pomodoist_upload_years(user_id,year) values(actor,yr) on conflict do nothing;
      select bytes into used_month from private.pomodoist_upload_months where user_id=actor and month=month_start for update;
      select bytes into used_year from private.pomodoist_upload_years where user_id=actor and year=yr for update;
      if used_month+held+upload.bytes>1000000000 or used_year+held+upload.bytes>5000000000 then raise exception using errcode='54000',message='Attachment quota exceeded for completion period'; end if;
      update private.pomodoist_upload_months set bytes=bytes+upload.bytes where user_id=actor and month=month_start;
      update private.pomodoist_upload_years set bytes=bytes+upload.bytes where user_id=actor and year=yr;
      update private.pomodoist_uploads set finished_at=now() where id=upload.id returning * into upload;
      d:=jsonb_build_object('id',upload.id,'scopeId',scope,'taskId',upload.task_id,'createdBy',actor,
        'name',upload.name,'contentType',upload.content_type,'bytes',upload.bytes,'createdAt',upload.finished_at);
      perform private.pomodoist_shared_put(scope,'attachment',upload.id::text,d);
      perform private.pomodoist_collaboration_event(scope,actor,'attachment.created',upload.id::text,jsonb_build_object('taskId',upload.task_id));
    end if;
    select data into d from private.pomodoist_shared_entities where scope_id=scope and entity_type='attachment' and entity_id=upload.id::text;
    return jsonb_build_object('attachment',d);
  end if;
  raise exception using errcode='22023',message='Unknown collaboration action';
end $_$;


ALTER FUNCTION private.pomodoist_collaboration(p_request jsonb) OWNER TO postgres;

--
-- Name: pomodoist_collaboration_event(uuid, uuid, text, text, jsonb); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.pomodoist_collaboration_event(p_scope uuid, p_actor uuid, p_kind text, p_entity text, p_data jsonb DEFAULT '{}'::jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform private.pomodoist_shared_put(p_scope,'activity',gen_random_uuid()::text,
    jsonb_build_object('scopeId',p_scope,'createdBy',p_actor,'kind',p_kind,'entityId',p_entity,'createdAt',now())||p_data);
  if p_kind in ('discussion','assignment') then
    insert into private.pomodoist_notifications(user_id,scope_id,kind,data)
      select m.user_id,p_scope,p_kind,jsonb_build_object('actorId',p_actor,'entityId',p_entity)||p_data
      from private.pomodoist_members m join private.pomodoist_shared_entities t on t.scope_id=m.scope_id and t.entity_type='task'
        and t.entity_id=case when p_kind='discussion' then p_data->>'taskId' else p_entity end
      where m.scope_id=p_scope and m.user_id<>p_actor and (
        t.data->'assigneeIds' ? m.user_id::text or (p_kind='discussion' and (
          t.data->>'createdBy'=m.user_id::text or exists(select 1 from private.pomodoist_shared_entities c where c.scope_id=p_scope
            and c.entity_type='comment' and c.data->>'taskId'=t.entity_id and c.data->>'createdBy'=m.user_id::text and c.deleted_at is null))));
  elsif p_kind in ('access.role','access.transfer') then
    insert into private.pomodoist_notifications(user_id,scope_id,kind,data)
      select user_id,p_scope,p_kind,jsonb_build_object('actorId',p_actor,'entityId',p_entity)
      from private.pomodoist_members where scope_id=p_scope and user_id::text=p_entity and user_id<>p_actor;
  elsif p_kind='access.remove' then
    insert into private.pomodoist_notifications(user_id,scope_id,kind,data)
      select id,null,p_kind,jsonb_build_object('scopeId',p_scope) from auth.users where id::text=p_entity;
  end if;
  perform private.pomodoist_collaboration_hint(p_scope);
end $$;


ALTER FUNCTION private.pomodoist_collaboration_event(p_scope uuid, p_actor uuid, p_kind text, p_entity text, p_data jsonb) OWNER TO postgres;

--
-- Name: pomodoist_collaboration_hint(uuid, uuid); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.pomodoist_collaboration_hint(p_scope uuid, p_user uuid DEFAULT NULL::uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare u uuid; begin
  for u in select user_id from private.pomodoist_members where scope_id=p_scope union select p_user where p_user is not null loop
    begin
      perform realtime.send(jsonb_build_object('appId','pomodoist','scopeId',p_scope,'deviceId','collaboration-server'),
        'changed','sync:'||u::text||':pomodoist',true);
    exception when others then null; -- A failed hint must never undo a durable mutation.
    end;
  end loop;
end $$;


ALTER FUNCTION private.pomodoist_collaboration_hint(p_scope uuid, p_user uuid) OWNER TO postgres;

--
-- Name: pomodoist_collaboration_mcp(uuid, uuid, uuid, jsonb); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.pomodoist_collaboration_mcp(p_subject uuid, p_session_id uuid, p_client_id uuid, p_request jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare actor uuid; previous_claims text; response jsonb; begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode='42501',message='Service role required'; end if;
  actor:=public.resolve_pomodoist_mcp_session(p_subject,p_session_id,p_client_id);
  if actor is null then raise exception using errcode='42501',message='MCP session is unavailable'; end if;
  previous_claims:=current_setting('request.jwt.claims',true);
  -- Bind the dispatcher to the already-validated session, preserving its live membership checks.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'session_id',p_session_id,'role','authenticated')::text,true);
  begin
    response:=private.pomodoist_collaboration(p_request);
    if p_request->>'action'='state' then
      response:=response||jsonb_build_object('personalRevision',coalesce((select max(server_revision)
        from public.sync_entities where user_id=actor and app_id='pomodoist'),0));
    end if;
  exception when others then
    perform set_config('request.jwt.claims',coalesce(previous_claims,''),true);
    raise;
  end;
  perform set_config('request.jwt.claims',coalesce(previous_claims,''),true);
  return response;
end $$;


ALTER FUNCTION private.pomodoist_collaboration_mcp(p_subject uuid, p_session_id uuid, p_client_id uuid, p_request jsonb) OWNER TO postgres;

--
-- Name: pomodoist_collaboration_storage_cleanup(text[]); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.pomodoist_collaboration_storage_cleanup(p_deleted text[] DEFAULT ARRAY[]::text[]) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$ begin
  if current_setting('request.jwt.claims',true)::jsonb->>'role' is distinct from 'service_role' then
    raise exception using errcode='42501',message='Service role required'; end if;
  delete from private.pomodoist_storage_deletions where object_path=any(p_deleted);
  return jsonb_build_object('paths',coalesce((select jsonb_agg(object_path) from
    (select object_path from private.pomodoist_storage_deletions order by created_at limit 100) q),'[]'));
end $$;


ALTER FUNCTION private.pomodoist_collaboration_storage_cleanup(p_deleted text[]) OWNER TO postgres;

--
-- Name: pomodoist_google_calendar_service_unchecked(text, uuid, jsonb); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.pomodoist_google_calendar_service_unchecked(p_action text, p_user_id uuid DEFAULT NULL::uuid, p_payload jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
declare
  v_now timestamptz := pg_catalog.timezone('utc', pg_catalog.now());
  v_result jsonb;
  v_secret_id uuid;
  v_refresh_token text;
  v_item jsonb;
  v_operations jsonb := '[]'::jsonb;
  v_claim_limit integer;
  v_webhook_user uuid;
  v_calendar_id text;
  v_worker_url text;
  v_worker_secret text;
  v_worker_secret_id uuid;
  v_current_secret text;
  v_should_wake boolean;
begin
  if p_action = 'configure_worker' then
    v_worker_url := p_payload ->> 'functionUrl';
    v_worker_secret := p_payload ->> 'workerSecret';
    if coalesce(v_worker_url, '') !~ '^https://[^[:space:]]+$'
      or length(coalesce(v_worker_secret, '')) < 32
    then
      raise exception 'invalid_google_calendar_worker_configuration';
    end if;
    select id, decrypted_secret into v_worker_secret_id, v_current_secret
    from vault.decrypted_secrets
    where name = 'pomodoist-google-calendar-worker-url'
    order by created_at, id limit 1;
    if v_worker_secret_id is null then
      v_worker_secret_id := vault.create_secret(
        v_worker_url, 'pomodoist-google-calendar-worker-url',
        'Google Calendar Edge worker URL'
      );
    elsif v_current_secret is distinct from v_worker_url then
      perform vault.update_secret(v_worker_secret_id, v_worker_url, null, null);
    end if;
    delete from vault.secrets
    where name = 'pomodoist-google-calendar-worker-url'
      and id <> v_worker_secret_id;
    v_worker_secret_id := null;
    v_current_secret := null;
    select id, decrypted_secret into v_worker_secret_id, v_current_secret
    from vault.decrypted_secrets
    where name = 'pomodoist-google-calendar-worker-secret'
    order by created_at, id limit 1;
    if v_worker_secret_id is null then
      v_worker_secret_id := vault.create_secret(
        v_worker_secret, 'pomodoist-google-calendar-worker-secret',
        'Google Calendar Edge worker authentication secret'
      );
    elsif v_current_secret is distinct from v_worker_secret then
      perform vault.update_secret(v_worker_secret_id, v_worker_secret, null, null);
    end if;
    delete from vault.secrets
    where name = 'pomodoist-google-calendar-worker-secret'
      and id <> v_worker_secret_id;
    return pg_catalog.jsonb_build_object('configured', true);
  elsif p_action = 'store_oauth_state' then
    if p_user_id is null
      or length(coalesce(p_payload ->> 'stateHash', '')) <> 64
      or length(coalesce(p_payload ->> 'codeVerifier', '')) not between 43 and 128
      or (p_payload ->> 'expiresAt')::timestamptz <= v_now
    then
      raise exception 'invalid_google_calendar_oauth_state';
    end if;
    delete from private.pomodoist_google_calendar_oauth_states
    where user_id = p_user_id or expires_at <= v_now;
    insert into private.pomodoist_google_calendar_oauth_states (
      state_hash, user_id, code_verifier, expires_at
    ) values (
      p_payload ->> 'stateHash', p_user_id, p_payload ->> 'codeVerifier',
      (p_payload ->> 'expiresAt')::timestamptz
    );
    return '{}'::jsonb;
  elsif p_action = 'consume_oauth_state' then
    delete from private.pomodoist_google_calendar_oauth_states
    where state_hash = p_payload ->> 'stateHash' and expires_at > v_now
    returning pg_catalog.jsonb_build_object(
      'userId', user_id,
      'codeVerifier', code_verifier
    ) into v_result;
    return v_result;
  elsif p_action = 'connect' then
    v_refresh_token := p_payload ->> 'refreshToken';
    if p_user_id is null or length(coalesce(v_refresh_token, '')) < 1 then
      raise exception 'invalid_google_calendar_connection';
    end if;
    select refresh_token_secret_id into v_secret_id
    from private.pomodoist_google_calendar_accounts
    where user_id = p_user_id
    for update;
    if v_secret_id is null then
      v_secret_id := vault.create_secret(
        v_refresh_token,
        'pomodoist-google-calendar:' || p_user_id::text,
        'Google Calendar offline refresh token'
      );
    else
      perform vault.update_secret(v_secret_id, v_refresh_token, null, null);
    end if;
    select coalesce(
      (
        select calendar_id
        from private.pomodoist_google_calendar_accounts
        where user_id = p_user_id
      ),
      (
        select nullif(entity.data ->> 'calendarId', '')
        from public.sync_entities entity
        where entity.user_id = p_user_id
          and entity.app_id = 'pomodoist'
          and entity.entity_type = 'google_calendar_connection'
          and entity.deleted_at is null
        order by entity.server_revision desc
        limit 1
      ),
      (
        select nullif(entity.data ->> 'calendarId', '')
        from public.sync_entities entity
        where entity.user_id = p_user_id
          and entity.app_id = 'pomodoist'
          and entity.entity_type = 'google_calendar_event_link'
          and entity.deleted_at is null
        order by entity.client_updated_at, entity.entity_id
        limit 1
      )
    ) into v_calendar_id;
    insert into private.pomodoist_google_calendar_accounts (
      user_id, refresh_token_secret_id, calendar_id, status, last_error,
      updated_at
    ) values (p_user_id, v_secret_id, v_calendar_id, 'connecting', null, v_now)
    on conflict (user_id) do update
    set refresh_token_secret_id = excluded.refresh_token_secret_id,
        status = 'connecting',
        last_error = null,
        updated_at = v_now;
    insert into private.pomodoist_google_calendar_links (
      user_id, task_id, calendar_id, event_id, etag, google_updated_at,
      local_schedule_updated_at, last_schedule_fingerprint,
      unsupported_reason, created_at, updated_at
    )
    select
      p_user_id,
      entity.entity_id,
      entity.data ->> 'calendarId',
      entity.data ->> 'eventId',
      entity.data ->> 'etag',
      nullif(entity.data ->> 'googleUpdatedAt', '')::timestamptz,
      coalesce(
        nullif(entity.data ->> 'lastSyncedLocalUpdatedAt', '')::timestamptz,
        entity.client_updated_at
      ),
      null,
      entity.data ->> 'unsupportedReason',
      coalesce(
        nullif(entity.data ->> 'createdAt', '')::timestamptz,
        entity.client_updated_at
      ),
      v_now
    from public.sync_entities entity
    where entity.user_id = p_user_id
      and entity.app_id = 'pomodoist'
      and entity.entity_type = 'google_calendar_event_link'
      and entity.deleted_at is null
      and nullif(entity.data ->> 'calendarId', '') is not null
      and nullif(entity.data ->> 'eventId', '') is not null
    on conflict (user_id, task_id) do nothing;
    perform private.project_pomodoist_google_calendar_connection(p_user_id);
    perform private.queue_pomodoist_google_calendar(p_user_id);
    return '{}'::jsonb;
  elsif p_action = 'queue' then
    if p_user_id is null then raise exception 'user_id_required'; end if;
    perform private.queue_pomodoist_google_calendar(p_user_id);
    return '{}'::jsonb;
  elsif p_action = 'disconnect' then
    select refresh_token_secret_id into v_secret_id
    from private.pomodoist_google_calendar_accounts
    where user_id = p_user_id for update;
    if v_secret_id is not null then
      select decrypted_secret into v_refresh_token
      from vault.decrypted_secrets where id = v_secret_id;
      delete from vault.secrets where id = v_secret_id;
    end if;
    update private.pomodoist_google_calendar_accounts
    set refresh_token_secret_id = null,
        account_email = null,
        status = 'disconnected', sync_token = null,
        watch_channel_id = null, watch_resource_id = null,
        watch_token_hash = null, watch_expires_at = null,
        last_error = null, updated_at = v_now
    where user_id = p_user_id;
    delete from private.pomodoist_google_calendar_jobs where user_id = p_user_id;
    perform private.project_pomodoist_google_calendar_connection(p_user_id);
    return pg_catalog.jsonb_build_object('refreshToken', v_refresh_token);
  elsif p_action = 'webhook' then
    select user_id into v_webhook_user
    from private.pomodoist_google_calendar_accounts
    where status <> 'disconnected'
      and watch_channel_id = p_payload ->> 'channelId'
      and watch_resource_id = p_payload ->> 'resourceId'
      and watch_token_hash = p_payload ->> 'tokenHash';
    if v_webhook_user is not null then
      perform private.queue_pomodoist_google_calendar(v_webhook_user);
    end if;
    return pg_catalog.jsonb_build_object('accepted', v_webhook_user is not null);
  elsif p_action = 'claim' then
    v_claim_limit := least(
      greatest(coalesce((p_payload ->> 'limit')::integer, 10), 1),
      25
    );
    with candidates as (
      select job.user_id
      from private.pomodoist_google_calendar_jobs job
      where (job.status = 'pending' and job.due_at <= v_now)
         or (job.status = 'processing' and job.lease_until <= v_now)
      order by job.due_at, job.user_id
      for update skip locked
      limit v_claim_limit
    ), claimed as (
      update private.pomodoist_google_calendar_jobs job
      set status = 'processing', lease_until = v_now + interval '2 minutes',
          claimed_generation = generation, updated_at = v_now
      from candidates
      where job.user_id = candidates.user_id
      returning job.user_id, job.attempts
    )
    select coalesce(pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'userId', account.user_id,
        'attempts', claimed.attempts,
        'refreshToken', secret.decrypted_secret,
        'accountEmail', account.account_email,
        'calendarId', account.calendar_id,
        'calendarName', account.calendar_name,
        'syncToken', account.sync_token,
        'status', account.status,
        'watchChannelId', account.watch_channel_id,
        'watchResourceId', account.watch_resource_id,
        'watchExpiresAt', account.watch_expires_at,
        'lastSyncStartedAt', account.last_sync_started_at,
        'lastSyncFinishedAt', account.last_sync_finished_at,
        'lastError', account.last_error,
        'warning', account.warning,
        'createdAt', account.created_at,
        'updatedAt', account.updated_at,
        'tasks', coalesce((
          select pg_catalog.jsonb_agg(
            entity.data || pg_catalog.jsonb_build_object(
              '_clientUpdatedAt', entity.client_updated_at,
              '_deletedAt', entity.deleted_at,
              '_localScheduleUpdatedAt', coalesce(
                task_state.local_schedule_updated_at,
                entity.client_updated_at
              )
            ) order by entity.entity_id
          )
          from public.sync_entities entity
          left join private.pomodoist_google_calendar_task_state task_state
            on task_state.user_id = entity.user_id
           and task_state.task_id = entity.entity_id
          where entity.user_id = account.user_id
            and entity.app_id = 'pomodoist'
            and entity.entity_type = 'task'
        ), '[]'::jsonb),
        'links', coalesce((
          select pg_catalog.jsonb_agg(
            pg_catalog.to_jsonb(link) - 'user_id'
            order by link.created_at, link.task_id
          )
          from private.pomodoist_google_calendar_links link
          where link.user_id = account.user_id
        ), '[]'::jsonb)
      ) order by account.user_id
    ), '[]'::jsonb) into v_result
    from claimed
    join private.pomodoist_google_calendar_accounts account
      on account.user_id = claimed.user_id
    join vault.decrypted_secrets secret
      on secret.id = account.refresh_token_secret_id;
    update private.pomodoist_google_calendar_accounts account
    set status = 'connecting', last_sync_started_at = v_now, updated_at = v_now
    where account.user_id in (select (value ->> 'userId')::uuid from pg_catalog.jsonb_array_elements(v_result));
    return v_result;
  elsif p_action = 'complete' then
    if p_user_id is null then raise exception 'user_id_required'; end if;
    if coalesce(p_payload #>> '{account,refreshToken}', '') <> '' then
      select refresh_token_secret_id into v_secret_id
      from private.pomodoist_google_calendar_accounts
      where user_id = p_user_id for update;
      if v_secret_id is not null then
        perform vault.update_secret(
          v_secret_id, p_payload #>> '{account,refreshToken}', null, null
        );
      end if;
    end if;
    update private.pomodoist_google_calendar_accounts
    set account_email = coalesce(p_payload #>> '{account,accountEmail}', account_email),
        calendar_id = coalesce(p_payload #>> '{account,calendarId}', calendar_id),
        calendar_name = coalesce(p_payload #>> '{account,calendarName}', calendar_name),
        sync_token = coalesce(p_payload #>> '{account,syncToken}', sync_token),
        watch_channel_id = coalesce(p_payload #>> '{account,watchChannelId}', watch_channel_id),
        watch_resource_id = coalesce(p_payload #>> '{account,watchResourceId}', watch_resource_id),
        watch_token_hash = coalesce(p_payload #>> '{account,watchTokenHash}', watch_token_hash),
        watch_expires_at = coalesce((p_payload #>> '{account,watchExpiresAt}')::timestamptz, watch_expires_at),
        status = 'connected', last_error = null,
        warning = p_payload #>> '{account,warning}',
        last_sync_finished_at = v_now, updated_at = v_now
    where user_id = p_user_id;
    for v_item in select value from pg_catalog.jsonb_array_elements(coalesce(p_payload -> 'links', '[]'::jsonb)) loop
      insert into private.pomodoist_google_calendar_links (
        user_id, task_id, calendar_id, event_id, etag, google_updated_at,
        local_schedule_updated_at, last_schedule_fingerprint,
        unsupported_reason, created_at, updated_at
      ) values (
        p_user_id, v_item ->> 'taskId', v_item ->> 'calendarId',
        v_item ->> 'eventId', v_item ->> 'etag',
        (v_item ->> 'googleUpdatedAt')::timestamptz,
        (v_item ->> 'localScheduleUpdatedAt')::timestamptz,
        v_item ->> 'lastScheduleFingerprint', v_item ->> 'unsupportedReason',
        coalesce((v_item ->> 'createdAt')::timestamptz, v_now), v_now
      ) on conflict (user_id, task_id) do update
      set calendar_id = excluded.calendar_id, event_id = excluded.event_id,
          etag = excluded.etag, google_updated_at = excluded.google_updated_at,
          local_schedule_updated_at = excluded.local_schedule_updated_at,
          last_schedule_fingerprint = excluded.last_schedule_fingerprint,
          unsupported_reason = excluded.unsupported_reason, updated_at = v_now;
    end loop;
    delete from private.pomodoist_google_calendar_links
    where user_id = p_user_id
      and task_id in (
        select value #>> '{}'
        from pg_catalog.jsonb_array_elements(
          coalesce(p_payload -> 'removedTaskIds', '[]'::jsonb)
        )
      );
    v_operations := coalesce(p_payload -> 'operations', '[]'::jsonb);
    if pg_catalog.jsonb_array_length(v_operations) > 0 then
      perform private.push_changes_for_user(
        p_user_id, 'pomodoist', 'google-calendar-server', v_operations
      );
      perform realtime.send(
        pg_catalog.jsonb_build_object(
          'appId', 'pomodoist', 'deviceId', 'google-calendar-server',
          'sentAt', pg_catalog.to_char(
            pg_catalog.clock_timestamp() at time zone 'UTC',
            'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
          )
        ),
        'changed', 'sync:' || p_user_id::text || ':pomodoist', true
      );
    end if;
    update private.pomodoist_google_calendar_jobs
    set status = 'pending',
        due_at = case
          when generation = claimed_generation then v_now + interval '24 hours'
          else v_now
        end,
        lease_until = null, attempts = 0, last_error = null, updated_at = v_now
    where user_id = p_user_id
    returning generation <> claimed_generation into v_should_wake;
    if coalesce(v_should_wake, false) then
      perform private.invoke_pomodoist_google_calendar_worker();
    end if;
    return '{}'::jsonb;
  elsif p_action = 'fail' then
    update private.pomodoist_google_calendar_jobs
    set status = 'pending',
        due_at = v_now + pg_catalog.make_interval(
          secs => least(
            greatest(coalesce((p_payload ->> 'retrySeconds')::integer, 30), 5),
            3600
          )
        ),
        lease_until = null, attempts = attempts + 1,
        last_error = pg_catalog.left(coalesce(p_payload ->> 'error', 'Unknown error'), 1000),
        updated_at = v_now
    where user_id = p_user_id;
    update private.pomodoist_google_calendar_accounts
    set status = 'error', last_error = pg_catalog.left(coalesce(p_payload ->> 'error', 'Unknown error'), 1000),
        last_sync_finished_at = v_now, updated_at = v_now
    where user_id = p_user_id;
    perform private.project_pomodoist_google_calendar_connection(p_user_id);
    return '{}'::jsonb;
  end if;
  raise exception 'unsupported_google_calendar_service_action';
end;
$_$;


ALTER FUNCTION private.pomodoist_google_calendar_service_unchecked(p_action text, p_user_id uuid, p_payload jsonb) OWNER TO postgres;

--
-- Name: pomodoist_history_entitlement_changed(); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.pomodoist_history_entitlement_changed() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare u uuid; r record; begin
  u:=case when tg_op='DELETE' then old.user_id else new.user_id end;
  perform private.pomodoist_history_refresh(null,u);
  for r in select scope_id from private.pomodoist_members where user_id=u loop
    perform private.pomodoist_history_refresh(r.scope_id);
    perform private.pomodoist_collaboration_hint(r.scope_id);
  end loop;
  return null;
end $$;


ALTER FUNCTION private.pomodoist_history_entitlement_changed() OWNER TO postgres;

--
-- Name: pomodoist_history_refresh(uuid, uuid); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.pomodoist_history_refresh(p_scope uuid DEFAULT NULL::uuid, p_user uuid DEFAULT NULL::uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare paid boolean; begin
  if p_scope is not null then
    select exists(select 1 from private.pomodoist_members where scope_id=p_scope
      and public.has_active_pomodoist_paid_entitlement(user_id)) into paid;
    update private.pomodoist_scopes set grace_ends_at=case when paid then null
      when history_unlimited then coalesce(grace_ends_at,now()+interval '30 days') else grace_ends_at end,
      history_unlimited=paid where id=p_scope;
  end if;
  if p_user is not null and exists(select 1 from auth.users where id=p_user) then
    paid:=public.has_active_pomodoist_paid_entitlement(p_user);
    insert into private.pomodoist_personal_history(user_id,history_unlimited) values(p_user,paid)
    on conflict(user_id) do update set grace_ends_at=case when paid then null
      when private.pomodoist_personal_history.history_unlimited then coalesce(private.pomodoist_personal_history.grace_ends_at,now()+interval '30 days')
      else private.pomodoist_personal_history.grace_ends_at end,history_unlimited=paid;
  end if;
end $$;


ALTER FUNCTION private.pomodoist_history_refresh(p_scope uuid, p_user uuid) OWNER TO postgres;

--
-- Name: pomodoist_history_timestamp(text, timestamp with time zone); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.pomodoist_history_timestamp(p_value text, p_fallback timestamp with time zone) RETURNS timestamp with time zone
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $_$ begin
  if p_value~'^[0-9]+$' then return to_timestamp(p_value::numeric/1000); end if;
  return coalesce(nullif(p_value,'')::timestamptz,p_fallback);
exception when others then return p_fallback; end $_$;


ALTER FUNCTION private.pomodoist_history_timestamp(p_value text, p_fallback timestamp with time zone) OWNER TO postgres;

--
-- Name: pomodoist_mcp_access_token_hook(jsonb); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.pomodoist_mcp_access_token_hook(event jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $_$
declare
  v_claims jsonb := event->'claims';
  v_client_id uuid;
  v_issuer text;
  v_scope text;
  v_subject uuid;
  v_output jsonb;
begin
  if coalesce(v_claims->>'client_id', '') = '' then
    return jsonb_build_object('claims', v_claims);
  end if;

  begin
    v_client_id := (v_claims->>'client_id')::uuid;
    v_subject := (event->>'user_id')::uuid;
  exception
    when invalid_text_representation then
      raise exception using
        errcode = '22023',
        message = 'Invalid OAuth identity';
  end;

  v_issuer := v_claims->>'iss';
  if v_issuer is null or v_issuer !~
    '^(https://[a-zA-Z0-9.-]+(:[0-9]{1,5})?|http://(localhost|127\.0\.0\.1|\[::1\])(:[0-9]{1,5})?)(/[^/?#[:space:]]+)*/auth/v1$'
  then
    raise exception using
      errcode = '22023',
      message = 'Invalid OAuth issuer';
  end if;

  v_scope := coalesce(v_claims->>'scope', '');
  if exists (
    select 1
    from regexp_split_to_table(trim(v_scope), '[[:space:]]+') as requested(scope)
    where lower(requested.scope) in ('openid', 'profile', 'phone')
  ) then
    raise exception using
      errcode = '22023',
      message = 'MCP OAuth scope is not permitted';
  end if;

  v_output := jsonb_build_object(
    'iss', v_issuer,
    'aud', private.pomodoist_mcp_audience(v_issuer),
    'exp', v_claims->'exp',
    'iat', v_claims->'iat',
    'sub', private.pomodoist_mcp_subject(v_subject, v_client_id)::text,
    'role', 'pomodoist_mcp',
    'aal', v_claims->'aal',
    'session_id', v_claims->'session_id',
    'email', '',
    'phone', '',
    'is_anonymous', v_claims->'is_anonymous',
    'client_id', v_client_id::text
  );

  if v_claims ? 'scope' then
    v_output := v_output || jsonb_build_object('scope', v_claims->'scope');
  end if;

  return jsonb_build_object('claims', v_output);
end;
$_$;


ALTER FUNCTION private.pomodoist_mcp_access_token_hook(event jsonb) OWNER TO postgres;

--
-- Name: pomodoist_mcp_audience(text); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.pomodoist_mcp_audience(p_issuer text) RETURNS text
    LANGUAGE sql STABLE STRICT SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select coalesce(
    (select mcp_audience from private.pomodoist_instance_settings
     where singleton and mcp_issuer = p_issuer),
    left(p_issuer, -length('/auth/v1')) || '/functions/v1/pomodoist-mcp'
  );
$$;


ALTER FUNCTION private.pomodoist_mcp_audience(p_issuer text) OWNER TO postgres;

--
-- Name: pomodoist_mcp_finite_timestamptz(text); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.pomodoist_mcp_finite_timestamptz(p_value text) RETURNS timestamp with time zone
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $_$
declare
  v_value timestamptz;
begin
  if p_value is null
    or p_value !~
      '^[0-9]{4}-[0-9]{2}-[0-9]{2}[Tt][0-9]{2}:[0-9]{2}:[0-9]{2}([.][0-9]+)?([Zz]|[+-][0-9]{2}:[0-9]{2})$'
    or not pg_catalog.pg_input_is_valid(
      p_value,
      'timestamp with time zone'
    )
  then
    return null;
  end if;

  v_value := p_value::timestamptz;
  if not pg_catalog.isfinite(v_value) then
    return null;
  end if;
  return v_value;
end;
$_$;


ALTER FUNCTION private.pomodoist_mcp_finite_timestamptz(p_value text) OWNER TO postgres;

--
-- Name: pomodoist_mcp_json_array(text); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.pomodoist_mcp_json_array(p_value text) RETURNS jsonb
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO ''
    AS $$
declare
  v_value jsonb;
begin
  begin
    v_value := p_value::jsonb;
  exception
    when others then
      return '[]'::jsonb;
  end;
  return case
    when pg_catalog.jsonb_typeof(v_value) = 'array' then v_value
    else '[]'::jsonb
  end;
end;
$$;


ALTER FUNCTION private.pomodoist_mcp_json_array(p_value text) OWNER TO postgres;

--
-- Name: pomodoist_mcp_mutation_snapshot(uuid); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.pomodoist_mcp_mutation_snapshot(p_user_id uuid) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select pg_catalog.jsonb_build_object(
    'tasks', coalesce(
      pg_catalog.jsonb_agg(
        entity.data || pg_catalog.jsonb_build_object('id', entity.entity_id)
        order by entity.data ->> 'orderKey', entity.entity_id
      ) filter (where entity.entity_type = 'task'),
      '[]'::jsonb
    ),
    'projects', coalesce(
      pg_catalog.jsonb_agg(
        entity.data || pg_catalog.jsonb_build_object('id', entity.entity_id)
        order by entity.data ->> 'orderKey', entity.entity_id
      ) filter (where entity.entity_type = 'project'),
      '[]'::jsonb
    ),
    'labels', coalesce(
      pg_catalog.jsonb_agg(
        entity.data || pg_catalog.jsonb_build_object('id', entity.entity_id)
        order by entity.data ->> 'orderKey', entity.entity_id
      ) filter (where entity.entity_type = 'label'),
      '[]'::jsonb
    ),
    'taskLabels', coalesce(
      pg_catalog.jsonb_agg(
        entity.data
          || pg_catalog.jsonb_build_object('entityId', entity.entity_id)
        order by entity.entity_id
      ) filter (where entity.entity_type = 'task_label'),
      '[]'::jsonb
    ),
    'assignments', coalesce(
      pg_catalog.jsonb_agg(
        entity.data
          || pg_catalog.jsonb_build_object('taskId', entity.entity_id)
        order by entity.entity_id
      ) filter (where entity.entity_type = 'task_kanban_status'),
      '[]'::jsonb
    ),
    'completions', coalesce(
      pg_catalog.jsonb_agg(
        entity.data || pg_catalog.jsonb_build_object('id', entity.entity_id)
        order by entity.data ->> 'completedAt' desc, entity.entity_id desc
      ) filter (where entity.entity_type = 'task_completion'),
      '[]'::jsonb
    ),
    'settings', coalesce(
      (
        pg_catalog.jsonb_agg(
          entity.data || pg_catalog.jsonb_build_object(
            'id',
            entity.entity_id
          )
          order by entity.entity_id
        ) filter (where entity.entity_type = 'kanban_settings')
      ) -> 0,
      'null'::jsonb
    )
  )
  from public.sync_entities entity
  where p_user_id is not null
    and entity.user_id = p_user_id
    and entity.app_id = 'pomodoist'
    and entity.entity_type in (
      'task',
      'project',
      'label',
      'task_label',
      'task_kanban_status',
      'task_completion',
      'kanban_settings'
    )
    and entity.deleted_at is null
    and pg_catalog.jsonb_typeof(entity.data) = 'object'
    and coalesce(entity.data ->> 'isDeleted', 'false') <> 'true';
$$;


ALTER FUNCTION private.pomodoist_mcp_mutation_snapshot(p_user_id uuid) OWNER TO postgres;

--
-- Name: pomodoist_mcp_productivity_metrics(uuid, date, text); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.pomodoist_mcp_productivity_metrics(p_user_id uuid, p_report_date date, p_time_zone text) RETURNS jsonb
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
  with completions as (
    select
      entity_id as id,
      data ->> 'taskId' as task_id,
      private.pomodoist_mcp_finite_timestamptz(
        data ->> 'completedAt'
      ) as completed_at
    from public.sync_entities
    where user_id = p_user_id
      and app_id = 'pomodoist'
      and entity_type = 'task_completion'
      and deleted_at is null
  ),
  intervals as (
    select
      entity_id as id,
      data ->> 'taskId' as task_id,
      data ->> 'type' as type,
      data ->> 'status' as status,
      private.pomodoist_mcp_finite_timestamptz(
        data ->> 'startedAt'
      ) as started_at,
      private.pomodoist_mcp_finite_timestamptz(
        data ->> 'completedAt'
      ) as completed_at,
      private.pomodoist_mcp_finite_timestamptz(
        data ->> 'stoppedAt'
      ) as stopped_at,
      case
        when pg_catalog.pg_input_is_valid(
          data ->> 'pausedTotalSeconds',
          'integer'
        )
        then (data ->> 'pausedTotalSeconds')::integer
        else 0
      end as paused_seconds
    from public.sync_entities
    where user_id = p_user_id
      and app_id = 'pomodoist'
      and entity_type = 'focus_interval'
      and deleted_at is null
      and coalesce(data ->> 'isDeleted', 'false') <> 'true'
  ),
  completed_work as (
    select
      *,
      coalesce(completed_at, started_at) as finished_at,
      greatest(
        pg_catalog.floor(
          extract(epoch from coalesce(
            completed_at,
            stopped_at,
            pg_catalog.now()
          )) - extract(epoch from started_at)
        )::bigint - paused_seconds,
        0::bigint
      ) as actual_seconds
    from intervals
    where type = 'work'
      and status = 'completed'
      and started_at is not null
  ),
  stopped_intervals as (
    select *
    from intervals
    where status = 'stopped'
      and started_at is not null
  ),
  open_tasks as (
    select
      case
        when pg_catalog.pg_input_is_valid(
          data ->> 'estimatedFocusIntervals',
          'integer'
        )
        then (data ->> 'estimatedFocusIntervals')::integer
        else 0
      end as estimate,
      private.pomodoist_mcp_schedule_date(
        data ->> 'dueJson',
        p_time_zone
      ) as due_date
    from public.sync_entities
    where user_id = p_user_id
      and app_id = 'pomodoist'
      and entity_type = 'task'
      and deleted_at is null
      and coalesce(data ->> 'isDeleted', 'false') <> 'true'
      and coalesce(data ->> 'status', 'open') <> 'completed'
  ),
  days as (
    select day::date
    from pg_catalog.generate_series(
      p_report_date - 6,
      p_report_date,
      interval '1 day'
    ) day
  ),
  daily as (
    select
      days.day,
      (
        select pg_catalog.count(*)::integer
        from completions
        where completed_at is not null
          and (completed_at at time zone p_time_zone)::date = days.day
      ) as completed_tasks,
      (
        select pg_catalog.count(*)::integer
        from completed_work
        where (started_at at time zone p_time_zone)::date = days.day
      ) as completed_focus_intervals,
      (
        select coalesce(pg_catalog.sum(actual_seconds), 0)::bigint
        from completed_work
        where (started_at at time zone p_time_zone)::date = days.day
      ) as total_focus_seconds
    from days
  ),
  completion_days as (
    select
      (completed_at at time zone p_time_zone)::date as day,
      pg_catalog.count(*)::integer as count
    from completions
    where completed_at is not null
    group by 1
  ),
  work_days as (
    select
      (started_at at time zone p_time_zone)::date as day,
      pg_catalog.count(*)::integer as count
    from completed_work
    group by 1
  ),
  stopped_days as (
    select distinct (started_at at time zone p_time_zone)::date as day
    from stopped_intervals
  )
  select pg_catalog.jsonb_build_object(
    'reportDate', pg_catalog.to_char(p_report_date, 'YYYY-MM-DD'),
    'timeZone', p_time_zone,
    'daily', pg_catalog.jsonb_build_object(
      'completedTasks',
      (select completed_tasks from daily where day = p_report_date),
      'completedFocusIntervals',
      (select completed_focus_intervals from daily where day = p_report_date),
      'totalFocusSeconds',
      (select total_focus_seconds from daily where day = p_report_date)
    ),
    'plannedFocusIntervals',
    (
      select coalesce(pg_catalog.sum(estimate), 0)::integer
      from open_tasks
      where due_date <= p_report_date
    ),
    'openTasks', (select pg_catalog.count(*)::integer from open_tasks),
    'allTime', pg_catalog.jsonb_build_object(
      'completedTasks',
      (
        select pg_catalog.count(*)::integer
        from completions
        where completed_at is not null
      ),
      'completedFocusIntervals',
      (select pg_catalog.count(*)::integer from completed_work)
    ),
    'lastSevenDays',
    (
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'date', pg_catalog.to_char(day, 'YYYY-MM-DD'),
          'completedTasks', completed_tasks,
          'completedFocusIntervals', completed_focus_intervals,
          'totalFocusSeconds', total_focus_seconds
        )
        order by day
      )
      from daily
    ),
    'achievementInputs', pg_catalog.jsonb_build_object(
      'completedTasks',
      (
        select pg_catalog.count(*)::integer
        from completions
        where completed_at is not null
      ),
      'completedWorkIntervals',
      (select pg_catalog.count(*)::integer from completed_work),
      'comboFlags', pg_catalog.jsonb_build_object(
        'dayNotWasted',
        exists (
          select 1
          from completion_days completion_day
          join work_days work_day using (day)
          where completion_day.count >= 1 and work_day.count >= 1
        ),
        'focusPlusCheck',
        exists (
          select 1
          from completion_days completion_day
          join work_days work_day using (day)
          where completion_day.count >= 3 and work_day.count >= 3
        ),
        'noFuss',
        exists (
          select 1
          from work_days work_day
          where work_day.count >= 5
            and not exists (
              select 1 from stopped_days where stopped_days.day = work_day.day
            )
        ),
        'cleanEntry',
        exists (
          select 1
          from completions completion
          join completed_work work
            on work.task_id = completion.task_id
          where completion.task_id is not null
            and work.finished_at <= completion.completed_at
        ),
        'tomatoClosed',
        exists (
          select 1
          from completions completion
          join completed_work work
            on work.task_id = completion.task_id
          where completion.task_id is not null
            and (work.started_at at time zone p_time_zone)::date
              = (completion.completed_at at time zone p_time_zone)::date
        )
      )
    )
  );
$$;


ALTER FUNCTION private.pomodoist_mcp_productivity_metrics(p_user_id uuid, p_report_date date, p_time_zone text) OWNER TO postgres;

--
-- Name: pomodoist_mcp_schedule_date(text, text); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.pomodoist_mcp_schedule_date(p_due_json text, p_time_zone text) RETURNS date
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $_$
declare
  v_due jsonb;
  v_date date;
  v_start timestamptz;
  v_end timestamptz;
begin
  if p_due_json is null or pg_catalog.btrim(p_due_json) = '' then
    return null;
  end if;

  begin
    v_due := p_due_json::jsonb;
  exception
    when others then
      return null;
  end;

  if pg_catalog.jsonb_typeof(v_due) is distinct from 'object' then
    return null;
  end if;

  if v_due ->> 'type' = 'allDay'
    and pg_catalog.jsonb_typeof(v_due -> 'date') = 'string'
    and v_due ->> 'date' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
  then
    begin
      v_date := (v_due ->> 'date')::date;
      if pg_catalog.to_char(v_date, 'YYYY-MM-DD') = v_due ->> 'date' then
        return v_date;
      end if;
    exception
      when invalid_datetime_format or datetime_field_overflow then
        return null;
    end;
  elsif v_due ->> 'type' = 'timed'
    and pg_catalog.jsonb_typeof(v_due -> 'start') = 'string'
    and pg_catalog.jsonb_typeof(v_due -> 'end') = 'string'
  then
    v_start := private.pomodoist_mcp_finite_timestamptz(
      v_due ->> 'start'
    );
    v_end := private.pomodoist_mcp_finite_timestamptz(v_due ->> 'end');
    if v_start is not null and v_end is not null and v_end > v_start then
      return (v_start at time zone p_time_zone)::date;
    end if;
  end if;

  return null;
end;
$_$;


ALTER FUNCTION private.pomodoist_mcp_schedule_date(p_due_json text, p_time_zone text) OWNER TO postgres;

--
-- Name: pomodoist_mcp_subject(uuid, uuid); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.pomodoist_mcp_subject(p_user_id uuid, p_client_id uuid) RETURNS uuid
    LANGUAGE sql IMMUTABLE STRICT SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select extensions.uuid_generate_v5(
    '6ba7b811-9dad-11d1-80b4-00c04fd430c8'::uuid,
    'pomodoist-mcp:' || p_user_id::text || ':' || p_client_id::text
  );
$$;


ALTER FUNCTION private.pomodoist_mcp_subject(p_user_id uuid, p_client_id uuid) OWNER TO postgres;

--
-- Name: pomodoist_mcp_task_json(text, jsonb); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.pomodoist_mcp_task_json(p_id text, p_data jsonb) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $$
  select pg_catalog.jsonb_build_object(
    'id', p_id,
    'createdBy', p_data->'createdBy',
    'completedBy', p_data->'completedBy',
    'assigneeIds', coalesce(p_data->'assigneeIds','[]'::jsonb),
    'scopeId', p_data->'scopeId',
    'content', p_data -> 'content',
    'description', p_data -> 'description',
    'projectId', p_data -> 'projectId',
    'parentId', p_data -> 'parentId',
    'priority', p_data -> 'priority',
    'dueJson', p_data -> 'dueJson',
    'status', p_data -> 'status',
    'estimatedFocusIntervals', p_data -> 'estimatedFocusIntervals',
    'completedFocusIntervals', p_data -> 'completedFocusIntervals',
    'totalFocusSeconds', p_data -> 'totalFocusSeconds',
    'orderKey', p_data -> 'orderKey',
    'dayOrder', p_data -> 'dayOrder',
    'createdAt', p_data -> 'createdAt',
    'updatedAt', p_data -> 'updatedAt',
    'completedAt', p_data -> 'completedAt'
  );
$$;


ALTER FUNCTION private.pomodoist_mcp_task_json(p_id text, p_data jsonb) OWNER TO postgres;

--
-- Name: pomodoist_member_deleted(); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.pomodoist_member_deleted() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare item record; begin
  if exists(select 1 from private.pomodoist_scopes where id=old.scope_id) then
    for item in select * from private.pomodoist_shared_entities where scope_id=old.scope_id and entity_type='task' and data->'assigneeIds' ? old.user_id::text loop
      perform private.pomodoist_shared_put(old.scope_id,'task',item.entity_id,item.data||jsonb_build_object('assigneeIds',(item.data->'assigneeIds')-old.user_id::text),item.deleted_at);
    end loop;
    perform private.pomodoist_history_refresh(old.scope_id);
    perform private.pomodoist_collaboration_hint(old.scope_id,old.user_id);
  end if;
  return null;
end $$;


ALTER FUNCTION private.pomodoist_member_deleted() OWNER TO postgres;

--
-- Name: pomodoist_members_json(uuid); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.pomodoist_members_json(p_scope uuid) RETURNS jsonb
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select coalesce(jsonb_agg(jsonb_build_object('userId',m.user_id,'role',m.role,'displayName',coalesce(p.display_name,'Member')) order by m.joined_at),'[]')
  from private.pomodoist_members m left join public.profiles p on p.id=m.user_id where m.scope_id=p_scope;
$$;


ALTER FUNCTION private.pomodoist_members_json(p_scope uuid) OWNER TO postgres;

--
-- Name: pomodoist_preferences_json(uuid, uuid); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.pomodoist_preferences_json(p_user uuid, p_scope uuid DEFAULT NULL::uuid) RETURNS jsonb
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select coalesce(jsonb_agg(jsonb_build_object('scopeId',scope_id,'entityType',entity_type,'entityId',entity_id,'data',data,'updatedAt',updated_at)),'[]')
    from private.pomodoist_shared_preferences where user_id=p_user and (p_scope is null or scope_id=p_scope);
$$;


ALTER FUNCTION private.pomodoist_preferences_json(p_user uuid, p_scope uuid) OWNER TO postgres;

--
-- Name: pomodoist_scope_json(uuid, uuid); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.pomodoist_scope_json(p_scope uuid, p_user uuid) RETURNS jsonb
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select jsonb_build_object('id',s.id,'rootProjectId',s.root_project_id,'ownerId',s.owner_id,'role',m.role,
    'revision',s.revision,'historyUnlimited',s.history_unlimited,'graceEndsAt',s.grace_ends_at,
    'publicToken',case when m.role='administrator' then s.public_token end)
  from private.pomodoist_scopes s join private.pomodoist_members m on m.scope_id=s.id where s.id=p_scope and m.user_id=p_user;
$$;


ALTER FUNCTION private.pomodoist_scope_json(p_scope uuid, p_user uuid) OWNER TO postgres;

--
-- Name: pomodoist_shared_apply(uuid, uuid, text, jsonb); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.pomodoist_shared_apply(p_scope uuid, p_actor uuid, p_role text, p_op jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  typ text:=p_op->>'entityType'; eid text:=p_op->>'entityId'; op text:=p_op->>'operation';
  payload jsonb:=p_op->'payload'; base bigint:=(p_op->>'baseRevision')::bigint;
  e private.pomodoist_shared_entities%rowtype; s private.pomodoist_scopes%rowtype;
  d jsonb; result jsonb; conflicts jsonb:='[]'; k text; v jsonb; parent text; assignee text; c record;
  changed boolean; allowed text[]; focus_started timestamptz; focus_completed timestamptz; focus_seconds integer;
begin
  payload:=payload-array['schemaVersion','commandType','isFavorite','isCollapsed','dayOrder','viewStyle','completedFocusIntervals','totalFocusSeconds'];
  select * into s from private.pomodoist_scopes where id=p_scope;
  if p_role not in ('administrator','member') then raise exception using errcode='42501',message='Editor role required'; end if;
  if coalesce(typ,'') not in ('project','section','task','label','task_label','task_kanban_status','task_completion','comment','focus_interval') or coalesce(eid,'')='' or length(eid)>200
    or coalesce(op,'') not in ('upsert','delete','assign') or jsonb_typeof(payload) is distinct from 'object'
    or base is null or base<0 or base>s.revision or coalesce(p_op->>'opId','')='' or length(p_op->>'opId')>200
    or nullif(p_op->>'clientUpdatedAt','')::timestamptz is null then
    raise exception using errcode='22023',message='Invalid shared operation';
  end if;
  select * into e from private.pomodoist_shared_entities where scope_id=p_scope and entity_type=typ and entity_id=eid;
  if e.deleted_at is not null then
    return jsonb_build_object('opId',p_op->>'opId','status','rejected','code','deleted','error','Deletion wins','serverRevision',e.server_revision);
  end if;
  if typ='comment' and e.entity_id is not null and e.data->>'createdBy'<>p_actor::text
    and not (op='delete' and p_role='administrator') then
    raise exception using errcode='42501',message='Only the author may edit a comment';
  end if;
  if typ='focus_interval' and op='upsert' and e.entity_id is not null and e.data->>'createdBy'=p_actor::text
    and e.data->>'taskId'=payload->>'taskId'
    and coalesce((e.data->>'durationSeconds')::integer,(e.data->>'plannedSeconds')::integer)=coalesce((payload->>'durationSeconds')::integer,(payload->>'plannedSeconds')::integer)
    and private.pomodoist_history_timestamp(e.data->>'startedAt',null)=private.pomodoist_history_timestamp(payload->>'startedAt',null) then
    return jsonb_build_object('opId',p_op->>'opId','status','applied','entityType',typ,'entityId',eid,'data',e.data,
      'serverRevision',e.server_revision,'deletedAt',e.deleted_at,'updatedAt',e.updated_at);
  end if;
  if typ in ('focus_interval','task_completion') and (e.entity_id is not null or op<>'upsert') then
    raise exception using errcode='42501',message='Completed focus contributions are immutable';
  end if;
  if typ='label' and e.entity_id is not null and (payload ? 'systemKey') and payload->'systemKey' is distinct from e.data->'systemKey' then
    raise exception using errcode='42501',message='System status identity is immutable'; end if;
  if typ='project' and eid=s.root_project_id and (op='delete' or (payload ? 'parentId' and payload->>'parentId' is not null)) then
    raise exception using errcode='42501',message='Shared root cannot be moved or deleted with a content operation';
  end if;
  if typ='task' and op='upsert' and payload->>'recurrenceSourceId' is not null then
    if not exists(select 1 from private.pomodoist_shared_entities where scope_id=p_scope and entity_type='task'
      and entity_id=payload->>'recurrenceSourceId' and deleted_at is null)
      or length(coalesce(payload->>'occurrenceKey','')) not between 1 and 200 then
      raise exception using errcode='22023',message='Invalid recurrence source or occurrence'; end if;
    select successor_id into parent from private.pomodoist_recurrence_successors where scope_id=p_scope and source_id=payload->>'recurrenceSourceId';
    if parent is not null and parent<>eid then
      raise exception using errcode='40001',message='A successor already exists for this recurrence source'; end if;
    insert into private.pomodoist_recurrence_successors values(p_scope,payload->>'recurrenceSourceId',payload->>'occurrenceKey',eid) on conflict do nothing;
  end if;
  d:=coalesce(e.data,'{}');
  if op='delete' then
    if e.entity_id is null then raise exception using errcode='22023',message='Entity not found'; end if;
    if typ='project' then
      parent:=coalesce(d->>'parentId',s.root_project_id);
      for c in select * from private.pomodoist_shared_entities where scope_id=p_scope and deleted_at is null
        and ((entity_type='project' and data->>'parentId'=eid) or (entity_type in ('task','section') and data->>'projectId'=eid)) loop
        perform private.pomodoist_shared_put(p_scope,c.entity_type,c.entity_id,
          c.data||jsonb_build_object(case when c.entity_type='project' then 'parentId' else 'projectId' end,parent));
      end loop;
    elsif typ='section' then
      for c in select * from private.pomodoist_shared_entities where scope_id=p_scope and entity_type='task' and data->>'sectionId'=eid and deleted_at is null loop
        perform private.pomodoist_shared_put(p_scope,'task',c.entity_id,c.data||jsonb_build_object('sectionId',null));
      end loop;
    elsif typ='label' then
      if d->>'systemKey' in ('backlog','done') then raise exception using errcode='42501',message='Protected shared status cannot be deleted'; end if;
      for c in select * from private.pomodoist_shared_entities where scope_id=p_scope and entity_type in ('task_label','task_kanban_status') and data->>'labelId'=eid and deleted_at is null loop
        perform private.pomodoist_shared_put(p_scope,c.entity_type,c.entity_id,c.data,now());
      end loop;
    elsif typ='task' then
      -- Subtasks remain in the same project and inherit the removed task's parent.
      for c in select * from private.pomodoist_shared_entities where scope_id=p_scope and entity_type='task'
        and deleted_at is null and data->>'parentId'=eid loop
        perform private.pomodoist_shared_put(p_scope,'task',c.entity_id,c.data||jsonb_build_object('parentId',d->'parentId'));
      end loop;
    end if;
    result:=private.pomodoist_shared_put(p_scope,typ,eid,d,now());
  elsif op='assign' then
    if typ<>'task' or e.entity_id is null or jsonb_typeof(payload->'add') is distinct from 'array'
      or jsonb_typeof(payload->'remove') is distinct from 'array' then raise exception using errcode='22023',message='Invalid assignment operation'; end if;
    for assignee in select jsonb_array_elements_text(payload->'add') loop
      if not exists(select 1 from private.pomodoist_members where scope_id=p_scope and user_id::text=assignee and role<>'observer') then
        raise exception using errcode='22023',message='Assignee must be an accepted editor';
      end if;
    end loop;
    select coalesce(jsonb_agg(to_jsonb(x) order by x),'[]') into v from (
      select jsonb_array_elements_text(coalesce(d->'assigneeIds','[]')) x union select jsonb_array_elements_text(payload->'add')
      except select jsonb_array_elements_text(payload->'remove')) a;
    d:=d||jsonb_build_object('assigneeIds',v); result:=private.pomodoist_shared_put(p_scope,typ,eid,d);
  else
    allowed:=case typ
      when 'task' then array['id','schemaVersion','content','description','projectId','parentId','priority','orderKey','dueJson','deadlineJson',
        'sectionId','recurrenceSourceId','occurrenceKey','durationSeconds','estimatedFocusIntervals','status','completedAt','createdAt','updatedAt','labelIds','labelIdsJson','repeatJson',
        'recurrenceJson','isDeleted','createdBy','scopeId','assigneeIds','completedBy','userId']
      when 'project' then array['id','schemaVersion','name','description','parentId','color','icon','orderKey','isArchived','createdAt','updatedAt','isDeleted','createdBy','scopeId','userId']
      when 'label' then array['id','schemaVersion','name','color','icon','orderKey','kind','systemKey','createdAt','updatedAt','isDeleted','createdBy','scopeId','userId']
      when 'section' then array['id','schemaVersion','name','projectId','orderKey','isArchived','createdAt','updatedAt','isDeleted','createdBy','scopeId','userId']
      when 'task_label' then array['id','schemaVersion','taskId','labelId','kind','changedAt','createdAt','updatedAt','isDeleted','scopeId','userId']
      when 'task_kanban_status' then array['id','schemaVersion','taskId','labelId','kind','changedAt','createdAt','updatedAt','isDeleted','scopeId','userId']
      when 'task_completion' then array['id','schemaVersion','taskId','userId','completedAt','snapshotJson','createdAt','scopeId']
      when 'comment' then array['id','taskId','body','mentions','createdAt','updatedAt','createdBy','scopeId']
      when 'focus_interval' then array['id','schemaVersion','taskId','projectId','runId','type','status','plannedSeconds','durationSeconds','startedAt','pausedAt','pausedTotalSeconds','completedAt','stoppedAt','sequenceNumber','createdAt','updatedAt','isDeleted','createdBy','scopeId','userId'] end;
    for k,v in select * from jsonb_each(payload) loop
      if not (k=any(allowed)) then raise exception using errcode='22023',message='Unsupported shared field: '||k; end if;
      if k in ('recurrenceSourceId','occurrenceKey') and e.entity_id is not null and e.data->k is distinct from v then
        raise exception using errcode='42501',message='Recurrence source is immutable'; end if;
      if k in ('userId','id','scopeId','createdBy','createdAt','completedBy','completedAt','updatedAt') then continue; end if;
      if k='assigneeIds' and e.entity_id is not null then
        if v is distinct from d->k then raise exception using errcode='22023',message='Use assignment add/remove operations'; end if;
        continue;
      end if;
      if coalesce((e.field_revision->>k)::bigint,0)>base and e.data->k is distinct from v then conflicts:=conflicts||to_jsonb(k); end if;
    end loop;
    if jsonb_array_length(conflicts)>0 then
      return jsonb_build_object('opId',p_op->>'opId','status','conflict','fields',conflicts,'current',e.data,'data',e.data,
        'serverRevision',e.server_revision,'entityType',typ,'entityId',eid);
    end if;
    d:=d||(payload-array['userId','id','scopeId','createdBy','createdAt','completedBy','completedAt','updatedAt']);
    d:=d||jsonb_build_object('id',eid,'scopeId',p_scope,'createdBy',coalesce(e.data->>'createdBy',p_actor::text),
      'createdAt',coalesce(e.data->'createdAt',to_jsonb(now())),'updatedAt',now());
    if d->>'isDeleted'='true' then raise exception using errcode='22023',message='Use a delete operation'; end if;
    if typ in ('task','project','label','section') then
      k:=case when typ='task' then 'content' else 'name' end;
      if jsonb_typeof(d->k) is distinct from 'string' or length(btrim(d->>k)) not between 1 and 20000 then
        raise exception using errcode='22023',message='Missing or invalid entity title'; end if;
    end if;
    if typ='task' and (coalesce(d->>'status','open') not in ('open','completed')
      or (d ? 'priority' and ((d->>'priority')::integer not between 1 and 4))) then
      raise exception using errcode='22023',message='Invalid task status or priority'; end if;
    if typ='project' then
      parent:=d->>'parentId';
      if eid<>s.root_project_id and (parent is null or not exists(select 1 from private.pomodoist_shared_entities
        where scope_id=p_scope and entity_type='project' and entity_id=parent and deleted_at is null)) then
        raise exception using errcode='22023',message='Project parent must be in the same shared scope';
      end if;
      if exists(with recursive ancestors as (
        select entity_id,data->>'parentId' parent_id from private.pomodoist_shared_entities where scope_id=p_scope and entity_type='project' and entity_id=parent
        union select e2.entity_id,e2.data->>'parentId' from private.pomodoist_shared_entities e2 join ancestors a on e2.entity_id=a.parent_id
          where e2.scope_id=p_scope and e2.entity_type='project') select 1 from ancestors where entity_id=eid) then
        raise exception using errcode='22023',message='Project cycle';
      end if;
    elsif typ='task' then
      if not exists(select 1 from private.pomodoist_shared_entities where scope_id=p_scope and entity_type='project'
        and entity_id=d->>'projectId' and deleted_at is null) then raise exception using errcode='22023',message='Task project must be in the same shared scope'; end if;
      if e.entity_id is not null and e.data->>'projectId' is distinct from d->>'projectId' and not(payload ? 'sectionId') then
        d:=d||jsonb_build_object('sectionId',null);
      end if;
      if d->>'sectionId' is not null and not exists(select 1 from private.pomodoist_shared_entities where scope_id=p_scope
        and entity_type='section' and entity_id=d->>'sectionId' and deleted_at is null and data->>'projectId'=d->>'projectId') then
        raise exception using errcode='22023',message='Section must belong to the task project'; end if;
      parent:=d->>'parentId';
      if parent is not null and not exists(select 1 from private.pomodoist_shared_entities where scope_id=p_scope and entity_type='task'
        and entity_id=parent and deleted_at is null and data->>'projectId'=d->>'projectId') then
        raise exception using errcode='22023',message='Subtask parent must belong to the same project';
      end if;
      if exists(with recursive ancestors as (
        select entity_id,data->>'parentId' parent_id from private.pomodoist_shared_entities where scope_id=p_scope and entity_type='task' and entity_id=parent
        union select e2.entity_id,e2.data->>'parentId' from private.pomodoist_shared_entities e2 join ancestors a on e2.entity_id=a.parent_id
          where e2.scope_id=p_scope and e2.entity_type='task') select 1 from ancestors where entity_id=eid) then
        raise exception using errcode='22023',message='Task cycle';
      end if;
      if jsonb_typeof(coalesce(d->'assigneeIds','[]'))<>'array' then raise exception using errcode='22023',message='Invalid assignees'; end if;
      for assignee in select jsonb_array_elements_text(coalesce(d->'assigneeIds','[]')) loop
        if not exists(select 1 from private.pomodoist_members where scope_id=p_scope and user_id::text=assignee and role<>'observer') then
          raise exception using errcode='22023',message='Assignee must be an accepted editor';
        end if;
      end loop;
      d:=d||jsonb_build_object('assigneeIds',coalesce(d->'assigneeIds','[]'));
      if d->>'status'='completed' and e.data->>'status' is distinct from 'completed' then
        d:=d||jsonb_build_object('completedBy',p_actor,'completedAt',now());
      elsif d->>'status' is distinct from 'completed' then d:=d||jsonb_build_object('completedBy',null,'completedAt',null); end if;
      -- Moving a task moves its complete subtask tree, preserving the same scope.
      if e.entity_id is not null and e.data->>'projectId' is distinct from d->>'projectId' then
        for c in with recursive children as (
          select * from private.pomodoist_shared_entities where scope_id=p_scope and entity_type='task' and data->>'parentId'=eid and deleted_at is null
          union select t.* from private.pomodoist_shared_entities t join children p on t.data->>'parentId'=p.entity_id
            where t.scope_id=p_scope and t.entity_type='task' and t.deleted_at is null) select * from children loop
          perform private.pomodoist_shared_put(p_scope,'task',c.entity_id,c.data||jsonb_build_object('projectId',d->>'projectId','sectionId',null));
        end loop;
      end if;
    elsif typ='section' then
      if not exists(select 1 from private.pomodoist_shared_entities where scope_id=p_scope and entity_type='project' and entity_id=d->>'projectId' and deleted_at is null) then
        raise exception using errcode='22023',message='Section project must belong to the shared scope'; end if;
      if e.entity_id is not null and e.data->>'projectId' is distinct from d->>'projectId' then
        for c in select * from private.pomodoist_shared_entities where scope_id=p_scope and entity_type='task'
          and data->>'sectionId'=eid and deleted_at is null loop
          perform private.pomodoist_shared_put(p_scope,'task',c.entity_id,c.data||jsonb_build_object('sectionId',null));
        end loop;
      end if;
    elsif typ in ('comment','focus_interval','task_label','task_kanban_status','task_completion') then
      if not exists(select 1 from private.pomodoist_shared_entities where scope_id=p_scope and entity_type='task'
        and entity_id=d->>'taskId' and deleted_at is null) then raise exception using errcode='22023',message='Task is inaccessible'; end if;
      if e.entity_id is not null and d->>'taskId' is distinct from e.data->>'taskId' then raise exception using errcode='22023',message='Discussion cannot be moved'; end if;
      if typ='comment' then
        if jsonb_typeof(d->'body') is distinct from 'string' or length(btrim(d->>'body'))=0 or length(d->>'body')>20000 then
          raise exception using errcode='22023',message='Comment must contain 1 to 20000 characters'; end if;
        if jsonb_typeof(coalesce(d->'mentions','[]'))<>'array' then raise exception using errcode='22023',message='Invalid mentions'; end if;
        for assignee in select jsonb_array_elements_text(coalesce(d->'mentions','[]')) loop
          if not exists(select 1 from private.pomodoist_members where scope_id=p_scope and user_id::text=assignee) then
            raise exception using errcode='22023',message='Mention must name an accepted member'; end if;
        end loop;
      elsif typ in ('task_label','task_kanban_status') then
        if (typ='task_kanban_status' and eid<>d->>'taskId')
          or (typ='task_label' and eid<>(d->>'taskId')||':'||(d->>'labelId')) then
          raise exception using errcode='22023',message='Invalid label relation identity'; end if;
        if not exists(select 1 from private.pomodoist_shared_entities where scope_id=p_scope and entity_type='label' and entity_id=d->>'labelId' and deleted_at is null) then
          raise exception using errcode='22023',message='Label must belong to the shared scope'; end if;
      elsif typ='task_completion' then
        if e.entity_id is not null then raise exception using errcode='42501',message='Completion records are immutable'; end if;
        select data into v from private.pomodoist_shared_entities where scope_id=p_scope and entity_type='task' and entity_id=d->>'taskId';
        if v->>'status' is distinct from 'completed' or v->>'completedBy' is distinct from p_actor::text then
          raise exception using errcode='42501',message='Only the completing actor may record completion'; end if;
        d:=d||jsonb_build_object('userId',p_actor,'completedAt',v->'completedAt','snapshotJson',v);
      else
        d:=d||jsonb_build_object('userId',p_actor);
        focus_seconds:=coalesce((d->>'durationSeconds')::integer,(d->>'plannedSeconds')::integer);
        focus_started:=private.pomodoist_history_timestamp(payload->>'startedAt',null);
        focus_completed:=private.pomodoist_history_timestamp(payload->>'completedAt',null);
        if focus_seconds is null or focus_seconds not between 1 and 86400 or focus_started is null or focus_completed is null
          or focus_completed>now()+interval '5 minutes' or focus_started>focus_completed-focus_seconds*interval '1 second'
          or coalesce(d->>'type','work')<>'work' or coalesce(d->>'status','completed')<>'completed' then
          raise exception using errcode='22023',message='Invalid completed focus interval'; end if;
        d:=d||jsonb_build_object('durationSeconds',focus_seconds,'startedAt',focus_started,'completedAt',focus_completed);
      end if;
    end if;
    result:=private.pomodoist_shared_put(p_scope,typ,eid,d);
  end if;
  if typ='focus_interval' then
    select jsonb_build_object('totalFocusSeconds',coalesce(sum(coalesce((data->>'durationSeconds')::bigint,(data->>'plannedSeconds')::bigint)),0),'completedFocusIntervals',count(*)) into v
      from private.pomodoist_shared_entities where scope_id=p_scope and entity_type='focus_interval' and data->>'taskId'=d->>'taskId' and deleted_at is null;
    select data into payload from private.pomodoist_shared_entities where scope_id=p_scope and entity_type='task' and entity_id=d->>'taskId';
    perform private.pomodoist_shared_put(p_scope,'task',d->>'taskId',payload||v);
  end if;
  perform private.pomodoist_collaboration_event(p_scope,p_actor,case when op='assign' then 'assignment' when typ='comment' then 'discussion' else typ||'.'||op end,eid,
    case when typ='comment' then jsonb_build_object('taskId',d->>'taskId') else '{}'::jsonb end);
  if typ='task' and op='upsert' and e.entity_id is null and jsonb_array_length(coalesce(d->'assigneeIds','[]'))>0 then
    perform private.pomodoist_collaboration_event(p_scope,p_actor,'assignment',eid);
  end if;
  if typ='comment' and op='upsert' then
    insert into private.pomodoist_notifications(user_id,scope_id,kind,data)
      select value::uuid,p_scope,'mention',jsonb_build_object('taskId',d->>'taskId','commentId',eid,'actorId',p_actor)
      from jsonb_array_elements_text(coalesce(d->'mentions','[]')) where value<>p_actor::text;
  end if;
  return result||jsonb_build_object('opId',p_op->>'opId','status','applied');
end $$;


ALTER FUNCTION private.pomodoist_shared_apply(p_scope uuid, p_actor uuid, p_role text, p_op jsonb) OWNER TO postgres;

--
-- Name: pomodoist_shared_put(uuid, text, text, jsonb, timestamp with time zone); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.pomodoist_shared_put(p_scope uuid, p_type text, p_id text, p_data jsonb, p_deleted timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare r bigint; clocks jsonb; old_data jsonb; begin
  update private.pomodoist_scopes set revision=revision+1 where id=p_scope returning revision into r;
  select data,field_revision into old_data,clocks from private.pomodoist_shared_entities
    where scope_id=p_scope and entity_type=p_type and entity_id=p_id;
  select coalesce(jsonb_object_agg(key,case when old_data->key is distinct from value
    then to_jsonb(r) else coalesce(clocks->key,to_jsonb(r)) end),'{}') into clocks from jsonb_each(p_data);
  insert into private.pomodoist_shared_entities(scope_id,entity_type,entity_id,data,field_revision,server_revision,deleted_at)
    values(p_scope,p_type,p_id,p_data,clocks,r,p_deleted)
  on conflict(scope_id,entity_type,entity_id) do update set data=excluded.data,field_revision=excluded.field_revision,
    server_revision=excluded.server_revision,deleted_at=excluded.deleted_at,updated_at=now();
  return jsonb_build_object('entityType',p_type,'entityId',p_id,'data',p_data,'serverRevision',r,'deletedAt',p_deleted,'updatedAt',now());
end $$;


ALTER FUNCTION private.pomodoist_shared_put(p_scope uuid, p_type text, p_id text, p_data jsonb, p_deleted timestamp with time zone) OWNER TO postgres;

--
-- Name: pomodoist_transfer_guard(); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.pomodoist_transfer_guard() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if new.app_id <> 'pomodoist' then return new; end if;
  if new.deleted_at is null and exists(select 1 from private.pomodoist_transferred_entities
      where user_id=new.user_id and entity_type=new.entity_type and entity_id=new.entity_id) then
    raise exception using errcode='42501',message='Entity was transferred to a shared scope';
  end if;
  if new.deleted_at is null and new.entity_type in ('project','task','section') and exists(select 1 from private.pomodoist_transferred_entities where user_id=new.user_id
      and entity_type='project' and entity_id=case when new.entity_type='project' then new.data->>'parentId' else new.data->>'projectId' end) then
    raise exception using errcode='42501',message='Personal writes cannot target shared projects';
  end if;
  if new.deleted_at is null and new.entity_type in ('task_label','task_kanban_status','task_completion')
    and exists(select 1 from private.pomodoist_transferred_entities where user_id=new.user_id and entity_type='task' and entity_id=new.data->>'taskId') then
    raise exception using errcode='42501',message='Personal content writes cannot target transferred tasks'; end if;
  if new.entity_type='task' and jsonb_typeof(new.data)='object' then
    new.data:=jsonb_set(new.data,'{createdBy}',coalesce(case when tg_op='UPDATE' then old.data->'createdBy' end,to_jsonb(new.user_id::text)));
    if new.data->>'status'='completed' and (tg_op='INSERT' or old.data->>'status' is distinct from 'completed') then
      new.data:=new.data||jsonb_build_object('completedBy',new.user_id);
    end if;
  end if;
  return new;
end $$;


ALTER FUNCTION private.pomodoist_transfer_guard() OWNER TO postgres;

--
-- Name: project_pomodoist_google_calendar_connection(uuid); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.project_pomodoist_google_calendar_connection(p_user_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_now timestamptz := pg_catalog.timezone('utc', pg_catalog.now());
  v_operations jsonb;
begin
  select pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
    'opId', 'google-calendar:connection:' || account.status || ':' || v_now::text,
    'entityType', 'google_calendar_connection',
    'entityId', 'primary',
    'operation', 'upsert',
    'payload', pg_catalog.jsonb_build_object(
      'id', 'primary',
      'accountEmail', case when account.status = 'disconnected' then null else account.account_email end,
      'calendarId', case when account.status = 'disconnected' then null else account.calendar_id end,
      'ownerDeviceId', case
        when account.status = 'disconnected' then null
        else 'google-calendar-server'
      end,
      'calendarName', account.calendar_name,
      'syncToken', case when account.status = 'disconnected' then null else account.sync_token end,
      'status', account.status,
      'lastError', account.last_error,
      'warning', account.warning,
      'lastSyncStartedAt', account.last_sync_started_at,
      'lastSyncFinishedAt', account.last_sync_finished_at,
      'createdAt', account.created_at,
      'updatedAt', account.updated_at
    ),
    'clientUpdatedAt', account.updated_at
  )) into v_operations
  from private.pomodoist_google_calendar_accounts account
  where account.user_id = p_user_id;
  if v_operations is null then return; end if;
  perform private.push_changes_for_user(
    p_user_id, 'pomodoist', 'google-calendar-server', v_operations
  );
  perform realtime.send(
    pg_catalog.jsonb_build_object(
      'appId', 'pomodoist', 'deviceId', 'google-calendar-server',
      'sentAt', pg_catalog.to_char(
        pg_catalog.clock_timestamp() at time zone 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
      )
    ),
    'changed', 'sync:' || p_user_id::text || ':pomodoist', true
  );
end;
$$;


ALTER FUNCTION private.project_pomodoist_google_calendar_connection(p_user_id uuid) OWNER TO postgres;

--
-- Name: pull_changes(text, text, bigint, integer); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.pull_changes(p_app_id text, p_device_id text, p_since_revision bigint DEFAULT 0, p_limit integer DEFAULT 500) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_user_id uuid := auth.uid();
  v_limit integer := least(greatest(coalesce(p_limit, 500), 1), 1000);
  v_changes jsonb;
  v_next_cursor bigint;
  v_has_more boolean;
  v_server_revision bigint;
  v_has_pomodoist_paid_entitlement boolean := false;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  insert into public.sync_devices (
    user_id,
    app_id,
    device_id,
    last_seen_cursor,
    last_seen_at
  )
  values (
    v_user_id,
    p_app_id,
    p_device_id,
    coalesce(p_since_revision, 0),
    timezone('utc', now())
  )
  on conflict (user_id, app_id, device_id) do update
  set last_seen_cursor = excluded.last_seen_cursor,
      last_seen_at = excluded.last_seen_at
  where public.sync_devices.last_seen_cursor
          is distinct from excluded.last_seen_cursor
     or public.sync_devices.last_seen_at
          < excluded.last_seen_at - interval '5 minutes';

  if p_app_id = 'pomodoist' then
    perform private.pomodoist_history_refresh(null,v_user_id);
    select history_unlimited or coalesce(grace_ends_at>now(),false) into v_has_pomodoist_paid_entitlement
      from private.pomodoist_personal_history where user_id=v_user_id;
  end if;

  select coalesce(max(server_revision), 0)
  into v_server_revision
  from public.sync_entities
  where user_id = v_user_id
    and app_id = p_app_id;

  if coalesce(p_since_revision, 0) > v_server_revision then
    return jsonb_build_object(
      'nextCursor', v_server_revision,
      'hasMore', false,
      'changes', '[]'::jsonb
    );
  end if;

  with page as (
    select *
    from public.sync_entities
    where user_id = v_user_id
      and app_id = p_app_id
      and server_revision > coalesce(p_since_revision, 0)
      and (
        deleted_at is null
        or deleted_at > timezone('utc', now()) - interval '90 days'
        or exists(select 1 from private.pomodoist_transferred_entities t where t.user_id=v_user_id
          and t.entity_type=public.sync_entities.entity_type and t.entity_id=public.sync_entities.entity_id)
        or (
          entity_type = 'task'
          and (v_has_pomodoist_paid_entitlement or deleted_at > now()-interval '365 days')
        )
      )
    order by server_revision asc
    limit v_limit + 1
  ),
  limited as (
    select *
    from page
    order by server_revision asc
    limit v_limit
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'entityType', entity_type,
      'entityId', entity_id,
      'serverRevision', server_revision,
      'deletedAt', deleted_at,
      'data', data,
      'updatedAt', updated_at
    ) order by server_revision asc), '[]'::jsonb),
    coalesce(max(server_revision), v_server_revision),
    (select count(*) > v_limit from page)
  into v_changes, v_next_cursor, v_has_more
  from limited;

  return jsonb_build_object(
    'nextCursor', v_next_cursor,
    'hasMore', coalesce(v_has_more, false),
    'changes', v_changes
  );
end;
$$;


ALTER FUNCTION private.pull_changes(p_app_id text, p_device_id text, p_since_revision bigint, p_limit integer) OWNER TO postgres;

--
-- Name: push_changes(text, text, jsonb); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.push_changes(p_app_id text, p_device_id text, p_operations jsonb) RETURNS jsonb
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select private.push_changes_for_user(
    auth.uid(),
    p_app_id,
    p_device_id,
    p_operations
  );
$$;


ALTER FUNCTION private.push_changes(p_app_id text, p_device_id text, p_operations jsonb) OWNER TO postgres;

--
-- Name: push_changes_for_user(uuid, text, text, jsonb); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.push_changes_for_user(p_user_id uuid, p_app_id text, p_device_id text, p_operations jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_op jsonb; v_op_id text; v_entity_type text; v_entity_id text;
  v_operation text; v_payload jsonb; v_client_updated_at timestamptz;
  v_revision bigint; v_inserted boolean; v_existing public.sync_entities%rowtype;
  v_data jsonb; v_clock jsonb; v_field_key text; v_field_value jsonb;
  v_field_clock timestamptz; v_deleted_at timestamptz;
  v_is_protected_pomodoist_anchor boolean;
  v_applied jsonb := '[]'::jsonb; v_server_revision bigint := 0;
begin
  if p_user_id is null then raise exception 'Authentication required'; end if;

  -- Validate the entire batch before locks, device updates or operation receipts.
  -- SQL NULL remains an empty batch for existing internal callers.
  if p_operations is not null and pg_catalog.jsonb_typeof(p_operations) <> 'array' then
    raise exception using errcode = '22023', message = 'Invalid sync batch: expected an array';
  end if;
  for v_op in select value from pg_catalog.jsonb_array_elements(coalesce(p_operations, '[]'::jsonb)) loop
    if pg_catalog.jsonb_typeof(v_op) <> 'object' then
      raise exception using errcode = '22023', message = 'Invalid sync operation: expected an object';
    end if;
    for v_field_key, v_field_value in
      select * from (values
        ('opId', coalesce(nullif(v_op -> 'opId', 'null'::jsonb), v_op -> 'op_id')),
        ('entityType', coalesce(nullif(v_op -> 'entityType', 'null'::jsonb), v_op -> 'entity_type')),
        ('entityId', coalesce(nullif(v_op -> 'entityId', 'null'::jsonb), v_op -> 'entity_id'))
      ) as identifiers(name, value)
    loop
      if pg_catalog.jsonb_typeof(v_field_value) is distinct from 'string'
         or pg_catalog.btrim(v_field_value #>> '{}') = '' then
        raise exception using errcode = '22023',
          message = 'Invalid sync identifier: ' || v_field_key;
      end if;
    end loop;
    if coalesce(v_op ->> 'operation', 'upsert') not in ('upsert', 'delete') then
      raise exception using errcode = '22023', message = 'Invalid sync operation: expected upsert or delete';
    end if;
    if coalesce(pg_catalog.jsonb_typeof(v_op -> 'payload'), 'object') <> 'object' then
      raise exception using errcode = '22023', message = 'Invalid sync payload: expected an object';
    end if;
  end loop;
  if p_app_id = 'pomodoist' then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('pomodoist-google-calendar:' || p_user_id::text, 0));
  end if;
  insert into public.sync_devices (user_id, app_id, device_id, last_seen_at)
  values (p_user_id, p_app_id, p_device_id, pg_catalog.timezone('utc', pg_catalog.now()))
  on conflict (user_id, app_id, device_id) do update
  set last_seen_at = excluded.last_seen_at
  where public.sync_devices.last_seen_at < excluded.last_seen_at - interval '5 minutes';

  for v_op in select value from pg_catalog.jsonb_array_elements(coalesce(p_operations, '[]'::jsonb)) loop
    v_op_id := coalesce(v_op ->> 'opId', v_op ->> 'op_id');
    v_entity_type := coalesce(v_op ->> 'entityType', v_op ->> 'entity_type');
    v_entity_id := coalesce(v_op ->> 'entityId', v_op ->> 'entity_id');
    v_operation := coalesce(v_op ->> 'operation', 'upsert');
    v_payload := coalesce(v_op -> 'payload', '{}'::jsonb);
    v_client_updated_at := coalesce(nullif(coalesce(v_op ->> 'clientUpdatedAt', v_op ->> 'client_updated_at'), '')::timestamptz,
      pg_catalog.timezone('utc', pg_catalog.now()));
    if v_op_id is null or v_entity_type is null or v_entity_id is null then
      raise exception 'Invalid sync operation: %', v_op;
    end if;
    v_is_protected_pomodoist_anchor := p_app_id = 'pomodoist' and (
      (v_entity_type = 'project' and v_entity_id = 'inbox') or
      (v_entity_type = 'label' and v_entity_id in ('kanban-status-backlog-v1', 'kanban-status-done-v1')) or
      (v_entity_type = 'kanban_settings' and v_entity_id = 'kanban-settings-primary-v1'));
    if v_operation = 'delete' and v_is_protected_pomodoist_anchor then
      raise exception using errcode = '22023', message = pg_catalog.format(
        'Protected Pomodoist system anchor cannot be deleted: %s/%s', v_entity_type, v_entity_id);
    end if;
    v_revision := pg_catalog.nextval('public.sync_revision_seq');
    v_inserted := false;
    insert into public.sync_operation_receipts (user_id, op_id, server_revision)
    values (p_user_id, v_op_id, v_revision) on conflict (user_id, op_id) do nothing
    returning true into v_inserted;
    if not coalesce(v_inserted, false) then continue; end if;
    select * into v_existing from public.sync_entities
    where user_id = p_user_id and app_id = p_app_id and entity_type = v_entity_type and entity_id = v_entity_id
    for update;
    v_data := coalesce(v_existing.data, '{}'::jsonb);
    v_clock := coalesce(v_existing.field_clock, '{}'::jsonb);
    v_deleted_at := v_existing.deleted_at;
    if v_operation = 'delete' then
      v_deleted_at := coalesce(v_deleted_at, v_client_updated_at);
    elsif v_deleted_at is null or v_is_protected_pomodoist_anchor then
      v_deleted_at := null;
      for v_field_key, v_field_value in select key, value from pg_catalog.jsonb_each(v_payload) loop
        v_field_clock := nullif(v_clock ->> v_field_key, '')::timestamptz;
        if v_field_clock is null or v_field_clock <= v_client_updated_at then
          v_data := pg_catalog.jsonb_set(v_data, array[v_field_key], v_field_value, true);
          v_clock := pg_catalog.jsonb_set(v_clock, array[v_field_key], pg_catalog.to_jsonb(v_client_updated_at), true);
        end if;
      end loop;
    end if;
    insert into public.sync_entities (user_id, app_id, entity_type, entity_id, server_revision,
      client_updated_at, deleted_at, data, field_clock)
    values (p_user_id, p_app_id, v_entity_type, v_entity_id, v_revision, v_client_updated_at, v_deleted_at, v_data, v_clock)
    on conflict (user_id, app_id, entity_type, entity_id) do update
    set server_revision = excluded.server_revision, client_updated_at = excluded.client_updated_at,
      deleted_at = excluded.deleted_at, data = excluded.data, field_clock = excluded.field_clock;
    v_server_revision := greatest(v_server_revision, v_revision);
    v_applied := v_applied || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
      'entityType', v_entity_type, 'entityId', v_entity_id, 'serverRevision', v_revision,
      'deletedAt', v_deleted_at, 'data', v_data, 'updatedAt', v_client_updated_at));
  end loop;
  select coalesce(pg_catalog.max(server_revision), 0) into v_server_revision
  from public.sync_entities where user_id = p_user_id and app_id = p_app_id;
  return pg_catalog.jsonb_build_object('serverRevision', v_server_revision, 'applied', v_applied);
end;
$$;


ALTER FUNCTION private.push_changes_for_user(p_user_id uuid, p_app_id text, p_device_id text, p_operations jsonb) OWNER TO postgres;

--
-- Name: queue_pomodoist_google_calendar(uuid, timestamp with time zone); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.queue_pomodoist_google_calendar(p_user_id uuid, p_due_at timestamp with time zone DEFAULT timezone('utc'::text, now())) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_due_at timestamptz;
  v_status text;
  v_should_wake boolean := false;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('pomodoist-google-calendar:' || p_user_id::text, 0)
  );
  if not exists (
    select 1
    from private.pomodoist_google_calendar_accounts
    where user_id = p_user_id and status <> 'disconnected'
  ) then
    return;
  end if;
  select status, due_at into v_status, v_due_at
  from private.pomodoist_google_calendar_jobs
  where user_id = p_user_id
  for update;
  if not found then
    insert into private.pomodoist_google_calendar_jobs (user_id, due_at)
    values (p_user_id, p_due_at);
    v_should_wake := p_due_at <= pg_catalog.timezone('utc', pg_catalog.now());
  else
    update private.pomodoist_google_calendar_jobs
    set status = case when v_status = 'processing' then 'processing' else 'pending' end,
        due_at = least(v_due_at, p_due_at),
        generation = generation + 1,
        lease_until = case when v_status = 'processing' then lease_until else null end,
        last_error = null,
        updated_at = pg_catalog.timezone('utc', pg_catalog.now())
    where user_id = p_user_id;
    v_should_wake := v_status <> 'processing'
      and v_due_at > pg_catalog.timezone('utc', pg_catalog.now())
      and p_due_at <= pg_catalog.timezone('utc', pg_catalog.now());
  end if;
  if v_should_wake then
    perform private.invoke_pomodoist_google_calendar_worker();
  end if;
end;
$$;


ALTER FUNCTION private.queue_pomodoist_google_calendar(p_user_id uuid, p_due_at timestamp with time zone) OWNER TO postgres;

--
-- Name: read_pomodoist_mcp_v1(uuid, text, jsonb); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.read_pomodoist_mcp_v1(p_user_id uuid, p_operation text, p_arguments jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
declare
  v_view text;
  v_time_zone text;
  v_query text;
  v_project_id text;
  v_task_id text;
  v_report_date date;
  v_limit integer := 50;
  v_filter jsonb := '{}'::jsonb;
  v_cursor jsonb;
  v_cursor_text text;
  v_items jsonb := '[]'::jsonb;
  v_positions jsonb := '[]'::jsonb;
  v_last jsonb;
  v_has_more boolean := false;
  v_row public.sync_entities%rowtype;
  v_settings jsonb;
  v_statuses jsonb;
  v_assignments jsonb;
begin
  if p_user_id is null
    or p_operation not in (
      'list_tasks',
      'get_task',
      'list_projects',
      'list_labels',
      'get_kanban_board',
      'list_focus_history',
      'get_productivity_report',
      'get_achievements'
    )
    or pg_catalog.jsonb_typeof(p_arguments) is distinct from 'object'
  then
    raise exception using
      errcode = '22023',
      message = 'Invalid Pomodoist MCP read request';
  end if;

  if p_operation = 'get_task' then
    if exists (
      select 1
      from pg_catalog.jsonb_object_keys(p_arguments) key
      where key <> 'task_id'
    )
      or pg_catalog.jsonb_typeof(p_arguments -> 'task_id')
        is distinct from 'string'
      or p_arguments ->> 'task_id'
        !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,199}$'
    then
      raise exception using
        errcode = '22023',
        message = 'Invalid Pomodoist MCP read request';
    end if;

    v_task_id := p_arguments ->> 'task_id';
    select *
    into v_row
    from public.sync_entities
    where user_id = p_user_id
      and app_id = 'pomodoist'
      and entity_type = 'task'
      and entity_id = v_task_id;

    if not found then
      return pg_catalog.jsonb_build_object(
        'status', 'missing',
        'taskId', v_task_id
      );
    end if;
    if v_row.deleted_at is not null
      or coalesce(v_row.data ->> 'isDeleted', 'false') = 'true'
    then
      return pg_catalog.jsonb_build_object(
        'status', 'tombstoned',
        'taskId', v_task_id
      );
    end if;
    return pg_catalog.jsonb_build_object(
      'status', 'found',
      'task', private.pomodoist_mcp_task_json(
        v_row.entity_id,
        v_row.data
      )
    );
  end if;

  if p_operation in ('get_productivity_report', 'get_achievements') then
    if exists (
      select 1
      from pg_catalog.jsonb_object_keys(p_arguments) key
      where key not in ('date', 'time_zone')
    )
      or pg_catalog.jsonb_typeof(p_arguments -> 'date')
        is distinct from 'string'
      or pg_catalog.jsonb_typeof(p_arguments -> 'time_zone')
        is distinct from 'string'
      or p_arguments ->> 'date' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
      or not exists (
        select 1
        from pg_catalog.pg_timezone_names
        where name = p_arguments ->> 'time_zone'
      )
    then
      raise exception using
        errcode = '22023',
        message = 'Invalid Pomodoist MCP read request';
    end if;

    begin
      v_report_date := (p_arguments ->> 'date')::date;
    exception
      when invalid_datetime_format or datetime_field_overflow then
        raise exception using
          errcode = '22023',
          message = 'Invalid Pomodoist MCP read request';
    end;
    if pg_catalog.to_char(v_report_date, 'YYYY-MM-DD')
      <> p_arguments ->> 'date'
    then
      raise exception using
        errcode = '22023',
        message = 'Invalid Pomodoist MCP read request';
    end if;
    return private.pomodoist_mcp_productivity_metrics(
      p_user_id,
      v_report_date,
      p_arguments ->> 'time_zone'
    );
  end if;

  if p_operation = 'get_kanban_board' then
    if p_arguments <> '{}'::jsonb then
      raise exception using
        errcode = '22023',
        message = 'Invalid Pomodoist MCP read request';
    end if;

    select pg_catalog.jsonb_build_object(
      'id', entity_id,
      'selectedProjectIds',
      private.pomodoist_mcp_json_array(data ->> 'selectedProjectIdsJson'),
      'focusStatusLabelId', data -> 'focusStatusLabelId',
      'createdAt', data -> 'createdAt',
      'updatedAt', data -> 'updatedAt'
    )
    into v_settings
    from public.sync_entities
    where user_id = p_user_id
      and app_id = 'pomodoist'
      and entity_type = 'kanban_settings'
      and entity_id = 'kanban-settings-primary-v1'
      and deleted_at is null;

    select coalesce(
      pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'id', entity_id,
          'name', data -> 'name',
          'color', data -> 'color',
          'systemKey', data -> 'systemKey',
          'orderKey', data -> 'orderKey',
          'createdAt', data -> 'createdAt',
          'updatedAt', data -> 'updatedAt'
        )
        order by
          case data ->> 'systemKey'
            when 'backlog' then 0
            when 'done' then 2
            else 1
          end,
          data ->> 'orderKey',
          entity_id
      ),
      '[]'::jsonb
    )
    into v_statuses
    from public.sync_entities
    where user_id = p_user_id
      and app_id = 'pomodoist'
      and entity_type = 'label'
      and deleted_at is null
      and data ->> 'kind' = 'kanbanStatus'
      and coalesce(data ->> 'isDeleted', 'false') <> 'true';

    select coalesce(
      pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'taskId', assignment.entity_id,
          'statusId', assignment.data ->> 'labelId'
        )
        order by assignment.entity_id
      ),
      '[]'::jsonb
    )
    into v_assignments
    from public.sync_entities assignment
    join public.sync_entities task
      on task.user_id = assignment.user_id
      and task.app_id = 'pomodoist'
      and task.entity_type = 'task'
      and task.entity_id = assignment.entity_id
      and task.deleted_at is null
      and coalesce(task.data ->> 'isDeleted', 'false') <> 'true'
    join public.sync_entities status
      on status.user_id = assignment.user_id
      and status.app_id = 'pomodoist'
      and status.entity_type = 'label'
      and status.entity_id = assignment.data ->> 'labelId'
      and status.deleted_at is null
      and status.data ->> 'kind' = 'kanbanStatus'
      and coalesce(status.data ->> 'isDeleted', 'false') <> 'true'
    where assignment.user_id = p_user_id
      and assignment.app_id = 'pomodoist'
      and assignment.entity_type = 'task_kanban_status'
      and assignment.deleted_at is null;

    return pg_catalog.jsonb_build_object(
      'settings', coalesce(
        v_settings,
        pg_catalog.jsonb_build_object(
          'id', 'kanban-settings-primary-v1',
          'selectedProjectIds', '[]'::jsonb,
          'focusStatusLabelId', null
        )
      ),
      'statuses', v_statuses,
      'assignments', v_assignments
    );
  end if;

  if p_operation = 'list_tasks' then
    if exists (
      select 1
      from pg_catalog.jsonb_object_keys(p_arguments) key
      where key not in (
        'view', 'time_zone', 'date', 'project_id', 'query',
        'limit', 'cursor'
      )
    )
      or pg_catalog.jsonb_typeof(p_arguments -> 'view')
        is distinct from 'string'
      or p_arguments ->> 'view' not in (
        'inbox', 'today', 'upcoming', 'date',
        'project', 'search', 'all', 'completed'
      )
    then
      raise exception using
        errcode = '22023',
        message = 'Invalid Pomodoist MCP read request';
    end if;

    v_view := p_arguments ->> 'view';
    if v_view in ('today', 'upcoming', 'date') then
      if pg_catalog.jsonb_typeof(p_arguments -> 'time_zone')
          is distinct from 'string'
        or not exists (
          select 1
          from pg_catalog.pg_timezone_names
          where name = p_arguments ->> 'time_zone'
        )
      then
        raise exception using
          errcode = '22023',
          message = 'Invalid Pomodoist MCP read request';
      end if;
      v_time_zone := p_arguments ->> 'time_zone';
      v_filter := v_filter || pg_catalog.jsonb_build_object(
        'time_zone',
        v_time_zone
      );
    elsif p_arguments ? 'time_zone' then
      raise exception using
        errcode = '22023',
        message = 'Invalid Pomodoist MCP read request';
    end if;

    if v_view = 'date' then
      if pg_catalog.jsonb_typeof(p_arguments -> 'date')
          is distinct from 'string'
        or p_arguments ->> 'date' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
      then
        raise exception using
          errcode = '22023',
          message = 'Invalid Pomodoist MCP read request';
      end if;
      begin
        v_report_date := (p_arguments ->> 'date')::date;
      exception
        when invalid_datetime_format or datetime_field_overflow then
          raise exception using
            errcode = '22023',
            message = 'Invalid Pomodoist MCP read request';
      end;
      if pg_catalog.to_char(v_report_date, 'YYYY-MM-DD')
        <> p_arguments ->> 'date'
      then
        raise exception using
          errcode = '22023',
          message = 'Invalid Pomodoist MCP read request';
      end if;
      v_filter := v_filter || pg_catalog.jsonb_build_object(
        'date',
        pg_catalog.to_char(v_report_date, 'YYYY-MM-DD')
      );
    elsif p_arguments ? 'date' then
      raise exception using
        errcode = '22023',
        message = 'Invalid Pomodoist MCP read request';
    end if;

    if v_view = 'project' then
      if pg_catalog.jsonb_typeof(p_arguments -> 'project_id')
          is distinct from 'string'
        or p_arguments ->> 'project_id'
          !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,199}$'
      then
        raise exception using
          errcode = '22023',
          message = 'Invalid Pomodoist MCP read request';
      end if;
      v_project_id := p_arguments ->> 'project_id';
      v_filter := v_filter || pg_catalog.jsonb_build_object(
        'project_id',
        v_project_id
      );
    elsif p_arguments ? 'project_id' then
      raise exception using
        errcode = '22023',
        message = 'Invalid Pomodoist MCP read request';
    end if;

    if v_view = 'search' then
      if pg_catalog.jsonb_typeof(p_arguments -> 'query')
          is distinct from 'string'
        or pg_catalog.btrim(p_arguments ->> 'query') = ''
        or pg_catalog.length(pg_catalog.btrim(p_arguments ->> 'query')) > 500
      then
        raise exception using
          errcode = '22023',
          message = 'Invalid Pomodoist MCP read request';
      end if;
      v_query := pg_catalog.lower(
        pg_catalog.btrim(p_arguments ->> 'query')
      );
      v_filter := v_filter || pg_catalog.jsonb_build_object(
        'query',
        v_query
      );
    elsif p_arguments ? 'query' then
      raise exception using
        errcode = '22023',
        message = 'Invalid Pomodoist MCP read request';
    end if;
    v_filter := v_filter || pg_catalog.jsonb_build_object('view', v_view);
  elsif p_operation in (
    'list_projects',
    'list_labels',
    'list_focus_history'
  ) then
    if exists (
      select 1
      from pg_catalog.jsonb_object_keys(p_arguments) key
      where key not in ('limit', 'cursor')
    ) then
      raise exception using
        errcode = '22023',
        message = 'Invalid Pomodoist MCP read request';
    end if;
  end if;

  if p_arguments ? 'limit' then
    if pg_catalog.jsonb_typeof(p_arguments -> 'limit')
        is distinct from 'number'
      or p_arguments ->> 'limit' !~ '^[0-9]+$'
      or not pg_catalog.pg_input_is_valid(
        p_arguments ->> 'limit',
        'integer'
      )
    then
      raise exception using
        errcode = '22023',
        message = 'Invalid Pomodoist MCP read request';
    end if;
    v_limit := (p_arguments ->> 'limit')::integer;
    if v_limit < 1 or v_limit > 100 then
      raise exception using
        errcode = '22023',
        message = 'Invalid Pomodoist MCP read request';
    end if;
  end if;

  if p_arguments ? 'cursor' then
    if pg_catalog.jsonb_typeof(p_arguments -> 'cursor')
        is distinct from 'string'
      or pg_catalog.btrim(p_arguments ->> 'cursor') = ''
      or pg_catalog.length(p_arguments ->> 'cursor') > 4096
    then
      raise exception using
        errcode = '22023',
        message = 'Invalid Pomodoist MCP read request';
    end if;
    begin
      v_cursor_text := pg_catalog.convert_from(
        pg_catalog.decode(p_arguments ->> 'cursor', 'base64'),
        'UTF8'
      );
      v_cursor := v_cursor_text::jsonb;
    exception
      when others then
        raise exception using
          errcode = '22023',
          message = 'Invalid Pomodoist MCP read request';
    end;
    if pg_catalog.jsonb_typeof(v_cursor) is distinct from 'object'
      or v_cursor ->> 'b' is distinct from pg_catalog.encode(
        extensions.digest(
          p_user_id::text || E'\x1f'
            || p_operation || E'\x1f'
            || v_filter::text || E'\x1fv1',
          'sha256'
        ),
        'hex'
      )
      or v_cursor ->> 'o' is distinct from p_operation
      or v_cursor -> 'f' is distinct from v_filter
      or pg_catalog.jsonb_typeof(v_cursor -> 'k') is distinct from 'object'
    then
      raise exception using
        errcode = '22023',
        message = 'Invalid Pomodoist MCP read request';
    end if;
  end if;

  if p_operation = 'list_tasks' then
    if v_cursor is not null and (
      pg_catalog.jsonb_typeof(v_cursor #> '{k,d}') is distinct from 'number'
      or v_cursor #>> '{k,d}' !~ '^-?[0-9]+$'
      or not pg_catalog.pg_input_is_valid(v_cursor #>> '{k,d}', 'integer')
      or pg_catalog.jsonb_typeof(v_cursor #> '{k,o}')
        is distinct from 'string'
      or pg_catalog.jsonb_typeof(v_cursor #> '{k,i}')
        is distinct from 'string'
    ) then
      raise exception using
        errcode = '22023',
        message = 'Invalid Pomodoist MCP read request';
    end if;

    with candidates as (
      select
        entity_id,
        data,
        case
          when pg_catalog.pg_input_is_valid(data ->> 'dayOrder', 'integer')
          then (data ->> 'dayOrder')::integer
          else 999999
        end as day_order,
        coalesce(data ->> 'orderKey', '') as order_key,
        private.pomodoist_mcp_schedule_date(
          data ->> 'dueJson',
          coalesce(v_time_zone, 'UTC')
        ) as due_date
      from public.sync_entities
      where user_id = p_user_id
        and app_id = 'pomodoist'
        and entity_type = 'task'
        and deleted_at is null
        and coalesce(data ->> 'isDeleted', 'false') <> 'true'
    ),
    filtered as (
      select *
      from candidates
      where case v_view
        when 'inbox' then
          data ->> 'status' <> 'completed'
          and data ->> 'projectId' = 'inbox'
          and due_date is null
        when 'today' then
          data ->> 'status' <> 'completed'
          and due_date is not null
          and due_date <= (
            pg_catalog.now() at time zone v_time_zone
          )::date
        when 'upcoming' then
          data ->> 'status' <> 'completed'
          and due_date is not null
          and due_date > (
            pg_catalog.now() at time zone v_time_zone
          )::date
        when 'date' then
          data ->> 'status' <> 'completed'
          and due_date = v_report_date
        when 'project' then
          data ->> 'status' <> 'completed'
          and data ->> 'projectId' = v_project_id
        when 'search' then
          data ->> 'status' <> 'completed'
          and (
            pg_catalog.strpos(
              pg_catalog.lower(coalesce(data ->> 'content', '')),
              v_query
            ) > 0
            or pg_catalog.strpos(
              pg_catalog.lower(coalesce(data ->> 'description', '')),
              v_query
            ) > 0
          )
        when 'all' then data ->> 'status' <> 'completed'
        when 'completed' then data ->> 'status' = 'completed'
      end
    ),
    page as (
      select
        *,
        pg_catalog.row_number() over (
          order by day_order, order_key, entity_id
        ) as row_number
      from filtered
      where v_cursor is null
        or (day_order, order_key, entity_id) > (
          (v_cursor #>> '{k,d}')::integer,
          v_cursor #>> '{k,o}',
          v_cursor #>> '{k,i}'
        )
      order by day_order, order_key, entity_id
      limit v_limit + 1
    )
    select
      coalesce(
        pg_catalog.jsonb_agg(
          private.pomodoist_mcp_task_json(entity_id, data)
          order by day_order, order_key, entity_id
        ) filter (where row_number <= v_limit),
        '[]'::jsonb
      ),
      coalesce(
        pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'd', day_order,
            'o', order_key,
            'i', entity_id
          )
          order by day_order, order_key, entity_id
        ) filter (where row_number <= v_limit),
        '[]'::jsonb
      ),
      pg_catalog.count(*) > v_limit
    into v_items, v_positions, v_has_more
    from page;
  elsif p_operation in ('list_projects', 'list_labels') then
    if v_cursor is not null and (
      pg_catalog.jsonb_typeof(v_cursor #> '{k,o}')
        is distinct from 'string'
      or pg_catalog.jsonb_typeof(v_cursor #> '{k,i}')
        is distinct from 'string'
    ) then
      raise exception using
        errcode = '22023',
        message = 'Invalid Pomodoist MCP read request';
    end if;

    with page as (
      select
        entity_id,
        data,
        coalesce(data ->> 'orderKey', '') as order_key,
        pg_catalog.row_number() over (
          order by coalesce(data ->> 'orderKey', ''), entity_id
        ) as row_number
      from public.sync_entities
      where user_id = p_user_id
        and app_id = 'pomodoist'
        and entity_type = case
          when p_operation = 'list_projects' then 'project'
          else 'label'
        end
        and deleted_at is null
        and coalesce(data ->> 'isDeleted', 'false') <> 'true'
        and (
          p_operation = 'list_projects'
          or data ->> 'kind' = 'user'
        )
        and (
          v_cursor is null
          or (coalesce(data ->> 'orderKey', ''), entity_id) > (
            v_cursor #>> '{k,o}',
            v_cursor #>> '{k,i}'
          )
        )
      order by coalesce(data ->> 'orderKey', ''), entity_id
      limit v_limit + 1
    )
    select
      coalesce(
        pg_catalog.jsonb_agg(
          case
            when p_operation = 'list_projects' then
              pg_catalog.jsonb_build_object(
                'id', entity_id,
                'name', data -> 'name',
                'color', data -> 'color',
                'parentId', data -> 'parentId',
                'viewStyle', data -> 'viewStyle',
                'isFavorite', data -> 'isFavorite',
                'isArchived', data -> 'isArchived',
                'orderKey', data -> 'orderKey',
                'createdAt', data -> 'createdAt',
                'updatedAt', data -> 'updatedAt'
              )
            else
              pg_catalog.jsonb_build_object(
                'id', entity_id,
                'name', data -> 'name',
                'color', data -> 'color',
                'orderKey', data -> 'orderKey',
                'isFavorite', data -> 'isFavorite',
                'createdAt', data -> 'createdAt',
                'updatedAt', data -> 'updatedAt'
              )
          end
          order by order_key, entity_id
        ) filter (where row_number <= v_limit),
        '[]'::jsonb
      ),
      coalesce(
        pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object('o', order_key, 'i', entity_id)
          order by order_key, entity_id
        ) filter (where row_number <= v_limit),
        '[]'::jsonb
      ),
      pg_catalog.count(*) > v_limit
    into v_items, v_positions, v_has_more
    from page;
  else
    if v_cursor is not null and (
      pg_catalog.jsonb_typeof(v_cursor #> '{k,s}')
        is distinct from 'string'
      or private.pomodoist_mcp_finite_timestamptz(
        v_cursor #>> '{k,s}'
      ) is null
      or pg_catalog.jsonb_typeof(v_cursor #> '{k,i}')
        is distinct from 'string'
    ) then
      raise exception using
        errcode = '22023',
        message = 'Invalid Pomodoist MCP read request';
    end if;

    with candidates as (
      select
        entity_id,
        data,
        private.pomodoist_mcp_finite_timestamptz(
          data ->> 'startedAt'
        ) as started_at,
        coalesce(
          private.pomodoist_mcp_finite_timestamptz(
            data ->> 'completedAt'
          ),
          private.pomodoist_mcp_finite_timestamptz(
            data ->> 'stoppedAt'
          )
        ) as completed_at,
        case
          when pg_catalog.pg_input_is_valid(
            data ->> 'pausedTotalSeconds',
            'integer'
          )
          then (data ->> 'pausedTotalSeconds')::integer
          else 0
        end as paused_seconds
      from public.sync_entities
      where user_id = p_user_id
        and app_id = 'pomodoist'
        and entity_type = 'focus_interval'
        and deleted_at is null
        and coalesce(data ->> 'isDeleted', 'false') <> 'true'
        and data ->> 'type' = 'work'
        and data ->> 'status' = 'completed'
    ),
    page as (
      select
        *,
        pg_catalog.row_number() over (
          order by started_at desc, entity_id desc
        ) as row_number
      from candidates
      where started_at is not null
        and completed_at is not null
        and (
          v_cursor is null
          or (started_at, entity_id) < (
            (v_cursor #>> '{k,s}')::timestamptz,
            v_cursor #>> '{k,i}'
          )
        )
      order by started_at desc, entity_id desc
      limit v_limit + 1
    )
    select
      coalesce(
        pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'id', entity_id,
            'taskId', data -> 'taskId',
            'projectId', data -> 'projectId',
            'startedAt', started_at,
            'completedAt', completed_at,
            'actualSeconds',
            greatest(
              pg_catalog.floor(
                extract(epoch from completed_at)
                - extract(epoch from started_at)
              )::bigint - paused_seconds,
              0::bigint
            )
          )
          order by started_at desc, entity_id desc
        ) filter (where row_number <= v_limit),
        '[]'::jsonb
      ),
      coalesce(
        pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            's', started_at,
            'i', entity_id
          )
          order by started_at desc, entity_id desc
        ) filter (where row_number <= v_limit),
        '[]'::jsonb
      ),
      pg_catalog.count(*) > v_limit
    into v_items, v_positions, v_has_more
    from page;
  end if;

  if v_has_more then
    v_last := v_positions -> (
      pg_catalog.jsonb_array_length(v_positions) - 1
    );
    v_cursor_text := pg_catalog.replace(
      pg_catalog.encode(
        pg_catalog.convert_to(
          pg_catalog.jsonb_build_object(
            'b', pg_catalog.encode(
              extensions.digest(
                p_user_id::text || E'\x1f'
                  || p_operation || E'\x1f'
                  || v_filter::text || E'\x1fv1',
                'sha256'
              ),
              'hex'
            ),
            'o', p_operation,
            'f', v_filter,
            'k', v_last
          )::text,
          'UTF8'
        ),
        'base64'
      ),
      E'\n',
      ''
    );
  else
    v_cursor_text := null;
  end if;

  return pg_catalog.jsonb_build_object(
    'items', v_items,
    'nextCursor', v_cursor_text
  );
end;
$_$;


ALTER FUNCTION private.read_pomodoist_mcp_v1(p_user_id uuid, p_operation text, p_arguments jsonb) OWNER TO postgres;

--
-- Name: reconcile_pomodoist_profile_pro(); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.reconcile_pomodoist_profile_pro() RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO ''
    AS $$
  with expected as (
    select
      p.id,
      public.has_active_pomodoist_paid_entitlement(p.id) as is_pro
    from public.profiles p
  )
  update public.profiles p
  set pomodoist_is_pro = expected.is_pro
  from expected
  where p.id = expected.id
    and p.pomodoist_is_pro is distinct from expected.is_pro;
$$;


ALTER FUNCTION private.reconcile_pomodoist_profile_pro() OWNER TO postgres;

--
-- Name: refresh_pomodoist_profile_pro(uuid); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.refresh_pomodoist_profile_pro(p_user_id uuid) RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO ''
    AS $$
  with expected as (
    select public.has_active_pomodoist_paid_entitlement(p_user_id) as is_pro
  )
  update public.profiles p
  set pomodoist_is_pro = expected.is_pro
  from expected
  where p.id = p_user_id
    and p.pomodoist_is_pro is distinct from expected.is_pro;
$$;


ALTER FUNCTION private.refresh_pomodoist_profile_pro(p_user_id uuid) OWNER TO postgres;

--
-- Name: sync_pomodoist_profile_pro(); Type: FUNCTION; Schema: private; Owner: postgres
--

CREATE FUNCTION private.sync_pomodoist_profile_pro() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if tg_op = 'DELETE' then
    if old.app_id = 'pomodoist' then
      perform private.refresh_pomodoist_profile_pro(old.user_id);
    end if;
    return old;
  end if;

  if tg_op = 'INSERT' then
    if new.app_id = 'pomodoist' then
      perform private.refresh_pomodoist_profile_pro(new.user_id);
    end if;
    return new;
  end if;

  if old.app_id = 'pomodoist' then
    perform private.refresh_pomodoist_profile_pro(old.user_id);
  end if;
  if new.app_id = 'pomodoist'
      and (old.app_id <> 'pomodoist' or new.user_id is distinct from old.user_id) then
    perform private.refresh_pomodoist_profile_pro(new.user_id);
  end if;
  return new;
end;
$$;


ALTER FUNCTION private.sync_pomodoist_profile_pro() OWNER TO postgres;

--
-- Name: begin_pomodoist_telegram_link(bigint, bytea, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.begin_pomodoist_telegram_link(p_telegram_user_id bigint, p_token_hash bytea, p_expires_at timestamp with time zone) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_account public.pomodoist_telegram_accounts%rowtype;
begin
  if pg_catalog.octet_length(p_token_hash) <> 32
    or p_expires_at <= pg_catalog.timezone('utc', pg_catalog.now())
    or p_expires_at > pg_catalog.timezone('utc', pg_catalog.now()) + interval '15 minutes 5 seconds'
  then
    raise exception using errcode = '22023', message = 'Invalid Telegram link token';
  end if;

  select * into v_account
  from public.pomodoist_telegram_accounts
  where telegram_user_id = p_telegram_user_id
  for update;
  if not found
    or v_account.linked_at is not null
    or v_account.guest_user_id is null
    or v_account.user_id is distinct from v_account.guest_user_id
  then
    raise exception using errcode = '22023', message = 'Telegram account already linked';
  end if;

  delete from public.pomodoist_telegram_link_attempts
  where telegram_user_id = p_telegram_user_id;

  insert into public.pomodoist_telegram_link_attempts (
    token_hash,
    telegram_user_id,
    expires_at
  ) values (p_token_hash, p_telegram_user_id, p_expires_at);
end;
$$;


ALTER FUNCTION public.begin_pomodoist_telegram_link(p_telegram_user_id bigint, p_token_hash bytea, p_expires_at timestamp with time zone) OWNER TO postgres;

--
-- Name: bootstrap_pomodoist_telegram(bigint, uuid, uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.bootstrap_pomodoist_telegram(p_telegram_user_id bigint, p_guest_user_id uuid, p_client_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_account public.pomodoist_telegram_accounts%rowtype;
begin
  if p_telegram_user_id <= 0 or p_guest_user_id is null or p_client_id is null then
    raise exception using errcode = '22023', message = 'Invalid Telegram identity';
  end if;

  insert into public.pomodoist_telegram_accounts (
    telegram_user_id,
    user_id,
    guest_user_id,
    client_id
  )
  values (p_telegram_user_id, p_guest_user_id, p_guest_user_id, p_client_id)
  on conflict (telegram_user_id) do nothing;

  select * into strict v_account
  from public.pomodoist_telegram_accounts
  where telegram_user_id = p_telegram_user_id;

  return pg_catalog.jsonb_build_object(
    'telegramUserId', v_account.telegram_user_id::text,
    'userId', v_account.user_id::text,
    'guestUserId', v_account.guest_user_id::text,
    'clientId', v_account.client_id::text,
    'linked', v_account.guest_user_id is null
      or v_account.user_id is distinct from v_account.guest_user_id
  );
end;
$$;


ALTER FUNCTION public.bootstrap_pomodoist_telegram(p_telegram_user_id bigint, p_guest_user_id uuid, p_client_id uuid) OWNER TO postgres;

--
-- Name: complete_pomodoist_telegram_link(bytea, uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.complete_pomodoist_telegram_link(p_token_hash bytea, p_target_user_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_attempt public.pomodoist_telegram_link_attempts%rowtype;
  v_account public.pomodoist_telegram_accounts%rowtype;
  v_now timestamptz := pg_catalog.timezone('utc', pg_catalog.now());
  v_entity_types text[] := array[
    'task',
    'task_completion',
    'focus_run',
    'focus_interval',
    'focus_event'
  ];
begin
  select * into v_attempt
  from public.pomodoist_telegram_link_attempts
  where token_hash = p_token_hash
    and used_at is null
    and expires_at > v_now;
  if not found then
    raise exception using
      errcode = '22023',
      message = 'Invalid or expired Telegram link token';
  end if;

  select * into strict v_account
  from public.pomodoist_telegram_accounts
  where telegram_user_id = v_attempt.telegram_user_id
  for update;

  select * into v_attempt
  from public.pomodoist_telegram_link_attempts
  where token_hash = p_token_hash
    and telegram_user_id = v_account.telegram_user_id
    and used_at is null
    and expires_at > v_now
  for update;
  if not found then
    raise exception using
      errcode = '22023',
      message = 'Invalid or expired Telegram link token';
  end if;

  if v_account.linked_at is not null
    or v_account.guest_user_id is null
    or v_account.user_id is distinct from v_account.guest_user_id
  then
    raise exception using
      errcode = '22023',
      message = 'Invalid or expired Telegram link token';
  end if;

  if p_target_user_id is null
    or p_target_user_id = v_account.guest_user_id
    or not exists (select 1 from public.profiles where id = p_target_user_id)
  then
    raise exception using errcode = '22023', message = 'Invalid Pomodoist target account';
  end if;

  if exists (
    select 1
    from public.sync_entities guest_run
    where guest_run.user_id = v_account.guest_user_id
      and guest_run.app_id = 'pomodoist'
      and guest_run.entity_type = 'focus_run'
      and guest_run.deleted_at is null
      and guest_run.data ->> 'status' in ('active', 'paused')
      and exists (
        select 1
        from public.sync_entities target_run
        where target_run.user_id = p_target_user_id
          and target_run.app_id = 'pomodoist'
          and target_run.entity_type = 'focus_run'
          and target_run.deleted_at is null
          and target_run.data ->> 'status' in ('active', 'paused')
      )
  ) then
    raise exception using errcode = '23505', message = 'Telegram account merge conflict';
  end if;

  if exists (
    select 1
    from public.sync_entities guest_entity
    join public.sync_entities target_entity
      on target_entity.user_id = p_target_user_id
      and target_entity.app_id = guest_entity.app_id
      and target_entity.entity_type = guest_entity.entity_type
      and target_entity.entity_id = guest_entity.entity_id
    where guest_entity.user_id = v_account.guest_user_id
      and guest_entity.app_id = 'pomodoist'
      and guest_entity.entity_type = any(v_entity_types)
  ) then
    raise exception using errcode = '23505', message = 'Telegram account merge conflict';
  end if;

  update public.sync_entities
  set user_id = p_target_user_id,
      server_revision = pg_catalog.nextval('public.sync_revision_seq')
  where user_id = v_account.guest_user_id
    and app_id = 'pomodoist'
    and entity_type = any(v_entity_types);

  insert into public.sync_operation_receipts (
    user_id,
    op_id,
    server_revision,
    inserted_at
  )
  select p_target_user_id, op_id, server_revision, inserted_at
  from public.sync_operation_receipts
  where user_id = v_account.guest_user_id
  on conflict (user_id, op_id) do nothing;

  delete from public.sync_operation_receipts
  where user_id = v_account.guest_user_id;

  update public.pomodoist_telegram_accounts
  set user_id = p_target_user_id,
      linked_at = v_now,
      updated_at = v_now
  where telegram_user_id = v_account.telegram_user_id;

  update public.pomodoist_telegram_link_attempts
  set used_at = v_now
  where telegram_user_id = v_account.telegram_user_id
    and used_at is null;

  perform realtime.send(
    pg_catalog.jsonb_build_object(
      'appId', 'pomodoist',
      'deviceId', 'telegram:' || v_account.client_id::text,
      'sentAt', pg_catalog.to_char(
        pg_catalog.clock_timestamp() at time zone 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
      )
    ),
    'changed',
    'sync:' || p_target_user_id::text || ':pomodoist',
    true
  );

  return pg_catalog.jsonb_build_object(
    'linked', true,
    'telegramUserId', v_account.telegram_user_id::text,
    'userId', p_target_user_id::text,
    'guestUserId', v_account.guest_user_id::text
  );
end;
$$;


ALTER FUNCTION public.complete_pomodoist_telegram_link(p_token_hash bytea, p_target_user_id uuid) OWNER TO postgres;

--
-- Name: consume_pomodoist_mcp_rate_limit(uuid, uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.consume_pomodoist_mcp_rate_limit(p_user_id uuid, p_client_id uuid) RETURNS TABLE(allowed boolean, retry_after_seconds integer)
    LANGUAGE sql STRICT SECURITY DEFINER
    SET search_path TO ''
    AS $$
  with consumed as (
    insert into private.pomodoist_mcp_rate_limits (
      user_id,
      client_id,
      window_started_at,
      call_count
    )
    values (
      p_user_id,
      p_client_id,
      statement_timestamp(),
      1
    )
    on conflict (user_id, client_id) do update
    set
      window_started_at = case
        when private.pomodoist_mcp_rate_limits.window_started_at
          <= statement_timestamp() - interval '60 seconds'
        then statement_timestamp()
        else private.pomodoist_mcp_rate_limits.window_started_at
      end,
      call_count = case
        when private.pomodoist_mcp_rate_limits.window_started_at
          <= statement_timestamp() - interval '60 seconds'
        then 1
        else least(private.pomodoist_mcp_rate_limits.call_count + 1, 121)
      end
    returning call_count, window_started_at
  )
  select
    consumed.call_count <= 120,
    case
      when consumed.call_count <= 120 then null
      else greatest(
        1,
        ceil(extract(
          epoch from consumed.window_started_at
            + interval '60 seconds'
            - statement_timestamp()
        ))::integer
      )
    end
  from consumed;
$$;


ALTER FUNCTION public.consume_pomodoist_mcp_rate_limit(p_user_id uuid, p_client_id uuid) OWNER TO postgres;

--
-- Name: consume_quota(text, text, integer, timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.consume_quota(p_app_id text, p_quota_key text, p_units integer, p_period_start timestamp with time zone DEFAULT NULL::timestamp with time zone, p_period_end timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS jsonb
    LANGUAGE sql
    SET search_path TO ''
    AS $$
  SELECT private.consume_quota(p_app_id, p_quota_key, p_units, p_period_start, p_period_end);
$$;


ALTER FUNCTION public.consume_quota(p_app_id text, p_quota_key text, p_units integer, p_period_start timestamp with time zone, p_period_end timestamp with time zone) OWNER TO postgres;

--
-- Name: ensure_profile(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.ensure_profile() RETURNS uuid
    LANGUAGE sql
    SET search_path TO ''
    AS $$
  SELECT private.ensure_profile();
$$;


ALTER FUNCTION public.ensure_profile() OWNER TO postgres;

--
-- Name: get_account_overview(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_account_overview() RETURNS jsonb
    LANGUAGE sql
    SET search_path TO ''
    AS $$
  SELECT private.get_account_overview();
$$;


ALTER FUNCTION public.get_account_overview() OWNER TO postgres;

--
-- Name: get_apple_app_account_token(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_apple_app_account_token() RETURNS uuid
    LANGUAGE sql
    SET search_path TO ''
    AS $$
  SELECT private.get_apple_app_account_token();
$$;


ALTER FUNCTION public.get_apple_app_account_token() OWNER TO postgres;

--
-- Name: get_usage_period(text, text, timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_usage_period(p_app_id text, p_quota_key text, p_period_start timestamp with time zone DEFAULT NULL::timestamp with time zone, p_period_end timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS jsonb
    LANGUAGE sql
    SET search_path TO ''
    AS $$
  SELECT private.get_usage_period(p_app_id, p_quota_key, p_period_start, p_period_end);
$$;


ALTER FUNCTION public.get_usage_period(p_app_id text, p_quota_key text, p_period_start timestamp with time zone, p_period_end timestamp with time zone) OWNER TO postgres;

--
-- Name: handle_new_user(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.handle_new_user() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  insert into public.profiles (
    id,
    email,
    display_name,
    avatar_url,
    revenuecat_app_user_id
  )
  values (
    new.id,
    new.email,
    coalesce(
      new.raw_user_meta_data ->> 'full_name',
      new.raw_user_meta_data ->> 'name',
      split_part(coalesce(new.email, ''), '@', 1)
    ),
    new.raw_user_meta_data ->> 'avatar_url',
    new.id::text
  )
  on conflict (id) do update
  set email = excluded.email,
      display_name = coalesce(public.profiles.display_name, excluded.display_name),
      avatar_url = coalesce(public.profiles.avatar_url, excluded.avatar_url);

  perform private.initialize_additional_account(new.id);
  perform private.grant_pomodoist_selfhost_access(new.id);

  return new;
end;
$$;


ALTER FUNCTION public.handle_new_user() OWNER TO postgres;

--
-- Name: has_active_pomodoist_paid_entitlement(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.has_active_pomodoist_paid_entitlement(p_user_id uuid) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$
  select exists (
    select 1
    from public.user_entitlements e
    where e.user_id = p_user_id
      and e.app_id = 'pomodoist'
      and e.status = 'active'
      and e.purchase_type in ('subscription', 'lifetime')
      and (e.valid_until is null or e.valid_until > timezone('utc', now()))
  );
$$;


ALTER FUNCTION public.has_active_pomodoist_paid_entitlement(p_user_id uuid) OWNER TO postgres;

--
-- Name: link_pomodoist_stripe_customer(uuid, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.link_pomodoist_stripe_customer(p_user_id uuid, p_stripe_customer_id text) RETURNS text
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
declare
  v_customer_id text;
begin
  if p_user_id is null
      or p_stripe_customer_id is null
      or length(p_stripe_customer_id) not between 1 and 255
      or not exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'invalid_pomodoist_stripe_customer';
  end if;

  insert into private.pomodoist_stripe_customers (
    user_id,
    stripe_customer_id
  ) values (
    p_user_id,
    p_stripe_customer_id
  ) on conflict (user_id) do nothing;

  select stripe_customer_id
  into v_customer_id
  from private.pomodoist_stripe_customers
  where user_id = p_user_id;

  return v_customer_id;
exception
  when unique_violation then
    raise exception 'pomodoist_stripe_customer_already_linked';
end;
$$;


ALTER FUNCTION public.link_pomodoist_stripe_customer(p_user_id uuid, p_stripe_customer_id text) OWNER TO postgres;

--
-- Name: pomodoist_account_deletion_check(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.pomodoist_account_deletion_check(p_user_id uuid) RETURNS jsonb
    LANGUAGE sql
    SET search_path TO ''
    AS $$
  select private.pomodoist_account_deletion_check(p_user_id);
$$;


ALTER FUNCTION public.pomodoist_account_deletion_check(p_user_id uuid) OWNER TO postgres;

--
-- Name: pomodoist_collaboration(jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.pomodoist_collaboration(p_request jsonb) RETURNS jsonb
    LANGUAGE sql
    SET search_path TO ''
    AS $$ select private.pomodoist_collaboration(p_request); $$;


ALTER FUNCTION public.pomodoist_collaboration(p_request jsonb) OWNER TO postgres;

--
-- Name: pomodoist_collaboration_mcp(uuid, uuid, uuid, jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.pomodoist_collaboration_mcp(p_subject uuid, p_session_id uuid, p_client_id uuid, p_request jsonb) RETURNS jsonb
    LANGUAGE sql
    SET search_path TO ''
    AS $$
  select private.pomodoist_collaboration_mcp(p_subject,p_session_id,p_client_id,p_request);
$$;


ALTER FUNCTION public.pomodoist_collaboration_mcp(p_subject uuid, p_session_id uuid, p_client_id uuid, p_request jsonb) OWNER TO postgres;

--
-- Name: pomodoist_collaboration_storage_cleanup(text[]); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.pomodoist_collaboration_storage_cleanup(p_deleted text[] DEFAULT ARRAY[]::text[]) RETURNS jsonb
    LANGUAGE sql
    SET search_path TO ''
    AS $$ select private.pomodoist_collaboration_storage_cleanup(p_deleted); $$;


ALTER FUNCTION public.pomodoist_collaboration_storage_cleanup(p_deleted text[]) OWNER TO postgres;

--
-- Name: pomodoist_google_calendar_service(text, uuid, jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.pomodoist_google_calendar_service(p_action text, p_user_id uuid DEFAULT NULL::uuid, p_payload jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_now timestamptz := pg_catalog.timezone('utc', pg_catalog.now());
  v_result jsonb;
  v_claimed_generation bigint;
  v_generation bigint;
  v_job_claimed_generation bigint;
begin
  if p_action = 'claim' then
    v_result := private.pomodoist_google_calendar_service_unchecked(
      p_action, p_user_id, p_payload
    );
    select coalesce(
      pg_catalog.jsonb_agg(
        item.value || pg_catalog.jsonb_build_object(
          'claimedGeneration', job.claimed_generation
        ) order by item.ordinality
      ),
      '[]'::jsonb
    ) into v_result
    from pg_catalog.jsonb_array_elements(v_result) with ordinality as item(value, ordinality)
    join private.pomodoist_google_calendar_jobs job
      on job.user_id = (item.value ->> 'userId')::uuid;
    return v_result;
  end if;

  if p_action in ('complete', 'fail')
    and p_payload ? 'claimedGeneration'
  then
    if p_user_id is null then
      raise exception 'user_id_required';
    end if;
    v_claimed_generation := (p_payload ->> 'claimedGeneration')::bigint;
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        'pomodoist-google-calendar:' || p_user_id::text,
        0
      )
    );
    select generation, claimed_generation
      into v_generation, v_job_claimed_generation
    from private.pomodoist_google_calendar_jobs
    where user_id = p_user_id
    for update;

    if not found
      or v_claimed_generation is distinct from v_generation
      or v_claimed_generation is distinct from v_job_claimed_generation
    then
      update private.pomodoist_google_calendar_jobs
      set status = 'pending', due_at = v_now, lease_until = null,
          updated_at = v_now
      where user_id = p_user_id;
      if found then
        perform private.invoke_pomodoist_google_calendar_worker();
      end if;
      return pg_catalog.jsonb_build_object('stale', true);
    end if;
  end if;

  if p_action = 'fail' and p_payload ->> 'transientConflict' = 'true' then
    update private.pomodoist_google_calendar_jobs
    set status = 'pending', due_at = v_now, lease_until = null,
        last_error = null, updated_at = v_now
    where user_id = p_user_id;
    update private.pomodoist_google_calendar_accounts
    set status = 'connecting', last_error = null, updated_at = v_now
    where user_id = p_user_id;
    perform private.invoke_pomodoist_google_calendar_worker();
    return pg_catalog.jsonb_build_object('retrying', true);
  end if;

  return private.pomodoist_google_calendar_service_unchecked(
    p_action, p_user_id, p_payload
  );
end;
$$;


ALTER FUNCTION public.pomodoist_google_calendar_service(p_action text, p_user_id uuid, p_payload jsonb) OWNER TO postgres;

--
-- Name: pomodoist_llm_quota(uuid, text, uuid, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.pomodoist_llm_quota(p_user_id uuid, p_purchase_subject text, p_request_id uuid, p_action text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
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
$_$;


ALTER FUNCTION public.pomodoist_llm_quota(p_user_id uuid, p_purchase_subject text, p_request_id uuid, p_action text) OWNER TO postgres;

--
-- Name: pomodoist_openclaw_action(uuid, uuid, uuid, uuid, text, text, bigint, jsonb, jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.pomodoist_openclaw_action(p_subject uuid, p_session_id uuid, p_client_id uuid, p_request_id uuid, p_action text, p_arguments_hash text, p_expected_revision bigint DEFAULT NULL::bigint, p_operations jsonb DEFAULT NULL::jsonb, p_result jsonb DEFAULT NULL::jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
declare
  v_user_id uuid; v_revision bigint; v_receipt private.pomodoist_openclaw_receipts%rowtype;
  v_push jsonb; v_result jsonb; v_op jsonb;
begin
  if p_request_id is null or p_action is null or p_arguments_hash is null or p_arguments_hash !~ '^[a-f0-9]{64}$'
    or p_action not in ('create_task','update_task','complete_task','restore_task','delete_task',
      'create_project','update_project','delete_project','create_label','delete_label','set_task_details','focus') then
    raise exception using errcode = '22023', message = 'Invalid OpenClaw action';
  end if;
  v_user_id := public.resolve_pomodoist_mcp_session(p_subject, p_session_id, p_client_id);
  if v_user_id is null then raise exception using errcode = '42501', message = 'OpenClaw authorization revoked'; end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('pomodoist-google-calendar:' || v_user_id::text, 0));
  -- Resolve again after waiting; a revoked session must not replay a receipt.
  if public.resolve_pomodoist_mcp_session(p_subject, p_session_id, p_client_id) is distinct from v_user_id then
    raise exception using errcode = '42501', message = 'OpenClaw authorization revoked';
  end if;
  select * into v_receipt from private.pomodoist_openclaw_receipts
  where user_id = v_user_id and client_id = p_client_id and request_id = p_request_id;
  if found then
    if v_receipt.action <> p_action or v_receipt.arguments_hash <> p_arguments_hash then
      raise exception using errcode = '22023', message = 'OpenClaw request_id was reused';
    end if;
    if p_operations is null then return pg_catalog.jsonb_build_object('result', v_receipt.result); end if;
    return v_receipt.result;
  end if;
  select coalesce(pg_catalog.max(server_revision), 0) into v_revision
  from public.sync_entities where user_id = v_user_id and app_id = 'pomodoist';
  if p_operations is null then return pg_catalog.jsonb_build_object('revision', v_revision::text); end if;
  if p_expected_revision is distinct from v_revision then
    raise exception using errcode = '40001', message = 'OpenClaw snapshot changed';
  end if;
  if pg_catalog.jsonb_typeof(p_operations) is distinct from 'array'
    or pg_catalog.jsonb_array_length(p_operations) not between 1 and 1000
    or pg_catalog.jsonb_typeof(p_result) is distinct from 'object'
    or pg_catalog.pg_column_size(p_result) > 65536 then
    raise exception using errcode = '22023', message = 'Invalid OpenClaw action batch';
  end if;
  if p_action = 'focus' then
    if pg_catalog.jsonb_array_length(p_operations) > 50 then
      raise exception using errcode = '22023', message = 'Invalid OpenClaw Focus batch';
    end if;
    for v_op in select value from pg_catalog.jsonb_array_elements(p_operations) loop
      if pg_catalog.jsonb_typeof(v_op) is distinct from 'object'
        or coalesce(v_op ->> 'opId', '') = ''
        or coalesce(v_op ->> 'entityId', '') !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,199}$'
        or coalesce(v_op ->> 'entityType', '') not in ('task','focus_run','focus_interval','focus_event')
        or v_op ->> 'operation' is distinct from 'upsert'
        or pg_catalog.jsonb_typeof(v_op -> 'payload') is distinct from 'object'
        or (v_op -> 'payload' ? 'userId' and v_op #>> '{payload,userId}' is distinct from 'local-user')
        or (v_op ->> 'entityType' = 'task' and v_op #>> '{payload,commandType}' is distinct from 'task.focus.complete')
        or coalesce(v_op ->> 'clientUpdatedAt', '') = '' then
        raise exception using errcode = '22023', message = 'Invalid OpenClaw Focus operation';
      end if;
    end loop;
    -- Existing shared trigger enforces one active/paused Focus run per account.
    v_push := private.push_changes_for_user(v_user_id, 'pomodoist', 'mcp:' || p_client_id::text, p_operations);
  else
    v_push := public.push_pomodoist_mcp_changes(v_user_id, p_client_id, p_operations);
  end if;
  v_result := p_result || pg_catalog.jsonb_build_object('server_revision', v_push ->> 'serverRevision');
  insert into private.pomodoist_openclaw_receipts (user_id, client_id, request_id, action, arguments_hash, result)
  values (v_user_id, p_client_id, p_request_id, p_action, p_arguments_hash, v_result);
  return v_result;
end;
$_$;


ALTER FUNCTION public.pomodoist_openclaw_action(p_subject uuid, p_session_id uuid, p_client_id uuid, p_request_id uuid, p_action text, p_arguments_hash text, p_expected_revision bigint, p_operations jsonb, p_result jsonb) OWNER TO postgres;

--
-- Name: pomodoist_stripe_checkout_context(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.pomodoist_stripe_checkout_context(p_user_id uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $$
declare
  v_result jsonb;
begin
  select jsonb_build_object(
    'profileCreatedAt', profile.created_at,
    'stripeCustomerId', customer.stripe_customer_id,
    'firstSubscriptionPaidAt', customer.first_subscription_paid_at,
    'hasActiveEntitlement', public.has_active_pomodoist_paid_entitlement(p_user_id),
    'hasLifetimePurchase', exists (
      select 1
      from private.pomodoist_stripe_claims claim
      where claim.user_id = p_user_id
        and claim.purchase_type = 'lifetime'
    )
  )
  into v_result
  from public.profiles profile
  left join private.pomodoist_stripe_customers customer
    on customer.user_id = profile.id
  where profile.id = p_user_id;

  if v_result is null then
    raise exception 'pomodoist_profile_not_found';
  end if;
  return v_result;
end;
$$;


ALTER FUNCTION public.pomodoist_stripe_checkout_context(p_user_id uuid) OWNER TO postgres;

--
-- Name: pomodoist_subscription_offer_state(text, text, text, text[], uuid, boolean, text, uuid, bigint, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.pomodoist_subscription_offer_state(p_environment text, p_app_transaction_id text, p_campaign_id text, p_original_transaction_ids text[], p_user_id uuid, p_redeemed boolean, p_product_id text, p_nonce uuid, p_timestamp bigint, p_signature_max_age_seconds integer) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $_$
declare
  v_row private.pomodoist_subscription_offers%rowtype;
  v_now timestamptz := clock_timestamp();
begin
  if p_environment is null or p_environment not in ('Production', 'Sandbox')
    or p_app_transaction_id is null or p_app_transaction_id !~ '^[0-9]{1,128}$'
    or p_campaign_id is distinct from 'return-2026-v1'
    or coalesce(cardinality(p_original_transaction_ids), 0) not between 1 and 2000
    or p_redeemed is null
    or p_signature_max_age_seconds is null or p_signature_max_age_seconds not between 1 and 604800
    or (p_product_id is not null and (
      p_product_id not in ('pomodoist.pro.monthly', 'pomodoist.pro.annual')
      or p_nonce is null or p_timestamp is null
      or abs(extract(epoch from v_now) * 1000 - p_timestamp) > 60000
    )) then raise exception 'invalid_offer_state'; end if;

  insert into private.pomodoist_subscription_offers(environment, app_transaction_id, campaign_id)
  values (p_environment, p_app_transaction_id, p_campaign_id) on conflict do nothing;
  select * into v_row from private.pomodoist_subscription_offers
    where environment = p_environment and app_transaction_id = p_app_transaction_id
      and campaign_id = p_campaign_id for update;

  -- Redemption evidence is monotonic, including subsequent refunds/revocations.
  if p_redeemed then
    update private.pomodoist_subscription_offers set redeemed = true
      where environment = p_environment and app_transaction_id = p_app_transaction_id and campaign_id = p_campaign_id;
    v_row.redeemed := true;
  end if;
  if v_row.redeemed then return jsonb_build_object('code', 'already_redeemed'); end if;

  if p_user_id is not null and exists (
    select 1 from public.pomodoist_purchase_claims c where c.environment = p_environment
      and c.original_transaction_id = any(p_original_transaction_ids)
      and c.linked_user_id is not null and c.linked_user_id <> p_user_id
  ) then return jsonb_build_object('code', 'purchase_already_linked'); end if;

  -- Optional account auth can only restrict eligibility. Also exclude a linked
  -- account's current Stripe/lifetime entitlement for an accountless proof.
  if (p_user_id is not null and public.has_active_pomodoist_paid_entitlement(p_user_id))
    or exists (
      select 1 from public.pomodoist_purchase_claims c
      where c.environment = p_environment and c.original_transaction_id = any(p_original_transaction_ids)
        and c.linked_user_id is not null
        and public.has_active_pomodoist_paid_entitlement(c.linked_user_id)
    ) then return jsonb_build_object('code', 'not_eligible'); end if;

  if v_row.lease_until > v_now then
    return jsonb_build_object('code', 'offer_pending', 'retryAfter', to_char(v_row.lease_until at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'));
  end if;
  if p_product_id is not null then
    -- The operator must configure an Apple-confirmed V2 maximum lifetime.
    -- No cancellation unlock; add five minutes for clock skew/propagation.
    update private.pomodoist_subscription_offers
    set lease_until = to_timestamp(p_timestamp / 1000.0) + make_interval(secs => p_signature_max_age_seconds + 300),
        nonce = p_nonce, product_id = p_product_id
    where environment = p_environment and app_transaction_id = p_app_transaction_id and campaign_id = p_campaign_id;
  end if;
  return jsonb_build_object('code', 'eligible');
end;
$_$;


ALTER FUNCTION public.pomodoist_subscription_offer_state(p_environment text, p_app_transaction_id text, p_campaign_id text, p_original_transaction_ids text[], p_user_id uuid, p_redeemed boolean, p_product_id text, p_nonce uuid, p_timestamp bigint, p_signature_max_age_seconds integer) OWNER TO postgres;

--
-- Name: pomodoist_voice_quota(uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.pomodoist_voice_quota(p_user_id uuid, p_request_id uuid, p_action text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_period public.usage_periods%rowtype;
  v_request private.pomodoist_voice_requests%rowtype;
  v_start timestamptz := pg_catalog.date_trunc('month', now(), 'UTC');
  v_end timestamptz := (v_start at time zone 'UTC' + interval '1 month') at time zone 'UTC';
  v_limit integer;
  v_unit text;
  v_pending integer;
begin
  if p_user_id is null or p_request_id is null or p_action is null
     or p_action not in ('reserve', 'complete', 'release') then
    raise exception using errcode = '22023', message = 'Invalid voice quota request';
  end if;

  select u.* into v_period
  from public.usage_periods u
  join private.pomodoist_voice_requests r on r.usage_period_id = u.id
  where r.request_id = p_request_id and u.user_id = p_user_id
  for update of u;

  if not found then
    if p_action = 'release' then return jsonb_build_object('allowed', true); end if;
    if p_action = 'complete' then
      raise exception using errcode = '22023', message = 'Voice reservation expired or missing';
    end if;
    select limit_value, unit into v_limit, v_unit from public.quota_definitions
    where app_id = 'pomodoist' and quota_key = 'voice_transcriptions' and period = 'monthly';
    if not found then raise exception 'Voice quota is not configured'; end if;
    insert into public.usage_periods (user_id, app_id, quota_key, period_start, period_end, used, limit_value, unit)
    values (p_user_id, 'pomodoist', 'voice_transcriptions', v_start, v_end, 0, v_limit, v_unit)
    on conflict (user_id, app_id, quota_key, period_start) do update
    set limit_value = excluded.limit_value, period_end = excluded.period_end, unit = excluded.unit
    returning * into v_period;
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
      raise exception using errcode = '22023', message = 'Voice reservation expired or missing';
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


ALTER FUNCTION public.pomodoist_voice_quota(p_user_id uuid, p_request_id uuid, p_action text) OWNER TO postgres;

--
-- Name: prune_pomodoist_free_task_history(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.prune_pomodoist_free_task_history() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare r record; scope_rec record; deleted integer:=0; n integer; begin
  for r in select id from auth.users loop perform private.pomodoist_history_refresh(null,r.id); end loop;
  delete from public.sync_entities e using private.pomodoist_personal_history h
    where e.user_id=h.user_id and e.app_id='pomodoist' and e.entity_type='task' and not h.history_unlimited
      and not exists(select 1 from private.pomodoist_transferred_entities transferred where transferred.user_id=e.user_id
        and transferred.entity_type=e.entity_type and transferred.entity_id=e.entity_id)
      and (h.grace_ends_at is null or h.grace_ends_at<=now())
      and ((e.deleted_at is not null and e.deleted_at<now()-interval '365 days') or (e.data->>'status'='completed'
        and private.pomodoist_history_timestamp(e.data->>'completedAt',e.updated_at)<now()-interval '365 days'));
  get diagnostics deleted=row_count;
  for scope_rec in select id from private.pomodoist_scopes for update loop
    perform private.pomodoist_history_refresh(scope_rec.id);
    -- Retain tombstone identities and revisions permanently; remove aged content only.
    -- This permits every stale client to purge cached history without resurrection.
    for r in select e.* from private.pomodoist_shared_entities e join private.pomodoist_scopes s on s.id=e.scope_id
      where e.scope_id=scope_rec.id and e.entity_type='task' and e.data<>'{}'::jsonb and not s.history_unlimited
      and (s.grace_ends_at is null or s.grace_ends_at<=now())
      and ((e.deleted_at is not null and e.deleted_at<now()-interval '365 days') or (e.data->>'status'='completed'
        and private.pomodoist_history_timestamp(e.data->>'completedAt',e.updated_at)<now()-interval '365 days')) loop
      -- Earlier purges in this pass may already have promoted this task.
      select current_task.* into r from private.pomodoist_shared_entities current_task
        where current_task.scope_id=r.scope_id and current_task.entity_type='task' and current_task.entity_id=r.entity_id;
      declare surviving_child record; promoted_parent text; begin
        select parent.entity_id into promoted_parent from private.pomodoist_shared_entities parent
          where parent.scope_id=r.scope_id and parent.entity_type='task' and parent.entity_id=r.data->>'parentId'
            and parent.deleted_at is null and parent.data->>'projectId'=r.data->>'projectId';
        for surviving_child in select * from private.pomodoist_shared_entities where scope_id=r.scope_id and entity_type='task'
          and data->>'parentId'=r.entity_id and deleted_at is null loop
          perform private.pomodoist_shared_put(r.scope_id,'task',surviving_child.entity_id,
            surviving_child.data||jsonb_build_object('parentId',promoted_parent));
        end loop;
      end;
      delete from private.pomodoist_shared_receipts where scope_id=r.scope_id and request->>'entityId'=r.entity_id;
      perform private.pomodoist_shared_put(r.scope_id,'task',r.entity_id,'{}',coalesce(r.deleted_at,now()));
      deleted:=deleted+1;
      -- Task-associated records receive tombstones through the same revision sequence.
      declare child record; begin
        for child in select * from private.pomodoist_shared_entities where scope_id=r.scope_id and data->>'taskId'=r.entity_id loop
          delete from private.pomodoist_shared_receipts where scope_id=r.scope_id and request->>'entityType'=child.entity_type and request->>'entityId'=child.entity_id;
          perform private.pomodoist_shared_put(r.scope_id,child.entity_type,child.entity_id,'{}',now());
        end loop;
      end;
      declare f record; begin
        for f in select * from private.pomodoist_uploads where scope_id=r.scope_id and task_id=r.entity_id and deleted_at is null loop
          if f.finished_at is not null then update private.pomodoist_upload_years set bytes=bytes-f.bytes
            where user_id=f.user_id and year=extract(year from f.finished_at at time zone 'UTC')::integer; end if;
          update private.pomodoist_uploads set deleted_at=now() where id=f.id;
          insert into private.pomodoist_storage_deletions(object_path) values(f.object_path) on conflict do nothing;
        end loop;
      end;
      perform private.pomodoist_collaboration_hint(r.scope_id);
    end loop;
  end loop;
  insert into private.pomodoist_storage_deletions(object_path) select object_path from private.pomodoist_uploads
    where finished_at is null and expires_at<=now() on conflict do nothing;
  return deleted;
end $$;


ALTER FUNCTION public.prune_pomodoist_free_task_history() OWNER TO postgres;

--
-- Name: prune_pomodoist_sync_receipts(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.prune_pomodoist_sync_receipts() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_batch integer;
  v_deleted integer := 0;
begin
  for v_batch_number in 1..20 loop
    with candidates as (
      select r.ctid
      from public.sync_operation_receipts r
      where r.inserted_at < timezone('utc', now()) - interval '48 hours'
      order by r.inserted_at
      limit 5000
      for update skip locked
    ),
    deleted as (
      delete from public.sync_operation_receipts r
      using candidates c
      where r.ctid = c.ctid
      returning 1
    )
    select count(*)::integer into v_batch from deleted;

    v_deleted := v_deleted + v_batch;
    exit when v_batch = 0;
  end loop;

  return v_deleted;
end;
$$;


ALTER FUNCTION public.prune_pomodoist_sync_receipts() OWNER TO postgres;

--
-- Name: pull_changes(text, text, bigint, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.pull_changes(p_app_id text, p_device_id text, p_since_revision bigint DEFAULT 0, p_limit integer DEFAULT 500) RETURNS jsonb
    LANGUAGE sql
    SET search_path TO ''
    AS $$
  SELECT private.pull_changes(p_app_id, p_device_id, p_since_revision, p_limit);
$$;


ALTER FUNCTION public.pull_changes(p_app_id text, p_device_id text, p_since_revision bigint, p_limit integer) OWNER TO postgres;

--
-- Name: push_changes(text, text, jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.push_changes(p_app_id text, p_device_id text, p_operations jsonb) RETURNS jsonb
    LANGUAGE sql
    SET search_path TO ''
    AS $$
  SELECT private.push_changes(p_app_id, p_device_id, p_operations);
$$;


ALTER FUNCTION public.push_changes(p_app_id text, p_device_id text, p_operations jsonb) OWNER TO postgres;

--
-- Name: push_pomodoist_draft_changes(text, text, jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.push_pomodoist_draft_changes(p_device_id text, p_command_id text, p_operations jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_user_id uuid := auth.uid();
  v_revision bigint;
  v_first jsonb;
  v_rest jsonb;
begin
  if v_user_id is null then raise exception 'Authentication required'; end if;
  if p_command_id is null or pg_catalog.btrim(p_command_id) = ''
    or pg_catalog.jsonb_typeof(p_operations) is distinct from 'array'
    or pg_catalog.jsonb_array_length(p_operations) = 0
    or (p_operations -> 0 ->> 'opId') is distinct from p_command_id
  then raise exception using errcode = '22023', message = 'Invalid draft batch'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_user_id::text || ':' || p_command_id, 0));
  select server_revision into v_revision from public.sync_operation_receipts
    where user_id = v_user_id and op_id = p_command_id;
  if found then
    return pg_catalog.jsonb_build_object('serverRevision', v_revision, 'applied', '[]'::jsonb);
  end if;
  if exists (select 1 from pg_catalog.jsonb_array_elements(p_operations) op
    group by op ->> 'opId' having count(*) > 1)
  then raise exception using errcode = '22023', message = 'Duplicate draft operation IDs'; end if;
  -- The unique receipt arbitrates even an in-flight older server that does not
  -- take the advisory lock. Never apply remaining drafts if its first op won.
  v_first := private.push_changes_for_user(v_user_id, 'pomodoist', p_device_id,
    pg_catalog.jsonb_build_array(p_operations -> 0));
  if pg_catalog.jsonb_array_length(v_first -> 'applied') = 0 then return v_first; end if;
  v_rest := private.push_changes_for_user(v_user_id, 'pomodoist', p_device_id, p_operations - 0);
  return pg_catalog.jsonb_build_object('serverRevision', v_rest -> 'serverRevision',
    'applied', (v_first -> 'applied') || (v_rest -> 'applied'));
end;
$$;


ALTER FUNCTION public.push_pomodoist_draft_changes(p_device_id text, p_command_id text, p_operations jsonb) OWNER TO postgres;

--
-- Name: push_pomodoist_mcp_changes(uuid, uuid, jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.push_pomodoist_mcp_changes(p_user_id uuid, p_client_id uuid, p_operations jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_op jsonb;
  v_op_id text;
  v_entity_type text;
  v_entity_id text;
  v_operation text;
  v_payload jsonb;
  v_client_updated_at text;
  v_system_operations jsonb := '[]'::jsonb;
begin
  if p_user_id is null
    or p_client_id is null
    or pg_catalog.jsonb_typeof(p_operations) is distinct from 'array'
  then
    raise exception using
      errcode = '22023',
      message = 'Invalid Pomodoist MCP sync batch';
  end if;

  if pg_catalog.jsonb_array_length(p_operations) = 0 then
    raise exception using
      errcode = '22023',
      message = 'Invalid Pomodoist MCP sync batch';
  end if;

  for v_op in
    select value from pg_catalog.jsonb_array_elements(p_operations)
  loop
    if pg_catalog.jsonb_typeof(v_op) is distinct from 'object' then
      raise exception using
        errcode = '22023',
        message = 'Invalid Pomodoist MCP sync operation';
    end if;

    v_op_id := coalesce(v_op ->> 'opId', v_op ->> 'op_id');
    v_entity_type := coalesce(
      v_op ->> 'entityType',
      v_op ->> 'entity_type'
    );
    v_entity_id := coalesce(
      v_op ->> 'entityId',
      v_op ->> 'entity_id'
    );
    v_operation := v_op ->> 'operation';
    v_payload := v_op -> 'payload';
    v_client_updated_at := coalesce(
      v_op ->> 'clientUpdatedAt',
      v_op ->> 'client_updated_at'
    );

    if pg_catalog.btrim(coalesce(v_op_id, '')) = ''
      or pg_catalog.btrim(coalesce(v_entity_id, '')) = ''
      or pg_catalog.jsonb_typeof(
        coalesce(v_op -> 'opId', v_op -> 'op_id')
      ) is distinct from 'string'
      or pg_catalog.jsonb_typeof(
        coalesce(v_op -> 'entityType', v_op -> 'entity_type')
      ) is distinct from 'string'
      or pg_catalog.jsonb_typeof(
        coalesce(v_op -> 'entityId', v_op -> 'entity_id')
      ) is distinct from 'string'
      or pg_catalog.jsonb_typeof(v_op -> 'operation')
        is distinct from 'string'
      or pg_catalog.jsonb_typeof(
        coalesce(
          v_op -> 'clientUpdatedAt',
          v_op -> 'client_updated_at'
        )
      ) is distinct from 'string'
      or v_entity_type not in (
        'project',
        'task',
        'task_completion',
        'label',
        'task_label',
        'task_kanban_status',
        'kanban_settings'
      )
      or v_operation not in ('upsert', 'delete')
      or pg_catalog.jsonb_typeof(v_payload) is distinct from 'object'
      or pg_catalog.btrim(coalesce(v_client_updated_at, '')) = ''
      or (
        v_payload ? 'userId'
        and (v_payload ->> 'userId') is distinct from 'local-user'
      )
      or v_op_id like 'pomodoist-mcp-system:%'
      or (
        v_entity_id = 'inbox'
        and v_entity_type <> 'project'
      )
      or (
        v_entity_id in (
          'kanban-status-backlog-v1',
          'kanban-status-done-v1'
        )
        and v_entity_type <> 'label'
      )
      or (
        v_entity_id = 'kanban-settings-primary-v1'
        and v_entity_type <> 'kanban_settings'
      )
      or (
        v_entity_type = 'kanban_settings'
        and v_entity_id <> 'kanban-settings-primary-v1'
      )
    then
      raise exception using
        errcode = '22023',
        message = 'Invalid Pomodoist MCP sync operation';
    end if;

    begin
      perform v_client_updated_at::timestamptz;
    exception
      when invalid_datetime_format or datetime_field_overflow then
        raise exception using
          errcode = '22023',
          message = 'Invalid Pomodoist MCP sync operation';
    end;
  end loop;

  if (
    select pg_catalog.count(*) <> pg_catalog.count(distinct operation.op_id)
    from (
      select coalesce(
        value ->> 'opId',
        value ->> 'op_id'
      ) as op_id
      from pg_catalog.jsonb_array_elements(p_operations)
    ) as operation
  ) then
    raise exception using
      errcode = '22023',
      message = 'Invalid Pomodoist MCP sync operation';
  end if;

  -- ponytail: concurrent first calls can add redundant anchor receipts; add
  -- a per-user advisory lock only if that write amplification becomes noisy.
  if not exists (
    select 1
    from public.sync_entities
    where user_id = p_user_id
      and app_id = 'pomodoist'
      and entity_type = 'project'
      and entity_id = 'inbox'
      and deleted_at is null
  ) then
    v_system_operations := v_system_operations
      || pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object(
          'opId', 'pomodoist-mcp-system:project:inbox:v1:'
            || pg_catalog.gen_random_uuid()::text,
          'entityType', 'project',
          'entityId', 'inbox',
          'operation', 'upsert',
          'payload', pg_catalog.jsonb_build_object(
            'schemaVersion', 1,
            'id', 'inbox',
            'userId', 'local-user',
            'name', 'Inbox',
            'color', null,
            'parentId', null,
            'viewStyle', 'list',
            'isFavorite', true,
            'isArchived', false,
            'isDeleted', false,
            'orderKey', 'a',
            'createdAt', '2000-01-01T00:00:00.000Z',
            'updatedAt', '2000-01-01T00:00:00.000Z'
          ),
          'clientUpdatedAt', '2000-01-01T00:00:00.000Z'
        )
      );
  end if;

  if not exists (
    select 1
    from public.sync_entities
    where user_id = p_user_id
      and app_id = 'pomodoist'
      and entity_type = 'label'
      and entity_id = 'kanban-status-backlog-v1'
      and deleted_at is null
  ) then
    v_system_operations := v_system_operations
      || pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object(
          'opId', 'pomodoist-mcp-system:label:backlog:v1:'
            || pg_catalog.gen_random_uuid()::text,
          'entityType', 'label',
          'entityId', 'kanban-status-backlog-v1',
          'operation', 'upsert',
          'payload', pg_catalog.jsonb_build_object(
            'schemaVersion', 1,
            'id', 'kanban-status-backlog-v1',
            'userId', 'local-user',
            'name', 'Backlog',
            'color', null,
            'kind', 'kanbanStatus',
            'systemKey', 'backlog',
            'orderKey', '00000000000000000000',
            'isFavorite', false,
            'isDeleted', false,
            'createdAt', '2000-01-01T00:00:00.000Z',
            'updatedAt', '2000-01-01T00:00:00.000Z'
          ),
          'clientUpdatedAt', '2000-01-01T00:00:00.000Z'
        )
      );
  end if;

  if not exists (
    select 1
    from public.sync_entities
    where user_id = p_user_id
      and app_id = 'pomodoist'
      and entity_type = 'label'
      and entity_id = 'kanban-status-done-v1'
      and deleted_at is null
  ) then
    v_system_operations := v_system_operations
      || pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object(
          'opId', 'pomodoist-mcp-system:label:done:v1:'
            || pg_catalog.gen_random_uuid()::text,
          'entityType', 'label',
          'entityId', 'kanban-status-done-v1',
          'operation', 'upsert',
          'payload', pg_catalog.jsonb_build_object(
            'schemaVersion', 1,
            'id', 'kanban-status-done-v1',
            'userId', 'local-user',
            'name', 'Done',
            'color', null,
            'kind', 'kanbanStatus',
            'systemKey', 'done',
            'orderKey', '00004503599627370496',
            'isFavorite', false,
            'isDeleted', false,
            'createdAt', '2000-01-01T00:00:00.000Z',
            'updatedAt', '2000-01-01T00:00:00.000Z'
          ),
          'clientUpdatedAt', '2000-01-01T00:00:00.000Z'
        )
      );
  end if;

  if not exists (
    select 1
    from public.sync_entities
    where user_id = p_user_id
      and app_id = 'pomodoist'
      and entity_type = 'kanban_settings'
      and entity_id = 'kanban-settings-primary-v1'
      and deleted_at is null
  ) then
    v_system_operations := v_system_operations
      || pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object(
          'opId', 'pomodoist-mcp-system:kanban-settings:v1:'
            || pg_catalog.gen_random_uuid()::text,
          'entityType', 'kanban_settings',
          'entityId', 'kanban-settings-primary-v1',
          'operation', 'upsert',
          'payload', pg_catalog.jsonb_build_object(
            'schemaVersion', 1,
            'id', 'kanban-settings-primary-v1',
            'userId', 'local-user',
            'selectedProjectIdsJson', '["inbox"]',
            'focusStatusLabelId', 'kanban-status-backlog-v1',
            'createdAt', '2000-01-01T00:00:00.000Z',
            'updatedAt', '2000-01-01T00:00:00.000Z'
          ),
          'clientUpdatedAt', '2000-01-01T00:00:00.000Z'
        )
      );
  end if;

  return private.push_changes_for_user(
    p_user_id,
    'pomodoist',
    'mcp:' || p_client_id::text,
    v_system_operations || p_operations
  );
end;
$$;


ALTER FUNCTION public.push_pomodoist_mcp_changes(p_user_id uuid, p_client_id uuid, p_operations jsonb) OWNER TO postgres;

--
-- Name: push_pomodoist_telegram_changes(bigint, uuid, uuid, jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.push_pomodoist_telegram_changes(p_telegram_user_id bigint, p_expected_user_id uuid, p_client_id uuid, p_operations jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_op jsonb;
  v_entity_type text;
  v_entity_id text;
  v_focus_run_id text;
  v_account public.pomodoist_telegram_accounts%rowtype;
begin
  if p_telegram_user_id is null
    or p_telegram_user_id <= 0
    or p_expected_user_id is null
    or p_client_id is null
    or pg_catalog.jsonb_typeof(p_operations) is distinct from 'array'
    or pg_catalog.jsonb_array_length(p_operations) not between 1 and 50
  then
    raise exception using errcode = '22023', message = 'Invalid Telegram sync batch';
  end if;

  select * into v_account
  from public.pomodoist_telegram_accounts
  where telegram_user_id = p_telegram_user_id
  for update;
  if not found
    or v_account.user_id is distinct from p_expected_user_id
    or v_account.client_id is distinct from p_client_id
  then
    raise exception using errcode = '40001', message = 'Telegram mapping changed';
  end if;

  for v_op in select value from pg_catalog.jsonb_array_elements(p_operations)
  loop
    v_entity_type := coalesce(v_op ->> 'entityType', v_op ->> 'entity_type');
    v_entity_id := coalesce(v_op ->> 'entityId', v_op ->> 'entity_id');
    if pg_catalog.jsonb_typeof(v_op) is distinct from 'object'
      or pg_catalog.btrim(coalesce(v_op ->> 'opId', v_op ->> 'op_id', '')) = ''
      or pg_catalog.btrim(coalesce(v_op ->> 'entityId', v_op ->> 'entity_id', '')) = ''
      or v_entity_type not in (
        'task',
        'task_completion',
        'focus_run',
        'focus_interval',
        'focus_event'
      )
      or v_op ->> 'operation' not in ('upsert', 'delete')
      or pg_catalog.jsonb_typeof(v_op -> 'payload') is distinct from 'object'
      or (
        v_op -> 'payload' ? 'userId'
        and v_op #>> '{payload,userId}' is distinct from 'local-user'
      )
      or coalesce(v_op ->> 'clientUpdatedAt', v_op ->> 'client_updated_at') is null
    then
      raise exception using errcode = '22023', message = 'Invalid Telegram sync operation';
    end if;

    if v_entity_type = 'focus_run'
      and v_op ->> 'operation' = 'upsert'
      and v_op #>> '{payload,status}' in ('active', 'paused')
    then
      if v_focus_run_id is not null and v_focus_run_id is distinct from v_entity_id then
        raise exception using errcode = '22023', message = 'Invalid Telegram sync operation';
      end if;
      v_focus_run_id := v_entity_id;
    end if;
  end loop;

  if v_focus_run_id is not null and exists (
    select 1
    from public.sync_entities
    where user_id = v_account.user_id
      and app_id = 'pomodoist'
      and entity_type = 'focus_run'
      and entity_id is distinct from v_focus_run_id
      and deleted_at is null
      and data ->> 'status' in ('active', 'paused')
  ) then
    raise exception using errcode = '23505', message = 'Telegram Focus already active';
  end if;

  return private.push_changes_for_user(
    v_account.user_id,
    'pomodoist',
    'telegram:' || p_client_id::text,
    p_operations
  );
end;
$$;


ALTER FUNCTION public.push_pomodoist_telegram_changes(p_telegram_user_id bigint, p_expected_user_id uuid, p_client_id uuid, p_operations jsonb) OWNER TO postgres;

--
-- Name: read_pomodoist_companion_state(bigint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.read_pomodoist_companion_state(p_since_revision bigint DEFAULT 0) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_user_id uuid := auth.uid();
  v_result jsonb;
begin
  if v_user_id is null then raise exception 'Authentication required'; end if;
  with active_runs as (
    select entity_id from public.sync_entities
    where user_id = v_user_id and app_id = 'pomodoist' and entity_type = 'focus_run'
      and deleted_at is null and data ->> 'isDeleted' is distinct from 'true'
      and data ->> 'endedAt' is null and data ->> 'status' in ('active','paused')
  ), page as (
    select entity_type, entity_id, server_revision, deleted_at, data
    from public.sync_entities e
    where e.user_id = v_user_id and e.app_id = 'pomodoist' and e.deleted_at is null
      and e.server_revision > coalesce(p_since_revision, 0)
      and (e.entity_type in ('task','project','label','focus_preset')
        or (e.entity_type = 'focus_run' and e.entity_id in (select entity_id from active_runs))
        or (e.entity_type = 'focus_interval' and e.data ->> 'runId' in (select entity_id from active_runs)))
    order by server_revision limit 1001
  ), limited as (select * from page order by server_revision limit 1000)
  select pg_catalog.jsonb_build_object(
    'changes', coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'entityType', entity_type, 'entityId', entity_id, 'serverRevision', server_revision,
      'deletedAt', deleted_at, 'data', data) order by server_revision), '[]'::jsonb),
    'nextCursor', coalesce(max(server_revision), p_since_revision, 0),
    'hasMore', (select count(*) > 1000 from page)) into v_result from limited;
  return v_result;
end;
$$;


ALTER FUNCTION public.read_pomodoist_companion_state(p_since_revision bigint) OWNER TO postgres;

--
-- Name: read_pomodoist_mcp(uuid, text, jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.read_pomodoist_mcp(p_user_id uuid, p_operation text, p_arguments jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if p_operation = 'mutation_snapshot' then
    if p_user_id is null or p_arguments <> '{}'::jsonb then
      raise exception using
        errcode = '22023',
        message = 'Invalid Pomodoist MCP read request';
    end if;
    return private.pomodoist_mcp_mutation_snapshot(p_user_id);
  end if;
  return private.read_pomodoist_mcp_v1(
    p_user_id,
    p_operation,
    p_arguments
  );
end;
$$;


ALTER FUNCTION public.read_pomodoist_mcp(p_user_id uuid, p_operation text, p_arguments jsonb) OWNER TO postgres;

--
-- Name: read_pomodoist_openclaw_state(uuid, uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.read_pomodoist_openclaw_state(p_subject uuid, p_session_id uuid, p_client_id uuid, p_task_id text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
declare v_user_id uuid; v_entities jsonb;
begin
  v_user_id := public.resolve_pomodoist_mcp_session(p_subject, p_session_id, p_client_id);
  if v_user_id is null then raise exception using errcode = '42501', message = 'OpenClaw authorization revoked'; end if;
  if p_task_id is not null and p_task_id !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,199}$' then
    raise exception using errcode = '22023', message = 'Invalid OpenClaw task';
  end if;
  with active_runs as (
    select entity_id, data ->> 'taskId' as task_id from public.sync_entities
    where user_id = v_user_id and app_id = 'pomodoist' and entity_type = 'focus_run'
      and deleted_at is null and data ->> 'status' in ('active','paused') and data ->> 'endedAt' is null
  ), selected as (
    select entity_type, entity_id, server_revision, deleted_at, data from public.sync_entities
    where user_id = v_user_id and app_id = 'pomodoist' and deleted_at is null and (
      entity_type = 'focus_preset'
      or (entity_type = 'focus_run' and entity_id in (select entity_id from active_runs))
      or (entity_type = 'focus_interval' and data ->> 'runId' in (select entity_id from active_runs)
        and data ->> 'status' in ('running','paused','ready'))
      or (entity_type = 'task' and (entity_id = p_task_id or entity_id in (select task_id from active_runs)))
    ) order by server_revision limit 1001
  ) select coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(selected)), '[]'::jsonb) into v_entities from selected;
  if pg_catalog.jsonb_array_length(v_entities) > 1000 then
    raise exception using errcode = '22023', message = 'OpenClaw Focus snapshot too large';
  end if;
  return pg_catalog.jsonb_build_object('entities', v_entities, 'serverNow', pg_catalog.clock_timestamp());
end;
$_$;


ALTER FUNCTION public.read_pomodoist_openclaw_state(p_subject uuid, p_session_id uuid, p_client_id uuid, p_task_id text) OWNER TO postgres;

--
-- Name: record_pomodoist_purchase(text, text, text, text, text, timestamp with time zone, timestamp with time zone, timestamp with time zone, uuid, timestamp with time zone, jsonb, uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.record_pomodoist_purchase(p_original_transaction_id text, p_latest_transaction_id text, p_product_id text, p_environment text, p_purchase_type text, p_purchased_at timestamp with time zone, p_expires_at timestamp with time zone, p_revoked_at timestamp with time zone, p_app_account_token uuid, p_signed_at timestamp with time zone, p_raw_claims jsonb, p_user_id uuid DEFAULT NULL::uuid) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
declare
  v_claim public.pomodoist_purchase_claims%rowtype;
  v_applied boolean := false;
  v_status text;
  v_valid_until timestamptz;
begin
  if p_original_transaction_id is null
      or length(p_original_transaction_id) not between 1 and 128
      or p_latest_transaction_id is null
      or length(p_latest_transaction_id) not between 1 and 128
      or p_purchased_at is null
      or p_signed_at is null
      or p_raw_claims is null
      or p_environment not in ('Production', 'Sandbox', 'Xcode', 'LocalTesting')
      or not (
        (p_product_id in ('pomodoist.pro.monthly', 'pomodoist.pro.annual')
          and p_purchase_type = 'subscription')
        or
        (p_product_id in ('pomodoist.pro.lifetime', 'pomodoist.pro.lifetime.launch')
          and p_purchase_type = 'lifetime')
      ) then
    raise exception 'invalid_pomodoist_purchase';
  end if;

  if p_user_id is not null
      and not exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'pomodoist_profile_not_found';
  end if;

  insert into public.pomodoist_purchase_claims (
    original_transaction_id,
    latest_transaction_id,
    product_id,
    environment,
    purchase_type,
    purchased_at,
    expires_at,
    revoked_at,
    app_account_token,
    latest_signed_at,
    raw_claims
  )
  values (
    p_original_transaction_id,
    p_latest_transaction_id,
    p_product_id,
    p_environment,
    p_purchase_type,
    p_purchased_at,
    p_expires_at,
    p_revoked_at,
    p_app_account_token,
    p_signed_at,
    p_raw_claims
  )
  on conflict (original_transaction_id) do nothing;

  select *
  into v_claim
  from public.pomodoist_purchase_claims
  where original_transaction_id = p_original_transaction_id
  for update;

  if p_user_id is not null
      and v_claim.linked_user_id is not null
      and v_claim.linked_user_id <> p_user_id then
    raise exception 'pomodoist_purchase_already_linked';
  end if;

  if p_signed_at >= v_claim.latest_signed_at then
    update public.pomodoist_purchase_claims
    set latest_transaction_id = p_latest_transaction_id,
        product_id = p_product_id,
        environment = p_environment,
        purchase_type = p_purchase_type,
        purchased_at = p_purchased_at,
        expires_at = p_expires_at,
        revoked_at = p_revoked_at,
        app_account_token = coalesce(
          p_app_account_token,
          pomodoist_purchase_claims.app_account_token
        ),
        latest_signed_at = p_signed_at,
        raw_claims = p_raw_claims
    where original_transaction_id = p_original_transaction_id
    returning * into v_claim;
    v_applied := true;
  end if;

  if p_user_id is not null and v_claim.linked_user_id is null then
    update public.pomodoist_purchase_claims
    set linked_user_id = p_user_id,
        linked_at = timezone('utc', now())
    where original_transaction_id = p_original_transaction_id
    returning * into v_claim;
  end if;

  if v_claim.revoked_at is not null then
    v_status := 'revoked';
    v_valid_until := v_claim.revoked_at;
  elsif v_claim.purchase_type = 'lifetime' then
    v_status := 'active';
    v_valid_until := null;
  elsif v_claim.expires_at > timezone('utc', now()) then
    v_status := 'active';
    v_valid_until := v_claim.expires_at;
  else
    v_status := 'expired';
    v_valid_until := v_claim.expires_at;
  end if;

  if v_claim.linked_user_id is not null
      and exists (
        select 1 from public.profiles where id = v_claim.linked_user_id
      ) then
    insert into public.user_entitlements (
      user_id,
      app_id,
      entitlement_id,
      source,
      purchase_type,
      status,
      product_id,
      store,
      valid_from,
      valid_until,
      renews_at,
      raw_payload
    )
    values (
      v_claim.linked_user_id,
      'pomodoist',
      'app_store:' || v_claim.original_transaction_id,
      'app_store',
      v_claim.purchase_type,
      v_status,
      v_claim.product_id,
      'app_store',
      v_claim.purchased_at,
      v_valid_until,
      case
        when v_claim.purchase_type = 'subscription' then v_claim.expires_at
        else null
      end,
      v_claim.raw_claims
    )
    on conflict (user_id, app_id, entitlement_id) do update
    set source = excluded.source,
        purchase_type = excluded.purchase_type,
        status = excluded.status,
        product_id = excluded.product_id,
        store = excluded.store,
        valid_from = excluded.valid_from,
        valid_until = excluded.valid_until,
        renews_at = excluded.renews_at,
        raw_payload = excluded.raw_payload;
  end if;

  return jsonb_build_object(
    'applied', v_applied,
    'originalTransactionId', v_claim.original_transaction_id,
    'productId', v_claim.product_id,
    'linkedUserId', v_claim.linked_user_id,
    'status', v_status,
    'validUntil', v_valid_until
  );
end;
$$;


ALTER FUNCTION public.record_pomodoist_purchase(p_original_transaction_id text, p_latest_transaction_id text, p_product_id text, p_environment text, p_purchase_type text, p_purchased_at timestamp with time zone, p_expires_at timestamp with time zone, p_revoked_at timestamp with time zone, p_app_account_token uuid, p_signed_at timestamp with time zone, p_raw_claims jsonb, p_user_id uuid) OWNER TO postgres;

--
-- Name: record_pomodoist_stripe_event(text, text, timestamp with time zone, text, text, uuid, text, text, text, timestamp with time zone, timestamp with time zone, boolean, jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.record_pomodoist_stripe_event(p_event_id text, p_event_type text, p_event_created_at timestamp with time zone, p_stripe_object_id text, p_stripe_customer_id text, p_user_id uuid, p_product_id text, p_purchase_type text, p_status text, p_valid_from timestamp with time zone, p_valid_until timestamp with time zone, p_first_subscription_paid boolean, p_raw_payload jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
declare
  v_customer_id text;
  v_claim private.pomodoist_stripe_claims%rowtype;
  v_inserted integer := 0;
begin
  if p_event_id is null
      or length(p_event_id) not between 1 and 255
      or p_event_type is null
      or length(p_event_type) not between 1 and 255
      or p_event_created_at is null
      or p_stripe_object_id is null
      or length(p_stripe_object_id) not between 1 and 255
      or p_stripe_customer_id is null
      or length(p_stripe_customer_id) not between 1 and 255
      or p_user_id is null
      or p_status not in ('active', 'inactive', 'expired', 'revoked')
      or p_raw_payload is null
      or not (
        (p_product_id in ('pomodoist.pro.monthly', 'pomodoist.pro.annual')
          and p_purchase_type = 'subscription'
          and p_valid_from is not null
          and p_valid_until is not null)
        or
        (p_product_id in ('pomodoist.pro.lifetime', 'pomodoist.pro.lifetime.launch')
          and p_purchase_type = 'lifetime'
          and (p_status = 'revoked' or p_valid_from is not null))
      )
      or (p_first_subscription_paid and p_purchase_type <> 'subscription')
      or not exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'invalid_pomodoist_stripe_event';
  end if;

  select stripe_customer_id
  into v_customer_id
  from private.pomodoist_stripe_customers
  where user_id = p_user_id
  for update;

  if v_customer_id is null or v_customer_id <> p_stripe_customer_id then
    raise exception 'pomodoist_stripe_customer_mismatch';
  end if;

  if p_first_subscription_paid then
    update private.pomodoist_stripe_customers
    set first_subscription_paid_at = coalesce(
      first_subscription_paid_at,
      p_event_created_at
    )
    where user_id = p_user_id;
  end if;

  insert into private.pomodoist_stripe_events (
    event_id,
    event_type,
    event_created_at
  ) values (
    p_event_id,
    p_event_type,
    p_event_created_at
  ) on conflict (event_id) do nothing;
  get diagnostics v_inserted = row_count;

  if v_inserted = 0 then
    return jsonb_build_object('applied', false, 'reason', 'duplicate');
  end if;

  select *
  into v_claim
  from private.pomodoist_stripe_claims
  where stripe_object_id = p_stripe_object_id
  for update;

  if found and (
      v_claim.user_id <> p_user_id
      or v_claim.stripe_customer_id <> p_stripe_customer_id
    ) then
    raise exception 'pomodoist_stripe_claim_already_linked';
  end if;

  if found and p_event_created_at < v_claim.latest_event_created_at then
    return jsonb_build_object('applied', false, 'reason', 'stale');
  end if;

  insert into private.pomodoist_stripe_claims (
    stripe_object_id,
    stripe_customer_id,
    user_id,
    product_id,
    purchase_type,
    status,
    valid_from,
    valid_until,
    latest_event_created_at,
    raw_payload
  ) values (
    p_stripe_object_id,
    p_stripe_customer_id,
    p_user_id,
    p_product_id,
    p_purchase_type,
    p_status,
    p_valid_from,
    p_valid_until,
    p_event_created_at,
    p_raw_payload
  )
  on conflict (stripe_object_id) do update
  set product_id = excluded.product_id,
      purchase_type = excluded.purchase_type,
      status = excluded.status,
      valid_from = coalesce(excluded.valid_from, private.pomodoist_stripe_claims.valid_from),
      valid_until = excluded.valid_until,
      latest_event_created_at = excluded.latest_event_created_at,
      raw_payload = excluded.raw_payload
  returning * into v_claim;

  insert into public.user_entitlements (
    user_id,
    app_id,
    entitlement_id,
    source,
    purchase_type,
    status,
    product_id,
    store,
    valid_from,
    valid_until,
    renews_at,
    raw_payload
  ) values (
    p_user_id,
    'pomodoist',
    'stripe:' || p_stripe_object_id,
    'stripe',
    p_purchase_type,
    p_status,
    p_product_id,
    'stripe',
    v_claim.valid_from,
    p_valid_until,
    case when p_purchase_type = 'subscription' then p_valid_until else null end,
    p_raw_payload
  )
  on conflict (user_id, app_id, entitlement_id) do update
  set source = excluded.source,
      purchase_type = excluded.purchase_type,
      status = excluded.status,
      product_id = excluded.product_id,
      store = excluded.store,
      valid_from = excluded.valid_from,
      valid_until = excluded.valid_until,
      renews_at = excluded.renews_at,
      raw_payload = excluded.raw_payload;

  return jsonb_build_object(
    'applied', true,
    'stripeObjectId', p_stripe_object_id,
    'status', p_status
  );
end;
$$;


ALTER FUNCTION public.record_pomodoist_stripe_event(p_event_id text, p_event_type text, p_event_created_at timestamp with time zone, p_stripe_object_id text, p_stripe_customer_id text, p_user_id uuid, p_product_id text, p_purchase_type text, p_status text, p_valid_from timestamp with time zone, p_valid_until timestamp with time zone, p_first_subscription_paid boolean, p_raw_payload jsonb) OWNER TO postgres;

--
-- Name: resolve_pomodoist_mcp_session(uuid, uuid, uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.resolve_pomodoist_mcp_session(p_subject uuid, p_session_id uuid, p_client_id uuid) RETURNS uuid
    LANGUAGE sql STABLE STRICT SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select session.user_id
  from auth.sessions as session
  where session.id = p_session_id
    and session.oauth_client_id = p_client_id
    and (
      session.not_after is null
      or session.not_after > statement_timestamp()
    )
    and private.pomodoist_mcp_subject(
      session.user_id,
      session.oauth_client_id
    ) = p_subject
  limit 1;
$$;


ALTER FUNCTION public.resolve_pomodoist_mcp_session(p_subject uuid, p_session_id uuid, p_client_id uuid) OWNER TO postgres;

--
-- Name: run_pomodoist_free_task_pruning(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.run_pomodoist_free_task_pruning() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_started_at timestamptz := clock_timestamp();
  v_deleted integer;
begin
  v_deleted := public.prune_pomodoist_free_task_history();
  insert into public.sync_maintenance_runs (
    job_name,
    started_at,
    finished_at,
    deleted_rows
  ) values (
    'pomodoist-free-task-prune',
    v_started_at,
    clock_timestamp(),
    v_deleted
  );
end;
$$;


ALTER FUNCTION public.run_pomodoist_free_task_pruning() OWNER TO postgres;

--
-- Name: run_pomodoist_receipt_pruning(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.run_pomodoist_receipt_pruning() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_started_at timestamptz := clock_timestamp();
  v_deleted integer;
begin
  v_deleted := public.prune_pomodoist_sync_receipts();
  insert into public.sync_maintenance_runs (
    job_name,
    started_at,
    finished_at,
    deleted_rows
  ) values (
    'pomodoist-sync-receipt-prune',
    v_started_at,
    clock_timestamp(),
    v_deleted
  );
end;
$$;


ALTER FUNCTION public.run_pomodoist_receipt_pruning() OWNER TO postgres;

--
-- Name: send_pomodoist_mcp_sync_hint(uuid, uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.send_pomodoist_mcp_sync_hint(p_user_id uuid, p_client_id uuid) RETURNS void
    LANGUAGE plpgsql STRICT SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform realtime.send(
    pg_catalog.jsonb_build_object(
      'appId', 'pomodoist',
      'deviceId', 'mcp:' || p_client_id::text,
      'sentAt', pg_catalog.to_char(
        pg_catalog.clock_timestamp() at time zone 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
      )
    ),
    'changed',
    'sync:' || p_user_id::text || ':pomodoist',
    true
  );
end;
$$;


ALTER FUNCTION public.send_pomodoist_mcp_sync_hint(p_user_id uuid, p_client_id uuid) OWNER TO postgres;

--
-- Name: touch_updated_at(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.touch_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;


ALTER FUNCTION public.touch_updated_at() OWNER TO postgres;

--
-- Name: unlink_pomodoist_telegram(bigint, uuid, uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.unlink_pomodoist_telegram(p_telegram_user_id bigint, p_expected_user_id uuid, p_guest_user_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_account public.pomodoist_telegram_accounts%rowtype;
  v_now timestamptz := pg_catalog.timezone('utc', pg_catalog.now());
begin
  if p_telegram_user_id <= 0
    or p_expected_user_id is null
    or p_guest_user_id is null
    or p_expected_user_id = p_guest_user_id
    or not exists (
      select 1 from public.profiles where id = p_guest_user_id
    )
  then
    raise exception using errcode = '22023', message = 'Invalid Telegram unlink';
  end if;

  select * into v_account
  from public.pomodoist_telegram_accounts
  where telegram_user_id = p_telegram_user_id
  for update;

  if not found
    or v_account.user_id is distinct from p_expected_user_id
    or v_account.linked_at is null
  then
    raise exception using errcode = '40001', message = 'Telegram mapping changed';
  end if;

  update public.pomodoist_telegram_accounts
  set user_id = p_guest_user_id,
      guest_user_id = p_guest_user_id,
      linked_at = null,
      updated_at = v_now
  where telegram_user_id = p_telegram_user_id;

  delete from public.pomodoist_telegram_link_attempts
  where telegram_user_id = p_telegram_user_id;

  return pg_catalog.jsonb_build_object(
    'telegramUserId', v_account.telegram_user_id::text,
    'userId', p_guest_user_id::text,
    'guestUserId', p_guest_user_id::text,
    'clientId', v_account.client_id::text,
    'linked', false
  );
end;
$$;


ALTER FUNCTION public.unlink_pomodoist_telegram(p_telegram_user_id bigint, p_expected_user_id uuid, p_guest_user_id uuid) OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: pomodoist_google_calendar_accounts; Type: TABLE; Schema: private; Owner: postgres
--

CREATE TABLE private.pomodoist_google_calendar_accounts (
    user_id uuid NOT NULL,
    refresh_token_secret_id uuid,
    account_email text,
    calendar_id text,
    calendar_name text DEFAULT 'Pomodoist'::text NOT NULL,
    sync_token text,
    status text DEFAULT 'connecting'::text NOT NULL,
    last_error text,
    warning text,
    last_sync_started_at timestamp with time zone,
    last_sync_finished_at timestamp with time zone,
    watch_channel_id text,
    watch_resource_id text,
    watch_token_hash text,
    watch_expires_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    CONSTRAINT pomodoist_google_calendar_accounts_status_check CHECK ((status = ANY (ARRAY['connecting'::text, 'connected'::text, 'error'::text, 'disconnected'::text])))
);


ALTER TABLE private.pomodoist_google_calendar_accounts OWNER TO postgres;

--
-- Name: pomodoist_google_calendar_jobs; Type: TABLE; Schema: private; Owner: postgres
--

CREATE TABLE private.pomodoist_google_calendar_jobs (
    user_id uuid NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    due_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    lease_until timestamp with time zone,
    generation bigint DEFAULT 1 NOT NULL,
    claimed_generation bigint,
    attempts integer DEFAULT 0 NOT NULL,
    last_error text,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    CONSTRAINT pomodoist_google_calendar_jobs_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'processing'::text])))
);


ALTER TABLE private.pomodoist_google_calendar_jobs OWNER TO postgres;

--
-- Name: pomodoist_google_calendar_links; Type: TABLE; Schema: private; Owner: postgres
--

CREATE TABLE private.pomodoist_google_calendar_links (
    user_id uuid NOT NULL,
    task_id text NOT NULL,
    calendar_id text NOT NULL,
    event_id text NOT NULL,
    etag text,
    google_updated_at timestamp with time zone,
    local_schedule_updated_at timestamp with time zone NOT NULL,
    last_schedule_fingerprint text,
    unsupported_reason text,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);


ALTER TABLE private.pomodoist_google_calendar_links OWNER TO postgres;

--
-- Name: pomodoist_google_calendar_oauth_states; Type: TABLE; Schema: private; Owner: postgres
--

CREATE TABLE private.pomodoist_google_calendar_oauth_states (
    state_hash text NOT NULL,
    user_id uuid NOT NULL,
    code_verifier text NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    CONSTRAINT pomodoist_google_calendar_oauth_states_code_verifier_check CHECK (((length(code_verifier) >= 43) AND (length(code_verifier) <= 128))),
    CONSTRAINT pomodoist_google_calendar_oauth_states_state_hash_check CHECK ((length(state_hash) = 64))
);


ALTER TABLE private.pomodoist_google_calendar_oauth_states OWNER TO postgres;

--
-- Name: pomodoist_google_calendar_task_state; Type: TABLE; Schema: private; Owner: postgres
--

CREATE TABLE private.pomodoist_google_calendar_task_state (
    user_id uuid NOT NULL,
    task_id text NOT NULL,
    local_schedule_updated_at timestamp with time zone NOT NULL
);


ALTER TABLE private.pomodoist_google_calendar_task_state OWNER TO postgres;

--
-- Name: pomodoist_instance_settings; Type: TABLE; Schema: private; Owner: postgres
--

CREATE TABLE private.pomodoist_instance_settings (
    singleton boolean DEFAULT true NOT NULL,
    selfhost_features_enabled boolean DEFAULT false NOT NULL,
    mcp_issuer text,
    mcp_audience text,
    CONSTRAINT pomodoist_instance_settings_singleton_check CHECK (singleton)
);


ALTER TABLE private.pomodoist_instance_settings OWNER TO postgres;

--
-- Name: pomodoist_invitations; Type: TABLE; Schema: private; Owner: postgres
--

CREATE TABLE private.pomodoist_invitations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    scope_id uuid NOT NULL,
    token text DEFAULT encode(extensions.gen_random_bytes(32), 'hex'::text) NOT NULL,
    email text,
    role text NOT NULL,
    created_by uuid NOT NULL,
    expires_at timestamp with time zone DEFAULT (now() + '7 days'::interval) NOT NULL,
    revoked_at timestamp with time zone,
    accepted_by uuid,
    accepted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT pomodoist_invitations_role_check CHECK ((role = ANY (ARRAY['member'::text, 'observer'::text])))
);


ALTER TABLE private.pomodoist_invitations OWNER TO postgres;

--
-- Name: pomodoist_mcp_rate_limits; Type: TABLE; Schema: private; Owner: postgres
--

CREATE TABLE private.pomodoist_mcp_rate_limits (
    user_id uuid NOT NULL,
    client_id uuid NOT NULL,
    window_started_at timestamp with time zone NOT NULL,
    call_count integer NOT NULL,
    CONSTRAINT pomodoist_mcp_rate_limits_call_count_check CHECK (((call_count >= 1) AND (call_count <= 121)))
);


ALTER TABLE private.pomodoist_mcp_rate_limits OWNER TO postgres;

--
-- Name: pomodoist_members; Type: TABLE; Schema: private; Owner: postgres
--

CREATE TABLE private.pomodoist_members (
    scope_id uuid NOT NULL,
    user_id uuid NOT NULL,
    role text NOT NULL,
    joined_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT pomodoist_members_role_check CHECK ((role = ANY (ARRAY['administrator'::text, 'member'::text, 'observer'::text])))
);


ALTER TABLE private.pomodoist_members OWNER TO postgres;

--
-- Name: pomodoist_notifications; Type: TABLE; Schema: private; Owner: postgres
--

CREATE TABLE private.pomodoist_notifications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    scope_id uuid,
    kind text NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    read_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE private.pomodoist_notifications OWNER TO postgres;

--
-- Name: pomodoist_openclaw_receipts; Type: TABLE; Schema: private; Owner: postgres
--

CREATE TABLE private.pomodoist_openclaw_receipts (
    user_id uuid NOT NULL,
    client_id uuid NOT NULL,
    request_id uuid NOT NULL,
    action text NOT NULL,
    arguments_hash text NOT NULL,
    result jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT pomodoist_openclaw_receipts_arguments_hash_check CHECK ((arguments_hash ~ '^[a-f0-9]{64}$'::text))
);


ALTER TABLE private.pomodoist_openclaw_receipts OWNER TO postgres;

--
-- Name: pomodoist_personal_history; Type: TABLE; Schema: private; Owner: postgres
--

CREATE TABLE private.pomodoist_personal_history (
    user_id uuid NOT NULL,
    history_unlimited boolean NOT NULL,
    grace_ends_at timestamp with time zone
);


ALTER TABLE private.pomodoist_personal_history OWNER TO postgres;

--
-- Name: pomodoist_recurrence_successors; Type: TABLE; Schema: private; Owner: postgres
--

CREATE TABLE private.pomodoist_recurrence_successors (
    scope_id uuid NOT NULL,
    source_id text NOT NULL,
    occurrence_key text NOT NULL,
    successor_id text NOT NULL
);


ALTER TABLE private.pomodoist_recurrence_successors OWNER TO postgres;

--
-- Name: pomodoist_scopes; Type: TABLE; Schema: private; Owner: postgres
--

CREATE TABLE private.pomodoist_scopes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    root_project_id text NOT NULL,
    owner_id uuid NOT NULL,
    revision bigint DEFAULT 0 NOT NULL,
    history_unlimited boolean DEFAULT false NOT NULL,
    grace_ends_at timestamp with time zone,
    public_token text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE private.pomodoist_scopes OWNER TO postgres;

--
-- Name: pomodoist_shared_entities; Type: TABLE; Schema: private; Owner: postgres
--

CREATE TABLE private.pomodoist_shared_entities (
    scope_id uuid NOT NULL,
    entity_type text NOT NULL,
    entity_id text NOT NULL,
    data jsonb NOT NULL,
    field_revision jsonb DEFAULT '{}'::jsonb NOT NULL,
    server_revision bigint NOT NULL,
    deleted_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT pomodoist_shared_entities_entity_type_check CHECK ((entity_type = ANY (ARRAY['project'::text, 'section'::text, 'task'::text, 'label'::text, 'task_label'::text, 'task_kanban_status'::text, 'task_completion'::text, 'comment'::text, 'activity'::text, 'focus_interval'::text, 'attachment'::text])))
);


ALTER TABLE private.pomodoist_shared_entities OWNER TO postgres;

--
-- Name: pomodoist_shared_preferences; Type: TABLE; Schema: private; Owner: postgres
--

CREATE TABLE private.pomodoist_shared_preferences (
    scope_id uuid NOT NULL,
    user_id uuid NOT NULL,
    entity_type text NOT NULL,
    entity_id text NOT NULL,
    data jsonb NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE private.pomodoist_shared_preferences OWNER TO postgres;

--
-- Name: pomodoist_shared_receipts; Type: TABLE; Schema: private; Owner: postgres
--

CREATE TABLE private.pomodoist_shared_receipts (
    scope_id uuid NOT NULL,
    user_id uuid NOT NULL,
    op_id text NOT NULL,
    request jsonb NOT NULL,
    result jsonb NOT NULL
);


ALTER TABLE private.pomodoist_shared_receipts OWNER TO postgres;

--
-- Name: pomodoist_storage_deletions; Type: TABLE; Schema: private; Owner: postgres
--

CREATE TABLE private.pomodoist_storage_deletions (
    object_path text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE private.pomodoist_storage_deletions OWNER TO postgres;

--
-- Name: pomodoist_stripe_claims; Type: TABLE; Schema: private; Owner: postgres
--

CREATE TABLE private.pomodoist_stripe_claims (
    stripe_object_id text NOT NULL,
    stripe_customer_id text NOT NULL,
    user_id uuid NOT NULL,
    product_id text NOT NULL,
    purchase_type text NOT NULL,
    status text NOT NULL,
    valid_from timestamp with time zone,
    valid_until timestamp with time zone,
    latest_event_created_at timestamp with time zone NOT NULL,
    raw_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    CONSTRAINT pomodoist_stripe_claims_check CHECK ((((product_id = ANY (ARRAY['pomodoist.pro.monthly'::text, 'pomodoist.pro.annual'::text])) AND (purchase_type = 'subscription'::text)) OR ((product_id = ANY (ARRAY['pomodoist.pro.lifetime'::text, 'pomodoist.pro.lifetime.launch'::text])) AND (purchase_type = 'lifetime'::text)))),
    CONSTRAINT pomodoist_stripe_claims_purchase_type_check CHECK ((purchase_type = ANY (ARRAY['subscription'::text, 'lifetime'::text]))),
    CONSTRAINT pomodoist_stripe_claims_status_check CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text, 'expired'::text, 'revoked'::text]))),
    CONSTRAINT pomodoist_stripe_claims_stripe_customer_id_check CHECK (((length(stripe_customer_id) >= 1) AND (length(stripe_customer_id) <= 255))),
    CONSTRAINT pomodoist_stripe_claims_stripe_object_id_check CHECK (((length(stripe_object_id) >= 1) AND (length(stripe_object_id) <= 255)))
);


ALTER TABLE private.pomodoist_stripe_claims OWNER TO postgres;

--
-- Name: pomodoist_stripe_customers; Type: TABLE; Schema: private; Owner: postgres
--

CREATE TABLE private.pomodoist_stripe_customers (
    user_id uuid NOT NULL,
    stripe_customer_id text NOT NULL,
    first_subscription_paid_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    CONSTRAINT pomodoist_stripe_customers_stripe_customer_id_check CHECK (((length(stripe_customer_id) >= 1) AND (length(stripe_customer_id) <= 255)))
);


ALTER TABLE private.pomodoist_stripe_customers OWNER TO postgres;

--
-- Name: pomodoist_stripe_events; Type: TABLE; Schema: private; Owner: postgres
--

CREATE TABLE private.pomodoist_stripe_events (
    event_id text NOT NULL,
    event_type text NOT NULL,
    event_created_at timestamp with time zone NOT NULL,
    processed_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    CONSTRAINT pomodoist_stripe_events_event_id_check CHECK (((length(event_id) >= 1) AND (length(event_id) <= 255))),
    CONSTRAINT pomodoist_stripe_events_event_type_check CHECK (((length(event_type) >= 1) AND (length(event_type) <= 255)))
);


ALTER TABLE private.pomodoist_stripe_events OWNER TO postgres;

--
-- Name: pomodoist_subscription_offers; Type: TABLE; Schema: private; Owner: postgres
--

CREATE TABLE private.pomodoist_subscription_offers (
    environment text NOT NULL,
    app_transaction_id text NOT NULL,
    campaign_id text NOT NULL,
    redeemed boolean DEFAULT false NOT NULL,
    lease_until timestamp with time zone,
    nonce uuid,
    product_id text,
    CONSTRAINT pomodoist_subscription_offers_app_transaction_id_check CHECK ((app_transaction_id ~ '^[0-9]{1,128}$'::text)),
    CONSTRAINT pomodoist_subscription_offers_campaign_id_check CHECK ((campaign_id = 'return-2026-v1'::text)),
    CONSTRAINT pomodoist_subscription_offers_environment_check CHECK ((environment = ANY (ARRAY['Production'::text, 'Sandbox'::text])))
);


ALTER TABLE private.pomodoist_subscription_offers OWNER TO postgres;

--
-- Name: pomodoist_transferred_entities; Type: TABLE; Schema: private; Owner: postgres
--

CREATE TABLE private.pomodoist_transferred_entities (
    user_id uuid NOT NULL,
    entity_type text NOT NULL,
    entity_id text NOT NULL,
    scope_id uuid NOT NULL
);


ALTER TABLE private.pomodoist_transferred_entities OWNER TO postgres;

--
-- Name: pomodoist_upload_months; Type: TABLE; Schema: private; Owner: postgres
--

CREATE TABLE private.pomodoist_upload_months (
    user_id uuid NOT NULL,
    month date NOT NULL,
    bytes bigint DEFAULT 0 NOT NULL,
    CONSTRAINT pomodoist_upload_months_bytes_check CHECK (((bytes >= 0) AND (bytes <= 1000000000)))
);


ALTER TABLE private.pomodoist_upload_months OWNER TO postgres;

--
-- Name: pomodoist_upload_years; Type: TABLE; Schema: private; Owner: postgres
--

CREATE TABLE private.pomodoist_upload_years (
    user_id uuid NOT NULL,
    year integer NOT NULL,
    bytes bigint DEFAULT 0 NOT NULL,
    CONSTRAINT pomodoist_upload_years_bytes_check CHECK (((bytes >= 0) AND (bytes <= '5000000000'::bigint)))
);


ALTER TABLE private.pomodoist_upload_years OWNER TO postgres;

--
-- Name: pomodoist_uploads; Type: TABLE; Schema: private; Owner: postgres
--

CREATE TABLE private.pomodoist_uploads (
    id uuid NOT NULL,
    scope_id uuid NOT NULL,
    task_id text NOT NULL,
    user_id uuid NOT NULL,
    name text NOT NULL,
    content_type text NOT NULL,
    bytes bigint NOT NULL,
    object_path text NOT NULL,
    expires_at timestamp with time zone DEFAULT (now() + '02:00:00'::interval) NOT NULL,
    finished_at timestamp with time zone,
    deleted_at timestamp with time zone,
    CONSTRAINT pomodoist_uploads_bytes_check CHECK (((bytes >= 1) AND (bytes <= 20000000)))
);


ALTER TABLE private.pomodoist_uploads OWNER TO postgres;

--
-- Name: pomodoist_voice_requests; Type: TABLE; Schema: private; Owner: postgres
--

CREATE TABLE private.pomodoist_voice_requests (
    request_id uuid NOT NULL,
    usage_period_id uuid NOT NULL,
    completed boolean DEFAULT false NOT NULL,
    expires_at timestamp with time zone DEFAULT (now() + '00:10:00'::interval) NOT NULL
);


ALTER TABLE private.pomodoist_voice_requests OWNER TO postgres;

--
-- Name: apps; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.apps (
    id text NOT NULL,
    display_name text NOT NULL,
    description text,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);


ALTER TABLE public.apps OWNER TO postgres;

--
-- Name: pomodoist_purchase_claims; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.pomodoist_purchase_claims (
    original_transaction_id text NOT NULL,
    latest_transaction_id text NOT NULL,
    product_id text NOT NULL,
    environment text NOT NULL,
    purchase_type text NOT NULL,
    purchased_at timestamp with time zone NOT NULL,
    expires_at timestamp with time zone,
    revoked_at timestamp with time zone,
    app_account_token uuid,
    linked_user_id uuid,
    linked_at timestamp with time zone,
    latest_signed_at timestamp with time zone NOT NULL,
    raw_claims jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    CONSTRAINT pomodoist_purchase_claims_check CHECK ((((product_id = ANY (ARRAY['pomodoist.pro.monthly'::text, 'pomodoist.pro.annual'::text])) AND (purchase_type = 'subscription'::text)) OR ((product_id = ANY (ARRAY['pomodoist.pro.lifetime'::text, 'pomodoist.pro.lifetime.launch'::text])) AND (purchase_type = 'lifetime'::text)))),
    CONSTRAINT pomodoist_purchase_claims_environment_check CHECK ((environment = ANY (ARRAY['Production'::text, 'Sandbox'::text, 'Xcode'::text, 'LocalTesting'::text]))),
    CONSTRAINT pomodoist_purchase_claims_latest_transaction_id_check CHECK (((length(latest_transaction_id) >= 1) AND (length(latest_transaction_id) <= 128))),
    CONSTRAINT pomodoist_purchase_claims_original_transaction_id_check CHECK (((length(original_transaction_id) >= 1) AND (length(original_transaction_id) <= 128))),
    CONSTRAINT pomodoist_purchase_claims_purchase_type_check CHECK ((purchase_type = ANY (ARRAY['subscription'::text, 'lifetime'::text])))
);


ALTER TABLE public.pomodoist_purchase_claims OWNER TO postgres;

--
-- Name: COLUMN pomodoist_purchase_claims.linked_user_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.pomodoist_purchase_claims.linked_user_id IS 'Permanent first-account ownership marker. No FK by design so account deletion cannot release the purchase.';


--
-- Name: pomodoist_telegram_accounts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.pomodoist_telegram_accounts (
    telegram_user_id bigint NOT NULL,
    user_id uuid NOT NULL,
    guest_user_id uuid,
    client_id uuid NOT NULL,
    linked_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    CONSTRAINT pomodoist_telegram_accounts_telegram_user_id_check CHECK ((telegram_user_id > 0))
);


ALTER TABLE public.pomodoist_telegram_accounts OWNER TO postgres;

--
-- Name: pomodoist_telegram_link_attempts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.pomodoist_telegram_link_attempts (
    token_hash bytea NOT NULL,
    telegram_user_id bigint NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    used_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    CONSTRAINT pomodoist_telegram_link_attempts_token_hash_check CHECK ((octet_length(token_hash) = 32))
);


ALTER TABLE public.pomodoist_telegram_link_attempts OWNER TO postgres;

--
-- Name: products; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.products (
    id text NOT NULL,
    app_id text NOT NULL,
    revenuecat_entitlement_id text NOT NULL,
    product_type text NOT NULL,
    display_name text NOT NULL,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    CONSTRAINT products_product_type_check CHECK ((product_type = ANY (ARRAY['subscription'::text, 'lifetime'::text, 'consumable'::text])))
);


ALTER TABLE public.products OWNER TO postgres;

--
-- Name: profiles; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.profiles (
    id uuid NOT NULL,
    email text,
    display_name text,
    avatar_url text,
    revenuecat_app_user_id text NOT NULL,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    apple_app_account_token uuid DEFAULT gen_random_uuid() NOT NULL,
    pomodoist_is_pro boolean DEFAULT false NOT NULL
);


ALTER TABLE public.profiles OWNER TO postgres;

--
-- Name: quota_definitions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.quota_definitions (
    app_id text NOT NULL,
    quota_key text NOT NULL,
    limit_value integer NOT NULL,
    unit text DEFAULT 'count'::text NOT NULL,
    period text DEFAULT 'monthly'::text NOT NULL,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    CONSTRAINT quota_definitions_limit_value_check CHECK ((limit_value >= 0)),
    CONSTRAINT quota_definitions_period_check CHECK ((period = 'monthly'::text))
);


ALTER TABLE public.quota_definitions OWNER TO postgres;

--
-- Name: storage_usage; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.storage_usage (
    user_id uuid NOT NULL,
    app_id text NOT NULL,
    used_bytes bigint DEFAULT 0 NOT NULL,
    limit_bytes bigint DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    CONSTRAINT storage_usage_limit_bytes_check CHECK ((limit_bytes >= 0)),
    CONSTRAINT storage_usage_used_bytes_check CHECK ((used_bytes >= 0))
);


ALTER TABLE public.storage_usage OWNER TO postgres;

--
-- Name: sync_devices; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sync_devices (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    app_id text NOT NULL,
    device_id text NOT NULL,
    device_name text,
    platform text,
    last_seen_cursor bigint DEFAULT 0 NOT NULL,
    last_seen_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);


ALTER TABLE public.sync_devices OWNER TO postgres;

--
-- Name: sync_entities; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sync_entities (
    user_id uuid NOT NULL,
    app_id text NOT NULL,
    entity_type text NOT NULL,
    entity_id text NOT NULL,
    server_revision bigint NOT NULL,
    client_updated_at timestamp with time zone NOT NULL,
    deleted_at timestamp with time zone,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    field_clock jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);


ALTER TABLE public.sync_entities OWNER TO postgres;

--
-- Name: sync_maintenance_runs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sync_maintenance_runs (
    id bigint NOT NULL,
    job_name text NOT NULL,
    started_at timestamp with time zone NOT NULL,
    finished_at timestamp with time zone NOT NULL,
    deleted_rows integer NOT NULL,
    CONSTRAINT sync_maintenance_runs_deleted_rows_check CHECK ((deleted_rows >= 0))
);


ALTER TABLE public.sync_maintenance_runs OWNER TO postgres;

--
-- Name: sync_maintenance_runs_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.sync_maintenance_runs ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.sync_maintenance_runs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: sync_operation_receipts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sync_operation_receipts (
    user_id uuid NOT NULL,
    op_id text NOT NULL,
    server_revision bigint NOT NULL,
    inserted_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);


ALTER TABLE public.sync_operation_receipts OWNER TO postgres;

--
-- Name: sync_operations; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sync_operations (
    user_id uuid NOT NULL,
    app_id text NOT NULL,
    op_id text NOT NULL,
    device_id text NOT NULL,
    entity_type text NOT NULL,
    entity_id text NOT NULL,
    operation text NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    client_updated_at timestamp with time zone NOT NULL,
    server_revision bigint NOT NULL,
    inserted_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    CONSTRAINT sync_operations_operation_check CHECK ((operation = ANY (ARRAY['upsert'::text, 'delete'::text])))
);


ALTER TABLE public.sync_operations OWNER TO postgres;

--
-- Name: sync_revision_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.sync_revision_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.sync_revision_seq OWNER TO postgres;

--
-- Name: usage_periods; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.usage_periods (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    app_id text NOT NULL,
    quota_key text NOT NULL,
    period_start timestamp with time zone NOT NULL,
    period_end timestamp with time zone NOT NULL,
    used integer DEFAULT 0 NOT NULL,
    limit_value integer NOT NULL,
    unit text DEFAULT 'count'::text NOT NULL,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    purchase_subject text,
    CONSTRAINT usage_periods_limit_value_check CHECK ((limit_value >= 0)),
    CONSTRAINT usage_periods_owner_check CHECK ((((user_id IS NOT NULL) AND (purchase_subject IS NULL)) OR ((user_id IS NULL) AND (app_id = 'pomodoist'::text) AND (quota_key = 'llm_requests'::text) AND (purchase_subject IS NOT NULL) AND (purchase_subject ~ '^apple:(Production|Sandbox):[^:]{1,128}$'::text)))),
    CONSTRAINT usage_periods_period_order_check CHECK ((period_end > period_start)),
    CONSTRAINT usage_periods_used_check CHECK ((used >= 0))
);


ALTER TABLE public.usage_periods OWNER TO postgres;

--
-- Name: COLUMN usage_periods.purchase_subject; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.usage_periods.purchase_subject IS 'StoreKit-only LLM identity: apple:<environment>:<verified originalTransactionId>. Never supplied directly by a client.';


--
-- Name: user_app_installs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_app_installs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    app_id text NOT NULL,
    device_id text NOT NULL,
    platform text,
    app_version text,
    last_seen_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);


ALTER TABLE public.user_app_installs OWNER TO postgres;

--
-- Name: user_entitlements; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_entitlements (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    app_id text NOT NULL,
    entitlement_id text NOT NULL,
    source text DEFAULT 'revenuecat'::text NOT NULL,
    purchase_type text DEFAULT 'subscription'::text NOT NULL,
    status text DEFAULT 'inactive'::text NOT NULL,
    product_id text,
    store text,
    valid_from timestamp with time zone,
    valid_until timestamp with time zone,
    renews_at timestamp with time zone,
    revenuecat_original_app_user_id text,
    raw_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    CONSTRAINT user_entitlements_purchase_type_check CHECK ((purchase_type = ANY (ARRAY['subscription'::text, 'lifetime'::text, 'consumable'::text]))),
    CONSTRAINT user_entitlements_status_check CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text, 'expired'::text, 'revoked'::text])))
);


ALTER TABLE public.user_entitlements OWNER TO postgres;

--
-- Name: pomodoist_google_calendar_accounts pomodoist_google_calendar_accounts_pkey; Type: CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_google_calendar_accounts
    ADD CONSTRAINT pomodoist_google_calendar_accounts_pkey PRIMARY KEY (user_id);


--
-- Name: pomodoist_google_calendar_jobs pomodoist_google_calendar_jobs_pkey; Type: CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_google_calendar_jobs
    ADD CONSTRAINT pomodoist_google_calendar_jobs_pkey PRIMARY KEY (user_id);


--
-- Name: pomodoist_google_calendar_links pomodoist_google_calendar_links_pkey; Type: CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_google_calendar_links
    ADD CONSTRAINT pomodoist_google_calendar_links_pkey PRIMARY KEY (user_id, task_id);


--
-- Name: pomodoist_google_calendar_oauth_states pomodoist_google_calendar_oauth_states_pkey; Type: CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_google_calendar_oauth_states
    ADD CONSTRAINT pomodoist_google_calendar_oauth_states_pkey PRIMARY KEY (state_hash);


--
-- Name: pomodoist_google_calendar_task_state pomodoist_google_calendar_task_state_pkey; Type: CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_google_calendar_task_state
    ADD CONSTRAINT pomodoist_google_calendar_task_state_pkey PRIMARY KEY (user_id, task_id);


--
-- Name: pomodoist_instance_settings pomodoist_instance_settings_pkey; Type: CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_instance_settings
    ADD CONSTRAINT pomodoist_instance_settings_pkey PRIMARY KEY (singleton);


--
-- Name: pomodoist_invitations pomodoist_invitations_pkey; Type: CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_invitations
    ADD CONSTRAINT pomodoist_invitations_pkey PRIMARY KEY (id);


--
-- Name: pomodoist_invitations pomodoist_invitations_token_key; Type: CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_invitations
    ADD CONSTRAINT pomodoist_invitations_token_key UNIQUE (token);


--
-- Name: pomodoist_mcp_rate_limits pomodoist_mcp_rate_limits_pkey; Type: CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_mcp_rate_limits
    ADD CONSTRAINT pomodoist_mcp_rate_limits_pkey PRIMARY KEY (user_id, client_id);


--
-- Name: pomodoist_members pomodoist_members_pkey; Type: CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_members
    ADD CONSTRAINT pomodoist_members_pkey PRIMARY KEY (scope_id, user_id);


--
-- Name: pomodoist_notifications pomodoist_notifications_pkey; Type: CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_notifications
    ADD CONSTRAINT pomodoist_notifications_pkey PRIMARY KEY (id);


--
-- Name: pomodoist_openclaw_receipts pomodoist_openclaw_receipts_pkey; Type: CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_openclaw_receipts
    ADD CONSTRAINT pomodoist_openclaw_receipts_pkey PRIMARY KEY (user_id, client_id, request_id);


--
-- Name: pomodoist_personal_history pomodoist_personal_history_pkey; Type: CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_personal_history
    ADD CONSTRAINT pomodoist_personal_history_pkey PRIMARY KEY (user_id);


--
-- Name: pomodoist_recurrence_successors pomodoist_recurrence_successo_scope_id_source_id_occurrence_key; Type: CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_recurrence_successors
    ADD CONSTRAINT pomodoist_recurrence_successo_scope_id_source_id_occurrence_key UNIQUE (scope_id, source_id, occurrence_key);


--
-- Name: pomodoist_recurrence_successors pomodoist_recurrence_successors_pkey; Type: CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_recurrence_successors
    ADD CONSTRAINT pomodoist_recurrence_successors_pkey PRIMARY KEY (scope_id, source_id);


--
-- Name: pomodoist_scopes pomodoist_scopes_pkey; Type: CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_scopes
    ADD CONSTRAINT pomodoist_scopes_pkey PRIMARY KEY (id);


--
-- Name: pomodoist_scopes pomodoist_scopes_public_token_key; Type: CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_scopes
    ADD CONSTRAINT pomodoist_scopes_public_token_key UNIQUE (public_token);


--
-- Name: pomodoist_shared_entities pomodoist_shared_entities_pkey; Type: CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_shared_entities
    ADD CONSTRAINT pomodoist_shared_entities_pkey PRIMARY KEY (scope_id, entity_type, entity_id);


--
-- Name: pomodoist_shared_preferences pomodoist_shared_preferences_pkey; Type: CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_shared_preferences
    ADD CONSTRAINT pomodoist_shared_preferences_pkey PRIMARY KEY (scope_id, user_id, entity_type, entity_id);


--
-- Name: pomodoist_shared_receipts pomodoist_shared_receipts_pkey; Type: CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_shared_receipts
    ADD CONSTRAINT pomodoist_shared_receipts_pkey PRIMARY KEY (scope_id, user_id, op_id);


--
-- Name: pomodoist_storage_deletions pomodoist_storage_deletions_pkey; Type: CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_storage_deletions
    ADD CONSTRAINT pomodoist_storage_deletions_pkey PRIMARY KEY (object_path);


--
-- Name: pomodoist_stripe_claims pomodoist_stripe_claims_pkey; Type: CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_stripe_claims
    ADD CONSTRAINT pomodoist_stripe_claims_pkey PRIMARY KEY (stripe_object_id);


--
-- Name: pomodoist_stripe_customers pomodoist_stripe_customers_pkey; Type: CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_stripe_customers
    ADD CONSTRAINT pomodoist_stripe_customers_pkey PRIMARY KEY (user_id);


--
-- Name: pomodoist_stripe_customers pomodoist_stripe_customers_stripe_customer_id_key; Type: CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_stripe_customers
    ADD CONSTRAINT pomodoist_stripe_customers_stripe_customer_id_key UNIQUE (stripe_customer_id);


--
-- Name: pomodoist_stripe_events pomodoist_stripe_events_pkey; Type: CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_stripe_events
    ADD CONSTRAINT pomodoist_stripe_events_pkey PRIMARY KEY (event_id);


--
-- Name: pomodoist_subscription_offers pomodoist_subscription_offers_pkey; Type: CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_subscription_offers
    ADD CONSTRAINT pomodoist_subscription_offers_pkey PRIMARY KEY (environment, app_transaction_id, campaign_id);


--
-- Name: pomodoist_transferred_entities pomodoist_transferred_entities_pkey; Type: CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_transferred_entities
    ADD CONSTRAINT pomodoist_transferred_entities_pkey PRIMARY KEY (user_id, entity_type, entity_id);


--
-- Name: pomodoist_upload_months pomodoist_upload_months_pkey; Type: CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_upload_months
    ADD CONSTRAINT pomodoist_upload_months_pkey PRIMARY KEY (user_id, month);


--
-- Name: pomodoist_upload_years pomodoist_upload_years_pkey; Type: CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_upload_years
    ADD CONSTRAINT pomodoist_upload_years_pkey PRIMARY KEY (user_id, year);


--
-- Name: pomodoist_uploads pomodoist_uploads_object_path_key; Type: CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_uploads
    ADD CONSTRAINT pomodoist_uploads_object_path_key UNIQUE (object_path);


--
-- Name: pomodoist_uploads pomodoist_uploads_pkey; Type: CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_uploads
    ADD CONSTRAINT pomodoist_uploads_pkey PRIMARY KEY (id);


--
-- Name: pomodoist_voice_requests pomodoist_voice_requests_pkey; Type: CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_voice_requests
    ADD CONSTRAINT pomodoist_voice_requests_pkey PRIMARY KEY (request_id);


--
-- Name: apps apps_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.apps
    ADD CONSTRAINT apps_pkey PRIMARY KEY (id);


--
-- Name: pomodoist_purchase_claims pomodoist_purchase_claims_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pomodoist_purchase_claims
    ADD CONSTRAINT pomodoist_purchase_claims_pkey PRIMARY KEY (original_transaction_id);


--
-- Name: pomodoist_telegram_accounts pomodoist_telegram_accounts_client_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pomodoist_telegram_accounts
    ADD CONSTRAINT pomodoist_telegram_accounts_client_id_key UNIQUE (client_id);


--
-- Name: pomodoist_telegram_accounts pomodoist_telegram_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pomodoist_telegram_accounts
    ADD CONSTRAINT pomodoist_telegram_accounts_pkey PRIMARY KEY (telegram_user_id);


--
-- Name: pomodoist_telegram_link_attempts pomodoist_telegram_link_attempts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pomodoist_telegram_link_attempts
    ADD CONSTRAINT pomodoist_telegram_link_attempts_pkey PRIMARY KEY (token_hash);


--
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (id);


--
-- Name: profiles profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);


--
-- Name: profiles profiles_revenuecat_app_user_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_revenuecat_app_user_id_key UNIQUE (revenuecat_app_user_id);


--
-- Name: quota_definitions quota_definitions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.quota_definitions
    ADD CONSTRAINT quota_definitions_pkey PRIMARY KEY (app_id, quota_key);


--
-- Name: storage_usage storage_usage_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.storage_usage
    ADD CONSTRAINT storage_usage_pkey PRIMARY KEY (user_id, app_id);


--
-- Name: sync_devices sync_devices_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sync_devices
    ADD CONSTRAINT sync_devices_pkey PRIMARY KEY (id);


--
-- Name: sync_devices sync_devices_user_id_app_id_device_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sync_devices
    ADD CONSTRAINT sync_devices_user_id_app_id_device_id_key UNIQUE (user_id, app_id, device_id);


--
-- Name: sync_entities sync_entities_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sync_entities
    ADD CONSTRAINT sync_entities_pkey PRIMARY KEY (user_id, app_id, entity_type, entity_id);


--
-- Name: sync_maintenance_runs sync_maintenance_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sync_maintenance_runs
    ADD CONSTRAINT sync_maintenance_runs_pkey PRIMARY KEY (id);


--
-- Name: sync_operation_receipts sync_operation_receipts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sync_operation_receipts
    ADD CONSTRAINT sync_operation_receipts_pkey PRIMARY KEY (user_id, op_id);


--
-- Name: sync_operations sync_operations_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sync_operations
    ADD CONSTRAINT sync_operations_pkey PRIMARY KEY (user_id, op_id);


--
-- Name: usage_periods usage_periods_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.usage_periods
    ADD CONSTRAINT usage_periods_pkey PRIMARY KEY (id);


--
-- Name: usage_periods usage_periods_user_id_app_id_quota_key_period_start_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.usage_periods
    ADD CONSTRAINT usage_periods_user_id_app_id_quota_key_period_start_key UNIQUE (user_id, app_id, quota_key, period_start);


--
-- Name: user_app_installs user_app_installs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_app_installs
    ADD CONSTRAINT user_app_installs_pkey PRIMARY KEY (id);


--
-- Name: user_app_installs user_app_installs_user_id_app_id_device_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_app_installs
    ADD CONSTRAINT user_app_installs_user_id_app_id_device_id_key UNIQUE (user_id, app_id, device_id);


--
-- Name: user_entitlements user_entitlements_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_entitlements
    ADD CONSTRAINT user_entitlements_pkey PRIMARY KEY (id);


--
-- Name: user_entitlements user_entitlements_user_id_app_id_entitlement_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_entitlements
    ADD CONSTRAINT user_entitlements_user_id_app_id_entitlement_id_key UNIQUE (user_id, app_id, entitlement_id);


--
-- Name: pomodoist_google_calendar_links_event_idx; Type: INDEX; Schema: private; Owner: postgres
--

CREATE INDEX pomodoist_google_calendar_links_event_idx ON private.pomodoist_google_calendar_links USING btree (user_id, event_id, created_at, task_id);


--
-- Name: pomodoist_invites_scope; Type: INDEX; Schema: private; Owner: postgres
--

CREATE INDEX pomodoist_invites_scope ON private.pomodoist_invitations USING btree (scope_id);


--
-- Name: pomodoist_members_user; Type: INDEX; Schema: private; Owner: postgres
--

CREATE INDEX pomodoist_members_user ON private.pomodoist_members USING btree (user_id);


--
-- Name: pomodoist_notifications_user; Type: INDEX; Schema: private; Owner: postgres
--

CREATE INDEX pomodoist_notifications_user ON private.pomodoist_notifications USING btree (user_id, created_at);


--
-- Name: pomodoist_shared_completion_unique; Type: INDEX; Schema: private; Owner: postgres
--

CREATE UNIQUE INDEX pomodoist_shared_completion_unique ON private.pomodoist_shared_entities USING btree (scope_id, ((data ->> 'taskId'::text)), ((data ->> 'completedAt'::text))) WHERE ((entity_type = 'task_completion'::text) AND (deleted_at IS NULL));


--
-- Name: pomodoist_shared_cursor; Type: INDEX; Schema: private; Owner: postgres
--

CREATE INDEX pomodoist_shared_cursor ON private.pomodoist_shared_entities USING btree (scope_id, server_revision);


--
-- Name: pomodoist_shared_focus_unique; Type: INDEX; Schema: private; Owner: postgres
--

CREATE UNIQUE INDEX pomodoist_shared_focus_unique ON private.pomodoist_shared_entities USING btree (scope_id, ((data ->> 'createdBy'::text)), ((data ->> 'startedAt'::text))) WHERE ((entity_type = 'focus_interval'::text) AND (deleted_at IS NULL));


--
-- Name: pomodoist_shared_system_label; Type: INDEX; Schema: private; Owner: postgres
--

CREATE UNIQUE INDEX pomodoist_shared_system_label ON private.pomodoist_shared_entities USING btree (scope_id, ((data ->> 'systemKey'::text))) WHERE ((entity_type = 'label'::text) AND (deleted_at IS NULL) AND ((data ->> 'systemKey'::text) IS NOT NULL));


--
-- Name: pomodoist_stripe_claims_user_idx; Type: INDEX; Schema: private; Owner: postgres
--

CREATE INDEX pomodoist_stripe_claims_user_idx ON private.pomodoist_stripe_claims USING btree (user_id, purchase_type);


--
-- Name: pomodoist_uploads_user; Type: INDEX; Schema: private; Owner: postgres
--

CREATE INDEX pomodoist_uploads_user ON private.pomodoist_uploads USING btree (user_id, finished_at);


--
-- Name: pomodoist_voice_requests_expiry_idx; Type: INDEX; Schema: private; Owner: postgres
--

CREATE INDEX pomodoist_voice_requests_expiry_idx ON private.pomodoist_voice_requests USING btree (expires_at);


--
-- Name: pomodoist_voice_requests_period_idx; Type: INDEX; Schema: private; Owner: postgres
--

CREATE INDEX pomodoist_voice_requests_period_idx ON private.pomodoist_voice_requests USING btree (usage_period_id);


--
-- Name: pomodoist_purchase_claims_linked_user_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX pomodoist_purchase_claims_linked_user_idx ON public.pomodoist_purchase_claims USING btree (linked_user_id) WHERE (linked_user_id IS NOT NULL);


--
-- Name: pomodoist_telegram_link_attempts_expiry_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX pomodoist_telegram_link_attempts_expiry_idx ON public.pomodoist_telegram_link_attempts USING btree (expires_at) WHERE (used_at IS NULL);


--
-- Name: profiles_apple_app_account_token_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX profiles_apple_app_account_token_idx ON public.profiles USING btree (apple_app_account_token);


--
-- Name: sync_entities_pomodoist_task_retention_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX sync_entities_pomodoist_task_retention_idx ON public.sync_entities USING btree (user_id, deleted_at, client_updated_at) WHERE ((app_id = 'pomodoist'::text) AND (entity_type = 'task'::text));


--
-- Name: sync_entities_pull_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX sync_entities_pull_idx ON public.sync_entities USING btree (user_id, app_id, server_revision);


--
-- Name: sync_entities_tombstone_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX sync_entities_tombstone_idx ON public.sync_entities USING btree (deleted_at) WHERE (deleted_at IS NOT NULL);


--
-- Name: sync_operation_receipts_inserted_at_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX sync_operation_receipts_inserted_at_idx ON public.sync_operation_receipts USING btree (inserted_at);


--
-- Name: sync_operations_app_inserted_at_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX sync_operations_app_inserted_at_idx ON public.sync_operations USING btree (app_id, inserted_at);


--
-- Name: sync_operations_user_app_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX sync_operations_user_app_idx ON public.sync_operations USING btree (user_id, app_id, inserted_at DESC);


--
-- Name: usage_periods_purchase_period_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX usage_periods_purchase_period_idx ON public.usage_periods USING btree (purchase_subject, app_id, quota_key, period_start) WHERE (purchase_subject IS NOT NULL);


--
-- Name: usage_periods_user_app_period_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX usage_periods_user_app_period_idx ON public.usage_periods USING btree (user_id, app_id, quota_key, period_start DESC);


--
-- Name: user_entitlements_user_app_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX user_entitlements_user_app_idx ON public.user_entitlements USING btree (user_id, app_id, status);


--
-- Name: pomodoist_members pomodoist_member_deleted; Type: TRIGGER; Schema: private; Owner: postgres
--

CREATE TRIGGER pomodoist_member_deleted AFTER DELETE ON private.pomodoist_members FOR EACH ROW EXECUTE FUNCTION private.pomodoist_member_deleted();


--
-- Name: pomodoist_stripe_claims pomodoist_stripe_claims_touch_updated_at; Type: TRIGGER; Schema: private; Owner: postgres
--

CREATE TRIGGER pomodoist_stripe_claims_touch_updated_at BEFORE UPDATE ON private.pomodoist_stripe_claims FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- Name: pomodoist_stripe_customers pomodoist_stripe_customers_touch_updated_at; Type: TRIGGER; Schema: private; Owner: postgres
--

CREATE TRIGGER pomodoist_stripe_customers_touch_updated_at BEFORE UPDATE ON private.pomodoist_stripe_customers FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- Name: pomodoist_purchase_claims pomodoist_capture_return_offer; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER pomodoist_capture_return_offer AFTER INSERT OR UPDATE ON public.pomodoist_purchase_claims FOR EACH ROW EXECUTE FUNCTION private.capture_pomodoist_return_offer();


--
-- Name: user_entitlements pomodoist_history_entitlement_changed; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER pomodoist_history_entitlement_changed AFTER INSERT OR DELETE OR UPDATE ON public.user_entitlements FOR EACH ROW EXECUTE FUNCTION private.pomodoist_history_entitlement_changed();


--
-- Name: pomodoist_purchase_claims pomodoist_purchase_claims_touch_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER pomodoist_purchase_claims_touch_updated_at BEFORE UPDATE ON public.pomodoist_purchase_claims FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- Name: sync_entities pomodoist_transfer_guard; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER pomodoist_transfer_guard BEFORE INSERT OR UPDATE ON public.sync_entities FOR EACH ROW EXECUTE FUNCTION private.pomodoist_transfer_guard();


--
-- Name: profiles profiles_touch_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER profiles_touch_updated_at BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- Name: quota_definitions quota_definitions_touch_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER quota_definitions_touch_updated_at BEFORE UPDATE ON public.quota_definitions FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- Name: storage_usage storage_usage_touch_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER storage_usage_touch_updated_at BEFORE UPDATE ON public.storage_usage FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- Name: sync_devices sync_devices_touch_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER sync_devices_touch_updated_at BEFORE UPDATE ON public.sync_devices FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- Name: sync_entities sync_entities_pomodoist_google_calendar_queue; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER sync_entities_pomodoist_google_calendar_queue AFTER INSERT OR DELETE OR UPDATE ON public.sync_entities FOR EACH ROW EXECUTE FUNCTION private.on_pomodoist_task_calendar_change();


--
-- Name: sync_entities sync_entities_single_active_pomodoist_focus; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER sync_entities_single_active_pomodoist_focus BEFORE INSERT OR UPDATE ON public.sync_entities FOR EACH ROW WHEN (((new.app_id = 'pomodoist'::text) AND (new.entity_type = 'focus_run'::text))) EXECUTE FUNCTION private.enforce_single_active_pomodoist_focus();


--
-- Name: sync_entities sync_entities_touch_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER sync_entities_touch_updated_at BEFORE UPDATE ON public.sync_entities FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- Name: usage_periods usage_periods_touch_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER usage_periods_touch_updated_at BEFORE UPDATE ON public.usage_periods FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- Name: user_app_installs user_app_installs_touch_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER user_app_installs_touch_updated_at BEFORE UPDATE ON public.user_app_installs FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- Name: user_entitlements user_entitlements_sync_pomodoist_profile_pro; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER user_entitlements_sync_pomodoist_profile_pro AFTER INSERT OR DELETE OR UPDATE ON public.user_entitlements FOR EACH ROW EXECUTE FUNCTION private.sync_pomodoist_profile_pro();


--
-- Name: user_entitlements user_entitlements_touch_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER user_entitlements_touch_updated_at BEFORE UPDATE ON public.user_entitlements FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- Name: pomodoist_google_calendar_accounts pomodoist_google_calendar_accounts_user_id_fkey; Type: FK CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_google_calendar_accounts
    ADD CONSTRAINT pomodoist_google_calendar_accounts_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: pomodoist_google_calendar_jobs pomodoist_google_calendar_jobs_user_id_fkey; Type: FK CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_google_calendar_jobs
    ADD CONSTRAINT pomodoist_google_calendar_jobs_user_id_fkey FOREIGN KEY (user_id) REFERENCES private.pomodoist_google_calendar_accounts(user_id) ON DELETE CASCADE;


--
-- Name: pomodoist_google_calendar_links pomodoist_google_calendar_links_user_id_fkey; Type: FK CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_google_calendar_links
    ADD CONSTRAINT pomodoist_google_calendar_links_user_id_fkey FOREIGN KEY (user_id) REFERENCES private.pomodoist_google_calendar_accounts(user_id) ON DELETE CASCADE;


--
-- Name: pomodoist_google_calendar_oauth_states pomodoist_google_calendar_oauth_states_user_id_fkey; Type: FK CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_google_calendar_oauth_states
    ADD CONSTRAINT pomodoist_google_calendar_oauth_states_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: pomodoist_google_calendar_task_state pomodoist_google_calendar_task_state_user_id_fkey; Type: FK CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_google_calendar_task_state
    ADD CONSTRAINT pomodoist_google_calendar_task_state_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: pomodoist_invitations pomodoist_invitations_scope_id_fkey; Type: FK CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_invitations
    ADD CONSTRAINT pomodoist_invitations_scope_id_fkey FOREIGN KEY (scope_id) REFERENCES private.pomodoist_scopes(id) ON DELETE CASCADE;


--
-- Name: pomodoist_mcp_rate_limits pomodoist_mcp_rate_limits_client_id_fkey; Type: FK CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_mcp_rate_limits
    ADD CONSTRAINT pomodoist_mcp_rate_limits_client_id_fkey FOREIGN KEY (client_id) REFERENCES auth.oauth_clients(id) ON DELETE CASCADE;


--
-- Name: pomodoist_mcp_rate_limits pomodoist_mcp_rate_limits_user_id_fkey; Type: FK CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_mcp_rate_limits
    ADD CONSTRAINT pomodoist_mcp_rate_limits_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: pomodoist_members pomodoist_members_scope_id_fkey; Type: FK CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_members
    ADD CONSTRAINT pomodoist_members_scope_id_fkey FOREIGN KEY (scope_id) REFERENCES private.pomodoist_scopes(id) ON DELETE CASCADE;


--
-- Name: pomodoist_members pomodoist_members_user_id_fkey; Type: FK CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_members
    ADD CONSTRAINT pomodoist_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: pomodoist_notifications pomodoist_notifications_scope_id_fkey; Type: FK CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_notifications
    ADD CONSTRAINT pomodoist_notifications_scope_id_fkey FOREIGN KEY (scope_id) REFERENCES private.pomodoist_scopes(id) ON DELETE CASCADE;


--
-- Name: pomodoist_notifications pomodoist_notifications_user_id_fkey; Type: FK CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_notifications
    ADD CONSTRAINT pomodoist_notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: pomodoist_openclaw_receipts pomodoist_openclaw_receipts_client_id_fkey; Type: FK CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_openclaw_receipts
    ADD CONSTRAINT pomodoist_openclaw_receipts_client_id_fkey FOREIGN KEY (client_id) REFERENCES auth.oauth_clients(id) ON DELETE CASCADE;


--
-- Name: pomodoist_openclaw_receipts pomodoist_openclaw_receipts_user_id_fkey; Type: FK CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_openclaw_receipts
    ADD CONSTRAINT pomodoist_openclaw_receipts_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: pomodoist_personal_history pomodoist_personal_history_user_id_fkey; Type: FK CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_personal_history
    ADD CONSTRAINT pomodoist_personal_history_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: pomodoist_recurrence_successors pomodoist_recurrence_successors_scope_id_fkey; Type: FK CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_recurrence_successors
    ADD CONSTRAINT pomodoist_recurrence_successors_scope_id_fkey FOREIGN KEY (scope_id) REFERENCES private.pomodoist_scopes(id) ON DELETE CASCADE;


--
-- Name: pomodoist_scopes pomodoist_scopes_owner_id_fkey; Type: FK CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_scopes
    ADD CONSTRAINT pomodoist_scopes_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES auth.users(id) ON DELETE RESTRICT;


--
-- Name: pomodoist_shared_entities pomodoist_shared_entities_scope_id_fkey; Type: FK CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_shared_entities
    ADD CONSTRAINT pomodoist_shared_entities_scope_id_fkey FOREIGN KEY (scope_id) REFERENCES private.pomodoist_scopes(id) ON DELETE CASCADE;


--
-- Name: pomodoist_shared_preferences pomodoist_shared_preferences_scope_id_user_id_fkey; Type: FK CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_shared_preferences
    ADD CONSTRAINT pomodoist_shared_preferences_scope_id_user_id_fkey FOREIGN KEY (scope_id, user_id) REFERENCES private.pomodoist_members(scope_id, user_id) ON DELETE CASCADE;


--
-- Name: pomodoist_shared_receipts pomodoist_shared_receipts_scope_id_fkey; Type: FK CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_shared_receipts
    ADD CONSTRAINT pomodoist_shared_receipts_scope_id_fkey FOREIGN KEY (scope_id) REFERENCES private.pomodoist_scopes(id) ON DELETE CASCADE;


--
-- Name: pomodoist_uploads pomodoist_uploads_scope_id_fkey; Type: FK CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_uploads
    ADD CONSTRAINT pomodoist_uploads_scope_id_fkey FOREIGN KEY (scope_id) REFERENCES private.pomodoist_scopes(id) ON DELETE CASCADE;


--
-- Name: pomodoist_voice_requests pomodoist_voice_requests_usage_period_id_fkey; Type: FK CONSTRAINT; Schema: private; Owner: postgres
--

ALTER TABLE ONLY private.pomodoist_voice_requests
    ADD CONSTRAINT pomodoist_voice_requests_usage_period_id_fkey FOREIGN KEY (usage_period_id) REFERENCES public.usage_periods(id) ON DELETE CASCADE;


--
-- Name: pomodoist_telegram_accounts pomodoist_telegram_accounts_guest_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pomodoist_telegram_accounts
    ADD CONSTRAINT pomodoist_telegram_accounts_guest_user_id_fkey FOREIGN KEY (guest_user_id) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: pomodoist_telegram_accounts pomodoist_telegram_accounts_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pomodoist_telegram_accounts
    ADD CONSTRAINT pomodoist_telegram_accounts_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: pomodoist_telegram_link_attempts pomodoist_telegram_link_attempts_telegram_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pomodoist_telegram_link_attempts
    ADD CONSTRAINT pomodoist_telegram_link_attempts_telegram_user_id_fkey FOREIGN KEY (telegram_user_id) REFERENCES public.pomodoist_telegram_accounts(telegram_user_id) ON DELETE CASCADE;


--
-- Name: products products_app_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_app_id_fkey FOREIGN KEY (app_id) REFERENCES public.apps(id) ON DELETE CASCADE;


--
-- Name: profiles profiles_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: quota_definitions quota_definitions_app_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.quota_definitions
    ADD CONSTRAINT quota_definitions_app_id_fkey FOREIGN KEY (app_id) REFERENCES public.apps(id) ON DELETE CASCADE;


--
-- Name: storage_usage storage_usage_app_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.storage_usage
    ADD CONSTRAINT storage_usage_app_id_fkey FOREIGN KEY (app_id) REFERENCES public.apps(id) ON DELETE CASCADE;


--
-- Name: storage_usage storage_usage_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.storage_usage
    ADD CONSTRAINT storage_usage_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: sync_devices sync_devices_app_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sync_devices
    ADD CONSTRAINT sync_devices_app_id_fkey FOREIGN KEY (app_id) REFERENCES public.apps(id) ON DELETE CASCADE;


--
-- Name: sync_devices sync_devices_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sync_devices
    ADD CONSTRAINT sync_devices_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: sync_entities sync_entities_app_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sync_entities
    ADD CONSTRAINT sync_entities_app_id_fkey FOREIGN KEY (app_id) REFERENCES public.apps(id) ON DELETE CASCADE;


--
-- Name: sync_entities sync_entities_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sync_entities
    ADD CONSTRAINT sync_entities_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: sync_operation_receipts sync_operation_receipts_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sync_operation_receipts
    ADD CONSTRAINT sync_operation_receipts_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: sync_operations sync_operations_app_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sync_operations
    ADD CONSTRAINT sync_operations_app_id_fkey FOREIGN KEY (app_id) REFERENCES public.apps(id) ON DELETE CASCADE;


--
-- Name: sync_operations sync_operations_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sync_operations
    ADD CONSTRAINT sync_operations_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: usage_periods usage_periods_app_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.usage_periods
    ADD CONSTRAINT usage_periods_app_id_fkey FOREIGN KEY (app_id) REFERENCES public.apps(id) ON DELETE CASCADE;


--
-- Name: usage_periods usage_periods_quota_definition_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.usage_periods
    ADD CONSTRAINT usage_periods_quota_definition_fkey FOREIGN KEY (app_id, quota_key) REFERENCES public.quota_definitions(app_id, quota_key);


--
-- Name: usage_periods usage_periods_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.usage_periods
    ADD CONSTRAINT usage_periods_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: user_app_installs user_app_installs_app_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_app_installs
    ADD CONSTRAINT user_app_installs_app_id_fkey FOREIGN KEY (app_id) REFERENCES public.apps(id) ON DELETE CASCADE;


--
-- Name: user_app_installs user_app_installs_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_app_installs
    ADD CONSTRAINT user_app_installs_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: user_entitlements user_entitlements_app_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_entitlements
    ADD CONSTRAINT user_entitlements_app_id_fkey FOREIGN KEY (app_id) REFERENCES public.apps(id) ON DELETE CASCADE;


--
-- Name: user_entitlements user_entitlements_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_entitlements
    ADD CONSTRAINT user_entitlements_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: pomodoist_google_calendar_accounts; Type: ROW SECURITY; Schema: private; Owner: postgres
--

ALTER TABLE private.pomodoist_google_calendar_accounts ENABLE ROW LEVEL SECURITY;

--
-- Name: pomodoist_google_calendar_jobs; Type: ROW SECURITY; Schema: private; Owner: postgres
--

ALTER TABLE private.pomodoist_google_calendar_jobs ENABLE ROW LEVEL SECURITY;

--
-- Name: pomodoist_google_calendar_links; Type: ROW SECURITY; Schema: private; Owner: postgres
--

ALTER TABLE private.pomodoist_google_calendar_links ENABLE ROW LEVEL SECURITY;

--
-- Name: pomodoist_google_calendar_oauth_states; Type: ROW SECURITY; Schema: private; Owner: postgres
--

ALTER TABLE private.pomodoist_google_calendar_oauth_states ENABLE ROW LEVEL SECURITY;

--
-- Name: pomodoist_google_calendar_task_state; Type: ROW SECURITY; Schema: private; Owner: postgres
--

ALTER TABLE private.pomodoist_google_calendar_task_state ENABLE ROW LEVEL SECURITY;

--
-- Name: pomodoist_instance_settings; Type: ROW SECURITY; Schema: private; Owner: postgres
--

ALTER TABLE private.pomodoist_instance_settings ENABLE ROW LEVEL SECURITY;

--
-- Name: pomodoist_invitations; Type: ROW SECURITY; Schema: private; Owner: postgres
--

ALTER TABLE private.pomodoist_invitations ENABLE ROW LEVEL SECURITY;

--
-- Name: pomodoist_mcp_rate_limits; Type: ROW SECURITY; Schema: private; Owner: postgres
--

ALTER TABLE private.pomodoist_mcp_rate_limits ENABLE ROW LEVEL SECURITY;

--
-- Name: pomodoist_members; Type: ROW SECURITY; Schema: private; Owner: postgres
--

ALTER TABLE private.pomodoist_members ENABLE ROW LEVEL SECURITY;

--
-- Name: pomodoist_notifications; Type: ROW SECURITY; Schema: private; Owner: postgres
--

ALTER TABLE private.pomodoist_notifications ENABLE ROW LEVEL SECURITY;

--
-- Name: pomodoist_openclaw_receipts; Type: ROW SECURITY; Schema: private; Owner: postgres
--

ALTER TABLE private.pomodoist_openclaw_receipts ENABLE ROW LEVEL SECURITY;

--
-- Name: pomodoist_personal_history; Type: ROW SECURITY; Schema: private; Owner: postgres
--

ALTER TABLE private.pomodoist_personal_history ENABLE ROW LEVEL SECURITY;

--
-- Name: pomodoist_recurrence_successors; Type: ROW SECURITY; Schema: private; Owner: postgres
--

ALTER TABLE private.pomodoist_recurrence_successors ENABLE ROW LEVEL SECURITY;

--
-- Name: pomodoist_scopes; Type: ROW SECURITY; Schema: private; Owner: postgres
--

ALTER TABLE private.pomodoist_scopes ENABLE ROW LEVEL SECURITY;

--
-- Name: pomodoist_shared_entities; Type: ROW SECURITY; Schema: private; Owner: postgres
--

ALTER TABLE private.pomodoist_shared_entities ENABLE ROW LEVEL SECURITY;

--
-- Name: pomodoist_shared_preferences; Type: ROW SECURITY; Schema: private; Owner: postgres
--

ALTER TABLE private.pomodoist_shared_preferences ENABLE ROW LEVEL SECURITY;

--
-- Name: pomodoist_shared_receipts; Type: ROW SECURITY; Schema: private; Owner: postgres
--

ALTER TABLE private.pomodoist_shared_receipts ENABLE ROW LEVEL SECURITY;

--
-- Name: pomodoist_storage_deletions; Type: ROW SECURITY; Schema: private; Owner: postgres
--

ALTER TABLE private.pomodoist_storage_deletions ENABLE ROW LEVEL SECURITY;

--
-- Name: pomodoist_stripe_claims; Type: ROW SECURITY; Schema: private; Owner: postgres
--

ALTER TABLE private.pomodoist_stripe_claims ENABLE ROW LEVEL SECURITY;

--
-- Name: pomodoist_stripe_customers; Type: ROW SECURITY; Schema: private; Owner: postgres
--

ALTER TABLE private.pomodoist_stripe_customers ENABLE ROW LEVEL SECURITY;

--
-- Name: pomodoist_stripe_events; Type: ROW SECURITY; Schema: private; Owner: postgres
--

ALTER TABLE private.pomodoist_stripe_events ENABLE ROW LEVEL SECURITY;

--
-- Name: pomodoist_subscription_offers; Type: ROW SECURITY; Schema: private; Owner: postgres
--

ALTER TABLE private.pomodoist_subscription_offers ENABLE ROW LEVEL SECURITY;

--
-- Name: pomodoist_transferred_entities; Type: ROW SECURITY; Schema: private; Owner: postgres
--

ALTER TABLE private.pomodoist_transferred_entities ENABLE ROW LEVEL SECURITY;

--
-- Name: pomodoist_upload_months; Type: ROW SECURITY; Schema: private; Owner: postgres
--

ALTER TABLE private.pomodoist_upload_months ENABLE ROW LEVEL SECURITY;

--
-- Name: pomodoist_upload_years; Type: ROW SECURITY; Schema: private; Owner: postgres
--

ALTER TABLE private.pomodoist_upload_years ENABLE ROW LEVEL SECURITY;

--
-- Name: pomodoist_uploads; Type: ROW SECURITY; Schema: private; Owner: postgres
--

ALTER TABLE private.pomodoist_uploads ENABLE ROW LEVEL SECURITY;

--
-- Name: pomodoist_voice_requests; Type: ROW SECURITY; Schema: private; Owner: postgres
--

ALTER TABLE private.pomodoist_voice_requests ENABLE ROW LEVEL SECURITY;

--
-- Name: apps Authenticated users can read app catalog; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Authenticated users can read app catalog" ON public.apps FOR SELECT TO authenticated USING (true);


--
-- Name: products Authenticated users can read product catalog; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Authenticated users can read product catalog" ON public.products FOR SELECT TO authenticated USING (true);


--
-- Name: quota_definitions Authenticated users can read quota definitions; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Authenticated users can read quota definitions" ON public.quota_definitions FOR SELECT TO authenticated USING (true);


--
-- Name: user_app_installs Users can insert own app installs; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can insert own app installs" ON public.user_app_installs FOR INSERT TO authenticated WITH CHECK ((( SELECT auth.uid() AS uid) = user_id));


--
-- Name: sync_devices Users can insert own sync devices; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can insert own sync devices" ON public.sync_devices FOR INSERT TO authenticated WITH CHECK ((( SELECT auth.uid() AS uid) = user_id));


--
-- Name: user_app_installs Users can read own app installs; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can read own app installs" ON public.user_app_installs FOR SELECT TO authenticated USING ((( SELECT auth.uid() AS uid) = user_id));


--
-- Name: user_entitlements Users can read own entitlements; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can read own entitlements" ON public.user_entitlements FOR SELECT TO authenticated USING ((( SELECT auth.uid() AS uid) = user_id));


--
-- Name: profiles Users can read own profile; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can read own profile" ON public.profiles FOR SELECT TO authenticated USING ((( SELECT auth.uid() AS uid) = id));


--
-- Name: storage_usage Users can read own storage usage; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can read own storage usage" ON public.storage_usage FOR SELECT TO authenticated USING ((auth.uid() = user_id));


--
-- Name: sync_devices Users can read own sync devices; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can read own sync devices" ON public.sync_devices FOR SELECT TO authenticated USING ((( SELECT auth.uid() AS uid) = user_id));


--
-- Name: sync_entities Users can read own sync entities; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can read own sync entities" ON public.sync_entities FOR SELECT TO authenticated USING ((( SELECT auth.uid() AS uid) = user_id));


--
-- Name: sync_operations Users can read own sync operations; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can read own sync operations" ON public.sync_operations FOR SELECT TO authenticated USING ((auth.uid() = user_id));


--
-- Name: usage_periods Users can read own usage; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can read own usage" ON public.usage_periods FOR SELECT TO authenticated USING ((( SELECT auth.uid() AS uid) = user_id));


--
-- Name: user_app_installs Users can update own app installs; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can update own app installs" ON public.user_app_installs FOR UPDATE TO authenticated USING ((( SELECT auth.uid() AS uid) = user_id)) WITH CHECK ((( SELECT auth.uid() AS uid) = user_id));


--
-- Name: profiles Users can update own profile; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can update own profile" ON public.profiles FOR UPDATE TO authenticated USING ((( SELECT auth.uid() AS uid) = id)) WITH CHECK ((( SELECT auth.uid() AS uid) = id));


--
-- Name: sync_devices Users can update own sync devices; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can update own sync devices" ON public.sync_devices FOR UPDATE TO authenticated USING ((( SELECT auth.uid() AS uid) = user_id)) WITH CHECK ((( SELECT auth.uid() AS uid) = user_id));


--
-- Name: apps; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.apps ENABLE ROW LEVEL SECURITY;

--
-- Name: pomodoist_purchase_claims; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.pomodoist_purchase_claims ENABLE ROW LEVEL SECURITY;

--
-- Name: pomodoist_telegram_accounts; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.pomodoist_telegram_accounts ENABLE ROW LEVEL SECURITY;

--
-- Name: pomodoist_telegram_link_attempts; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.pomodoist_telegram_link_attempts ENABLE ROW LEVEL SECURITY;

--
-- Name: products; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

--
-- Name: profiles; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

--
-- Name: quota_definitions; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.quota_definitions ENABLE ROW LEVEL SECURITY;

--
-- Name: storage_usage; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.storage_usage ENABLE ROW LEVEL SECURITY;

--
-- Name: sync_devices; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.sync_devices ENABLE ROW LEVEL SECURITY;

--
-- Name: sync_entities; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.sync_entities ENABLE ROW LEVEL SECURITY;

--
-- Name: sync_maintenance_runs; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.sync_maintenance_runs ENABLE ROW LEVEL SECURITY;

--
-- Name: sync_operation_receipts; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.sync_operation_receipts ENABLE ROW LEVEL SECURITY;

--
-- Name: sync_operations; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.sync_operations ENABLE ROW LEVEL SECURITY;

--
-- Name: usage_periods; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.usage_periods ENABLE ROW LEVEL SECURITY;

--
-- Name: user_app_installs; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.user_app_installs ENABLE ROW LEVEL SECURITY;

--
-- Name: user_entitlements; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.user_entitlements ENABLE ROW LEVEL SECURITY;

--
-- Name: SCHEMA private; Type: ACL; Schema: -; Owner: postgres
--

revoke all on all tables in schema public,private from public,anon,authenticated,service_role;
revoke all on all functions in schema public,private from public,anon,authenticated,service_role;
revoke all on all sequences in schema public,private from public,anon,authenticated,service_role;
GRANT USAGE ON SCHEMA private TO supabase_auth_admin;
GRANT USAGE ON SCHEMA private TO service_role;
GRANT USAGE ON SCHEMA private TO authenticated;


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: pg_database_owner
--

REVOKE USAGE ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO postgres;
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;


--
-- Name: FUNCTION additional_account_overview(p_user_id uuid, p_app_id text); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.additional_account_overview(p_user_id uuid, p_app_id text) FROM PUBLIC;


--
-- Name: FUNCTION capture_pomodoist_return_offer(); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.capture_pomodoist_return_offer() FROM PUBLIC;
GRANT ALL ON FUNCTION private.capture_pomodoist_return_offer() TO service_role;


--
-- Name: FUNCTION consume_quota(p_app_id text, p_quota_key text, p_units integer, p_period_start timestamp with time zone, p_period_end timestamp with time zone); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.consume_quota(p_app_id text, p_quota_key text, p_units integer, p_period_start timestamp with time zone, p_period_end timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION private.consume_quota(p_app_id text, p_quota_key text, p_units integer, p_period_start timestamp with time zone, p_period_end timestamp with time zone) TO authenticated;
GRANT ALL ON FUNCTION private.consume_quota(p_app_id text, p_quota_key text, p_units integer, p_period_start timestamp with time zone, p_period_end timestamp with time zone) TO service_role;


--
-- Name: FUNCTION enforce_single_active_pomodoist_focus(); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.enforce_single_active_pomodoist_focus() FROM PUBLIC;


--
-- Name: FUNCTION ensure_profile(); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.ensure_profile() FROM PUBLIC;
GRANT ALL ON FUNCTION private.ensure_profile() TO authenticated;
GRANT ALL ON FUNCTION private.ensure_profile() TO service_role;


--
-- Name: FUNCTION get_account_overview(); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.get_account_overview() FROM PUBLIC;
GRANT ALL ON FUNCTION private.get_account_overview() TO authenticated;
GRANT ALL ON FUNCTION private.get_account_overview() TO service_role;


--
-- Name: FUNCTION get_apple_app_account_token(); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.get_apple_app_account_token() FROM PUBLIC;
GRANT ALL ON FUNCTION private.get_apple_app_account_token() TO authenticated;
GRANT ALL ON FUNCTION private.get_apple_app_account_token() TO service_role;


--
-- Name: FUNCTION get_usage_period(p_app_id text, p_quota_key text, p_period_start timestamp with time zone, p_period_end timestamp with time zone); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.get_usage_period(p_app_id text, p_quota_key text, p_period_start timestamp with time zone, p_period_end timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION private.get_usage_period(p_app_id text, p_quota_key text, p_period_start timestamp with time zone, p_period_end timestamp with time zone) TO authenticated;
GRANT ALL ON FUNCTION private.get_usage_period(p_app_id text, p_quota_key text, p_period_start timestamp with time zone, p_period_end timestamp with time zone) TO service_role;


--
-- Name: FUNCTION grant_pomodoist_selfhost_access(p_user_id uuid); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.grant_pomodoist_selfhost_access(p_user_id uuid) FROM PUBLIC;


--
-- Name: FUNCTION initialize_additional_account(p_user_id uuid); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.initialize_additional_account(p_user_id uuid) FROM PUBLIC;


--
-- Name: FUNCTION invoke_pomodoist_google_calendar_worker(); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.invoke_pomodoist_google_calendar_worker() FROM PUBLIC;


--
-- Name: FUNCTION on_pomodoist_task_calendar_change(); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.on_pomodoist_task_calendar_change() FROM PUBLIC;


--
-- Name: FUNCTION pomodoist_account_deletion_check(p_user_id uuid); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.pomodoist_account_deletion_check(p_user_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION private.pomodoist_account_deletion_check(p_user_id uuid) TO service_role;


--
-- Name: FUNCTION pomodoist_collaboration(p_request jsonb); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.pomodoist_collaboration(p_request jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION private.pomodoist_collaboration(p_request jsonb) TO authenticated;
GRANT ALL ON FUNCTION private.pomodoist_collaboration(p_request jsonb) TO service_role;


--
-- Name: FUNCTION pomodoist_collaboration_event(p_scope uuid, p_actor uuid, p_kind text, p_entity text, p_data jsonb); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.pomodoist_collaboration_event(p_scope uuid, p_actor uuid, p_kind text, p_entity text, p_data jsonb) FROM PUBLIC;


--
-- Name: FUNCTION pomodoist_collaboration_hint(p_scope uuid, p_user uuid); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.pomodoist_collaboration_hint(p_scope uuid, p_user uuid) FROM PUBLIC;


--
-- Name: FUNCTION pomodoist_collaboration_mcp(p_subject uuid, p_session_id uuid, p_client_id uuid, p_request jsonb); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.pomodoist_collaboration_mcp(p_subject uuid, p_session_id uuid, p_client_id uuid, p_request jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION private.pomodoist_collaboration_mcp(p_subject uuid, p_session_id uuid, p_client_id uuid, p_request jsonb) TO service_role;


--
-- Name: FUNCTION pomodoist_collaboration_storage_cleanup(p_deleted text[]); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.pomodoist_collaboration_storage_cleanup(p_deleted text[]) FROM PUBLIC;
GRANT ALL ON FUNCTION private.pomodoist_collaboration_storage_cleanup(p_deleted text[]) TO service_role;


--
-- Name: FUNCTION pomodoist_google_calendar_service_unchecked(p_action text, p_user_id uuid, p_payload jsonb); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.pomodoist_google_calendar_service_unchecked(p_action text, p_user_id uuid, p_payload jsonb) FROM PUBLIC;


--
-- Name: FUNCTION pomodoist_history_entitlement_changed(); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.pomodoist_history_entitlement_changed() FROM PUBLIC;


--
-- Name: FUNCTION pomodoist_history_refresh(p_scope uuid, p_user uuid); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.pomodoist_history_refresh(p_scope uuid, p_user uuid) FROM PUBLIC;


--
-- Name: FUNCTION pomodoist_history_timestamp(p_value text, p_fallback timestamp with time zone); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.pomodoist_history_timestamp(p_value text, p_fallback timestamp with time zone) FROM PUBLIC;


--
-- Name: FUNCTION pomodoist_mcp_access_token_hook(event jsonb); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.pomodoist_mcp_access_token_hook(event jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION private.pomodoist_mcp_access_token_hook(event jsonb) TO supabase_auth_admin;


--
-- Name: FUNCTION pomodoist_mcp_audience(p_issuer text); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.pomodoist_mcp_audience(p_issuer text) FROM PUBLIC;
GRANT ALL ON FUNCTION private.pomodoist_mcp_audience(p_issuer text) TO supabase_auth_admin;


--
-- Name: FUNCTION pomodoist_mcp_finite_timestamptz(p_value text); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.pomodoist_mcp_finite_timestamptz(p_value text) FROM PUBLIC;


--
-- Name: FUNCTION pomodoist_mcp_json_array(p_value text); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.pomodoist_mcp_json_array(p_value text) FROM PUBLIC;


--
-- Name: FUNCTION pomodoist_mcp_mutation_snapshot(p_user_id uuid); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.pomodoist_mcp_mutation_snapshot(p_user_id uuid) FROM PUBLIC;


--
-- Name: FUNCTION pomodoist_mcp_productivity_metrics(p_user_id uuid, p_report_date date, p_time_zone text); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.pomodoist_mcp_productivity_metrics(p_user_id uuid, p_report_date date, p_time_zone text) FROM PUBLIC;


--
-- Name: FUNCTION pomodoist_mcp_schedule_date(p_due_json text, p_time_zone text); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.pomodoist_mcp_schedule_date(p_due_json text, p_time_zone text) FROM PUBLIC;


--
-- Name: FUNCTION pomodoist_mcp_subject(p_user_id uuid, p_client_id uuid); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.pomodoist_mcp_subject(p_user_id uuid, p_client_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION private.pomodoist_mcp_subject(p_user_id uuid, p_client_id uuid) TO supabase_auth_admin;


--
-- Name: FUNCTION pomodoist_mcp_task_json(p_id text, p_data jsonb); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.pomodoist_mcp_task_json(p_id text, p_data jsonb) FROM PUBLIC;


--
-- Name: FUNCTION pomodoist_member_deleted(); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.pomodoist_member_deleted() FROM PUBLIC;


--
-- Name: FUNCTION pomodoist_members_json(p_scope uuid); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.pomodoist_members_json(p_scope uuid) FROM PUBLIC;


--
-- Name: FUNCTION pomodoist_preferences_json(p_user uuid, p_scope uuid); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.pomodoist_preferences_json(p_user uuid, p_scope uuid) FROM PUBLIC;


--
-- Name: FUNCTION pomodoist_scope_json(p_scope uuid, p_user uuid); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.pomodoist_scope_json(p_scope uuid, p_user uuid) FROM PUBLIC;


--
-- Name: FUNCTION pomodoist_shared_apply(p_scope uuid, p_actor uuid, p_role text, p_op jsonb); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.pomodoist_shared_apply(p_scope uuid, p_actor uuid, p_role text, p_op jsonb) FROM PUBLIC;


--
-- Name: FUNCTION pomodoist_shared_put(p_scope uuid, p_type text, p_id text, p_data jsonb, p_deleted timestamp with time zone); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.pomodoist_shared_put(p_scope uuid, p_type text, p_id text, p_data jsonb, p_deleted timestamp with time zone) FROM PUBLIC;


--
-- Name: FUNCTION pomodoist_transfer_guard(); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.pomodoist_transfer_guard() FROM PUBLIC;


--
-- Name: FUNCTION project_pomodoist_google_calendar_connection(p_user_id uuid); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.project_pomodoist_google_calendar_connection(p_user_id uuid) FROM PUBLIC;


--
-- Name: FUNCTION pull_changes(p_app_id text, p_device_id text, p_since_revision bigint, p_limit integer); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.pull_changes(p_app_id text, p_device_id text, p_since_revision bigint, p_limit integer) FROM PUBLIC;
GRANT ALL ON FUNCTION private.pull_changes(p_app_id text, p_device_id text, p_since_revision bigint, p_limit integer) TO authenticated;
GRANT ALL ON FUNCTION private.pull_changes(p_app_id text, p_device_id text, p_since_revision bigint, p_limit integer) TO service_role;


--
-- Name: FUNCTION push_changes(p_app_id text, p_device_id text, p_operations jsonb); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.push_changes(p_app_id text, p_device_id text, p_operations jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION private.push_changes(p_app_id text, p_device_id text, p_operations jsonb) TO authenticated;
GRANT ALL ON FUNCTION private.push_changes(p_app_id text, p_device_id text, p_operations jsonb) TO service_role;


--
-- Name: FUNCTION push_changes_for_user(p_user_id uuid, p_app_id text, p_device_id text, p_operations jsonb); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.push_changes_for_user(p_user_id uuid, p_app_id text, p_device_id text, p_operations jsonb) FROM PUBLIC;


--
-- Name: FUNCTION queue_pomodoist_google_calendar(p_user_id uuid, p_due_at timestamp with time zone); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.queue_pomodoist_google_calendar(p_user_id uuid, p_due_at timestamp with time zone) FROM PUBLIC;


--
-- Name: FUNCTION read_pomodoist_mcp_v1(p_user_id uuid, p_operation text, p_arguments jsonb); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.read_pomodoist_mcp_v1(p_user_id uuid, p_operation text, p_arguments jsonb) FROM PUBLIC;


--
-- Name: FUNCTION reconcile_pomodoist_profile_pro(); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.reconcile_pomodoist_profile_pro() FROM PUBLIC;


--
-- Name: FUNCTION refresh_pomodoist_profile_pro(p_user_id uuid); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.refresh_pomodoist_profile_pro(p_user_id uuid) FROM PUBLIC;


--
-- Name: FUNCTION sync_pomodoist_profile_pro(); Type: ACL; Schema: private; Owner: postgres
--

REVOKE ALL ON FUNCTION private.sync_pomodoist_profile_pro() FROM PUBLIC;


--
-- Name: FUNCTION begin_pomodoist_telegram_link(p_telegram_user_id bigint, p_token_hash bytea, p_expires_at timestamp with time zone); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.begin_pomodoist_telegram_link(p_telegram_user_id bigint, p_token_hash bytea, p_expires_at timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION public.begin_pomodoist_telegram_link(p_telegram_user_id bigint, p_token_hash bytea, p_expires_at timestamp with time zone) TO service_role;


--
-- Name: FUNCTION bootstrap_pomodoist_telegram(p_telegram_user_id bigint, p_guest_user_id uuid, p_client_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.bootstrap_pomodoist_telegram(p_telegram_user_id bigint, p_guest_user_id uuid, p_client_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.bootstrap_pomodoist_telegram(p_telegram_user_id bigint, p_guest_user_id uuid, p_client_id uuid) TO service_role;


--
-- Name: FUNCTION complete_pomodoist_telegram_link(p_token_hash bytea, p_target_user_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.complete_pomodoist_telegram_link(p_token_hash bytea, p_target_user_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.complete_pomodoist_telegram_link(p_token_hash bytea, p_target_user_id uuid) TO service_role;


--
-- Name: FUNCTION consume_pomodoist_mcp_rate_limit(p_user_id uuid, p_client_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.consume_pomodoist_mcp_rate_limit(p_user_id uuid, p_client_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.consume_pomodoist_mcp_rate_limit(p_user_id uuid, p_client_id uuid) TO service_role;


--
-- Name: FUNCTION consume_quota(p_app_id text, p_quota_key text, p_units integer, p_period_start timestamp with time zone, p_period_end timestamp with time zone); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.consume_quota(p_app_id text, p_quota_key text, p_units integer, p_period_start timestamp with time zone, p_period_end timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION public.consume_quota(p_app_id text, p_quota_key text, p_units integer, p_period_start timestamp with time zone, p_period_end timestamp with time zone) TO authenticated;
GRANT ALL ON FUNCTION public.consume_quota(p_app_id text, p_quota_key text, p_units integer, p_period_start timestamp with time zone, p_period_end timestamp with time zone) TO service_role;


--
-- Name: FUNCTION ensure_profile(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.ensure_profile() FROM PUBLIC;
GRANT ALL ON FUNCTION public.ensure_profile() TO authenticated;
GRANT ALL ON FUNCTION public.ensure_profile() TO service_role;


--
-- Name: FUNCTION get_account_overview(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.get_account_overview() FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_account_overview() TO authenticated;
GRANT ALL ON FUNCTION public.get_account_overview() TO service_role;


--
-- Name: FUNCTION get_apple_app_account_token(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.get_apple_app_account_token() FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_apple_app_account_token() TO authenticated;
GRANT ALL ON FUNCTION public.get_apple_app_account_token() TO service_role;


--
-- Name: FUNCTION get_usage_period(p_app_id text, p_quota_key text, p_period_start timestamp with time zone, p_period_end timestamp with time zone); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.get_usage_period(p_app_id text, p_quota_key text, p_period_start timestamp with time zone, p_period_end timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_usage_period(p_app_id text, p_quota_key text, p_period_start timestamp with time zone, p_period_end timestamp with time zone) TO authenticated;
GRANT ALL ON FUNCTION public.get_usage_period(p_app_id text, p_quota_key text, p_period_start timestamp with time zone, p_period_end timestamp with time zone) TO service_role;


--
-- Name: FUNCTION handle_new_user(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC;


--
-- Name: FUNCTION has_active_pomodoist_paid_entitlement(p_user_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.has_active_pomodoist_paid_entitlement(p_user_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.has_active_pomodoist_paid_entitlement(p_user_id uuid) TO service_role;


--
-- Name: FUNCTION link_pomodoist_stripe_customer(p_user_id uuid, p_stripe_customer_id text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.link_pomodoist_stripe_customer(p_user_id uuid, p_stripe_customer_id text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.link_pomodoist_stripe_customer(p_user_id uuid, p_stripe_customer_id text) TO service_role;


--
-- Name: FUNCTION pomodoist_account_deletion_check(p_user_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.pomodoist_account_deletion_check(p_user_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.pomodoist_account_deletion_check(p_user_id uuid) TO service_role;


--
-- Name: FUNCTION pomodoist_collaboration(p_request jsonb); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.pomodoist_collaboration(p_request jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.pomodoist_collaboration(p_request jsonb) TO service_role;
GRANT ALL ON FUNCTION public.pomodoist_collaboration(p_request jsonb) TO authenticated;


--
-- Name: FUNCTION pomodoist_collaboration_mcp(p_subject uuid, p_session_id uuid, p_client_id uuid, p_request jsonb); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.pomodoist_collaboration_mcp(p_subject uuid, p_session_id uuid, p_client_id uuid, p_request jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.pomodoist_collaboration_mcp(p_subject uuid, p_session_id uuid, p_client_id uuid, p_request jsonb) TO service_role;


--
-- Name: FUNCTION pomodoist_collaboration_storage_cleanup(p_deleted text[]); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.pomodoist_collaboration_storage_cleanup(p_deleted text[]) FROM PUBLIC;
GRANT ALL ON FUNCTION public.pomodoist_collaboration_storage_cleanup(p_deleted text[]) TO service_role;


--
-- Name: FUNCTION pomodoist_google_calendar_service(p_action text, p_user_id uuid, p_payload jsonb); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.pomodoist_google_calendar_service(p_action text, p_user_id uuid, p_payload jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.pomodoist_google_calendar_service(p_action text, p_user_id uuid, p_payload jsonb) TO service_role;


--
-- Name: FUNCTION pomodoist_llm_quota(p_user_id uuid, p_purchase_subject text, p_request_id uuid, p_action text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.pomodoist_llm_quota(p_user_id uuid, p_purchase_subject text, p_request_id uuid, p_action text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.pomodoist_llm_quota(p_user_id uuid, p_purchase_subject text, p_request_id uuid, p_action text) TO service_role;


--
-- Name: FUNCTION pomodoist_openclaw_action(p_subject uuid, p_session_id uuid, p_client_id uuid, p_request_id uuid, p_action text, p_arguments_hash text, p_expected_revision bigint, p_operations jsonb, p_result jsonb); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.pomodoist_openclaw_action(p_subject uuid, p_session_id uuid, p_client_id uuid, p_request_id uuid, p_action text, p_arguments_hash text, p_expected_revision bigint, p_operations jsonb, p_result jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.pomodoist_openclaw_action(p_subject uuid, p_session_id uuid, p_client_id uuid, p_request_id uuid, p_action text, p_arguments_hash text, p_expected_revision bigint, p_operations jsonb, p_result jsonb) TO service_role;


--
-- Name: FUNCTION pomodoist_stripe_checkout_context(p_user_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.pomodoist_stripe_checkout_context(p_user_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.pomodoist_stripe_checkout_context(p_user_id uuid) TO service_role;


--
-- Name: FUNCTION pomodoist_subscription_offer_state(p_environment text, p_app_transaction_id text, p_campaign_id text, p_original_transaction_ids text[], p_user_id uuid, p_redeemed boolean, p_product_id text, p_nonce uuid, p_timestamp bigint, p_signature_max_age_seconds integer); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.pomodoist_subscription_offer_state(p_environment text, p_app_transaction_id text, p_campaign_id text, p_original_transaction_ids text[], p_user_id uuid, p_redeemed boolean, p_product_id text, p_nonce uuid, p_timestamp bigint, p_signature_max_age_seconds integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.pomodoist_subscription_offer_state(p_environment text, p_app_transaction_id text, p_campaign_id text, p_original_transaction_ids text[], p_user_id uuid, p_redeemed boolean, p_product_id text, p_nonce uuid, p_timestamp bigint, p_signature_max_age_seconds integer) TO service_role;


--
-- Name: FUNCTION pomodoist_voice_quota(p_user_id uuid, p_request_id uuid, p_action text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.pomodoist_voice_quota(p_user_id uuid, p_request_id uuid, p_action text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.pomodoist_voice_quota(p_user_id uuid, p_request_id uuid, p_action text) TO service_role;


--
-- Name: FUNCTION prune_pomodoist_free_task_history(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.prune_pomodoist_free_task_history() FROM PUBLIC;
GRANT ALL ON FUNCTION public.prune_pomodoist_free_task_history() TO service_role;


--
-- Name: FUNCTION prune_pomodoist_sync_receipts(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.prune_pomodoist_sync_receipts() FROM PUBLIC;
GRANT ALL ON FUNCTION public.prune_pomodoist_sync_receipts() TO service_role;


--
-- Name: FUNCTION pull_changes(p_app_id text, p_device_id text, p_since_revision bigint, p_limit integer); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.pull_changes(p_app_id text, p_device_id text, p_since_revision bigint, p_limit integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.pull_changes(p_app_id text, p_device_id text, p_since_revision bigint, p_limit integer) TO authenticated;
GRANT ALL ON FUNCTION public.pull_changes(p_app_id text, p_device_id text, p_since_revision bigint, p_limit integer) TO service_role;


--
-- Name: FUNCTION push_changes(p_app_id text, p_device_id text, p_operations jsonb); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.push_changes(p_app_id text, p_device_id text, p_operations jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.push_changes(p_app_id text, p_device_id text, p_operations jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.push_changes(p_app_id text, p_device_id text, p_operations jsonb) TO service_role;


--
-- Name: FUNCTION push_pomodoist_draft_changes(p_device_id text, p_command_id text, p_operations jsonb); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.push_pomodoist_draft_changes(p_device_id text, p_command_id text, p_operations jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.push_pomodoist_draft_changes(p_device_id text, p_command_id text, p_operations jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.push_pomodoist_draft_changes(p_device_id text, p_command_id text, p_operations jsonb) TO service_role;


--
-- Name: FUNCTION push_pomodoist_mcp_changes(p_user_id uuid, p_client_id uuid, p_operations jsonb); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.push_pomodoist_mcp_changes(p_user_id uuid, p_client_id uuid, p_operations jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.push_pomodoist_mcp_changes(p_user_id uuid, p_client_id uuid, p_operations jsonb) TO service_role;


--
-- Name: FUNCTION push_pomodoist_telegram_changes(p_telegram_user_id bigint, p_expected_user_id uuid, p_client_id uuid, p_operations jsonb); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.push_pomodoist_telegram_changes(p_telegram_user_id bigint, p_expected_user_id uuid, p_client_id uuid, p_operations jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.push_pomodoist_telegram_changes(p_telegram_user_id bigint, p_expected_user_id uuid, p_client_id uuid, p_operations jsonb) TO service_role;


--
-- Name: FUNCTION read_pomodoist_companion_state(p_since_revision bigint); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.read_pomodoist_companion_state(p_since_revision bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION public.read_pomodoist_companion_state(p_since_revision bigint) TO authenticated;
GRANT ALL ON FUNCTION public.read_pomodoist_companion_state(p_since_revision bigint) TO service_role;


--
-- Name: FUNCTION read_pomodoist_mcp(p_user_id uuid, p_operation text, p_arguments jsonb); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.read_pomodoist_mcp(p_user_id uuid, p_operation text, p_arguments jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.read_pomodoist_mcp(p_user_id uuid, p_operation text, p_arguments jsonb) TO service_role;


--
-- Name: FUNCTION read_pomodoist_openclaw_state(p_subject uuid, p_session_id uuid, p_client_id uuid, p_task_id text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.read_pomodoist_openclaw_state(p_subject uuid, p_session_id uuid, p_client_id uuid, p_task_id text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.read_pomodoist_openclaw_state(p_subject uuid, p_session_id uuid, p_client_id uuid, p_task_id text) TO service_role;


--
-- Name: FUNCTION record_pomodoist_purchase(p_original_transaction_id text, p_latest_transaction_id text, p_product_id text, p_environment text, p_purchase_type text, p_purchased_at timestamp with time zone, p_expires_at timestamp with time zone, p_revoked_at timestamp with time zone, p_app_account_token uuid, p_signed_at timestamp with time zone, p_raw_claims jsonb, p_user_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.record_pomodoist_purchase(p_original_transaction_id text, p_latest_transaction_id text, p_product_id text, p_environment text, p_purchase_type text, p_purchased_at timestamp with time zone, p_expires_at timestamp with time zone, p_revoked_at timestamp with time zone, p_app_account_token uuid, p_signed_at timestamp with time zone, p_raw_claims jsonb, p_user_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.record_pomodoist_purchase(p_original_transaction_id text, p_latest_transaction_id text, p_product_id text, p_environment text, p_purchase_type text, p_purchased_at timestamp with time zone, p_expires_at timestamp with time zone, p_revoked_at timestamp with time zone, p_app_account_token uuid, p_signed_at timestamp with time zone, p_raw_claims jsonb, p_user_id uuid) TO service_role;


--
-- Name: FUNCTION record_pomodoist_stripe_event(p_event_id text, p_event_type text, p_event_created_at timestamp with time zone, p_stripe_object_id text, p_stripe_customer_id text, p_user_id uuid, p_product_id text, p_purchase_type text, p_status text, p_valid_from timestamp with time zone, p_valid_until timestamp with time zone, p_first_subscription_paid boolean, p_raw_payload jsonb); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.record_pomodoist_stripe_event(p_event_id text, p_event_type text, p_event_created_at timestamp with time zone, p_stripe_object_id text, p_stripe_customer_id text, p_user_id uuid, p_product_id text, p_purchase_type text, p_status text, p_valid_from timestamp with time zone, p_valid_until timestamp with time zone, p_first_subscription_paid boolean, p_raw_payload jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.record_pomodoist_stripe_event(p_event_id text, p_event_type text, p_event_created_at timestamp with time zone, p_stripe_object_id text, p_stripe_customer_id text, p_user_id uuid, p_product_id text, p_purchase_type text, p_status text, p_valid_from timestamp with time zone, p_valid_until timestamp with time zone, p_first_subscription_paid boolean, p_raw_payload jsonb) TO service_role;


--
-- Name: FUNCTION resolve_pomodoist_mcp_session(p_subject uuid, p_session_id uuid, p_client_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.resolve_pomodoist_mcp_session(p_subject uuid, p_session_id uuid, p_client_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.resolve_pomodoist_mcp_session(p_subject uuid, p_session_id uuid, p_client_id uuid) TO service_role;


--
-- Name: FUNCTION run_pomodoist_free_task_pruning(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.run_pomodoist_free_task_pruning() FROM PUBLIC;
GRANT ALL ON FUNCTION public.run_pomodoist_free_task_pruning() TO service_role;


--
-- Name: FUNCTION run_pomodoist_receipt_pruning(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.run_pomodoist_receipt_pruning() FROM PUBLIC;
GRANT ALL ON FUNCTION public.run_pomodoist_receipt_pruning() TO service_role;


--
-- Name: FUNCTION send_pomodoist_mcp_sync_hint(p_user_id uuid, p_client_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.send_pomodoist_mcp_sync_hint(p_user_id uuid, p_client_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.send_pomodoist_mcp_sync_hint(p_user_id uuid, p_client_id uuid) TO service_role;


--
-- Name: FUNCTION touch_updated_at(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.touch_updated_at() FROM PUBLIC;


--
-- Name: FUNCTION unlink_pomodoist_telegram(p_telegram_user_id bigint, p_expected_user_id uuid, p_guest_user_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.unlink_pomodoist_telegram(p_telegram_user_id bigint, p_expected_user_id uuid, p_guest_user_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.unlink_pomodoist_telegram(p_telegram_user_id bigint, p_expected_user_id uuid, p_guest_user_id uuid) TO service_role;


--
-- Name: TABLE pomodoist_stripe_claims; Type: ACL; Schema: private; Owner: postgres
--

GRANT SELECT,INSERT,UPDATE ON TABLE private.pomodoist_stripe_claims TO service_role;


--
-- Name: TABLE pomodoist_stripe_customers; Type: ACL; Schema: private; Owner: postgres
--

GRANT SELECT,INSERT,UPDATE ON TABLE private.pomodoist_stripe_customers TO service_role;


--
-- Name: TABLE pomodoist_stripe_events; Type: ACL; Schema: private; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE private.pomodoist_stripe_events TO service_role;


--
-- Name: TABLE pomodoist_subscription_offers; Type: ACL; Schema: private; Owner: postgres
--

GRANT SELECT,INSERT,UPDATE ON TABLE private.pomodoist_subscription_offers TO service_role;


--
-- Name: TABLE apps; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.apps TO anon;
GRANT ALL ON TABLE public.apps TO authenticated;
GRANT ALL ON TABLE public.apps TO service_role;


--
-- Name: TABLE pomodoist_purchase_claims; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.pomodoist_purchase_claims TO service_role;


--
-- Name: TABLE pomodoist_telegram_accounts; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.pomodoist_telegram_accounts TO service_role;


--
-- Name: TABLE pomodoist_telegram_link_attempts; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.pomodoist_telegram_link_attempts TO service_role;


--
-- Name: TABLE products; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.products TO anon;
GRANT ALL ON TABLE public.products TO authenticated;
GRANT ALL ON TABLE public.products TO service_role;


--
-- Name: TABLE profiles; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.profiles TO anon;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.profiles TO authenticated;
GRANT SELECT ON TABLE public.profiles TO service_role;


--
-- Name: COLUMN profiles.display_name; Type: ACL; Schema: public; Owner: postgres
--

GRANT UPDATE(display_name) ON TABLE public.profiles TO authenticated;


--
-- Name: COLUMN profiles.avatar_url; Type: ACL; Schema: public; Owner: postgres
--

GRANT UPDATE(avatar_url) ON TABLE public.profiles TO authenticated;


--
-- Name: TABLE quota_definitions; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.quota_definitions TO anon;
GRANT ALL ON TABLE public.quota_definitions TO authenticated;
GRANT ALL ON TABLE public.quota_definitions TO service_role;


--
-- Name: TABLE storage_usage; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.storage_usage TO anon;
GRANT ALL ON TABLE public.storage_usage TO authenticated;
GRANT ALL ON TABLE public.storage_usage TO service_role;


--
-- Name: TABLE sync_devices; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.sync_devices TO anon;
GRANT ALL ON TABLE public.sync_devices TO authenticated;
GRANT SELECT,UPDATE ON TABLE public.sync_devices TO service_role;


--
-- Name: TABLE sync_entities; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.sync_entities TO anon;
GRANT ALL ON TABLE public.sync_entities TO authenticated;
GRANT SELECT ON TABLE public.sync_entities TO service_role;


--
-- Name: TABLE sync_maintenance_runs; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.sync_maintenance_runs TO service_role;


--
-- Name: SEQUENCE sync_maintenance_runs_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.sync_maintenance_runs_id_seq TO anon;
GRANT ALL ON SEQUENCE public.sync_maintenance_runs_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.sync_maintenance_runs_id_seq TO service_role;


--
-- Name: TABLE sync_operation_receipts; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.sync_operation_receipts TO service_role;


--
-- Name: TABLE sync_operations; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.sync_operations TO anon;
GRANT ALL ON TABLE public.sync_operations TO authenticated;
GRANT SELECT ON TABLE public.sync_operations TO service_role;


--
-- Name: SEQUENCE sync_revision_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.sync_revision_seq TO anon;
GRANT ALL ON SEQUENCE public.sync_revision_seq TO authenticated;
GRANT ALL ON SEQUENCE public.sync_revision_seq TO service_role;


--
-- Name: TABLE usage_periods; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.usage_periods TO anon;
GRANT ALL ON TABLE public.usage_periods TO authenticated;
GRANT ALL ON TABLE public.usage_periods TO service_role;


--
-- Name: TABLE user_app_installs; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.user_app_installs TO anon;
GRANT ALL ON TABLE public.user_app_installs TO authenticated;
GRANT SELECT ON TABLE public.user_app_installs TO service_role;


--
-- Name: TABLE user_entitlements; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.user_entitlements TO anon;
GRANT ALL ON TABLE public.user_entitlements TO authenticated;
GRANT SELECT,INSERT,UPDATE ON TABLE public.user_entitlements TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--



--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--



--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--



--
-- PostgreSQL database dump complete
--



--
-- PostgreSQL database dump
--


-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Data for Name: pomodoist_instance_settings; Type: TABLE DATA; Schema: private; Owner: postgres
--

INSERT INTO private.pomodoist_instance_settings (singleton, selfhost_features_enabled, mcp_issuer, mcp_audience) VALUES (true, false, NULL, NULL);


--
-- Data for Name: apps; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.apps (id, display_name, description, created_at) VALUES ('pomodoist', 'Pomodoist', 'Tasks, focus sessions, projects, labels, reports, and calendar sync.', '2026-09-22 16:37:07.439372+00');


--
-- Data for Name: products; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.products (id, app_id, revenuecat_entitlement_id, product_type, display_name, created_at) VALUES ('pomodoist_plus_monthly', 'pomodoist', 'pomodoist_plus', 'subscription', 'Pomodoist Plus Monthly', '2026-09-22 16:37:07.439372+00');


--
-- Data for Name: quota_definitions; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.quota_definitions (app_id, quota_key, limit_value, unit, period, created_at, updated_at) VALUES ('pomodoist', 'llm_requests', 1000, 'request', 'monthly', '2026-09-22 16:37:08.068457+00', '2026-09-22 16:37:08.068457+00');
INSERT INTO public.quota_definitions (app_id, quota_key, limit_value, unit, period, created_at, updated_at) VALUES ('pomodoist', 'voice_transcriptions', 1000, 'request', 'monthly', '2026-09-22 16:37:07.439372+00', '2026-09-22 16:37:08.068457+00');


--
-- PostgreSQL database dump complete
--



create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

grant select on public.apps to authenticated;
grant select, insert, update on public.user_app_installs to authenticated;

drop policy if exists "Users can receive own app sync broadcasts"
on realtime.messages;

create policy "Users can receive own app sync broadcasts"
on realtime.messages
for select
to authenticated
using (
  realtime.messages.extension = 'broadcast'
  and array_length(string_to_array((select realtime.topic()), ':'), 1) = 3
  and split_part((select realtime.topic()), ':', 1) = 'sync'
  and split_part((select realtime.topic()), ':', 2) = (select auth.uid())::text
  and exists (
    select 1
    from public.apps app
    where app.id = split_part((select realtime.topic()), ':', 3)
  )
);

drop policy if exists "Users can send own app sync broadcasts"
on realtime.messages;

create policy "Users can send own app sync broadcasts"
on realtime.messages
for insert
to authenticated
with check (
  realtime.messages.extension = 'broadcast'
  and array_length(string_to_array((select realtime.topic()), ':'), 1) = 3
  and split_part((select realtime.topic()), ':', 1) = 'sync'
  and split_part((select realtime.topic()), ':', 2) = (select auth.uid())::text
  and exists (
    select 1
    from public.apps app
    where app.id = split_part((select realtime.topic()), ':', 3)
  )
);

-- Storage is optional in core-only installations.
do $$ begin
  if to_regclass('storage.buckets') is not null then
    insert into storage.buckets(id,name,public,file_size_limit)
    values ('pomodoist-shared','pomodoist-shared',false,20000000)
    on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit;
  end if;
end $$;

select cron.schedule('pomodoist-free-task-prune', '17 3 * * *',
  'select public.run_pomodoist_free_task_pruning();');
select cron.schedule('pomodoist-sync-receipt-prune', '23 * * * *',
  'select public.run_pomodoist_receipt_pruning();');
select cron.schedule('pomodoist-profile-pro-reconcile', '37 3 * * *',
  'select private.reconcile_pomodoist_profile_pro();');
select cron.schedule('pomodoist-google-calendar-worker', '* * * * *',
  'select private.invoke_pomodoist_google_calendar_worker();');
notify pgrst, 'reload schema';

select cron.schedule('pomodoist-voice-request-prune','*/10 * * * *','delete from private.pomodoist_voice_requests where expires_at <= now()');


-- Keep the public RPC contract while isolating privileged implementations.

CREATE OR REPLACE FUNCTION private.consume_quota(p_app_id text, p_quota_key text, p_units integer, p_period_start timestamp with time zone DEFAULT NULL::timestamp with time zone, p_period_end timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.consume_quota(p_app_id text, p_quota_key text, p_units integer, p_period_start timestamp with time zone DEFAULT NULL::timestamp with time zone, p_period_end timestamp with time zone DEFAULT NULL::timestamp with time zone)
RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path = ''
AS $wrapper$
  SELECT private.consume_quota(p_app_id, p_quota_key, p_units, p_period_start, p_period_end);
$wrapper$;

REVOKE ALL ON FUNCTION public.consume_quota(p_app_id text, p_quota_key text, p_units integer, p_period_start timestamp with time zone, p_period_end timestamp with time zone) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.consume_quota(p_app_id text, p_quota_key text, p_units integer, p_period_start timestamp with time zone, p_period_end timestamp with time zone) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.consume_quota(p_app_id text, p_quota_key text, p_units integer, p_period_start timestamp with time zone, p_period_end timestamp with time zone) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.consume_quota(p_app_id text, p_quota_key text, p_units integer, p_period_start timestamp with time zone, p_period_end timestamp with time zone) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION private.ensure_profile()
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.ensure_profile()
RETURNS uuid
LANGUAGE sql SECURITY INVOKER SET search_path = ''
AS $wrapper$
  SELECT private.ensure_profile();
$wrapper$;

REVOKE ALL ON FUNCTION public.ensure_profile() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.ensure_profile() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ensure_profile() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.ensure_profile() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION private.get_account_overview()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET "TimeZone" TO 'UTC'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.get_account_overview()
RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path = ''
AS $wrapper$
  SELECT private.get_account_overview();
$wrapper$;

REVOKE ALL ON FUNCTION public.get_account_overview() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.get_account_overview() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_account_overview() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.get_account_overview() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION private.get_apple_app_account_token()
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.get_apple_app_account_token()
RETURNS uuid
LANGUAGE sql SECURITY INVOKER SET search_path = ''
AS $wrapper$
  SELECT private.get_apple_app_account_token();
$wrapper$;

REVOKE ALL ON FUNCTION public.get_apple_app_account_token() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.get_apple_app_account_token() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_apple_app_account_token() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.get_apple_app_account_token() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION private.get_usage_period(p_app_id text, p_quota_key text, p_period_start timestamp with time zone DEFAULT NULL::timestamp with time zone, p_period_end timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET "TimeZone" TO 'UTC'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.get_usage_period(p_app_id text, p_quota_key text, p_period_start timestamp with time zone DEFAULT NULL::timestamp with time zone, p_period_end timestamp with time zone DEFAULT NULL::timestamp with time zone)
RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path = ''
AS $wrapper$
  SELECT private.get_usage_period(p_app_id, p_quota_key, p_period_start, p_period_end);
$wrapper$;

REVOKE ALL ON FUNCTION public.get_usage_period(p_app_id text, p_quota_key text, p_period_start timestamp with time zone, p_period_end timestamp with time zone) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.get_usage_period(p_app_id text, p_quota_key text, p_period_start timestamp with time zone, p_period_end timestamp with time zone) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_usage_period(p_app_id text, p_quota_key text, p_period_start timestamp with time zone, p_period_end timestamp with time zone) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.get_usage_period(p_app_id text, p_quota_key text, p_period_start timestamp with time zone, p_period_end timestamp with time zone) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION private.pull_changes(p_app_id text, p_device_id text, p_since_revision bigint DEFAULT 0, p_limit integer DEFAULT 500)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    v_has_pomodoist_paid_entitlement :=
      public.has_active_pomodoist_paid_entitlement(v_user_id);
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
        or (
          entity_type = 'task'
          and v_has_pomodoist_paid_entitlement
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
$function$;

CREATE OR REPLACE FUNCTION public.pull_changes(p_app_id text, p_device_id text, p_since_revision bigint DEFAULT 0, p_limit integer DEFAULT 500)
RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path = ''
AS $wrapper$
  SELECT private.pull_changes(p_app_id, p_device_id, p_since_revision, p_limit);
$wrapper$;

REVOKE ALL ON FUNCTION public.pull_changes(p_app_id text, p_device_id text, p_since_revision bigint, p_limit integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.pull_changes(p_app_id text, p_device_id text, p_since_revision bigint, p_limit integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.pull_changes(p_app_id text, p_device_id text, p_since_revision bigint, p_limit integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.pull_changes(p_app_id text, p_device_id text, p_since_revision bigint, p_limit integer) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION private.push_changes(p_app_id text, p_device_id text, p_operations jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select private.push_changes_for_user(
    auth.uid(),
    p_app_id,
    p_device_id,
    p_operations
  );
$function$;

CREATE OR REPLACE FUNCTION public.push_changes(p_app_id text, p_device_id text, p_operations jsonb)
RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path = ''
AS $wrapper$
  SELECT private.push_changes(p_app_id, p_device_id, p_operations);
$wrapper$;

REVOKE ALL ON FUNCTION public.push_changes(p_app_id text, p_device_id text, p_operations jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.push_changes(p_app_id text, p_device_id text, p_operations jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.push_changes(p_app_id text, p_device_id text, p_operations jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.push_changes(p_app_id text, p_device_id text, p_operations jsonb) TO authenticated, service_role;

-- USAGE permits name resolution only; existing private object ACLs stay closed.
GRANT USAGE ON SCHEMA private TO authenticated;
ALTER FUNCTION public.touch_updated_at() SET search_path = '';

ALTER POLICY "Users can read own profile" ON public.profiles
  USING ((select auth.uid()) = id);

ALTER POLICY "Users can update own profile" ON public.profiles
  USING ((select auth.uid()) = id)
  WITH CHECK ((select auth.uid()) = id);

ALTER POLICY "Users can read own app installs" ON public.user_app_installs
  USING ((select auth.uid()) = user_id);

ALTER POLICY "Users can insert own app installs" ON public.user_app_installs

  WITH CHECK ((select auth.uid()) = user_id);

ALTER POLICY "Users can update own app installs" ON public.user_app_installs
  USING ((select auth.uid()) = user_id)
  WITH CHECK ((select auth.uid()) = user_id);

ALTER POLICY "Users can read own entitlements" ON public.user_entitlements
  USING ((select auth.uid()) = user_id);

ALTER POLICY "Users can read own usage" ON public.usage_periods
  USING ((select auth.uid()) = user_id);

ALTER POLICY "Users can read own sync devices" ON public.sync_devices
  USING ((select auth.uid()) = user_id);

ALTER POLICY "Users can insert own sync devices" ON public.sync_devices

  WITH CHECK ((select auth.uid()) = user_id);

ALTER POLICY "Users can update own sync devices" ON public.sync_devices
  USING ((select auth.uid()) = user_id)
  WITH CHECK ((select auth.uid()) = user_id);

ALTER POLICY "Users can read own sync entities" ON public.sync_entities
  USING ((select auth.uid()) = user_id);

NOTIFY pgrst, 'reload schema';

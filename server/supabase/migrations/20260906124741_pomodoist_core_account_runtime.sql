-- Canonical account runtime for hosted and independent Pomodoist servers.
-- Hosted deployments install their additional-account adapters first.
-- This migration never turns on local access or modifies existing purchases.
begin;
set local role postgres;
create schema if not exists private authorization postgres;
create table if not exists private.pomodoist_instance_settings (
  singleton boolean primary key default true check (singleton),
  selfhost_features_enabled boolean not null default false
);
alter table private.pomodoist_instance_settings
  add column if not exists mcp_issuer text,
  add column if not exists mcp_audience text;
alter table private.pomodoist_instance_settings enable row level security;
revoke all on table private.pomodoist_instance_settings
from public, anon, authenticated, service_role, pomodoist_mcp;
insert into private.pomodoist_instance_settings (singleton, selfhost_features_enabled)
values (true, false) on conflict (singleton) do nothing;

-- Only the multi-application deployment overrides these two concrete hooks.
do $install_hooks$
begin
  if to_regprocedure('private.initialize_additional_account(uuid)') is null then
    execute $hook$create function private.initialize_additional_account(p_user_id uuid)
      returns void language plpgsql set search_path = '' as $body$
      begin return; end;
      $body$$hook$;
  end if;
  if to_regprocedure('private.additional_account_overview(uuid,text)') is null then
    execute $hook$create function private.additional_account_overview(p_user_id uuid, p_app_id text)
      returns jsonb language sql stable set search_path = '' as $body$
      select '{}'::jsonb;
      $body$$hook$;
  end if;
end;
$install_hooks$;
revoke all on function private.initialize_additional_account(uuid)
from public, anon, authenticated, service_role, pomodoist_mcp;
revoke all on function private.additional_account_overview(uuid,text)
from public, anon, authenticated, service_role, pomodoist_mcp;

create or replace function private.grant_pomodoist_selfhost_access(p_user_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
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
revoke all on function private.grant_pomodoist_selfhost_access(uuid)
from public, anon, authenticated, service_role, pomodoist_mcp;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
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

create or replace function public.ensure_profile()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
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

  perform private.initialize_additional_account(v_user_id);
  perform private.grant_pomodoist_selfhost_access(v_user_id);

  return v_user_id;
end;
$$;

create or replace function public.get_account_overview()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
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
        'storage', (
          select jsonb_build_object(
            'appId', s.app_id,
            'usedBytes', s.used_bytes,
            'limitBytes', s.limit_bytes
          )
          from public.storage_usage s
          where s.user_id = v_user_id
            and s.app_id = a.id
        )
      ) || private.additional_account_overview(v_user_id, a.id)
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

-- Independent servers derive the resource from their own issuer. The hosted
-- adapter may configure its separate MCP gateway origin without a code fork.
create or replace function private.pomodoist_mcp_audience(p_issuer text)
returns text language sql stable strict security definer set search_path = '' as $$
  select coalesce(
    (select mcp_audience from private.pomodoist_instance_settings
     where singleton and mcp_issuer = p_issuer),
    left(p_issuer, -length('/auth/v1')) || '/functions/v1/pomodoist-mcp'
  );
$$;
revoke all on function private.pomodoist_mcp_audience(text)
from public, anon, authenticated, service_role, pomodoist_mcp;
grant execute on function private.pomodoist_mcp_audience(text) to supabase_auth_admin;

-- OAuth uses HTTPS outside exact loopback development hosts.
CREATE OR REPLACE FUNCTION private.pomodoist_mcp_access_token_hook(event jsonb) RETURNS jsonb
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


revoke all on function private.pomodoist_mcp_access_token_hook(jsonb)
from public, anon, authenticated, service_role, pomodoist_mcp;
grant execute on function private.pomodoist_mcp_access_token_hook(jsonb) to supabase_auth_admin;

-- Preserve existing service boundaries while removing unused public entrypoints.
drop function if exists public.consume_quota(text,text,integer,integer,text,timestamptz,timestamptz);
revoke all on function public.ensure_profile() from public, anon;
grant execute on function public.ensure_profile() to authenticated;
revoke all on function public.get_account_overview() from public, anon;
grant execute on function public.get_account_overview() to authenticated;
revoke all on function public.get_apple_app_account_token() from public, anon;
grant execute on function public.get_apple_app_account_token() to authenticated;
revoke all on function public.handle_new_user() from public, anon, authenticated, service_role;
revoke all on function public.touch_updated_at() from public, anon, authenticated, service_role;
revoke all on function public.get_usage_period(text,text,timestamptz,timestamptz) from public, anon;
revoke all on function public.consume_quota(text,text,integer,timestamptz,timestamptz) from public, anon;
notify pgrst, 'reload schema';
commit;

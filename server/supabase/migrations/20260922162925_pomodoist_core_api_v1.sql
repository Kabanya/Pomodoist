-- Pomodoist API v1 is additive. Existing public RPCs and data remain unchanged.
-- The migration runner supplies the transaction, including its ledger record.
create schema api_v1 authorization postgres;
revoke all on schema api_v1 from public, anon, authenticated, service_role;
grant usage on schema api_v1 to authenticated, service_role;

create function api_v1.ensure_profile() returns uuid
language sql security invoker set search_path = ''
as $$ select public.ensure_profile(); $$;

create function api_v1.get_account_overview() returns jsonb
language sql security invoker set search_path = ''
as $$ select public.get_account_overview(); $$;

create function api_v1.get_apple_app_account_token() returns uuid
language sql security invoker set search_path = ''
as $$ select public.get_apple_app_account_token(); $$;

create function api_v1.get_usage_period(
  p_app_id text, p_quota_key text,
  p_period_start timestamptz default null, p_period_end timestamptz default null
) returns jsonb language sql security invoker set search_path = ''
as $$ select public.get_usage_period(p_app_id, p_quota_key, p_period_start, p_period_end); $$;

create function api_v1.consume_quota(
  p_app_id text, p_quota_key text, p_units integer,
  p_period_start timestamptz default null, p_period_end timestamptz default null
) returns jsonb language sql security invoker set search_path = ''
as $$ select public.consume_quota(p_app_id, p_quota_key, p_units, p_period_start, p_period_end); $$;

create function api_v1.pull_changes(
  p_app_id text, p_device_id text, p_since_revision bigint default 0,
  p_limit integer default 500
) returns jsonb language sql security invoker set search_path = ''
as $$ select public.pull_changes(p_app_id, p_device_id, p_since_revision, p_limit); $$;

create function api_v1.push_changes(p_app_id text, p_device_id text, p_operations jsonb)
returns jsonb language sql security invoker set search_path = ''
as $$ select public.push_changes(p_app_id, p_device_id, p_operations); $$;

-- Functions default to PUBLIC EXECUTE even when schema USAGE is restricted.
revoke all on all functions in schema api_v1 from public, anon;
grant execute on all functions in schema api_v1 to authenticated, service_role;
notify pgrst, 'reload schema';

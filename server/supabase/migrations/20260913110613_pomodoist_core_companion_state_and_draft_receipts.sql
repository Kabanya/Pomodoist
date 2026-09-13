-- Keep the first task's legacy command receipt as the atomic batch receipt.
-- Existing accepted commands are acknowledged without recreating historical data.
create or replace function public.push_pomodoist_draft_changes(
  p_device_id text, p_command_id text, p_operations jsonb
) returns jsonb language plpgsql security definer set search_path = '' as $$
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
revoke all on function public.push_pomodoist_draft_changes(text,text,jsonb) from public, anon;
grant execute on function public.push_pomodoist_draft_changes(text,text,jsonb) to authenticated;

-- Companion projections need every task/project/label, but no historical events
-- or completed Focus runs. Paging bounds each read without truncating children.
create or replace function public.read_pomodoist_companion_state(p_since_revision bigint default 0)
returns jsonb language plpgsql security definer set search_path = '' as $$
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
revoke all on function public.read_pomodoist_companion_state(bigint) from public, anon;
grant execute on function public.read_pomodoist_companion_state(bigint) to authenticated;

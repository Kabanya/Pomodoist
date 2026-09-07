-- OpenClaw uses the existing MCP OAuth resource and shared sync store.
-- Apply after the immutable baseline, to both hosted and independent servers.
begin;

-- Preserve the existing sync algorithm; take the calendar/account lock BEFORE
-- row locks. All device, MCP, Telegram and calendar pushes then participate in
-- the same compare-and-commit boundary. Reuse the calendar key to avoid a new
-- lock-order inversion with its sync triggers. Other applications are unchanged.
create or replace function private.push_changes_for_user(
  p_user_id uuid, p_app_id text, p_device_id text, p_operations jsonb
) returns jsonb language plpgsql security definer set search_path = '' as $$
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
revoke all on function private.push_changes_for_user(uuid,text,text,jsonb)
from public, anon, authenticated, service_role, pomodoist_mcp;

create table private.pomodoist_openclaw_receipts (
  user_id uuid not null references auth.users(id) on delete cascade,
  client_id uuid not null references auth.oauth_clients(id) on delete cascade,
  request_id uuid not null,
  action text not null,
  arguments_hash text not null check (arguments_hash ~ '^[a-f0-9]{64}$'),
  result jsonb not null,
  created_at timestamptz not null default now(),
  primary key (user_id, client_id, request_id)
);
alter table private.pomodoist_openclaw_receipts enable row level security;
revoke all on table private.pomodoist_openclaw_receipts from public, anon, authenticated, service_role, pomodoist_mcp;

create function public.pomodoist_openclaw_action(
  p_subject uuid, p_session_id uuid, p_client_id uuid,
  p_request_id uuid, p_action text, p_arguments_hash text,
  p_expected_revision bigint default null, p_operations jsonb default null, p_result jsonb default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
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
$$;
revoke all on function public.pomodoist_openclaw_action(uuid,uuid,uuid,uuid,text,text,bigint,jsonb,jsonb)
from public, anon, authenticated, pomodoist_mcp;
grant execute on function public.pomodoist_openclaw_action(uuid,uuid,uuid,uuid,text,text,bigint,jsonb,jsonb) to service_role;

create function public.read_pomodoist_openclaw_state(
  p_subject uuid, p_session_id uuid, p_client_id uuid, p_task_id text default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
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
$$;
revoke all on function public.read_pomodoist_openclaw_state(uuid,uuid,uuid,text) from public, anon, authenticated, pomodoist_mcp;
grant execute on function public.read_pomodoist_openclaw_state(uuid,uuid,uuid,text) to service_role;
commit;

begin;

alter table public.usage_periods
  add constraint usage_periods_period_order_check check (period_end > period_start) not valid,
  add constraint usage_periods_quota_definition_fkey
    foreign key (app_id, quota_key) references public.quota_definitions(app_id, quota_key)
    on update no action on delete no action not valid;
-- Fail atomically on existing invalid data; never discard or rewrite usage.
alter table public.usage_periods validate constraint usage_periods_period_order_check;
alter table public.usage_periods validate constraint usage_periods_quota_definition_fkey;

CREATE OR REPLACE FUNCTION private.push_changes_for_user(p_user_id uuid, p_app_id text, p_device_id text, p_operations jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

notify pgrst, 'reload schema';
commit;

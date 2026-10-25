-- Deploy before clients that send isFocusEstimateManual. Legacy payloads omit it.
do $manual_estimate$
declare definition text; original text;
begin
  definition := pg_catalog.pg_get_functiondef('private.pomodoist_shared_apply(uuid,uuid,text,jsonb)'::regprocedure);
  original := $old$'durationSeconds','estimatedFocusIntervals'$old$;
  if strpos(definition, original) = 0 then raise exception 'Unexpected shared task fields'; end if;
  definition := replace(definition, original, $new$'durationSeconds','estimatedFocusIntervals','isFocusEstimateManual'$new$);
  original := 'for k,v in select * from jsonb_each(payload) loop';
  if strpos(definition, original) = 0 then raise exception 'Unexpected shared task validation'; end if;
  definition := replace(definition, original, $new$
    if typ='task' and payload ? 'isFocusEstimateManual'
      and jsonb_typeof(payload->'isFocusEstimateManual') is distinct from 'boolean' then
      raise exception using errcode='22023',message='Invalid Pomodoist manual focus estimate';
    end if;
    for k,v in select * from jsonb_each(payload) loop$new$);
  execute definition;

  definition := pg_catalog.pg_get_functiondef('private.push_changes_for_user(uuid,text,text,jsonb)'::regprocedure);
  original := $old$if coalesce(pg_catalog.jsonb_typeof(v_op -> 'payload'), 'object') <> 'object' then$old$;
  if strpos(definition, original) = 0 then raise exception 'Unexpected private sync validation'; end if;
  definition := replace(definition, original, $new$
    if p_app_id='pomodoist'
      and coalesce(v_op->>'entityType',v_op->>'entity_type')='task'
      and (v_op->'payload') ? 'isFocusEstimateManual'
      and pg_catalog.jsonb_typeof(v_op->'payload'->'isFocusEstimateManual') is distinct from 'boolean' then
      raise exception using errcode='22023',message='Invalid Pomodoist manual focus estimate';
    end if;
    if coalesce(pg_catalog.jsonb_typeof(v_op -> 'payload'), 'object') <> 'object' then$new$);
  execute definition;

  definition := pg_catalog.pg_get_functiondef('private.pomodoist_mcp_task_json(text,jsonb)'::regprocedure);
  original := $old$'estimatedFocusIntervals', p_data -> 'estimatedFocusIntervals',$old$;
  if strpos(definition, original) = 0 then raise exception 'Unexpected MCP task projection'; end if;
  definition := replace(definition, original, $new$'estimatedFocusIntervals', p_data -> 'estimatedFocusIntervals',
    'isFocusEstimateManual', coalesce(p_data->'isFocusEstimateManual','false'::jsonb),$new$);
  execute definition;
end $manual_estimate$;

-- Restore file protections lost by the habits writer and allow reusable labels.
do $sync_repairs$
declare definition text; original text;
begin
  definition := pg_catalog.pg_get_functiondef('private.push_changes_for_user(uuid,text,text,jsonb)'::regprocedure);
  original := E'begin\n  if p_user_id is null';
  if strpos(definition, original) = 0 then raise exception 'Unexpected private sync entry'; end if;
  definition := replace(definition, original, E'begin\n  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(''pomodoist-file-lifecycle'',0));\n  if p_user_id is null');
  original := $old$    v_operation := coalesce(v_op ->> 'operation', 'upsert');$old$;
  if strpos(definition, original) = 0 then raise exception 'Unexpected private sync operation'; end if;
  definition := replace(definition, original, $new$
    if p_app_id = 'pomodoist' and v_entity_type = 'attachment' then
      raise exception using errcode='42501',message='Attachment metadata is server-authored';
    end if;
    v_operation := coalesce(v_op ->> 'operation', 'upsert');$new$);
  original := $old$    if v_operation = 'delete' then
      v_deleted_at := coalesce(v_deleted_at, v_client_updated_at);
    elsif v_deleted_at is null or v_is_protected_pomodoist_anchor then$old$;
  if strpos(definition, original) = 0 then raise exception 'Unexpected private sync tombstone'; end if;
  definition := replace(definition, original, $new$
    -- Membership has its own clock: ignored stale writes must not move it back.
    if p_app_id = 'pomodoist' and v_entity_type = 'task_label' then
      v_field_clock := coalesce(nullif(v_clock->>'_membership','')::timestamptz,
        greatest(v_existing.client_updated_at, v_deleted_at,
          (select max(value::timestamptz) from pg_catalog.jsonb_each_text(v_clock))));
      if v_field_clock is not null and (v_client_updated_at < v_field_clock
        or (v_client_updated_at = v_field_clock and v_operation <> 'delete')) then
        continue;
      end if;
      if v_operation = 'upsert' and exists (
        select 1 from public.sync_entities parent
        where parent.user_id=p_user_id and parent.app_id=p_app_id
          and (parent.deleted_at is not null or parent.data->>'isDeleted'='true')
          and ((parent.entity_type='task' and parent.entity_id=coalesce(v_payload->>'taskId',v_data->>'taskId'))
            or (parent.entity_type='label' and parent.entity_id=coalesce(v_payload->>'labelId',v_data->>'labelId')))) then
        raise exception using errcode='22023',message='Task label references a deleted entity';
      end if;
      v_clock := pg_catalog.jsonb_set(v_clock,array['_membership'],pg_catalog.to_jsonb(v_client_updated_at),true);
      if v_operation = 'upsert' then v_deleted_at := null; end if;
    end if;
    if v_operation = 'delete' then
      v_deleted_at := case when p_app_id='pomodoist' and v_entity_type='task_label'
        then v_client_updated_at else coalesce(v_deleted_at, v_client_updated_at) end;
    elsif v_deleted_at is null or v_is_protected_pomodoist_anchor then$new$);
  execute definition;

  definition := pg_catalog.pg_get_functiondef('private.pomodoist_shared_apply(uuid,uuid,text,jsonb)'::regprocedure);
  original := $old$typ='task_kanban_status' and op='upsert' and base>=e.server_revision$old$;
  if strpos(definition, original) = 0 then raise exception 'Unexpected shared relation tombstone'; end if;
  definition := replace(definition, original,
    $new$typ in ('task_kanban_status','task_label') and op='upsert' and base>=e.server_revision$new$);
  execute definition;

  -- The generic calendar service was introduced after the file lock migration.
  definition := pg_catalog.pg_get_functiondef('private.calendar_service(text,uuid,text,jsonb)'::regprocedure);
  original := E'begin\n if p_provider';
  if strpos(definition, original) = 0 then raise exception 'Unexpected calendar service entry'; end if;
  definition := replace(definition, original, E'begin\n perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(''pomodoist-file-lifecycle'',0));\n if p_provider');
  execute definition;
end $sync_repairs$;

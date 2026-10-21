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

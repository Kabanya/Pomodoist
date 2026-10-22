-- Disambiguate the prepared effect revision from the worker-local revision.
do $migration$
declare definition text; original text; replacement text;
begin
  definition := pg_catalog.pg_get_functiondef('private.calendar_service(text,uuid,text,jsonb)'::regprocedure);
  original := $old$from private.pomodoist_calendar_effects where connection_id=c.id and task_id=p_payload->>'taskId' and revision=(p_payload->>'revision')::bigint and incarnation=(p_payload#>>'{link,incarnation}')::bigint$old$;
  replacement := $new$from private.pomodoist_calendar_effects e where e.connection_id=c.id and e.task_id=p_payload->>'taskId' and e.revision=(p_payload->>'revision')::bigint and e.incarnation=(p_payload#>>'{link,incarnation}')::bigint$new$;
  if pg_catalog.strpos(definition, original) = 0 then
    raise exception 'Unexpected calendar acknowledgement definition';
  end if;
  execute pg_catalog.replace(definition, original, replacement);
end $migration$;

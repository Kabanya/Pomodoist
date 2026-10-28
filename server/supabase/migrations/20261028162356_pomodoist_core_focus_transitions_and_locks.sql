-- Focus transactions may run together; lifecycle mutations still exclude them.
do $focus_transitions$
declare definition text; original text;
begin
 definition:=pg_get_functiondef('private.pomodoist_focus(jsonb)'::regprocedure);
 original:=$old$perform pg_advisory_xact_lock(hashtextextended('pomodoist-file-lifecycle',0));$old$;
 if strpos(definition,original)=0 then raise exception 'Unexpected Focus lifecycle lock'; end if;
 definition:=replace(definition,original,$new$perform pg_advisory_xact_lock_shared(hashtextextended('pomodoist-file-lifecycle',0));$new$);
 original:=$old$elsif action='cancelStop' then$old$;
 if strpos(definition,original)=0 then raise exception 'Unexpected Focus transition guard'; end if;
 definition:=replace(definition,original,$new$elsif action='complete' and i->>'status'='ready' then code:='invalid_focus_transition';
  elsif action='cancelStop' then$new$);
 execute definition;

 -- Concurrent accounts can credit the same shared project during expiry reads.
 definition:=pg_get_functiondef('private.pomodoist_focus_credit(uuid,uuid,jsonb,timestamptz)'::regprocedure);
 original:=$old$if scope is not null then$old$;
 if strpos(definition,original)=0 then raise exception 'Unexpected Focus shared credit'; end if;
 definition:=replace(definition,original,$new$if scope is not null then
   perform 1 from private.pomodoist_scopes where id=scope for update;$new$);
 execute definition;
end $focus_transitions$;

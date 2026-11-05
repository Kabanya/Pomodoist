-- Adjust a live interval inside the existing revision, expiry and receipt transaction.
do $focus_duration$
declare definition text; original text;
begin
 definition:=pg_get_functiondef('private.pomodoist_focus_without_task_blocking(jsonb)'::regprocedure);
 original:=$old$'startReady','pause','resume','restart','changePreset'$old$;
 if strpos(definition,original)=0 then raise exception 'Unexpected Focus action allowlist'; end if;
 definition:=replace(definition,original,$new$'startReady','pause','resume','restart','adjustDuration','changePreset'$new$);
 original:=$old$elsif action='changePreset' then$old$;
 if strpos(definition,original)=0 then raise exception 'Unexpected Focus duration branch'; end if;
 definition:=replace(definition,original,$new$elsif action='adjustDuration' then
   if i->>'id' is distinct from payload->>'intervalId' then code:='revision_conflict';
   elsif jsonb_typeof(payload->'deltaSeconds') is distinct from 'number'
     or coalesce(payload->>'deltaSeconds','') not in ('-300','300') then code:='invalid_focus_duration';
   elsif v_strict and payload->>'deltaSeconds'='-300' then code:='strict_exit_required';
   else
    remaining:=case i->>'status'
      when 'ready' then (i->>'plannedSeconds')::integer
      when 'running' then ceil(extract(epoch from a.deadline-stamp))::integer
      when 'paused' then (i->>'plannedSeconds')::integer-greatest(0,
        floor(extract(epoch from ((i->>'pausedAt')::timestamptz-(i->>'startedAt')::timestamptz)))::integer-(i->>'pausedTotalSeconds')::integer)
      else 0 end;
    if coalesce(remaining,0)<=0 or remaining+(payload->>'deltaSeconds')::integer<=0
      or (i->>'plannedSeconds')::integer+(payload->>'deltaSeconds')::integer not between 60 and 10800 then code:='invalid_focus_duration';
    else
     i:=i||jsonb_build_object('plannedSeconds',(i->>'plannedSeconds')::integer+(payload->>'deltaSeconds')::integer,'updatedAt',stamp);
     update private.pomodoist_focus_accounts
       set session=s||jsonb_build_object('interval',i),revision=revision+1,
           deadline=deadline+make_interval(secs=>(payload->>'deltaSeconds')::integer)
       where user_id=actor;
     perform private.pomodoist_focus_project(actor,'focus_interval',i->>'id',i);
     changed:=true;
    end if;
   end if;
  elsif action='changePreset' then$new$);
 execute definition;
end $focus_duration$;

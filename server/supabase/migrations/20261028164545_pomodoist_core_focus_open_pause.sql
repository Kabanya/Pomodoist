-- Terminal history must include the open pause before credit is calculated.
do $focus_pause$
declare signature text; definition text; original text;
begin
 foreach signature in array array[
  'private.pomodoist_focus_advance(uuid,timestamptz,boolean)',
  'private.pomodoist_focus_stop(uuid,timestamptz)'
 ] loop
  definition:=pg_get_functiondef(signature::regprocedure);
  if signature='private.pomodoist_focus_stop(uuid,timestamptz)' then
   original:=$old$i:=s->'interval'||jsonb_build_object('status','stopped'$old$;
   if strpos(definition,original)=0 then raise exception 'Unexpected Focus stop interval'; end if;
   definition:=replace(definition,original,$new$i:=s->'interval';
 i:=i||jsonb_build_object('status','stopped'$new$);
  end if;
  original:=$old$i:=i||jsonb_build_object('status',$old$;
  if strpos(definition,original)=0 then raise exception 'Unexpected Focus terminal interval in %',signature; end if;
  definition:=replace(definition,original,$new$if i->>'pausedAt' is not null then
  i:=i||jsonb_build_object('pausedTotalSeconds',coalesce((i->>'pausedTotalSeconds')::integer,0)+greatest(0,floor(extract(epoch from (stamp-(i->>'pausedAt')::timestamptz)))::integer),'pausedAt',null);
 end if;
 i:=i||jsonb_build_object('status',$new$);
  execute definition;
 end loop;
end $focus_pause$;

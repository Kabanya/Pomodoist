-- Keep a bounded replay window; revisions reject commands evicted from it.
create index pomodoist_focus_requests_device_recent_idx
 on private.pomodoist_focus_requests(user_id,(command->>'deviceId'),created_at desc,request_id desc);

do $focus_receipts$
declare definition text; original text;
begin
 definition:=pg_get_functiondef('private.pomodoist_focus(jsonb)'::regprocedure);
 original:=$old$if action<>'read' then
  select * into previous$old$;
 if strpos(definition,original)=0 then raise exception 'Unexpected Focus replay lookup'; end if;
 definition:=replace(definition,original,$new$if action not in ('read','registerDevice') then
  select * into previous$new$);

 original:=$old$if action not in ('read','registerDevice','profileUpsert','assignmentUpsert') and$old$;
 if strpos(definition,original)=0 then raise exception 'Unexpected Focus revision guard'; end if;
 definition:=replace(definition,original,$new$if action in ('profileUpsert','assignmentUpsert') and
   (jsonb_typeof(p_command->'expectedSettingsRevision') is distinct from 'number'
    or (p_command->>'expectedSettingsRevision')::numeric<>a.settings_revision) then code:='revision_conflict';
 elsif action not in ('read','registerDevice','profileUpsert','assignmentUpsert') and$new$);

 original:=$old$if action<>'read' then insert into private.pomodoist_focus_requests(user_id,request_id,command,response) values(actor,request,p_command,result); end if;$old$;
 if strpos(definition,original)=0 then raise exception 'Unexpected Focus replay receipt'; end if;
 definition:=replace(definition,original,$new$if action not in ('read','registerDevice') then
  insert into private.pomodoist_focus_requests(user_id,request_id,command,response) values(actor,request,p_command,result);
  delete from private.pomodoist_focus_requests
   where user_id=actor and request_id in (
    select request_id from private.pomodoist_focus_requests
    where user_id=actor and command->>'deviceId'=device
    order by created_at desc,request_id desc offset 5);
 end if;$new$);
 execute definition;
end $focus_receipts$;

-- Reclaim existing heartbeat history and excess responses during the upgrade.
delete from private.pomodoist_focus_requests where command->>'action' in ('read','registerDevice');
with ranked as (
 select user_id,request_id,row_number() over (
  partition by user_id,command->>'deviceId' order by created_at desc,request_id desc) position
 from private.pomodoist_focus_requests
)
delete from private.pomodoist_focus_requests r using ranked
 where r.user_id=ranked.user_id and r.request_id=ranked.request_id and ranked.position>5;

-- Short-lived metadata only; settings and image files remain on the selected app.
create table private.pomodoist_app_settings_devices (
 user_id uuid not null references auth.users(id) on delete cascade,
 device_id uuid not null, instance_id uuid not null, name text not null, platform text not null,
 capabilities jsonb not null, lease_until timestamptz not null, updated_at timestamptz not null,
 primary key(user_id,device_id)
);
create table private.pomodoist_app_settings_requests (
 user_id uuid not null references auth.users(id) on delete cascade,
 request_id uuid not null, client_id uuid not null, subject uuid not null, session_id uuid not null,
 device_id uuid not null, instance_id uuid not null, operation text not null, setting text,
 value jsonb, expected_version text, arguments_hash text not null,
 status text not null check(status in ('pending','claimed','applied','error','expired','uncertain')),
 result jsonb, created_at timestamptz not null, claim_deadline timestamptz not null, execution_deadline timestamptz,
 primary key(user_id,request_id),
 foreign key(user_id,device_id) references private.pomodoist_app_settings_devices on delete cascade
);
create index on private.pomodoist_app_settings_requests(user_id,device_id,created_at);
alter table private.pomodoist_app_settings_devices enable row level security;
alter table private.pomodoist_app_settings_requests enable row level security;
revoke all on private.pomodoist_app_settings_devices,private.pomodoist_app_settings_requests from public,anon,authenticated,service_role;

create function private.pomodoist_app_settings_json_safe(value jsonb, allow_source boolean default false, depth integer default 0)
returns boolean language plpgsql immutable set search_path='' as $$
declare item record; text_value text;
begin
 if value is null then return true; end if;
 if depth>8 or pg_catalog.pg_column_size(value)>32768 then return false; end if;
 if jsonb_typeof(value)='object' then
  for item in select * from jsonb_each(value) loop
   if length(item.key)>64 or item.key ~* '(bytes|base64|path|source.?url)' then return false; end if;
   if item.key='image_url' and allow_source then
    if jsonb_typeof(item.value)<>'string' or length(item.value#>>'{}')>2048 or (item.value#>>'{}') !~ '^https://[^/@[:space:]]+([/?#]|$)' then return false; end if;
   elsif not private.pomodoist_app_settings_json_safe(item.value,false,depth+1) then return false; end if;
  end loop;
 elsif jsonb_typeof(value)='array' then
  if jsonb_array_length(value)>128 then return false; end if;
  for item in select * from jsonb_array_elements(value) loop
   if not private.pomodoist_app_settings_json_safe(item.value,false,depth+1) then return false; end if;
  end loop;
 elsif jsonb_typeof(value)='string' then
  text_value:=value#>>'{}';
  if length(text_value)>2048 or text_value ~* '(https?://|data:|file:|^[\\/].+|^[a-z]:[\\/])' then return false; end if;
 end if;
 return true;
end $$;

create function private.pomodoist_app_settings_prune(actor uuid) returns void
language plpgsql set search_path='' as $$
begin
 update private.pomodoist_app_settings_requests r set status=case when r.status='pending' then 'expired' else 'uncertain' end,
  value=null, result=jsonb_build_object('status','error','code',case when r.status='pending' then 'request_expired' else 'outcome_uncertain' end)
 where r.user_id=actor and r.status in ('pending','claimed') and (
  (r.status='pending' and r.claim_deadline<=clock_timestamp()) or (r.status='claimed' and r.execution_deadline<=clock_timestamp()) or r.created_at<clock_timestamp()-interval '24 hours' or not exists(
   select 1 from private.pomodoist_app_settings_devices d where d.user_id=r.user_id and d.device_id=r.device_id and d.instance_id=r.instance_id and d.lease_until>clock_timestamp()));
 delete from private.pomodoist_app_settings_requests where user_id=actor and created_at<clock_timestamp()-interval '24 hours' and status not in ('pending','claimed');
 delete from private.pomodoist_app_settings_requests r using (
  select user_id,request_id,row_number() over(partition by device_id order by created_at desc,request_id) ordinal
  from private.pomodoist_app_settings_requests where user_id=actor
 ) ranked where r.user_id=ranked.user_id and r.request_id=ranked.request_id and ranked.ordinal>100 and r.status not in ('pending','claimed');
 delete from private.pomodoist_app_settings_devices d where user_id=actor and updated_at<clock_timestamp()-interval '24 hours' and not exists(
  select 1 from private.pomodoist_app_settings_requests r where r.user_id=d.user_id and r.device_id=d.device_id);
end $$;

create function private.pomodoist_app_settings_receipt(r private.pomodoist_app_settings_requests) returns jsonb
language sql stable set search_path='' as $$
 select jsonb_build_object('request_id',r.request_id,'device_id',r.device_id,'status',r.status) || case when r.result is null then '{}'::jsonb else jsonb_build_object('result',r.result) end;
$$;

create function public.pomodoist_app_settings_agent(p_subject uuid,p_session_id uuid,p_client_id uuid,p_command jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid; action text:=p_command->>'action'; device uuid; request uuid; d private.pomodoist_app_settings_devices%rowtype;
 r private.pomodoist_app_settings_requests%rowtype; args_hash text; operation text:=p_command->>'operation'; setting text:=p_command->>'setting';
begin
 actor:=public.resolve_pomodoist_mcp_session(p_subject,p_session_id,p_client_id);
 if actor is null then raise exception using errcode='42501',message='App settings authorization revoked'; end if;
 perform pg_advisory_xact_lock(hashtextextended('pomodoist-app-settings:'||actor::text,0));
 if public.resolve_pomodoist_mcp_session(p_subject,p_session_id,p_client_id) is distinct from actor then raise exception using errcode='42501',message='App settings authorization revoked'; end if;
 if jsonb_typeof(p_command) is distinct from 'object' or pg_column_size(p_command)>16384 then raise exception using errcode='22023',message='Invalid app settings command'; end if;
 perform private.pomodoist_app_settings_prune(actor);
 if action='list' then
  return jsonb_build_object('devices',coalesce((select jsonb_agg(jsonb_build_object('device_id',device_id,'name',name,'platform',platform,'capabilities',capabilities,'online',lease_until>clock_timestamp(),'lease_until',lease_until) order by name,device_id) from private.pomodoist_app_settings_devices where user_id=actor),'[]'::jsonb));
 end if;
 request:=(p_command->>'request_id')::uuid;
 if request is null then raise exception using errcode='22023',message='request_id is required'; end if;
 select * into r from private.pomodoist_app_settings_requests where user_id=actor and request_id=request;
 if action='status' then
  if not found or r.client_id<>p_client_id then raise exception using errcode='42501',message='App settings request unavailable'; end if;
  return private.pomodoist_app_settings_receipt(r);
 elsif action<>'request' or action is null then raise exception using errcode='22023',message='Invalid app settings action'; end if;
 device:=(p_command->>'device_id')::uuid;
 args_hash:=encode(sha256(convert_to((p_command-'action')::text,'UTF8')),'hex');
 if r.request_id is not null then
  if r.client_id<>p_client_id or r.arguments_hash<>args_hash then raise exception using errcode='22023',message='App settings request_id was reused'; end if;
  return private.pomodoist_app_settings_receipt(r);
 end if;
 if operation is null or operation not in ('read','shortcut','appearance') or device is null
  or (p_command-array['action','device_id','request_id','operation','setting','value','expected_version'])<>'{}'::jsonb
  or (operation='read' and (p_command ?| array['setting','value','expected_version']))
  or (operation<>'read' and (not p_command?'value' or jsonb_typeof(p_command->'expected_version') is distinct from 'string' or coalesce(p_command->>'expected_version','')='' or length(p_command->>'expected_version')>128))
  or (operation='shortcut' and setting is distinct from 'shortcuts')
  or (operation='appearance' and (setting is null or setting not in ('themeMode','theme','customTheme','icon','statusItemStyle','bottomNavigation','taskDetailLayout','taskListStyle','taskBranchStyle','taskRowSpacing','taskTimeDisplayMode','zoom','focusTimerStyle','focusViewMode')))
  or not private.pomodoist_app_settings_json_safe(p_command->'value',true) then
  raise exception using errcode='22023',message='Invalid app settings request';
 end if;
 if operation='shortcut' and (jsonb_typeof(p_command->'value')<>'object' or coalesce(p_command#>>'{value,command}','') not in ('toggleSidebar','togglePomo','toggleTaskDetails','toggleTaskDetailsAlternate','quickAdd','browse','search','today','upcoming','focus','focusAlternate','inbox','priorityMatrix','calendar','timeline','kanban','reports','settings','globalQuickAdd') or not (p_command->'value')?'binding' or ((p_command->'value')-array['command','binding','enabled'])<>'{}'::jsonb) then raise exception using errcode='22023',message='Invalid shortcut request'; end if;
 select * into d from private.pomodoist_app_settings_devices where user_id=actor and device_id=device;
 if not found then raise exception using errcode='42501',message='App settings device unavailable'; end if;
 -- Keep at most 100 receipts, pruning an oldest terminal receipt before admission.
 if (select count(*) from private.pomodoist_app_settings_requests where user_id=actor and device_id=device)>=100 then
  delete from private.pomodoist_app_settings_requests where (user_id,request_id) in (select user_id,request_id from private.pomodoist_app_settings_requests where user_id=actor and device_id=device and status not in ('pending','claimed') order by created_at,request_id limit 1);
  if not found then raise exception using errcode='22023',message='Too many pending app settings requests'; end if;
 end if;
 insert into private.pomodoist_app_settings_requests(user_id,request_id,client_id,subject,session_id,device_id,instance_id,operation,setting,value,expected_version,arguments_hash,status,created_at,claim_deadline)
 values(actor,request,p_client_id,p_subject,p_session_id,device,d.instance_id,operation,setting,p_command->'value',p_command->>'expected_version',args_hash,'pending',clock_timestamp(),clock_timestamp()+interval '15 seconds') returning * into r;
 if d.lease_until<=clock_timestamp() then
  update private.pomodoist_app_settings_requests set status='error',value=null,result='{"status":"error","code":"device_offline"}' where user_id=actor and request_id=request returning * into r;
  return private.pomodoist_app_settings_receipt(r);
 end if;
 begin
  perform realtime.send(jsonb_build_object('appId','pomodoist','deviceId',device,'requestId',request),'changed','sync:'||actor::text||':pomodoist',true);
 exception when others then null; -- Periodic device polling repairs missed hints.
 end;
 return private.pomodoist_app_settings_receipt(r);
end $$;

create function private.pomodoist_app_settings_device(p_command jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); action text:=p_command->>'action'; device uuid:=(p_command->>'deviceId')::uuid; instance uuid:=(p_command->>'instanceId')::uuid;
 d private.pomodoist_app_settings_devices%rowtype; r private.pomodoist_app_settings_requests%rowtype; v_result jsonb;
begin
 if actor is null or not private.pomodoist_session_is_active() then raise exception using errcode='42501',message='Active app session required'; end if;
 if device is null or instance is null or jsonb_typeof(p_command) is distinct from 'object' or pg_column_size(p_command)>32768 then raise exception using errcode='22023',message='Invalid app settings device command'; end if;
 perform pg_advisory_xact_lock(hashtextextended('pomodoist-app-settings:'||actor::text,0));
 if not private.pomodoist_session_is_active() then raise exception using errcode='42501',message='Active app session required'; end if;
 perform private.pomodoist_app_settings_prune(actor);
 select * into d from private.pomodoist_app_settings_devices where user_id=actor and device_id=device;
 if action='register' then
  if d.device_id is not null and d.instance_id<>instance and d.lease_until>clock_timestamp() then return jsonb_build_object('registered',false,'code','device_in_use','lease_until',d.lease_until); end if;
  if jsonb_typeof(p_command->'name') is distinct from 'string' or not private.pomodoist_app_settings_json_safe(p_command->'name') or coalesce(length(p_command->>'name'),0) not between 1 and 128 or coalesce(p_command->>'platform','') not in ('macOS','windows','linux','android','iOS','web') or jsonb_typeof(p_command->'capabilities') is distinct from 'object' or pg_column_size(p_command->'capabilities')>8192 or not private.pomodoist_app_settings_json_safe(p_command->'capabilities') then raise exception using errcode='22023',message='Invalid app settings device metadata'; end if;
  insert into private.pomodoist_app_settings_devices(user_id,device_id,instance_id,name,platform,capabilities,lease_until,updated_at)
   values(actor,device,instance,p_command->>'name',p_command->>'platform',p_command->'capabilities',clock_timestamp()+interval '60 seconds',clock_timestamp())
   on conflict(user_id,device_id) do update set instance_id=excluded.instance_id,name=excluded.name,platform=excluded.platform,capabilities=excluded.capabilities,lease_until=excluded.lease_until,updated_at=excluded.updated_at returning * into d;
  -- A restarted runtime cannot claim commands addressed to its predecessor.
  perform private.pomodoist_app_settings_prune(actor);
  return jsonb_build_object('registered',true,'device_id',device,'instance_id',instance,'lease_until',d.lease_until);
 end if;
 if d.device_id is null or d.instance_id<>instance or d.lease_until<=clock_timestamp() then return jsonb_build_object('commands','[]'::jsonb,'code','device_offline'); end if;
 if action='disconnect' then
  update private.pomodoist_app_settings_devices set lease_until=clock_timestamp() where user_id=actor and device_id=device;
  perform private.pomodoist_app_settings_prune(actor);
  return jsonb_build_object('disconnected',true);
 elsif action='claim' then
  select * into r from private.pomodoist_app_settings_requests where user_id=actor and device_id=device and instance_id=instance and status='claimed';
  if found then
   if public.resolve_pomodoist_mcp_session(r.subject,r.session_id,r.client_id) is distinct from actor then
    update private.pomodoist_app_settings_requests set status='uncertain',value=null,result='{"status":"error","code":"outcome_uncertain"}' where user_id=actor and request_id=r.request_id;
    return jsonb_build_object('commands','[]'::jsonb);
   end if;
   -- Retrying a lost claim response is safe only within the same runtime instance.
   return jsonb_build_object('commands',jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('request_id',r.request_id,'operation',r.operation,'setting',r.setting,'expected_version',r.expected_version)) || case when r.operation='read' then '{}'::jsonb else jsonb_build_object('value',r.value) end));
  end if;
  for r in select * from private.pomodoist_app_settings_requests where user_id=actor and device_id=device and instance_id=instance and status='pending' order by created_at,request_id loop
   if public.resolve_pomodoist_mcp_session(r.subject,r.session_id,r.client_id) is distinct from actor then
    update private.pomodoist_app_settings_requests set status='error',value=null,result='{"status":"error","code":"authorization_revoked"}' where user_id=actor and request_id=r.request_id;
    continue;
   end if;
   update private.pomodoist_app_settings_requests set status='claimed',execution_deadline=clock_timestamp()+interval '120 seconds' where user_id=actor and request_id=r.request_id;
   return jsonb_build_object('commands',jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('request_id',r.request_id,'operation',r.operation,'setting',r.setting,'expected_version',r.expected_version)) || case when r.operation='read' then '{}'::jsonb else jsonb_build_object('value',r.value) end));
  end loop;
  return jsonb_build_object('commands','[]'::jsonb);
 elsif action='finish' then
  select * into r from private.pomodoist_app_settings_requests where user_id=actor and request_id=(p_command->>'requestId')::uuid and device_id=device and instance_id=instance;
  if not found then raise exception using errcode='42501',message='App settings request unavailable'; end if;
  if r.status<>'claimed' then return private.pomodoist_app_settings_receipt(r); end if;
  v_result:=p_command->'result';
  if jsonb_typeof(v_result) is distinct from 'object' or coalesce(v_result->>'status','') not in ('applied','error') or not private.pomodoist_app_settings_json_safe(v_result) then raise exception using errcode='22023',message='Invalid app settings result'; end if;
  update private.pomodoist_app_settings_requests set status=v_result->>'status',value=null,result=v_result where user_id=actor and request_id=r.request_id returning * into r;
  return private.pomodoist_app_settings_receipt(r);
 else raise exception using errcode='22023',message='Invalid app settings device action'; end if;
end $$;

revoke all on function private.pomodoist_app_settings_json_safe(jsonb,boolean,integer),private.pomodoist_app_settings_prune(uuid),private.pomodoist_app_settings_receipt(private.pomodoist_app_settings_requests) from public,anon,authenticated,service_role;
create function api_v1.pomodoist_app_settings_device(p_command jsonb) returns jsonb
language sql security invoker set search_path='' as $$ select private.pomodoist_app_settings_device(p_command); $$;

revoke all on function private.pomodoist_app_settings_device(jsonb) from public,anon,authenticated,service_role;
grant execute on function private.pomodoist_app_settings_device(jsonb) to authenticated;
revoke all on function public.pomodoist_app_settings_agent(uuid,uuid,uuid,jsonb),api_v1.pomodoist_app_settings_device(jsonb) from public,anon,authenticated,service_role;
grant execute on function public.pomodoist_app_settings_agent(uuid,uuid,uuid,jsonb) to service_role;
grant execute on function api_v1.pomodoist_app_settings_device(jsonb) to authenticated;
notify pgrst,'reload schema';

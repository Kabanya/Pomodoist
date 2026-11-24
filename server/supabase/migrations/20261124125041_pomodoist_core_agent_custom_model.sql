create function private.pomodoist_custom_model_grant(owner_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$
  with owned as (
    -- Apple signs the expiry and revocation of each individual payment.
    -- A fresh refund of an older transaction may be the chain's latest
    -- notification even while a different monthly payment is still valid.
    select p.product_id, p.valid_until
    from public.pomodoist_purchase_claims c
    join private.pomodoist_custom_model_payments p
      on p.store = 'app_store' and p.claim_id = c.original_transaction_id
    where c.linked_user_id = owner_id and not p.revoked
    union all
    select p.product_id, case when c.status = 'active' and c.product_id = p.product_id
      then least(p.valid_until, c.valid_until) end
    from private.pomodoist_stripe_claims c
    join private.pomodoist_custom_model_payments p
      on p.store = 'stripe' and p.claim_id = c.stripe_object_id
    where c.user_id = owner_id and not p.revoked
  )
  select jsonb_build_object(
    'permanent', coalesce(bool_or(product_id in ('pomodoist.pro.annual',
      'pomodoist.pro.lifetime', 'pomodoist.pro.lifetime.launch')), false),
    'validUntil', max(valid_until) filter
      (where product_id = 'pomodoist.pro.monthly' and valid_until > now())
  ) from owned;
$$;

revoke all on function private.pomodoist_custom_model_grant(uuid) from public, anon, authenticated, service_role;

create or replace function private.pomodoist_custom_model_access() returns jsonb
language sql stable security definer set search_path = '' as $$
  select private.pomodoist_custom_model_grant(auth.uid());
$$;

create function private.pomodoist_has_custom_model(owner_id uuid) returns boolean
language sql stable set search_path = '' as $$
  select (g->>'permanent')::boolean or coalesce((g->>'validUntil')::timestamptz > now(), false)
  from private.pomodoist_custom_model_grant(owner_id) g;
$$;
revoke all on function private.pomodoist_has_custom_model(uuid) from public, anon, authenticated, service_role;

-- Validate incoming changes and the public projection separately. Only the
-- selected device's claim may contain a credential, never a settings receipt.
create function private.pomodoist_model_settings_valid(v jsonb, snapshot boolean) returns boolean
language plpgsql immutable set search_path = '' as $$
declare endpoint text := v->>'baseUrl';
begin
  if jsonb_typeof(v) is distinct from 'object' or jsonb_typeof(v->'enabled') is distinct from 'boolean'
    then return false; end if;
  if snapshot then
    if v - array['enabled','baseUrl','normalModel','smartModel','hasKey'] <> '{}'::jsonb
      or jsonb_typeof(v->'hasKey') is distinct from 'boolean'
      or jsonb_typeof(v->'smartModel') is distinct from 'string' then return false; end if;
  elsif v->'enabled' = 'false'::jsonb then
    return v = '{"enabled":false}'::jsonb;
  elsif v - array['enabled','baseUrl','normalModel','smartModel','apiKey'] <> '{}'::jsonb
    or (v ? 'apiKey' and (jsonb_typeof(v->'apiKey') <> 'string'
      or length(v->>'apiKey') > 4096 or v->>'apiKey' ~ '[[:cntrl:]]')) then return false;
  end if;
  return jsonb_typeof(v->'baseUrl') is not distinct from 'string'
    and jsonb_typeof(v->'normalModel') is not distinct from 'string'
    and (v->'enabled' = 'false'::jsonb or length(trim(v->>'normalModel')) > 0)
    and length(v->>'normalModel') <= 256 and v->>'normalModel' !~ '[[:cntrl:]]'
    and (not v ? 'smartModel' or (jsonb_typeof(v->'smartModel') = 'string'
      and length(v->>'smartModel') <= 256 and v->>'smartModel' !~ '[[:cntrl:]]'))
    and length(endpoint) <= 2048 and endpoint !~ '[[:space:][:cntrl:]?#]' and strpos(endpoint,chr(92)) = 0
    and ((v->'enabled' = 'false'::jsonb and endpoint = '')
      or endpoint ~* '^https://[^/@%[:space:]]+(/|$)'
      or endpoint ~* '^http://(localhost|127([.][0-9]{1,3}){3}|\[([0:]*:)?(:1|0*1)\])(:[0-9]+)?(/|$)');
end $$;
revoke all on function private.pomodoist_model_settings_valid(jsonb,boolean) from public, anon, authenticated, service_role;

-- Vault holds a supplied key only while its per-device request is deliverable.
alter table private.pomodoist_app_settings_requests add column credential_id uuid;
create function private.pomodoist_app_settings_credential() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    if new.operation = 'customModel' and coalesce(new.value->>'apiKey','') <> '' then
      new.credential_id := vault.create_secret(new.value->>'apiKey');
      new.value := new.value - 'apiKey';
    end if;
    return new;
  end if;
  if old.credential_id is not null then
    if tg_op = 'DELETE' or new.value is null then
      delete from vault.secrets where id = old.credential_id;
      if tg_op = 'UPDATE' then new.credential_id := null; end if;
    end if;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end $$;
revoke all on function private.pomodoist_app_settings_credential() from public, anon, authenticated, service_role;
create trigger app_settings_credential before insert or update of value or delete
  on private.pomodoist_app_settings_requests for each row execute function private.pomodoist_app_settings_credential();

create function private.pomodoist_app_settings_claim(r private.pomodoist_app_settings_requests) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object('commands', jsonb_build_array(
    jsonb_strip_nulls(jsonb_build_object('request_id',r.request_id,'operation',r.operation,
      'setting',r.setting,'expected_version',r.expected_version))
    || case when r.operation='read' then '{}'::jsonb else jsonb_build_object('value',
      case when r.credential_id is null then r.value else r.value || jsonb_build_object('apiKey',
        (select decrypted_secret from vault.decrypted_secrets where id=r.credential_id)) end) end));
$$;
revoke all on function private.pomodoist_app_settings_claim(private.pomodoist_app_settings_requests) from public, anon, authenticated, service_role;

-- A device lease or a completed read can outlive the underlying purchase.
create function private.pomodoist_model_capabilities(caps jsonb, allowed boolean) returns jsonb
language sql immutable set search_path = '' as $$
  select case when not allowed and caps->'operations' ? 'customModel'
    then jsonb_set(caps,'{operations}',(caps->'operations')-'customModel') else caps end;
$$;
revoke all on function private.pomodoist_model_capabilities(jsonb,boolean) from public, anon, authenticated, service_role;

create or replace function private.pomodoist_app_settings_receipt(r private.pomodoist_app_settings_requests)
returns jsonb language plpgsql stable set search_path = '' as $$
declare result jsonb := r.result;
begin
  if (r.operation='customModel' or result#>'{values,customModel}' is not null
      or result#>'{versions,customModel}' is not null or result#>'{capabilities,operations}' ? 'customModel')
     and not private.pomodoist_has_custom_model(r.user_id) then
    if r.operation='customModel' then
      result := result - array['value','setting','version'];
    else
      result := result #- '{values,customModel}' #- '{versions,customModel}';
      if result ? 'capabilities' then
        result := jsonb_set(result,'{capabilities}',private.pomodoist_model_capabilities(result->'capabilities',false));
      end if;
    end if;
  end if;
  return jsonb_build_object('request_id',r.request_id,'device_id',r.device_id,'status',r.status)
    || case when result is null then '{}'::jsonb else jsonb_build_object('result',result) end;
end $$;

create or replace function public.pomodoist_app_settings_agent(p_subject uuid,p_session_id uuid,p_client_id uuid,p_command jsonb)
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
  return jsonb_build_object('devices',coalesce((select jsonb_agg(jsonb_build_object('device_id',device_id,'name',name,'platform',platform,'capabilities',private.pomodoist_model_capabilities(capabilities,(select private.pomodoist_has_custom_model(actor))),'online',lease_until>clock_timestamp(),'lease_until',lease_until) order by name,device_id) from private.pomodoist_app_settings_devices where user_id=actor),'[]'::jsonb));
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
 if operation is null or operation not in ('read','shortcut','appearance','customModel') or device is null
  or (p_command-array['action','device_id','request_id','operation','setting','value','expected_version'])<>'{}'::jsonb
  or (operation='read' and (p_command ?| array['setting','value','expected_version']))
  or (operation<>'read' and (not p_command?'value' or jsonb_typeof(p_command->'expected_version') is distinct from 'string' or coalesce(p_command->>'expected_version','')='' or length(p_command->>'expected_version')>128))
  or (operation='shortcut' and setting is distinct from 'shortcuts')
  or (operation='appearance' and (setting is null or setting not in ('themeMode','theme','customTheme','icon','statusItemStyle','bottomNavigation','taskDetailLayout','taskListStyle','taskBranchStyle','taskRowSpacing','taskTimeDisplayMode','zoom','focusTimerStyle','focusViewMode')))
  or (operation='customModel' and (setting is distinct from 'customModel'
      or not private.pomodoist_model_settings_valid(p_command->'value',false)))
  or (operation<>'customModel' and not private.pomodoist_app_settings_json_safe(p_command->'value',true)) then
  raise exception using errcode='22023',message='Invalid app settings request';
 end if;
 if operation='customModel' and not private.pomodoist_has_custom_model(actor) then
  raise exception using errcode='42501',message='Custom model access unavailable';
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

create or replace function private.pomodoist_app_settings_device(p_command jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); action text:=p_command->>'action'; device uuid:=(p_command->>'deviceId')::uuid; instance uuid:=(p_command->>'instanceId')::uuid;
 d private.pomodoist_app_settings_devices%rowtype; r private.pomodoist_app_settings_requests%rowtype; v_result jsonb; checked_result jsonb; model jsonb;
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
   if public.resolve_pomodoist_mcp_session(r.subject,r.session_id,r.client_id) is distinct from actor
     or (r.operation='customModel' and not private.pomodoist_has_custom_model(actor)) then
    update private.pomodoist_app_settings_requests set status='uncertain',value=null,result='{"status":"error","code":"outcome_uncertain"}' where user_id=actor and request_id=r.request_id;
    return jsonb_build_object('commands','[]'::jsonb);
   end if;
   -- Retrying a lost claim response is safe only within the same runtime instance.
   return private.pomodoist_app_settings_claim(r);
  end if;
  for r in select * from private.pomodoist_app_settings_requests where user_id=actor and device_id=device and instance_id=instance and status='pending' order by created_at,request_id loop
   if public.resolve_pomodoist_mcp_session(r.subject,r.session_id,r.client_id) is distinct from actor
     or (r.operation='customModel' and not private.pomodoist_has_custom_model(actor)) then
    update private.pomodoist_app_settings_requests set status='error',value=null,result='{"status":"error","code":"authorization_revoked"}' where user_id=actor and request_id=r.request_id;
    continue;
   end if;
   update private.pomodoist_app_settings_requests set status='claimed',execution_deadline=clock_timestamp()+interval '120 seconds' where user_id=actor and request_id=r.request_id;
   return private.pomodoist_app_settings_claim(r);
  end loop;
  return jsonb_build_object('commands','[]'::jsonb);
 elsif action='finish' then
  select * into r from private.pomodoist_app_settings_requests where user_id=actor and request_id=(p_command->>'requestId')::uuid and device_id=device and instance_id=instance;
  if not found then raise exception using errcode='42501',message='App settings request unavailable'; end if;
  if r.status<>'claimed' then return private.pomodoist_app_settings_receipt(r); end if;
  v_result:=p_command->'result';
  checked_result:=v_result;
  if r.operation='read' and (v_result#>'{values,customModel}') is not null then
   model:=v_result#>'{values,customModel}';
   checked_result:=v_result #- '{values,customModel}';
  elsif r.operation='customModel' and v_result?'value' then
   model:=v_result->'value';
   checked_result:=v_result-'value';
  end if;
  if (model is not null and not private.pomodoist_model_settings_valid(model,true))
   or jsonb_path_exists(v_result,'$.**.apiKey')
   or jsonb_typeof(v_result) is distinct from 'object' or coalesce(v_result->>'status','') not in ('applied','error') or not private.pomodoist_app_settings_json_safe(checked_result) then raise exception using errcode='22023',message='Invalid app settings result'; end if;
  update private.pomodoist_app_settings_requests set status=v_result->>'status',value=null,result=v_result where user_id=actor and request_id=r.request_id returning * into r;
  return private.pomodoist_app_settings_receipt(r);
 else raise exception using errcode='22023',message='Invalid app settings device action'; end if;
end $$;

notify pgrst,'reload schema';

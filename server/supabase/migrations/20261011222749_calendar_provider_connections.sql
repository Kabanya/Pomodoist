-- Canonical calendar state is private. Client projections contain no credentials.
create table private.pomodoist_calendar_connections (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
  provider text not null check(provider in ('google','outlook')), account_id text, account_email text,
  credential_id uuid, calendar_id text, status text not null default 'connecting', generation bigint not null default 1,
  state jsonb not null default '{}', work jsonb not null default '{"generation":0,"hints":[],"publishRevision":null,"refresh":true,"recovery":false,"maintenance":false}',
  job_generation bigint not null default 0, due_at timestamptz not null default now(), recovery_at timestamptz not null default now(),
  lease uuid, lease_until timestamptz, attempts integer not null default 0, last_error text,
  last_sync_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(user_id,provider)
);
create index pomodoist_calendar_due on private.pomodoist_calendar_connections(provider,due_at) where status <> 'disconnected';
create unique index pomodoist_calendar_subscription on private.pomodoist_calendar_connections((state->>'subscriptionId')) where state->>'subscriptionId' is not null;
create table private.pomodoist_calendar_links (
  connection_id uuid not null references private.pomodoist_calendar_connections(id) on delete cascade,
  task_id text not null, event_id text not null, data jsonb not null,
  primary key(connection_id,task_id), unique(connection_id,event_id)
);
create table private.pomodoist_calendar_task_state (
  user_id uuid not null references public.profiles(id) on delete cascade, task_id text not null,
  incarnation bigint not null default 1, cleared_incarnation bigint, snapshot jsonb not null default '{}',
  primary key(user_id,task_id)
);
create table private.pomodoist_calendar_oauth_states (
  state_hash text primary key, user_id uuid not null references public.profiles(id) on delete cascade,
  provider text not null check(provider in ('google','outlook')), verifier text not null, expires_at timestamptz not null
);
create table private.pomodoist_calendar_workers (
  provider text primary key check(provider in ('google','outlook')), url text not null, secret_id uuid not null
);
create table private.pomodoist_calendar_effects (
  connection_id uuid not null references private.pomodoist_calendar_connections(id) on delete cascade,
  task_id text not null, revision bigint not null, incarnation bigint not null, kind text not null,
  event_id text, fields jsonb not null, primary key(connection_id,task_id)
);
alter table private.pomodoist_calendar_connections enable row level security;
alter table private.pomodoist_calendar_links enable row level security;
alter table private.pomodoist_calendar_task_state enable row level security;
alter table private.pomodoist_calendar_oauth_states enable row level security;
alter table private.pomodoist_calendar_workers enable row level security;
alter table private.pomodoist_calendar_effects enable row level security;
revoke all on private.pomodoist_calendar_connections, private.pomodoist_calendar_links,
 private.pomodoist_calendar_task_state, private.pomodoist_calendar_oauth_states,
 private.pomodoist_calendar_workers, private.pomodoist_calendar_effects from public, anon, authenticated;

create function private.calendar_snapshot(p_id uuid) returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object('id',c.id,'userId',c.user_id,'provider',c.provider,'generation',c.generation,'lease',c.lease,
 'calendarId',c.calendar_id,'state',c.state,'work',c.work || jsonb_build_object('generation',c.job_generation),
 'tasks',coalesce((select jsonb_agg(e.data || jsonb_build_object('id',e.entity_id,'_revision',e.server_revision,
   '_clientUpdatedAt',e.client_updated_at,'_deletedAt',e.deleted_at,'_fieldClock',e.field_clock,
   '_metadata',jsonb_build_object('incarnation',coalesce(s.incarnation,1),'clearedIncarnation',s.cleared_incarnation,'snapshot',coalesce(s.snapshot,'{}'))))
   from public.sync_entities e left join private.pomodoist_calendar_task_state s on s.user_id=e.user_id and s.task_id=e.entity_id
   where e.user_id=c.user_id and e.app_id='pomodoist' and e.entity_type='task'),'[]'),
 'links',coalesce((select jsonb_agg(l.data) from private.pomodoist_calendar_links l where l.connection_id=c.id),'[]'),
 'pendingEffects',coalesce((select jsonb_agg(jsonb_build_object('taskId',f.task_id,'revision',f.revision,'incarnation',f.incarnation,'kind',f.kind,'eventId',f.event_id,'fields',f.fields)) from private.pomodoist_calendar_effects f where f.connection_id=c.id),'[]'))
 from private.pomodoist_calendar_connections c where c.id=p_id;
$$;

create function private.calendar_project(p_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare c private.pomodoist_calendar_connections; payload jsonb; stamp timestamptz:=clock_timestamp();
begin
 select * into c from private.pomodoist_calendar_connections where id=p_id;
 if not found then return; end if;
 payload:=jsonb_build_object('id',c.provider,'provider',c.provider,'connectionId',c.id,
 'accountEmail',c.account_email,'calendarId',case when c.status='disconnected' then null else c.calendar_id end,
 'calendarName','Pomodoist','ownerDeviceId','calendar-server','status',c.status,'lastError',c.last_error,
 'warning',case when exists(select 1 from private.pomodoist_calendar_links where connection_id=c.id and data->>'unsupportedReason' is not null) then 'unsupported_event' else c.state->>'warning' end,'lastSyncFinishedAt',c.last_sync_at,'createdAt',c.created_at,'updatedAt',stamp);
 perform set_config('pomodoist.calendar_projecting','true',true);
 update public.sync_entities set deleted_at=null where user_id=c.user_id and app_id='pomodoist' and deleted_at is not null and ((entity_type='calendar_connection' and entity_id=c.provider) or (c.provider='google' and entity_type='google_calendar_connection' and entity_id='primary'));
 perform private.push_changes_for_user(c.user_id,'pomodoist','calendar-server',jsonb_build_array(jsonb_build_object(
 'opId',gen_random_uuid()::text,'entityType','calendar_connection','entityId',c.provider,'operation','upsert','payload',payload,'clientUpdatedAt',stamp)));
 if c.provider='google' then
  perform private.push_changes_for_user(c.user_id,'pomodoist','google-calendar-server',jsonb_build_array(jsonb_build_object(
   'opId',gen_random_uuid()::text,'entityType','google_calendar_connection','entityId','primary','operation','upsert',
   'payload',payload || jsonb_build_object('id','primary','ownerDeviceId','google-calendar-server'),'clientUpdatedAt',stamp)));
 end if;
 perform set_config('pomodoist.calendar_projecting','false',true);
 perform realtime.send(jsonb_build_object('appId','pomodoist','deviceId','calendar-server'),'changed','sync:'||c.user_id::text||':pomodoist',true);
end $$;

create function private.calendar_wake(p_provider text) returns void language plpgsql security definer set search_path='' as $$
declare cfg record;
begin
 if not exists(select 1 from private.pomodoist_calendar_connections where provider=p_provider and (status not in ('disconnected','reconnect_required') or state->>'cleanupPending'='true')
   and due_at<=now() and (lease_until is null or lease_until<=now())) then return; end if;
 select w.url,v.decrypted_secret into cfg from private.pomodoist_calendar_workers w join vault.decrypted_secrets v on v.id=w.secret_id where w.provider=p_provider;
 if found then perform net.http_post(url:=cfg.url,headers:=jsonb_build_object('Content-Type','application/json','X-Pomodoist-Worker-Secret',cfg.decrypted_secret),body:='{}',timeout_milliseconds:=55000); end if;
end $$;

create function private.calendar_enqueue(p_id uuid,p_work jsonb) returns void language plpgsql security definer set search_path='' as $$
declare c private.pomodoist_calendar_connections; hints jsonb;
begin
 select * into c from private.pomodoist_calendar_connections where id=p_id for update;
 if not found or c.status='disconnected' then return; end if;
 select coalesce(jsonb_agg(x.value),'[]') into hints from (
   select distinct on(value->>'eventId') value from jsonb_array_elements(
    coalesce(c.work->'hints','[]') || coalesce(p_work->'hints','[]')) with ordinality a(value,n) order by value->>'eventId',n desc
 ) x;
 update private.pomodoist_calendar_connections set job_generation=job_generation+1,due_at=least(due_at,now()),
 work=jsonb_build_object('generation',job_generation+1,'hints',case when jsonb_array_length(hints)>1000 then '[]'::jsonb else hints end,
 'publishRevision',greatest((work->>'publishRevision')::bigint,(p_work->>'publishRevision')::bigint),
 'refresh',coalesce((work->>'refresh')::boolean,false) or coalesce((p_work->>'refresh')::boolean,false),
 'recovery',coalesce((work->>'recovery')::boolean,false) or coalesce((p_work->>'recovery')::boolean,false) or jsonb_array_length(hints)>1000,
 'maintenance',coalesce((work->>'maintenance')::boolean,false) or coalesce((p_work->>'maintenance')::boolean,false)),updated_at=now() where id=p_id;
 if c.lease_until is null or c.lease_until<=now() then perform private.calendar_wake(c.provider); end if;
end $$;

-- Retain the existing trigger name and per-user lock used by account writes.
create or replace function private.on_pomodoist_task_calendar_change() returns trigger language plpgsql security definer set search_path='' as $$
declare uid uuid; tid text; c record; origin text:=current_setting('pomodoist.calendar_origin',true); changed boolean;
begin
 if tg_op='DELETE' then uid:=old.user_id; tid:=old.entity_id;
  if old.app_id<>'pomodoist' or old.entity_type<>'task' or not exists(select 1 from public.profiles where id=uid) then return old; end if;
 else uid:=new.user_id; tid:=new.entity_id;
  if new.app_id<>'pomodoist' or new.entity_type<>'task' then return new; end if;
  if tg_op='UPDATE' then
   changed:=old.deleted_at is distinct from new.deleted_at or
    (old.data->'content',old.data->'description',old.data->'status',old.data->'dueJson',old.data->'durationSeconds') is distinct from
    (new.data->'content',new.data->'description',new.data->'status',new.data->'dueJson',new.data->'durationSeconds');
   if not changed then return new; end if;
  end if;
 end if;
 insert into private.pomodoist_calendar_task_state(user_id,task_id) values(uid,tid) on conflict do nothing;
 if coalesce(origin,'')='' and tg_op='UPDATE' then
  if (old.data->>'dueJson') is null and (new.data->>'dueJson') is not null then
   update private.pomodoist_calendar_task_state set incarnation=incarnation+1 where user_id=uid and task_id=tid;
  elsif (old.data->>'dueJson') is not null and (new.data->>'dueJson') is null then
   update private.pomodoist_calendar_task_state set cleared_incarnation=incarnation where user_id=uid and task_id=tid;
  end if;
 end if;
 for c in select id from private.pomodoist_calendar_connections where user_id=uid and status<>'disconnected' and id::text<>coalesce(origin,'') loop
  perform private.calendar_enqueue(c.id,jsonb_build_object('publishRevision',case when tg_op='DELETE' then old.server_revision else new.server_revision end));
 end loop;
 if tg_op='DELETE' then return old; end if; return new;
end $$;

create function private.calendar_service(p_action text,p_user_id uuid,p_provider text,p_payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare c private.pomodoist_calendar_connections; item jsonb; result jsonb; secret uuid; claimed jsonb; task public.sync_entities;
 stamp timestamptz; revision bigint; payload jsonb; w record; guard jsonb:=p_payload->'guard';
begin
 if p_provider is not null and p_provider not in ('google','outlook') then raise exception 'invalid_calendar_provider'; end if;
 if p_action='configure' then
  if p_provider is null or coalesce(p_payload->>'url','') not like 'https://%' or length(coalesce(p_payload->>'secret',''))<16 then raise exception 'invalid_worker_configuration'; end if;
  select secret_id into secret from private.pomodoist_calendar_workers where provider=p_provider;
  if secret is null then secret:=vault.create_secret(p_payload->>'secret','pomodoist-calendar-worker-'||p_provider);
  else perform vault.update_secret(secret,p_payload->>'secret',null,null); end if;
  insert into private.pomodoist_calendar_workers(provider,url,secret_id) values(p_provider,p_payload->>'url',secret)
   on conflict(provider) do update set url=excluded.url,secret_id=excluded.secret_id;
  return '{}';
 elsif p_action='store_state' then
  delete from private.pomodoist_calendar_oauth_states where expires_at<now();
  insert into private.pomodoist_calendar_oauth_states values(p_payload->>'stateHash',p_user_id,p_provider,p_payload->>'verifier',least((p_payload->>'expiresAt')::timestamptz,now()+interval '10 minutes'));
  return '{}';
 elsif p_action='consume_state' then
  delete from private.pomodoist_calendar_oauth_states where state_hash=p_payload->>'stateHash' and provider=p_provider and expires_at>now()
   returning jsonb_build_object('userId',user_id,'verifier',verifier) into result; return result;
 elsif p_action='subscription' then
  select * into c from private.pomodoist_calendar_connections where state->>'subscriptionId'=p_payload->>'subscriptionId' and status<>'disconnected';
  if not found then return null; end if;
  return jsonb_build_object('connectionId',c.id,'generation',c.generation,'clientStateHash',c.state->>'clientStateHash','resource','me/events');
 elsif p_action='google_webhook' then
  select * into c from private.pomodoist_calendar_connections where provider='google' and status<>'disconnected'
   and state->>'watchChannelId'=p_payload->>'channelId' and state->>'watchResourceId'=p_payload->>'resourceId' and state->>'watchTokenHash'=p_payload->>'tokenHash';
  if not found then return jsonb_build_object('accepted',false); end if;
  perform private.calendar_enqueue(c.id,'{"refresh":true}'); return jsonb_build_object('accepted',true);
 elsif p_action='enqueue_notification' then
  select * into c from private.pomodoist_calendar_connections where id=(p_payload->>'connectionId')::uuid and generation=(p_payload->>'generation')::bigint and status<>'disconnected';
  if found then perform private.calendar_enqueue(c.id,p_payload->'work'); end if; return '{}';
 elsif p_action='claim' then
  result:='[]';
  for c in select * from private.pomodoist_calendar_connections where provider=p_provider and (status not in ('disconnected','reconnect_required') or state->>'cleanupPending'='true') and due_at<=now()
    and (lease_until is null or lease_until<=now()) order by due_at limit 10 for update skip locked loop
   update private.pomodoist_calendar_connections set lease=gen_random_uuid(),lease_until=now()+interval '5 minutes',
    work=work || jsonb_build_object('recovery',recovery_at<=now() or coalesce((work->>'recovery')::boolean,false)),updated_at=now() where id=c.id;
   select to_jsonb(decrypted_secret) into payload from vault.decrypted_secrets where id=c.credential_id;
   result:=result || jsonb_build_array(private.calendar_snapshot(c.id) || jsonb_build_object('credentials',payload));
  end loop; return result;
 end if;
 if p_user_id is null then raise exception 'user_id_required'; end if;
 perform pg_advisory_xact_lock(hashtextextended('pomodoist-google-calendar:'||p_user_id::text,0));
 if p_action='connect' then
  select * into c from private.pomodoist_calendar_connections where user_id=p_user_id and provider=p_provider for update;
  if not found then
   secret:=vault.create_secret(jsonb_build_object('refreshToken',p_payload->>'refreshToken')::text);
   insert into private.pomodoist_calendar_connections(user_id,provider,account_id,account_email,credential_id)
    values(p_user_id,p_provider,p_payload->>'accountId',p_payload->>'accountEmail',secret) returning * into c;
  else
   if c.credential_id is null then
    secret:=vault.create_secret(jsonb_build_object('refreshToken',p_payload->>'refreshToken')::text);
    update private.pomodoist_calendar_connections set credential_id=secret where id=c.id;
   else perform vault.update_secret(c.credential_id,jsonb_build_object('refreshToken',p_payload->>'refreshToken')::text,null,null); end if;
   if (c.account_id is not null and c.account_id is distinct from p_payload->>'accountId') or
     (c.account_id is null and c.account_email is distinct from p_payload->>'accountEmail') then
    delete from private.pomodoist_calendar_links where connection_id=c.id;
    update private.pomodoist_calendar_connections set calendar_id=null,state='{}' where id=c.id;
   end if;
   update private.pomodoist_calendar_connections set account_id=p_payload->>'accountId',account_email=p_payload->>'accountEmail',
    generation=generation+1,status='connecting',state=state-'cleanupPending',lease=null,lease_until=null,last_error=null,due_at=now() where id=c.id;
  end if;
  perform private.calendar_enqueue(c.id,'{"recovery":true,"maintenance":true}'); perform private.calendar_project(c.id); return jsonb_build_object('id',c.id);
 end if;
 select * into c from private.pomodoist_calendar_connections where user_id=p_user_id and provider=p_provider for update;
 if not found then return '{}'; end if;
 if p_action='queue' then perform private.calendar_enqueue(c.id,'{"refresh":true}'); return '{}'; end if;
 if p_action='disconnect' then
  update private.pomodoist_calendar_connections set generation=generation+1,status='disconnected',state=state || '{"cleanupPending":true}'::jsonb,due_at=now(),lease=null,lease_until=null,last_error=null where id=c.id;
  perform private.calendar_project(c.id); perform private.calendar_wake(c.provider); return '{}';
 end if;
 if guard is null or guard->>'connectionId'<>c.id::text or (guard->>'generation')::bigint<>c.generation or guard->>'lease' is distinct from c.lease::text or c.lease_until<=now() or (c.status='disconnected' and p_action not in ('cleanup_complete','fail','refresh_token')) then
  raise exception 'stale_calendar_worker';
 end if;
 if p_action='cleanup_complete' then
  delete from vault.secrets where id=c.credential_id;
  update private.pomodoist_calendar_connections set credential_id=null,lease=null,lease_until=null,state=state-'subscriptionId'-'subscriptionExpiresAt'-'clientState'-'clientStateHash'-'watchChannelId'-'watchResourceId'-'watchTokenHash'-'watchExpiresAt'-'cleanupPending' where id=c.id; return '{}';
 elsif p_action='snapshot' then return private.calendar_snapshot(c.id);
 elsif p_action='checkpoint' then
  update private.pomodoist_calendar_connections set calendar_id=p_payload->>'calendarId',state=p_payload->'state' where id=c.id; return '{}';
 elsif p_action='refresh_token' then
  perform vault.update_secret(c.credential_id,jsonb_build_object('refreshToken',p_payload->>'refreshToken')::text,null,null); return '{}';
 elsif p_action in ('accept','prepare_effect','save_link') then
  select * into task from public.sync_entities where user_id=p_user_id and app_id='pomodoist' and entity_type='task'
   and entity_id=coalesce(p_payload->>'taskId',p_payload#>>'{task,id}') for update;
  if p_action='save_link' then
   if not exists(select 1 from private.pomodoist_calendar_effects where connection_id=c.id and task_id=p_payload->>'taskId' and revision=(p_payload->>'revision')::bigint and incarnation=(p_payload#>>'{link,incarnation}')::bigint) then raise exception 'unprepared_calendar_acknowledgement'; end if;
   item:=p_payload->'link';
   insert into private.pomodoist_calendar_links values(c.id,p_payload->>'taskId',item->>'eventId',item)
    on conflict(connection_id,task_id) do update set event_id=excluded.event_id,data=excluded.data;
   delete from private.pomodoist_calendar_effects where connection_id=c.id and task_id=p_payload->>'taskId'; return '{}';
  end if;
  if not found or task.server_revision<>coalesce((p_payload->>'expectedRevision')::bigint,(p_payload->>'revision')::bigint) then return jsonb_build_object('accepted',false); end if;
  if p_action='prepare_effect' then
   insert into private.pomodoist_calendar_effects values(c.id,task.entity_id,task.server_revision,(p_payload->>'incarnation')::bigint,p_payload->>'kind',p_payload->>'eventId',p_payload->'fields')
    on conflict(connection_id,task_id) do update set revision=excluded.revision,incarnation=excluded.incarnation,kind=excluded.kind,event_id=excluded.event_id,fields=excluded.fields;
   return jsonb_build_object('accepted',true);
  end if;
  item:=p_payload->'task'; revision:=task.server_revision;
  if (p_payload->>'taskChanged')::boolean and task.deleted_at is null then
   stamp:=greatest(clock_timestamp(),task.client_updated_at+interval '1 microsecond');
   payload:=jsonb_build_object('content',item->'content','description',item->'description','status',item->'status',
    'dueJson',case when item->'schedule'='null'::jsonb then null else (item->'schedule')::text end,
    'durationSeconds',case when item#>>'{schedule,type}'='timed' then extract(epoch from ((item#>>'{schedule,end}')::timestamptz-(item#>>'{schedule,start}')::timestamptz))::integer else null end,'updatedAt',stamp);
   perform set_config('pomodoist.calendar_origin',c.id::text,true);
   perform private.push_changes_for_user(p_user_id,'pomodoist','calendar-server',jsonb_build_array(jsonb_build_object(
    'opId',gen_random_uuid()::text,'entityType','task','entityId',task.entity_id,'operation','upsert','payload',payload,'clientUpdatedAt',stamp)));
   perform set_config('pomodoist.calendar_origin','',true);
   select server_revision into revision from public.sync_entities where user_id=p_user_id and app_id='pomodoist' and entity_type='task' and entity_id=task.entity_id;
   perform realtime.send(jsonb_build_object('appId','pomodoist','deviceId','calendar-server'),'changed','sync:'||p_user_id::text||':pomodoist',true);
  end if;
  item:=item || jsonb_build_object('revision',revision);
  insert into private.pomodoist_calendar_task_state(user_id,task_id,incarnation,cleared_incarnation,snapshot)
   values(p_user_id,task.entity_id,(item->>'incarnation')::bigint,(item->>'clearedIncarnation')::bigint,item)
   on conflict(user_id,task_id) do update set incarnation=excluded.incarnation,cleared_incarnation=excluded.cleared_incarnation,snapshot=excluded.snapshot;
  if jsonb_array_length(p_payload->'links')=0 then
   delete from private.pomodoist_calendar_links where connection_id=c.id and task_id=task.entity_id;
  end if;
  for payload in select value from jsonb_array_elements(p_payload->'links') loop
   insert into private.pomodoist_calendar_links values(c.id,task.entity_id,payload->>'eventId',payload)
    on conflict(connection_id,task_id) do update set event_id=excluded.event_id,data=excluded.data;
  end loop;
  return jsonb_build_object('task',item);
 elsif p_action='remove_link' then
  delete from private.pomodoist_calendar_links where connection_id=c.id and task_id=p_payload->>'taskId';
  delete from private.pomodoist_calendar_effects where connection_id=c.id and task_id=p_payload->>'taskId'; return '{}';
 elsif p_action='complete' then
  update private.pomodoist_calendar_connections set state=p_payload->'state',calendar_id=p_payload->>'calendarId',status='connected',last_error=null,
   last_sync_at=now(),attempts=0,lease=null,lease_until=null,
   recovery_at=case when coalesce((work->>'recovery')::boolean,false) or coalesce((work->>'refresh')::boolean,false) then now()+interval '24 hours' else recovery_at end,
   work=case when job_generation=(p_payload->>'claimedGeneration')::bigint then '{"hints":[],"publishRevision":null,"refresh":false,"recovery":false,"maintenance":false}'::jsonb else work end,
   due_at=case when job_generation<>(p_payload->>'claimedGeneration')::bigint then now() else least(now()+interval '24 hours',
     greatest(now()+interval '5 minutes',coalesce((p_payload#>>'{state,subscriptionExpiresAt}')::timestamptz-interval '24 hours',now()+interval '24 hours')),
     case when coalesce((work->>'recovery')::boolean,false) or coalesce((work->>'refresh')::boolean,false) then now()+interval '24 hours' else recovery_at end) end,
   updated_at=now() where id=c.id;
  perform private.calendar_project(c.id); perform private.calendar_wake(c.provider); return '{}';
 elsif p_action='fail' then
  update private.pomodoist_calendar_connections set lease=null,lease_until=null,status=case when status='disconnected' then 'disconnected' when p_payload->>'error'='authorization_required' then 'reconnect_required' else 'error' end,
   last_error=p_payload->>'error',attempts=attempts+1,due_at=now()+make_interval(secs=>least(3600,greatest(coalesce((p_payload->>'retrySeconds')::integer,30),30*power(2,least(attempts,7))::integer))) where id=c.id;
  perform private.calendar_project(c.id); return '{}';
 end if;
 raise exception 'unsupported_calendar_action';
end $$;

create function public.pomodoist_calendar_service(p_action text,p_user_id uuid default null,p_provider text default null,p_payload jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$ select private.calendar_service(p_action,p_user_id,p_provider,p_payload); $$;
revoke all on function public.pomodoist_calendar_service(text,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.pomodoist_calendar_service(text,uuid,text,jsonb) to service_role;
revoke all on function private.calendar_service(text,uuid,text,jsonb),private.calendar_snapshot(uuid),private.calendar_project(uuid),private.calendar_wake(text),private.calendar_enqueue(uuid,jsonb) from public,anon,authenticated;
grant usage on schema private to service_role;
grant execute on function private.calendar_service(text,uuid,text,jsonb) to service_role;

-- Keep Google credentials, calendar IDs and linked event IDs during cutover.
insert into private.pomodoist_calendar_connections(user_id,provider,account_email,credential_id,calendar_id,status,state,created_at)
 select user_id,'google',account_email,refresh_token_secret_id,calendar_id,status,
 jsonb_build_object('syncToken',sync_token,'watchChannelId',watch_channel_id,'watchResourceId',watch_resource_id,'watchTokenHash',watch_token_hash,'watchExpiresAt',watch_expires_at),created_at
 from private.pomodoist_google_calendar_accounts on conflict(user_id,provider) do nothing;
insert into private.pomodoist_calendar_links(connection_id,task_id,event_id,data)
 select c.id,l.task_id,l.event_id,jsonb_build_object('taskId',l.task_id,'connectionId',c.id,'provider','google','eventId',l.event_id,'incarnation',1,'version',l.etag,
 'baseline',jsonb_build_object('content',e.data->>'content','description',e.data->'description','status',e.data->>'status',
 'schedule',case when l.last_schedule_fingerprint is null then null else l.last_schedule_fingerprint::jsonb end))
 from private.pomodoist_google_calendar_links l join private.pomodoist_calendar_connections c on c.user_id=l.user_id and c.provider='google'
 join public.sync_entities e on e.user_id=l.user_id and e.app_id='pomodoist' and e.entity_type='task' and e.entity_id=l.task_id
 on conflict do nothing;
-- Old jobs no longer own event writes. The new Google endpoint handles migrated channels.
delete from private.pomodoist_google_calendar_jobs;
select cron.schedule('pomodoist-calendar-workers','* * * * *', $job$select private.calendar_wake('google'); select private.calendar_wake('outlook');$job$);
notify pgrst,'reload schema';

create function private.calendar_projection_guard() returns trigger language plpgsql set search_path='' as $$
begin
 if new.app_id='pomodoist' and new.entity_type in ('calendar_connection','calendar_event_link','google_calendar_connection','google_calendar_event_link')
  and coalesce(current_setting('pomodoist.calendar_projecting',true),'')<>'true' then
  if tg_op='UPDATE' then return old; else return null; end if;
 end if; return new;
end $$;
create trigger calendar_projection_guard before insert or update on public.sync_entities for each row execute function private.calendar_projection_guard();
revoke all on function private.calendar_projection_guard() from public,anon,authenticated;

create function private.calendar_credential_cleanup() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if old.credential_id is not null then delete from vault.secrets where id=old.credential_id; end if;
 return old;
end $$;
create trigger calendar_credential_cleanup after delete on private.pomodoist_calendar_connections for each row execute function private.calendar_credential_cleanup();
revoke all on function private.calendar_credential_cleanup() from public,anon,authenticated;

insert into private.pomodoist_calendar_workers(provider,url,secret_id)
 select 'google',u.decrypted_secret,s.id from vault.decrypted_secrets u cross join vault.secrets s
 where u.name='pomodoist-google-calendar-worker-url' and s.name='pomodoist-google-calendar-worker-secret'
 on conflict(provider) do nothing;

-- Publish only safe event identities; provider baselines and secrets stay private.
create function private.calendar_project_link() returns trigger language plpgsql security definer set search_path='' as $$
declare c private.pomodoist_calendar_connections; l private.pomodoist_calendar_links; payload jsonb; stamp timestamptz:=clock_timestamp(); eid text;
begin
 if tg_op='DELETE' then l:=old; else l:=new; end if;
 select * into c from private.pomodoist_calendar_connections where id=l.connection_id;
 if not found then return null; end if;
 eid:=c.id::text||':'||l.task_id;
 payload:=jsonb_build_object('id',eid,'connectionId',c.id,'provider',c.provider,'taskId',l.task_id,
   'calendarId',c.calendar_id,'eventId',l.event_id,'unsupportedReason',l.data->>'unsupportedReason');
 if tg_op<>'DELETE' and exists(select 1 from public.sync_entities where user_id=c.user_id and app_id='pomodoist' and entity_type='calendar_event_link' and entity_id=eid and deleted_at is null and data=payload) then return null; end if;
 perform set_config('pomodoist.calendar_projecting','true',true);
 if tg_op<>'DELETE' then
  update public.sync_entities set deleted_at=null where user_id=c.user_id and app_id='pomodoist' and deleted_at is not null and ((entity_type='calendar_event_link' and entity_id=eid) or (c.provider='google' and entity_type='google_calendar_event_link' and entity_id=l.task_id));
 end if;
 perform private.push_changes_for_user(c.user_id,'pomodoist','calendar-server',jsonb_build_array(jsonb_build_object(
 'opId',gen_random_uuid()::text,'entityType','calendar_event_link','entityId',eid,
 'operation',case when tg_op='DELETE' then 'delete' else 'upsert' end,'payload',payload,'clientUpdatedAt',stamp)));
 if c.provider='google' then
  perform private.push_changes_for_user(c.user_id,'pomodoist','google-calendar-server',jsonb_build_array(jsonb_build_object(
   'opId',gen_random_uuid()::text,'entityType','google_calendar_event_link','entityId',l.task_id,
   'operation',case when tg_op='DELETE' then 'delete' else 'upsert' end,
   'payload',payload || jsonb_build_object('createdAt',stamp,'updatedAt',stamp),'clientUpdatedAt',stamp)));
 end if;
 perform set_config('pomodoist.calendar_projecting','false',true);
 return null;
end $$;
create trigger calendar_project_link after insert or update or delete on private.pomodoist_calendar_links for each row execute function private.calendar_project_link();
revoke all on function private.calendar_project_link() from public,anon,authenticated;
-- Initial projections make the migration visible even before the first worker runs.
select private.calendar_project(id) from private.pomodoist_calendar_connections;
update private.pomodoist_calendar_links set data=data;

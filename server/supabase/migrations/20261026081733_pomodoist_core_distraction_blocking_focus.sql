-- Shared Focus is revisioned server state. Existing offline history/sync remains compatible.
create table private.pomodoist_focus_accounts (
 user_id uuid primary key references public.profiles(id) on delete cascade,
 revision bigint not null default 0, session jsonb, deadline timestamptz,
 settings_revision bigint not null default 0, scope_id uuid
);
create table private.pomodoist_focus_requests (
 user_id uuid not null references public.profiles(id) on delete cascade,
 request_id text not null, command jsonb not null, response jsonb not null,
 created_at timestamptz not null default clock_timestamp(), primary key(user_id,request_id)
);
create table private.pomodoist_focus_devices (
 user_id uuid not null references public.profiles(id) on delete cascade,
 device_id text not null, name text, platform text, capabilities jsonb not null default '{}',
 last_seen_at timestamptz not null, detached boolean not null default false,
 exit_requested_at timestamptz, applied_revision bigint, primary key(user_id,device_id)
);
create table private.pomodoist_focus_owned_runs (
 user_id uuid not null references public.profiles(id) on delete cascade,
 run_id text not null, primary key(user_id,run_id)
);
alter table private.pomodoist_focus_owned_runs enable row level security;
revoke all on private.pomodoist_focus_owned_runs from public,anon,authenticated;
create table private.pomodoist_resource_cache (
 kind text not null, resource_id text not null, assignment jsonb not null,
 expires_at timestamptz not null, primary key(kind,resource_id)
);
alter table private.pomodoist_focus_accounts enable row level security;
alter table private.pomodoist_focus_requests enable row level security;
alter table private.pomodoist_focus_devices enable row level security;
alter table private.pomodoist_resource_cache enable row level security;
revoke all on private.pomodoist_focus_accounts,private.pomodoist_focus_requests,private.pomodoist_focus_devices,private.pomodoist_resource_cache from public,anon,authenticated;

create function private.pomodoist_public_resource(kind text,id text) returns boolean language sql immutable set search_path='' as $$
 select coalesce(length(id)<=253 and case kind
 when 'domain' then id=lower(id) and id ~ '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$'
   and id !~ '(^|\.)(local|localhost|internal|test|invalid|example|lan|home|onion)$|\.home\.arpa$'
 when 'app' then id ~ '^((macos|linux):[A-Za-z0-9][A-Za-z0-9_.!~-]{1,199}|windows:win32:[A-Za-z0-9][A-Za-z0-9_.!~ -]{0,194}\.[eE][xX][eE]|windows:aumid:[A-Za-z0-9][A-Za-z0-9_.!~-]{1,199})$' else false end,false)
$$;
create function private.pomodoist_distraction_validate(typ text,d jsonb) returns void language plpgsql set search_path='' as $$
declare cats text[]:=array['social','messaging','video','music','games','news','shopping','education','development','productivity','other','unclassified']; x jsonb; k text;
begin
 if jsonb_typeof(d)<>'object' or octet_length(d::text)>32768 or jsonb_typeof(d->'id') is distinct from 'string' or jsonb_typeof(d->'name') is distinct from 'string' or coalesce(length(d->>'id'),0) not between 1 and 253 or coalesce(length(btrim(d->>'name')),0) not between 1 and 100 then raise exception using errcode='22023',message='Invalid distraction resource'; end if;
 if d ? 'isDeleted' and jsonb_typeof(d->'isDeleted')<>'boolean' then raise exception using errcode='22023',message='Invalid distraction deletion'; end if;
 for k in select jsonb_object_keys(d) loop
  if not k=any(case when typ='distraction_profile' then array['id','name','blockedCategories','overrides','blockOnPause','blockOnShortBreak','blockOnLongBreak','updatedAt','isDeleted'] else array['id','kind','name','platform','category','source','sources','updatedAt','isDeleted'] end) then raise exception using errcode='22023',message='Unexpected distraction field'; end if;
 end loop;
 if typ='distraction_profile' then
  if jsonb_typeof(d->'blockedCategories') is distinct from 'array' or jsonb_array_length(d->'blockedCategories')>12 or jsonb_typeof(d->'overrides') is distinct from 'array' or jsonb_array_length(d->'overrides')>200 then raise exception using errcode='22023',message='Invalid distraction profile'; end if;
  for x in select value from jsonb_array_elements(d->'blockedCategories') loop if not coalesce(x#>>'{}'=any(cats),false) then raise exception using errcode='22023',message='Unknown distraction category'; end if; end loop;
  for x in select value from jsonb_array_elements(d->'overrides') loop
   if not private.pomodoist_public_resource(x->>'kind',x->>'id') or coalesce(x->>'action','') not in ('allow','block') or (x-array['kind','id','action'])<>'{}' then raise exception using errcode='22023',message='Invalid distraction override'; end if;
  end loop;
  foreach k in array array['blockOnPause','blockOnShortBreak','blockOnLongBreak'] loop if d ? k and jsonb_typeof(d->k)<>'boolean' then raise exception using errcode='22023',message='Invalid distraction phase policy'; end if; end loop;
 else
  if not private.pomodoist_public_resource(d->>'kind',d->>'id') or not coalesce(d->>'category'=any(cats),false) or coalesce(d->>'source','') not in ('manual','automatic') then raise exception using errcode='22023',message='Invalid resource assignment'; end if;
  if d ? 'sources' then
   if jsonb_typeof(d->'sources')<>'array' or jsonb_array_length(d->'sources')>3 then raise exception using errcode='22023',message='Invalid classification sources'; end if;
   for x in select value from jsonb_array_elements(d->'sources') loop
    if jsonb_typeof(x)<>'object' or (x-array['title','url'])<>'{}' or coalesce(length(x->>'title'),0) not between 1 and 200 or coalesce(length(x->>'url'),0) not between 10 and 2048 or x->>'url' !~ '^https://[A-Za-z0-9.-]+/' then raise exception using errcode='22023',message='Invalid classification source'; end if;
   end loop;
  end if;
 end if;
end$$;

create function private.pomodoist_focus_project(actor uuid,typ text,id text,d jsonb) returns void language plpgsql security definer set search_path='' as $$
begin
 perform set_config('pomodoist.focus_projecting','true',true);
 insert into public.sync_entities(user_id,app_id,entity_type,entity_id,server_revision,client_updated_at,data,deleted_at)
 values(actor,'pomodoist',typ,id,nextval('public.sync_revision_seq'),clock_timestamp(),d,case when d->>'isDeleted'='true' then clock_timestamp() else null end)
 on conflict(user_id,app_id,entity_type,entity_id) do update set server_revision=excluded.server_revision,client_updated_at=excluded.client_updated_at,data=excluded.data,deleted_at=excluded.deleted_at,updated_at=clock_timestamp();
 perform set_config('pomodoist.focus_projecting','false',true);
end$$;

create function private.pomodoist_focus_sync_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare s jsonb; cached jsonb;
begin
 if new.app_id<>'pomodoist' or current_setting('pomodoist.focus_projecting',true)='true' then return new; end if;
 if new.entity_type='focus_live' then raise exception using errcode='42501',message='Live Focus is server-authored'; end if;
 if new.entity_type in ('focus_run','focus_interval','focus_event') then
  perform pg_advisory_xact_lock(hashtextextended(new.user_id::text||':pomodoist:focus',0));
  select session into s from private.pomodoist_focus_accounts where user_id=new.user_id;
  if (new.entity_type='focus_run' and (exists(select 1 from private.pomodoist_focus_owned_runs where user_id=new.user_id and run_id=new.entity_id) or (s->'run'->>'status' in ('active','paused') and new.data->>'status' in ('active','paused'))))
    or (new.entity_type in ('focus_interval','focus_event') and (exists(select 1 from private.pomodoist_focus_owned_runs where user_id=new.user_id and run_id=new.data->>'runId') or (tg_op='UPDATE' and exists(select 1 from private.pomodoist_focus_owned_runs where user_id=old.user_id and run_id=old.data->>'runId')))) then raise exception using errcode='42501',message='Shared Focus history is server-authored'; end if;
 elsif new.entity_type in ('distraction_profile','resource_assignment') then
  perform private.pomodoist_distraction_validate(new.entity_type,new.data);
  if new.entity_id<>new.data->>'id' then raise exception using errcode='22023',message='Resource identity mismatch'; end if;
  if new.entity_type='resource_assignment' and new.data->>'source'='automatic' then
   if tg_op='UPDATE' and old.data->>'source'='manual' and old.data->>'category'<>'unclassified' then return old; end if;
   select assignment into cached from private.pomodoist_resource_cache where kind=new.data->>'kind' and resource_id=new.entity_id and expires_at>clock_timestamp();
   if (cached is null or cached->>'category'<>new.data->>'category' or coalesce(cached->'sources','[]')<>coalesce(new.data->'sources','[]')) and not (tg_op='UPDATE' and old.data->>'source'='automatic' and old.data->>'category'=new.data->>'category' and old.data->'sources'=new.data->'sources') then raise exception using errcode='42501',message='Automatic categories require verified search'; end if;
  end if;
  insert into private.pomodoist_focus_accounts(user_id) values(new.user_id) on conflict do nothing;
  update private.pomodoist_focus_accounts set settings_revision=settings_revision+1 where user_id=new.user_id;
 end if;
 return new;
end$$;
create trigger pomodoist_focus_sync_guard before insert or update on public.sync_entities for each row execute function private.pomodoist_focus_sync_guard();

create function private.pomodoist_focus_envelope(actor uuid,stamp timestamptz,device text) returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object('session',case when a.session is null then null else a.session||jsonb_build_object('revision',a.revision,'serverNow',stamp,'protectionExpiresAt',case when a.session->'interval'->>'status' in ('running','paused') then least(case when a.session->'interval'->>'status'='running' then a.deadline else stamp+interval '5 minutes' end,(a.session->>'exitRequestedAt')::timestamptz+make_interval(secs=>(a.session->>'strictExitSeconds')::integer),(select exit_requested_at+make_interval(secs=>(a.session->>'strictExitSeconds')::integer) from private.pomodoist_focus_devices where user_id=actor and device_id=device)) else null end) end,
 'serverNow',stamp,'settingsRevision',a.settings_revision,
 'profiles',coalesce((select jsonb_agg(data order by entity_id) from public.sync_entities where user_id=actor and app_id='pomodoist' and entity_type='distraction_profile' and deleted_at is null),'[]'),
 'assignments',coalesce((select jsonb_agg(data order by entity_id) from public.sync_entities where user_id=actor and app_id='pomodoist' and entity_type='resource_assignment' and deleted_at is null),'[]'),
 'devices',coalesce((select jsonb_agg(jsonb_build_object('deviceId',device_id,'name',name,'platform',platform,'capabilities',capabilities,'appliedRevision',applied_revision,'lastSeenAt',last_seen_at,'detached',detached,'exitRequestedAt',exit_requested_at,'sessionId',a.session->>'id',
 'protectionExpiresAt',case when not detached and a.session->'interval'->>'status' in ('running','paused') then least(case when a.session->'interval'->>'status'='running' then a.deadline else last_seen_at+interval '5 minutes' end,(a.session->>'exitRequestedAt')::timestamptz+make_interval(secs=>(a.session->>'strictExitSeconds')::integer),exit_requested_at+make_interval(secs=>(a.session->>'strictExitSeconds')::integer)) else null end) order by device_id) from private.pomodoist_focus_devices where user_id=actor),'[]'))
 from private.pomodoist_focus_accounts a where user_id=actor
$$;

create function private.pomodoist_focus_credit(actor uuid,scope uuid,i jsonb,stamp timestamptz) returns void language plpgsql security definer set search_path='' as $$
begin
 if i->>'status'='completed' and i->>'type'='work' and i->>'taskId' is not null then
  if scope is not null then
   if exists(select 1 from private.pomodoist_members where scope_id=scope and user_id=actor and role in ('administrator','member')) then
    perform private.pomodoist_shared_apply(scope,actor,'member',jsonb_build_object('entityType','focus_interval','entityId',i->>'id','operation','upsert','opId','focus:'||(i->>'id'),'baseRevision',(select revision from private.pomodoist_scopes where id=scope),'clientUpdatedAt',stamp,'payload',i||jsonb_build_object('durationSeconds',least((i->>'plannedSeconds')::integer,greatest(0,floor(extract(epoch from ((i->>'completedAt')::timestamptz-(i->>'startedAt')::timestamptz)))::integer-(i->>'pausedTotalSeconds')::integer)))));
    perform private.pomodoist_collaboration_hint(scope);
   end if;
  elsif exists(select 1 from public.sync_entities where user_id=actor and app_id='pomodoist' and entity_type='task' and entity_id=i->>'taskId' and deleted_at is null) then
   perform private.pomodoist_focus_project(actor,'task',i->>'taskId',(select data from public.sync_entities where user_id=actor and app_id='pomodoist' and entity_type='task' and entity_id=i->>'taskId')||
    (select jsonb_build_object('completedFocusIntervals',count(*),'totalFocusSeconds',coalesce(sum(least((data->>'plannedSeconds')::integer,greatest(0,floor(extract(epoch from ((data->>'completedAt')::timestamptz-(data->>'startedAt')::timestamptz)))::integer-coalesce((data->>'pausedTotalSeconds')::integer,0)))),0),'updatedAt',stamp) from public.sync_entities where user_id=actor and app_id='pomodoist' and entity_type='focus_interval' and deleted_at is null and data->>'taskId'=i->>'taskId' and data->>'type'='work' and data->>'status'='completed'));
  end if;
 end if;
end$$;

-- Normalize time representations before comparing already synchronized history.
create function private.pomodoist_focus_history_normalize(d jsonb,typ text) returns jsonb language plpgsql stable set search_path='' as $$
declare k text;
begin
 foreach k in array case when typ='focus_event' then array['occurredAt','createdAt'] else array['startedAt','pausedAt','completedAt','stoppedAt','createdAt','updatedAt'] end loop
  if d->>k is not null then d:=jsonb_set(d,array[k],to_jsonb((d->>k)::timestamptz)); end if;
 end loop;
 if typ='focus_event' and d->>'payloadJson' is not null then d:=jsonb_set(d,'{payloadJson}',to_jsonb((d->>'payloadJson')::jsonb::text)); end if;
 return d;
end$$;

-- Adopt the complete bounded run atomically before its local outbox is retired.
create function private.pomodoist_focus_adopt_history(actor uuid,scope uuid,r jsonb,current_interval jsonb,p jsonb,adopt jsonb,stamp timestamptz) returns void language plpgsql security definer set search_path='' as $$
declare history jsonb:=coalesce(adopt->'intervals','[]'); events jsonb:=coalesce(adopt->'events','[]'); normalized_history jsonb:='[]'; normalized_events jsonb:='[]'; x jsonb; existing jsonb; ref_interval jsonb; body jsonb;
 ids text[]:=array[]::text[]; event_ids text[]:=array[]::text[]; n integer:=0; completed_work integer:=0; expected_phase text:='work'; start_time timestamptz; end_time timestamptz; previous_end timestamptz; event_time timestamptz; previous_event_time timestamptz; run_start timestamptz:=(r->>'startedAt')::timestamptz; is_current boolean; planned integer; paused integer;
begin
 if jsonb_typeof(history) is distinct from 'array' or jsonb_typeof(events) is distinct from 'array' or jsonb_array_length(history)>1000 or jsonb_array_length(events)>5000
  or (adopt-array['run','interval','intervals','events'])<>'{}' or run_start is null or run_start>stamp or run_start<stamp-interval '7 days'
  or coalesce((r->>'createdAt')::timestamptz>run_start,true) or coalesce((adopt->'run'->>'updatedAt')::timestamptz>stamp,true)
  or (r->>'status'='paused') is distinct from (current_interval->>'status'='paused') then raise exception using errcode='22023',message='Invalid adopted Focus history'; end if;
 if exists(select 1 from public.sync_entities where user_id=actor and app_id='pomodoist' and entity_id=r->>'id' and entity_type in ('focus_interval','focus_event')) then raise exception using errcode='22023',message='Adopted run identity collision'; end if;
 select data into existing from public.sync_entities where user_id=actor and app_id='pomodoist' and entity_type='focus_run' and entity_id=r->>'id';
 if found and (existing->>'taskId' is distinct from r->>'taskId' or (existing->>'startedAt')::timestamptz is distinct from run_start) then raise exception using errcode='22023',message='Adopted run identity collision'; end if;
 -- Stored interval durations and historical break choices belong to their
 -- original presets. The current preset governs future transitions and exits.
 -- The current interval participates in sequence and chronology validation, but
 -- is projected only by the live authority after all terminal history succeeds.
 for x in select value from jsonb_array_elements(history||jsonb_build_array(current_interval||jsonb_build_object('updatedAt',adopt->'interval'->'updatedAt'))) loop
  n:=n+1; is_current:=n=jsonb_array_length(history)+1;
  if jsonb_typeof(x) is distinct from 'object' or coalesce(x->>'id','') !~ '^[A-Za-z0-9_-]{1,128}$' or x->>'id'=any(ids) or x->>'id'=r->>'id'
   or (x-array['id','runId','taskId','projectId','type','status','plannedSeconds','startedAt','pausedAt','pausedTotalSeconds','completedAt','stoppedAt','sequenceNumber','createdAt','updatedAt','isDeleted'])<>'{}'
   or x->>'runId' is distinct from r->>'id' or x->>'taskId' is distinct from r->>'taskId' or x->>'projectId' is distinct from r->>'projectId'
   or coalesce((x->>'isDeleted')::boolean,false) or (case when expected_phase='break' then coalesce(x->>'type','') not in ('shortBreak','longBreak') else x->>'type' is distinct from 'work' end)
   or jsonb_typeof(x->'sequenceNumber') is distinct from 'number' or (x->>'sequenceNumber')::numeric<>n
   or jsonb_typeof(x->'plannedSeconds') is distinct from 'number' or (x->>'plannedSeconds')::numeric<>trunc((x->>'plannedSeconds')::numeric)
   or jsonb_typeof(x->'pausedTotalSeconds') is distinct from 'number' or (x->>'pausedTotalSeconds')::numeric<>trunc((x->>'pausedTotalSeconds')::numeric)
   or (not is_current and coalesce(x->>'status','') not in ('completed','skipped','stopped')) then raise exception using errcode='22023',message='Invalid adopted Focus interval'; end if;
  if exists(select 1 from public.sync_entities where user_id=actor and app_id='pomodoist' and entity_id=x->>'id' and entity_type in ('focus_run','focus_event')) then raise exception using errcode='22023',message='Adopted interval identity collision'; end if;
  x:=private.pomodoist_focus_history_normalize(x,'focus_interval'); ids:=array_append(ids,x->>'id');
  start_time:=(x->>'startedAt')::timestamptz; planned:=(x->>'plannedSeconds')::integer; paused:=(x->>'pausedTotalSeconds')::integer;
  end_time:=case x->>'status' when 'completed' then (x->>'completedAt')::timestamptz when 'skipped' then (x->>'stoppedAt')::timestamptz when 'stopped' then (x->>'stoppedAt')::timestamptz when 'paused' then (x->>'pausedAt')::timestamptz else stamp end;
  if start_time is null or end_time is null or start_time<run_start or end_time<start_time or end_time>stamp or start_time<previous_end
   or coalesce((x->>'createdAt')::timestamptz>start_time,true) or (x->>'createdAt')::timestamptz<run_start
   or coalesce((x->>'updatedAt')::timestamptz<case when is_current then start_time else end_time end,true) or (x->>'updatedAt')::timestamptz>stamp
   or planned not between 60 and 10800 or paused<0 or paused>floor(extract(epoch from (end_time-start_time)))::integer
   or (x->>'status'<>'completed' and x->>'completedAt' is not null) or (x->>'status' not in ('skipped','stopped') and x->>'stoppedAt' is not null)
   or (x->>'status'<>'paused' and x->>'pausedAt' is not null)
   then raise exception using errcode='22023',message='Invalid adopted Focus timing'; end if;
  select case when deleted_at is null then data else null end into existing from public.sync_entities where user_id=actor and app_id='pomodoist' and entity_type='focus_interval' and entity_id=x->>'id';
  if found and (existing->>'runId' is distinct from r->>'id' or (not is_current and (private.pomodoist_focus_history_normalize(existing,'focus_interval')-'updatedAt') is distinct from (x-'updatedAt')) or (is_current and (existing->>'status' in ('completed','skipped','stopped') or existing->>'taskId' is distinct from x->>'taskId' or existing->>'projectId' is distinct from x->>'projectId' or existing->>'type' is distinct from x->>'type' or existing->'plannedSeconds' is distinct from x->'plannedSeconds' or existing->'sequenceNumber' is distinct from x->'sequenceNumber')))
   then raise exception using errcode='22023',message='Adopted interval identity collision'; end if;
  if not is_current then
   normalized_history:=normalized_history||jsonb_build_array(x);
   if x->>'type'='work' and x->>'status'='completed' then completed_work:=completed_work+1; end if;
   expected_phase:=case when x->>'type'='work' then 'break' else 'work' end;
   previous_end:=end_time;
  end if;
 end loop;
 if (r->>'completedWorkIntervals')::integer<>completed_work or completed_work>(r->>'targetWorkIntervals')::integer or (current_interval->>'type'='work' and completed_work>=(r->>'targetWorkIntervals')::integer) then raise exception using errcode='22023',message='Adopted run progress does not match history'; end if;
 for x in select value from jsonb_array_elements(events) loop
  if jsonb_typeof(x) is distinct from 'object' or coalesce(x->>'id','') !~ '^[A-Za-z0-9_-]{1,128}$' or x->>'id'=any(event_ids||ids) or x->>'id'=r->>'id'
   or (x-array['id','runId','intervalId','type','occurredAt','payloadJson','createdAt'])<>'{}' or x->>'runId' is distinct from r->>'id'
   or coalesce(x->>'type','') not in ('runStarted','intervalReady','intervalStarted','intervalPaused','intervalResumed','intervalRestarted','intervalCompleted','intervalSkipped','distractionLogged')
   or (x->>'intervalId' is not null and not x->>'intervalId'=any(ids)) then raise exception using errcode='22023',message='Invalid adopted Focus event'; end if;
  if exists(select 1 from public.sync_entities where user_id=actor and app_id='pomodoist' and entity_id=x->>'id' and entity_type in ('focus_run','focus_interval')) then raise exception using errcode='22023',message='Adopted event identity collision'; end if;
  x:=private.pomodoist_focus_history_normalize(x,'focus_event'); event_time:=(x->>'occurredAt')::timestamptz;
  body:=(x->>'payloadJson')::jsonb;
  if event_time is null or event_time<run_start or event_time>stamp or event_time<previous_event_time or coalesce((x->>'createdAt')::timestamptz<>event_time,true)
   or (body is not null and (jsonb_typeof(body) not in ('object','null') or octet_length(body::text)>8192 or (body-array['taskId','projectId','type','reason','note'])<>'{}'))
   or (body ? 'taskId' and body->>'taskId' is distinct from r->>'taskId') or (body ? 'projectId' and body->>'projectId' is distinct from r->>'projectId')
   or (x->>'type' like 'interval%' and x->>'intervalId' is null) then raise exception using errcode='22023',message='Invalid adopted Focus event timing'; end if;
  if x->>'intervalId' is not null then
   select value into ref_interval from jsonb_array_elements(normalized_history||jsonb_build_array(current_interval)) where value->>'id'=x->>'intervalId';
   if event_time<(ref_interval->>'createdAt')::timestamptz or event_time>coalesce((ref_interval->>'completedAt')::timestamptz,(ref_interval->>'stoppedAt')::timestamptz,stamp)
    or (body ? 'type' and body->>'type' is distinct from ref_interval->>'type')
    or (x->>'type'='intervalCompleted' and (ref_interval->>'status'<>'completed' or event_time is distinct from (ref_interval->>'completedAt')::timestamptz))
    or (x->>'type'='intervalSkipped' and (ref_interval->>'status'<>'skipped' or event_time is distinct from (ref_interval->>'stoppedAt')::timestamptz)) then raise exception using errcode='22023',message='Adopted event does not match interval'; end if;
  end if;
  select case when deleted_at is null then data else null end into existing from public.sync_entities where user_id=actor and app_id='pomodoist' and entity_type='focus_event' and entity_id=x->>'id';
  if found and private.pomodoist_focus_history_normalize(existing,'focus_event') is distinct from x then raise exception using errcode='22023',message='Adopted event identity collision'; end if;
  event_ids:=array_append(event_ids,x->>'id'); previous_event_time:=event_time; normalized_events:=normalized_events||jsonb_build_array(x);
 end loop;
 -- All validation above completes before history or aggregates are changed.
 for x in select value from jsonb_array_elements(normalized_history) loop
  if not exists(select 1 from public.sync_entities where user_id=actor and app_id='pomodoist' and entity_type='focus_interval' and entity_id=x->>'id') then perform private.pomodoist_focus_project(actor,'focus_interval',x->>'id',x); end if;
  perform private.pomodoist_focus_credit(actor,scope,x,stamp);
 end loop;
 for x in select value from jsonb_array_elements(normalized_events) loop
  if not exists(select 1 from public.sync_entities where user_id=actor and app_id='pomodoist' and entity_type='focus_event' and entity_id=x->>'id') then perform private.pomodoist_focus_project(actor,'focus_event',x->>'id',x); end if;
 end loop;
exception when invalid_text_representation or datetime_field_overflow or invalid_datetime_format or numeric_value_out_of_range then raise exception using errcode='22023',message='Invalid adopted Focus history value';
end$$;

-- Finish a single observed interval. The next interval is ready, never backfilled.
create function private.pomodoist_focus_advance(actor uuid,stamp timestamptz,completed boolean) returns void language plpgsql security definer set search_path='' as $$
declare a private.pomodoist_focus_accounts; s jsonb; r jsonb; i jsonb; p jsonb; n integer; phase text; seconds integer;
begin
 select * into a from private.pomodoist_focus_accounts where user_id=actor;
 s:=a.session; r:=s->'run'; i:=s->'interval'; p:=s->'preset';
 i:=i||jsonb_build_object('status',case when completed then 'completed' else 'skipped' end,'completedAt',case when completed then stamp else null end,'stoppedAt',case when completed then null else stamp end,'updatedAt',stamp);
 perform private.pomodoist_focus_project(actor,'focus_interval',i->>'id',i);
 perform private.pomodoist_focus_credit(actor,a.scope_id,i,stamp);
 n:=(r->>'completedWorkIntervals')::integer+case when completed and i->>'type'='work' then 1 else 0 end;
 r:=r||jsonb_build_object('completedWorkIntervals',n,'updatedAt',stamp);
 if i->>'type'<>'work' and n>=(r->>'targetWorkIntervals')::integer then
  r:=r||jsonb_build_object('status','completed','endedAt',stamp);
  s:=s||jsonb_build_object('run',r,'interval',i,'exitRequestedAt',null);
 else
  phase:=case when i->>'type'<>'work' then 'work' when n>0 and n%(p->>'intervalsBeforeLongBreak')::integer=0 then 'longBreak' else 'shortBreak' end;
  seconds:=case phase when 'work' then (p->>'workSeconds')::integer when 'longBreak' then (p->>'longBreakSeconds')::integer else (p->>'shortBreakSeconds')::integer end;
  i:=jsonb_build_object('id',gen_random_uuid(),'runId',r->>'id','taskId',r->'taskId','projectId',r->'projectId','type',phase,'status','ready','plannedSeconds',seconds,'startedAt',stamp,'pausedAt',null,'pausedTotalSeconds',0,'completedAt',null,'stoppedAt',null,'sequenceNumber',(i->>'sequenceNumber')::integer+1,'createdAt',stamp,'updatedAt',stamp,'isDeleted',false);
  r:=r||jsonb_build_object('status','active');
  s:=s||jsonb_build_object('run',r,'interval',i,'exitRequestedAt',s->'exitRequestedAt');
  perform private.pomodoist_focus_project(actor,'focus_interval',i->>'id',i);
 end if;
 perform private.pomodoist_focus_project(actor,'focus_run',r->>'id',r);
 update private.pomodoist_focus_accounts set session=s,revision=revision+1,deadline=null where user_id=actor;
end$$;

create function private.pomodoist_focus_stop(actor uuid,stamp timestamptz) returns void language plpgsql security definer set search_path='' as $$
declare s jsonb; r jsonb; i jsonb;
begin
 select session into s from private.pomodoist_focus_accounts where user_id=actor;
 r:=s->'run'||jsonb_build_object('status','stopped','endedAt',stamp,'updatedAt',stamp);
 i:=s->'interval'||jsonb_build_object('status','stopped','stoppedAt',stamp,'updatedAt',stamp);
 perform private.pomodoist_focus_project(actor,'focus_interval',i->>'id',i);
 perform private.pomodoist_focus_project(actor,'focus_run',r->>'id',r);
 update private.pomodoist_focus_accounts set session=s||jsonb_build_object('run',r,'interval',i,'exitRequestedAt',null),deadline=null,revision=revision+1 where user_id=actor;
end$$;

create function private.pomodoist_focus_preset(p jsonb) returns jsonb language plpgsql set search_path='' as $$
declare k text;
begin
 if jsonb_typeof(p) is distinct from 'object' or coalesce(length(p->>'id'),0) not between 1 and 128 or octet_length(p::text)>4096 then raise exception using errcode='22023',message='Invalid Focus preset'; end if;
 foreach k in array array['workSeconds','shortBreakSeconds','longBreakSeconds','intervalsBeforeLongBreak'] loop
  if jsonb_typeof(p->k) is distinct from 'number' or (p->>k)::numeric<>trunc((p->>k)::numeric) or (p->>k)::numeric not between (case k when 'intervalsBeforeLongBreak' then 1 else 60 end) and (case k when 'intervalsBeforeLongBreak' then 12 else 10800 end) then raise exception using errcode='22023',message='Invalid Focus preset duration'; end if;
 end loop;
 if (p-array['id','userId','name','workSeconds','shortBreakSeconds','longBreakSeconds','intervalsBeforeLongBreak','strictMode','allowPause','autoStartBreaks','autoStartWork','isDefault','createdAt','updatedAt','isDeleted'])<>'{}' then raise exception using errcode='22023',message='Unexpected Focus preset field'; end if;
 foreach k in array array['strictMode','allowPause','autoStartBreaks','autoStartWork'] loop if p ? k and jsonb_typeof(p->k)<>'boolean' then raise exception using errcode='22023',message='Invalid Focus preset flag'; end if; end loop;
 p:=jsonb_build_object('strictMode',false,'allowPause',true,'autoStartBreaks',false,'autoStartWork',false)||p;
 return p;
end$$;

create function private.pomodoist_focus(p_command jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); stamp timestamptz:=clock_timestamp(); action text:=p_command->>'action'; device text:=p_command->>'deviceId'; request text:=p_command->>'requestId'; payload jsonb:=coalesce(p_command->'payload','{}');
 a private.pomodoist_focus_accounts; previous private.pomodoist_focus_requests; s jsonb; r jsonb; i jsonb; p jsonb; d jsonb; result jsonb; code text; typ text; k text; id text; run_id text; interval_id text; remaining integer; v_strict boolean; exit_seconds integer; adopted boolean; changed boolean:=false; initial_account boolean; task_data jsonb; task_scope uuid;
begin
 if actor is null or not private.pomodoist_session_is_active() then raise sqlstate 'PT401' using message='Active account session required'; end if;
 if jsonb_typeof(p_command)<>'object' or octet_length(p_command::text)>(case when action='start' and payload ? 'adopt' then 2097152 else 65536 end) or coalesce(length(device),0) not between 1 and 128 or device !~ '^[A-Za-z0-9_.:-]+$' or coalesce(action,'') not in ('read','start','startReady','pause','resume','restart','changePreset','complete','skip','requestStop','cancelStop','detach','registerDevice','profileUpsert','assignmentUpsert') or jsonb_typeof(payload)<>'object' then raise exception using errcode='22023',message='Invalid Focus command'; end if;
 if action<>'read' and coalesce(length(request),0) not between 1 and 128 then raise exception using errcode='22023',message='Focus requestId required'; end if;
 -- Match the existing sync/calendar lock order before projecting shared history.
 perform pg_advisory_xact_lock(hashtextextended('pomodoist-file-lifecycle',0));
 perform pg_advisory_xact_lock(hashtextextended('pomodoist-google-calendar:'||actor::text,0));
 perform pg_advisory_xact_lock(hashtextextended(actor::text||':pomodoist:focus',0));
 insert into private.pomodoist_focus_accounts(user_id) values(actor) on conflict do nothing returning true into initial_account;
 if initial_account then
  foreach id in array array['work','study'] loop
   perform private.pomodoist_focus_project(actor,'distraction_profile',id,jsonb_build_object('id',id,'name',initcap(id),'blockedCategories','[]'::jsonb,'overrides','[]'::jsonb,'blockOnPause',true,'blockOnShortBreak',false,'blockOnLongBreak',false,'updatedAt',stamp,'isDeleted',false));
  end loop;
  update private.pomodoist_focus_accounts set settings_revision=1 where user_id=actor;
 end if;
 if action<>'read' then
  select * into previous from private.pomodoist_focus_requests where user_id=actor and request_id=request;
  if found then
   if previous.command<>p_command then raise exception using errcode='22023',message='Focus requestId reused with another command'; end if;
   return previous.response;
  end if;
 end if;
 select * into a from private.pomodoist_focus_accounts where user_id=actor for update;
 s:=a.session;
 if s->'run'->>'status' in ('active','paused') then
  if s->>'exitRequestedAt' is not null and (s->>'exitRequestedAt')::timestamptz+make_interval(secs=>(s->>'strictExitSeconds')::integer)<=stamp and (a.deadline is null or a.deadline>=(s->>'exitRequestedAt')::timestamptz+make_interval(secs=>(s->>'strictExitSeconds')::integer)) then
   perform private.pomodoist_focus_stop(actor,(s->>'exitRequestedAt')::timestamptz+make_interval(secs=>(s->>'strictExitSeconds')::integer)); changed:=true;
  elsif s->'interval'->>'status'='running' and a.deadline<=stamp then
   perform private.pomodoist_focus_advance(actor,a.deadline,true); changed:=true;
  end if;
 end if;
 update private.pomodoist_focus_devices set detached=true,exit_requested_at=null where user_id=actor and exit_requested_at+make_interval(secs=>coalesce((s->>'strictExitSeconds')::integer,0))<=stamp;
 insert into private.pomodoist_focus_devices(user_id,device_id,last_seen_at) values(actor,device,stamp)
 on conflict(user_id,device_id) do update set last_seen_at=excluded.last_seen_at;
 select * into a from private.pomodoist_focus_accounts where user_id=actor;
 if a.session->'run'->>'status' in ('active','paused') and a.session->>'exitRequestedAt' is not null and (a.session->>'exitRequestedAt')::timestamptz+make_interval(secs=>(a.session->>'strictExitSeconds')::integer)<=stamp then
  perform private.pomodoist_focus_stop(actor,(a.session->>'exitRequestedAt')::timestamptz+make_interval(secs=>(a.session->>'strictExitSeconds')::integer)); changed:=true;
  select * into a from private.pomodoist_focus_accounts where user_id=actor;
 end if;
 s:=a.session; r:=s->'run'; i:=s->'interval'; p:=s->'preset';
 v_strict:=coalesce((p->>'strictMode')::boolean,false); exit_seconds:=coalesce((s->>'strictExitSeconds')::integer,0);
 if action not in ('read','registerDevice','profileUpsert','assignmentUpsert') and (jsonb_typeof(p_command->'expectedRevision') is distinct from 'number' or (p_command->>'expectedRevision')::numeric<>a.revision) then code:='revision_conflict';
 elsif action='registerDevice' then
  if coalesce(length(payload->>'name'),0)>100 or payload->>'platform' not in ('macos','windows','linux','chrome') or jsonb_typeof(coalesce(payload->'capabilities','{}'))<>'object' or octet_length(coalesce(payload->'capabilities','{}')::text)>2048 then raise exception using errcode='22023',message='Invalid Focus device'; end if;
  update private.pomodoist_focus_devices set name=payload->>'name',platform=payload->>'platform',capabilities=coalesce(payload->'capabilities','{}'),applied_revision=case when jsonb_typeof(payload->'appliedRevision')='number' and (payload->>'appliedRevision')::numeric between 0 and a.revision then (payload->>'appliedRevision')::bigint else null end where user_id=actor and device_id=device;
 elsif action in ('profileUpsert','assignmentUpsert') then
  typ:=case action when 'profileUpsert' then 'distraction_profile' else 'resource_assignment' end;
  d:=coalesce(payload->case action when 'profileUpsert' then 'profile' else 'assignment' end,payload)||jsonb_build_object('updatedAt',stamp);
  if typ='distraction_profile' then d:=jsonb_build_object('blockOnPause',true,'blockOnShortBreak',false,'blockOnLongBreak',false)||d; end if;
  perform private.pomodoist_distraction_validate(typ,d); id:=d->>'id';
  if typ='resource_assignment' and d->>'source'='automatic' then
   if exists(select 1 from public.sync_entities where user_id=actor and app_id='pomodoist' and entity_type=typ and entity_id=id and deleted_at is null and data->>'source'='manual' and data->>'category'<>'unclassified') then code:='manual_assignment_preserved';
   elsif not exists(select 1 from private.pomodoist_resource_cache where kind=d->>'kind' and resource_id=id and expires_at>stamp and assignment->>'category'=d->>'category' and assignment->'sources'=d->'sources') and not exists(select 1 from public.sync_entities where user_id=actor and app_id='pomodoist' and entity_type='resource_assignment' and entity_id=id and deleted_at is null and data->>'source'='automatic' and data->>'category'=d->>'category' and data->'sources'=d->'sources') then raise exception using errcode='42501',message='Automatic categories require verified search'; end if;
  end if;
  if code is null then perform private.pomodoist_focus_project(actor,typ,id,d); update private.pomodoist_focus_accounts set settings_revision=settings_revision+1 where user_id=actor; end if;
 elsif action='start' then
  if r->>'status' in ('active','paused') then code:='focus_already_active';
  else
   p:=payload->'preset';
   p:=private.pomodoist_focus_preset(p);
   v_strict:=(p->>'strictMode')::boolean; exit_seconds:=case when v_strict then coalesce((payload->>'strictExitSeconds')::integer,60) else 0 end;
   if exit_seconds not in (0,60) then raise exception using errcode='22023',message='Invalid strict exit policy'; end if;
   if payload->>'profileId' is not null and not exists(select 1 from public.sync_entities where user_id=actor and app_id='pomodoist' and entity_type='distraction_profile' and entity_id=payload->>'profileId' and deleted_at is null) then raise exception using errcode='22023',message='Focus profile not found'; end if;
   if payload ? 'adopt' then payload:=payload||jsonb_build_object('taskId',coalesce(payload->'taskId',payload->'adopt'->'run'->'taskId'),'projectId',coalesce(payload->'projectId',payload->'adopt'->'run'->'projectId')); end if;
   if payload->>'taskId' is not null then
    select data into task_data from public.sync_entities where user_id=actor and app_id='pomodoist' and entity_type='task' and entity_id=payload->>'taskId' and deleted_at is null and data->>'status'<>'completed';
    if not found then
     select e.data,e.scope_id into task_data,task_scope from private.pomodoist_shared_entities e join private.pomodoist_members m on m.scope_id=e.scope_id where m.user_id=actor and m.role in ('administrator','member') and e.entity_type='task' and e.entity_id=payload->>'taskId' and e.deleted_at is null and e.data->>'status'<>'completed' limit 1;
    end if;
    if task_data is null then raise exception using errcode='22023',message='Focus task not found'; end if;
   elsif payload->>'projectId' is not null and not exists(select 1 from public.sync_entities where user_id=actor and app_id='pomodoist' and entity_type='project' and entity_id=payload->>'projectId' and deleted_at is null) then raise exception using errcode='22023',message='Focus project not found'; end if;
   adopted:=payload ? 'adopt'; run_id:=gen_random_uuid()::text; interval_id:=gen_random_uuid()::text;
   r:=jsonb_build_object('id',run_id,'userId',actor,'presetId',p->>'id','taskId',payload->'taskId','projectId',coalesce(task_data->'projectId',payload->'projectId'),'status','active','startedAt',stamp,'endedAt',null,'targetWorkIntervals',coalesce(nullif(payload->'targetWorkIntervals','null'::jsonb),p->'intervalsBeforeLongBreak'),'completedWorkIntervals',0,'createdAt',stamp,'updatedAt',stamp,'isDeleted',false,'note',payload->'note');
   i:=jsonb_build_object('id',interval_id,'runId',run_id,'taskId',r->'taskId','projectId',r->'projectId','type','work','status','running','plannedSeconds',p->'workSeconds','startedAt',stamp,'pausedAt',null,'pausedTotalSeconds',0,'completedAt',null,'stoppedAt',null,'sequenceNumber',1,'createdAt',stamp,'updatedAt',stamp,'isDeleted',false);
   if adopted then
    r:=payload->'adopt'->'run'; i:=payload->'adopt'->'interval';
    if jsonb_typeof(r) is distinct from 'object' or jsonb_typeof(i) is distinct from 'object'
      or coalesce(r->>'id','') !~ '^[A-Za-z0-9_-]{1,128}$' or coalesce(i->>'id','') !~ '^[A-Za-z0-9_-]{1,128}$'
      or coalesce(r->>'userId','') not in (actor::text,'local-user') or coalesce((r->>'isDeleted')::boolean,false) or coalesce((i->>'isDeleted')::boolean,false)
      or r->>'taskId' is distinct from payload->>'taskId' or i->>'taskId' is distinct from r->>'taskId' or i->>'projectId' is distinct from r->>'projectId'
      or coalesce(i->>'runId','')<>r->>'id' or coalesce(r->>'status','') not in ('active','paused')
      or coalesce(i->>'status','') not in ('running','paused','ready') or coalesce(i->>'type','') not in ('work','shortBreak','longBreak')
      or coalesce((i->>'startedAt')::timestamptz>stamp,true) or (i->>'startedAt')::timestamptz<stamp-interval '7 days'
      or coalesce((i->>'pausedTotalSeconds')::numeric,-1) not between 0 and 604800
      or coalesce((i->>'sequenceNumber')::numeric,0) not between 1 and 10000
      or (i->>'status'='paused' and (coalesce((i->>'pausedAt')::timestamptz>stamp,true) or (i->>'pausedAt')::timestamptz<(i->>'startedAt')::timestamptz))
      or (i->>'status'='running' and i->>'pausedAt' is not null)
      or coalesce(r->>'presetId','')<>p->>'id'
      or (r-array['id','userId','taskId','projectId','presetId','status','startedAt','endedAt','targetWorkIntervals','completedWorkIntervals','note','createdAt','updatedAt','isDeleted'])<>'{}'
      or (i-array['id','runId','taskId','projectId','type','status','plannedSeconds','startedAt','pausedAt','pausedTotalSeconds','completedAt','stoppedAt','sequenceNumber','createdAt','updatedAt','isDeleted'])<>'{}'
      or exists(select 1 from public.sync_entities where user_id=actor and app_id='pomodoist' and ((entity_type='focus_run' and entity_id=r->>'id' and data->>'status' not in ('active','paused')) or (entity_type='focus_interval' and entity_id=i->>'id' and (data->>'runId'<>r->>'id' or data->>'status' in ('completed','stopped','skipped'))))) then raise exception using errcode='22023',message='Invalid adopted Focus'; end if;
    -- Only known Focus fields cross this boundary; user identity is authoritative.
    r:=(r-array['userId','taskId','projectId'])||jsonb_build_object('userId',actor,'taskId',payload->'taskId','projectId',r->'projectId','updatedAt',stamp,'endedAt',null,'isDeleted',false);
    i:=i||jsonb_build_object('taskId',r->'taskId','projectId',r->'projectId','updatedAt',stamp,'isDeleted',false);
    run_id:=r->>'id'; interval_id:=i->>'id';
   end if;
   if coalesce((r->>'targetWorkIntervals')::numeric,0) not between 1 and 1000 or coalesce((r->>'completedWorkIntervals')::numeric,-1) not between 0 and (r->>'targetWorkIntervals')::numeric then raise exception using errcode='22023',message='Invalid Focus interval count'; end if;
   if exists(select 1 from public.sync_entities where user_id=actor and app_id='pomodoist' and entity_type='focus_run' and deleted_at is null and data->>'status' in ('active','paused') and entity_id<>run_id) then code:='offline_focus_conflict';
   else
    remaining:=case when i->>'status'='ready' then (i->>'plannedSeconds')::integer else (i->>'plannedSeconds')::integer-greatest(0,floor(extract(epoch from (case when i->>'status'='paused' then (i->>'pausedAt')::timestamptz else stamp end-(i->>'startedAt')::timestamptz)))::integer-(i->>'pausedTotalSeconds')::integer) end;
    if adopted and remaining<=0 then raise exception using errcode='22023',message='Adopted Focus has expired'; end if;
    if adopted then perform private.pomodoist_focus_adopt_history(actor,task_scope,r,i,p,payload->'adopt',stamp); end if;
    s:=jsonb_build_object('id',run_id,'run',r,'interval',i,'preset',p,'profileId',payload->'profileId','taskTitle',task_data->>'content','strictExitSeconds',exit_seconds,'exitRequestedAt',null);
    insert into private.pomodoist_focus_owned_runs(user_id,run_id) values(actor,run_id) on conflict do nothing;
    update private.pomodoist_focus_accounts set scope_id=task_scope,session=s,revision=revision+1,deadline=case when i->>'status'='running' then stamp+make_interval(secs=>remaining) else null end where user_id=actor;
    update private.pomodoist_focus_devices set detached=false,exit_requested_at=null where user_id=actor and device_id=device;
    perform private.pomodoist_focus_project(actor,'focus_run',run_id,r); perform private.pomodoist_focus_project(actor,'focus_interval',interval_id,i); changed:=true;
   end if;
  end if;
 elsif action<>'read' then
  if r is null or r->>'status' not in ('active','paused') then code:='focus_not_active';
  elsif action='cancelStop' then
   update private.pomodoist_focus_accounts set session=session||jsonb_build_object('exitRequestedAt',null),revision=revision+1 where user_id=actor;
   update private.pomodoist_focus_devices set exit_requested_at=null where user_id=actor and device_id=device; changed:=true;
  elsif action='detach' and exists(select 1 from private.pomodoist_focus_devices where user_id=actor and device_id=device and detached) then null;
  elsif action in ('requestStop','detach','restart','changePreset','skip','complete') and v_strict and i->>'status' in ('running','paused') then
   if action not in ('requestStop','detach') then code:='strict_exit_required';
   elsif exit_seconds=0 and coalesce((payload->>'confirmed')::boolean,false)=false then code:='strict_confirmation_required';
   elsif exit_seconds=60 then
    if action='detach' then update private.pomodoist_focus_devices set exit_requested_at=coalesce(exit_requested_at,stamp) where user_id=actor and device_id=device;
    else update private.pomodoist_focus_accounts set session=jsonb_set(session,'{exitRequestedAt}',to_jsonb(stamp)),revision=revision+1 where user_id=actor and session->>'exitRequestedAt' is null; changed:=true; end if;
    code:='strict_exit_pending';
   elsif action='detach' then update private.pomodoist_focus_devices set detached=true where user_id=actor and device_id=device;
   else perform private.pomodoist_focus_stop(actor,stamp); changed:=true; end if;
  elsif action='detach' then update private.pomodoist_focus_devices set detached=true where user_id=actor and device_id=device;
  elsif action='requestStop' then perform private.pomodoist_focus_stop(actor,stamp); changed:=true;
  elsif action in ('skip','complete') then perform private.pomodoist_focus_advance(actor,stamp,action='complete'); changed:=true;
  elsif action='changePreset' then
   p:=private.pomodoist_focus_preset(payload->'preset');
   r:=r||jsonb_build_object('presetId',p->>'id','updatedAt',stamp);
   update private.pomodoist_focus_accounts set session=s||jsonb_build_object('run',r,'preset',p,'strictExitSeconds',case when (p->>'strictMode')::boolean then case when v_strict then exit_seconds else 60 end else 0 end),revision=revision+1 where user_id=actor;
   perform private.pomodoist_focus_project(actor,'focus_run',r->>'id',r); changed:=true;
  elsif action='pause' then
   if i->>'status'<>'running' or not coalesce((p->>'allowPause')::boolean,true) then code:='pause_not_allowed'; else
    i:=i||jsonb_build_object('status','paused','pausedAt',stamp,'updatedAt',stamp); r:=r||jsonb_build_object('status','paused','updatedAt',stamp);
    update private.pomodoist_focus_accounts set session=s||jsonb_build_object('run',r,'interval',i),revision=revision+1,deadline=null where user_id=actor; changed:=true;
   end if;
  elsif action in ('resume','startReady','restart') then
   if (action='resume' and i->>'status'<>'paused') or (action='startReady' and i->>'status'<>'ready') then code:='invalid_focus_transition'; else
    remaining:=case when action='resume' then (i->>'plannedSeconds')::integer-greatest(0,floor(extract(epoch from ((i->>'pausedAt')::timestamptz-(i->>'startedAt')::timestamptz)))::integer-(i->>'pausedTotalSeconds')::integer) else (i->>'plannedSeconds')::integer end;
    if action='resume' then i:=i||jsonb_build_object('pausedTotalSeconds',(i->>'pausedTotalSeconds')::integer+greatest(0,floor(extract(epoch from (stamp-(i->>'pausedAt')::timestamptz)))::integer)); else i:=i||jsonb_build_object('startedAt',stamp,'pausedTotalSeconds',0); end if;
    i:=i||jsonb_build_object('status','running','pausedAt',null,'updatedAt',stamp); r:=r||jsonb_build_object('status','active','updatedAt',stamp);
    update private.pomodoist_focus_accounts set session=s||jsonb_build_object('run',r,'interval',i),revision=revision+1,deadline=stamp+make_interval(secs=>greatest(0,remaining)) where user_id=actor; changed:=true;
   end if;
  end if;
  if changed and action in ('pause','resume','startReady','restart') and code is null then perform private.pomodoist_focus_project(actor,'focus_run',r->>'id',r); perform private.pomodoist_focus_project(actor,'focus_interval',i->>'id',i); end if;
 end if;
 if changed then
  select session||jsonb_build_object('revision',revision) into s from private.pomodoist_focus_accounts where user_id=actor;
  perform private.pomodoist_focus_project(actor,'focus_live','current',s);
 end if;
 if changed or (action in ('profileUpsert','assignmentUpsert','detach','registerDevice','cancelStop') and code is null) or code='strict_exit_pending' then perform realtime.send(jsonb_build_object('appId','pomodoist','deviceId','focus-server'),'changed','sync:'||actor::text||':pomodoist',true); end if;
 result:=private.pomodoist_focus_envelope(actor,stamp,device);
 if code is not null then result:=result||jsonb_build_object('code',code); end if;
 if action<>'read' then insert into private.pomodoist_focus_requests(user_id,request_id,command,response) values(actor,request,p_command,result); end if;
 return result;
end$$;
create function public.pomodoist_focus(p_command jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.pomodoist_focus(p_command)$$;

create function private.pomodoist_resource_classification(p_resource jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); d jsonb;
begin
 if actor is null or not private.pomodoist_session_is_active() then raise sqlstate 'PT401' using message='Active account session required'; end if;
 if not private.pomodoist_public_resource(p_resource->>'kind',p_resource->>'id') then raise exception using errcode='22023',message='Invalid public resource'; end if;
 if not public.has_active_pomodoist_paid_entitlement(actor) then return jsonb_build_object('isPro',false,'assignment',null); end if;
 select assignment into d from private.pomodoist_resource_cache where kind=p_resource->>'kind' and resource_id=p_resource->>'id' and expires_at>clock_timestamp();
 return jsonb_build_object('isPro',true,'assignment',d);
end$$;
create function public.pomodoist_resource_classification(p_resource jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.pomodoist_resource_classification(p_resource)$$;
create function private.pomodoist_resource_cache_store(p_assignment jsonb) returns void language plpgsql security definer set search_path='' as $$
begin
 perform private.pomodoist_distraction_validate('resource_assignment',p_assignment);
 if p_assignment->>'source'<>'automatic' or jsonb_array_length(coalesce(p_assignment->'sources','[]'))<1 then raise exception using errcode='22023',message='Classification search sources required'; end if;
 insert into private.pomodoist_resource_cache(kind,resource_id,assignment,expires_at) values(p_assignment->>'kind',p_assignment->>'id',p_assignment,clock_timestamp()+interval '30 days') on conflict(kind,resource_id) do update set assignment=excluded.assignment,expires_at=excluded.expires_at;
end$$;
create function public.pomodoist_resource_cache_store(p_assignment jsonb) returns void language sql security invoker set search_path='' as $$select private.pomodoist_resource_cache_store(p_assignment)$$;
revoke all on function private.pomodoist_focus_preset(jsonb),private.pomodoist_public_resource(text,text),private.pomodoist_distraction_validate(text,jsonb),private.pomodoist_focus_project(uuid,text,text,jsonb),private.pomodoist_focus_sync_guard(),private.pomodoist_focus_envelope(uuid,timestamptz,text),private.pomodoist_focus_advance(uuid,timestamptz,boolean),private.pomodoist_focus_stop(uuid,timestamptz),private.pomodoist_focus(jsonb),private.pomodoist_resource_classification(jsonb),public.pomodoist_focus(jsonb),public.pomodoist_resource_classification(jsonb),private.pomodoist_resource_cache_store(jsonb),public.pomodoist_resource_cache_store(jsonb) from public,anon,authenticated;
grant execute on function private.pomodoist_focus(jsonb),private.pomodoist_resource_classification(jsonb),public.pomodoist_focus(jsonb),public.pomodoist_resource_classification(jsonb) to authenticated;
grant execute on function private.pomodoist_resource_cache_store(jsonb),public.pomodoist_resource_cache_store(jsonb) to service_role;
notify pgrst,'reload schema';

revoke all on function private.pomodoist_focus_history_normalize(jsonb,text),private.pomodoist_focus_credit(uuid,uuid,jsonb,timestamptz),private.pomodoist_focus_adopt_history(uuid,uuid,jsonb,jsonb,jsonb,jsonb,timestamptz) from public,anon,authenticated;

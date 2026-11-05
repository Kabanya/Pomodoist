-- Dependencies are task data; urgency and cascade settings belong to the actor.
-- These rules restrict task completion only; Focus remains independently available.
create function private.pomodoist_blocking_queue(d jsonb) returns text language sql immutable set search_path='' as $$
 select case when d->>'scopeId' is null then 'personal' else 'project:'||(d->>'projectId') end
$$;
create function private.pomodoist_blocking_own(d jsonb,actor text) returns boolean language sql immutable set search_path='' as $$
 select d is not null and (d->>'scopeId' is null or coalesce(d->'assigneeIds','[]') ? actor)
$$;
create function private.pomodoist_blocking_open(d jsonb,completed text[] default '{}') returns boolean language sql immutable set search_path='' as $$
 select d is not null and coalesce(d->>'status','open')<>'completed' and coalesce(d->>'isDeleted','false')<>'true' and not coalesce(d->>'id'=any(completed),false)
$$;
create function private.pomodoist_blocking_predecessors(d jsonb) returns text[] language plpgsql immutable set search_path='' as $$
declare a jsonb; result text[];
begin
 if d ? 'prerequisiteIdsJson' and jsonb_typeof(d->'prerequisiteIdsJson') is distinct from 'string' then raise exception using errcode='22023',message='Invalid task dependencies'; end if;
 a:=coalesce((d->>'prerequisiteIdsJson')::jsonb,'[]');
 if jsonb_typeof(a)<>'array' or jsonb_array_length(a)>200 or exists(select 1 from jsonb_array_elements(a) x where jsonb_typeof(x)<>'string' or length(x#>>'{}') not between 1 and 200) then
  raise exception using errcode='22023',message='Invalid task dependencies'; end if;
 select coalesce(array_agg(value),'{}') into result from jsonb_array_elements_text(a);
 if cardinality(result)<>(select count(distinct x) from unnest(result) x) then raise exception using errcode='22023',message='Duplicate task dependencies'; end if;
 return result;
exception when invalid_text_representation then raise exception using errcode='22023',message='Invalid task dependencies';
end$$;
create function private.pomodoist_blocking_schedule(d jsonb) returns jsonb language plpgsql immutable set search_path='' as $$
begin return coalesce((d->>'dueJson')::jsonb,'{}'); exception when invalid_text_representation then return '{}'; end$$;
create function private.pomodoist_blocking_day(d jsonb,zone text) returns date language plpgsql stable set search_path='' as $$
declare s jsonb:=private.pomodoist_blocking_schedule(d);
begin
 if s->>'date' is not null then return (s->>'date')::date; end if;
 return (coalesce(s->>'start',s->>'startAt')::timestamptz at time zone zone)::date;
exception when invalid_datetime_format or datetime_field_overflow then return null;
end$$;
create function private.pomodoist_blocking_requirements(g jsonb,id text) returns text[] language sql immutable set search_path='' as $$
 with recursive ancestors(id) as (select id union select g->a.id->>'parentId' from ancestors a where g->a.id->>'parentId' is not null)
 select coalesce(array_agg(distinct p),'{}') from ancestors a cross join lateral unnest(private.pomodoist_blocking_predecessors(g->a.id)) p
$$;
create function private.pomodoist_blocking_path(g jsonb,id text,completed text[] default '{}',open_only boolean default true) returns text[] language sql immutable set search_path='' as $$
 with recursive edges(a,b) as (
  select n.key,p from jsonb_each(g) n cross join lateral unnest(private.pomodoist_blocking_requirements(g,n.key)) p
  union select n.value->>'parentId',n.key from jsonb_each(g) n where n.value->>'parentId' is not null
 ), walk(id) as (
  select id union select e.b from walk w join edges e on e.a=w.id
   where not open_only or private.pomodoist_blocking_open(g->w.id,completed)
 ) select coalesce(array_agg(id),'{}') from walk
$$;
create function private.pomodoist_blocking_missing(g jsonb,id text,completed text[] default '{}') returns text[] language sql immutable set search_path='' as $$
 select coalesce(array_agg(p),'{}') from unnest(private.pomodoist_blocking_requirements(g,id)) p
 where not(p=any(completed)) and (g->p is null or private.pomodoist_blocking_open(g->p,completed))
$$;
create function private.pomodoist_blocking_graph(actor uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_object_agg(id,d),'{}') from (
  select e.entity_id id,e.data||jsonb_build_object('id',e.entity_id,'scopeId',null,'isDeleted',e.deleted_at is not null or e.data->>'isDeleted'='true') d
  from public.sync_entities e where e.user_id=actor and e.app_id='pomodoist' and e.entity_type='task' and not exists(select 1 from private.pomodoist_transferred_entities t where t.user_id=actor and t.entity_type='task' and t.entity_id=e.entity_id)
  union all
  select e.entity_id,e.data||jsonb_build_object('id',e.entity_id,'scopeId',e.scope_id,'isDeleted',e.deleted_at is not null or e.data->>'isDeleted'='true')
  from private.pomodoist_shared_entities e where e.entity_type='task' and exists(select 1 from private.pomodoist_members m where m.scope_id=e.scope_id and m.user_id=actor)
 ) tasks
$$;
create function private.pomodoist_blocking_preferences(actor uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_object_agg(entity_id,data),'{}') from public.sync_entities where user_id=actor and app_id='pomodoist' and entity_type='task_blocking' and deleted_at is null
$$;
create function private.pomodoist_blocking_selected(g jsonb,prefs jsonb,actor text,queue text,completed text[] default '{}') returns text language plpgsql stable set search_path='' as $$
declare selection jsonb:=prefs->queue; source jsonb:=g->(selection->>'taskId'); chosen text; zone text:=coalesce(prefs#>>'{settings,timeZone}','UTC');
begin
 if source is null or private.pomodoist_blocking_queue(source)<>queue then return null; end if;
 if private.pomodoist_blocking_open(source) and not private.pomodoist_blocking_own(source,actor) then return null; end if;
 if private.pomodoist_blocking_open(source,completed) and private.pomodoist_blocking_own(source,actor) then return source->>'id'; end if;
 if coalesce(selection->>'repeatWithSeries','true')='false' or selection->>'seriesId' is null then return null; end if;
 select n.key into chosen from jsonb_each(g) n
 where private.pomodoist_blocking_open(n.value,completed) and private.pomodoist_blocking_own(n.value,actor) and private.pomodoist_blocking_queue(n.value)=queue
  and coalesce(private.pomodoist_blocking_schedule(n.value)#>>'{recurrence,seriesId}',private.pomodoist_blocking_schedule(n.value)->>'recurrenceSeriesId')=selection->>'seriesId'
 order by private.pomodoist_blocking_day(n.value,zone) nulls first,n.key limit 1;
 return chosen;
end$$;
create function private.pomodoist_task_availability(g jsonb,prefs jsonb,actor text,target text,completed text[] default '{}') returns jsonb language plpgsql stable set search_path='' as $$
declare d jsonb:=g->target; queue text:=case when target is null then 'personal' else private.pomodoist_blocking_queue(d) end;
 zone text:=coalesce(prefs#>>'{settings,timeZone}','UTC'); today date:=(current_timestamp at time zone zone)::date;
 urgent text; reasons jsonb:='[]'; ids text[]:='{}'; missing text[]; source record; step text; ranks jsonb:='{}'; rank integer; best integer; target_rank integer;
begin
 missing:=case when target is null then '{}' else private.pomodoist_blocking_missing(g,target,completed) end;
 if cardinality(missing)>0 then reasons:=reasons||'"dependency"'::jsonb; ids:=missing; end if;
 if target is not null and not private.pomodoist_blocking_own(d,actor) then return jsonb_build_object('allowed',reasons='[]','reasons',reasons,'blockingTaskIds',ids); end if;
 if prefs->queue->>'taskId'=any(completed) then return jsonb_build_object('allowed',reasons='[]','reasons',reasons,'blockingTaskIds',ids); end if;
 urgent:=private.pomodoist_blocking_selected(g,prefs,actor,queue,completed);
 if urgent is not null and private.pomodoist_blocking_day(g->urgent,zone)>today then urgent:=null; end if;
 if urgent is not null then
  if target is null or not(target=any(private.pomodoist_blocking_path(g,urgent,completed))) then reasons:=reasons||'"urgent"'::jsonb; ids:=array_append(ids,urgent); end if;
 elsif target is not null and prefs#>>'{settings,priorityCascadeEnabled}'='true' then
  for source in select n.key,n.value from jsonb_each(g) n where private.pomodoist_blocking_open(n.value,completed)
   and private.pomodoist_blocking_own(n.value,actor) and private.pomodoist_blocking_queue(n.value)=queue and private.pomodoist_blocking_day(n.value,zone)<=today loop
   rank:=coalesce((source.value->>'priority')::integer,4);
   foreach step in array private.pomodoist_blocking_path(g,source.key,completed) loop
    if private.pomodoist_blocking_open(g->step,completed) and private.pomodoist_blocking_own(g->step,actor) and private.pomodoist_blocking_queue(g->step)=queue and cardinality(private.pomodoist_blocking_missing(g,step,completed))=0 then
     ranks:=jsonb_set(ranks,array[step],to_jsonb(least(coalesce((ranks->>step)::integer,5),rank)));
    end if;
   end loop;
  end loop;
  select min(value::integer) into best from jsonb_each_text(ranks);
  target_rank:=coalesce((ranks->>target)::integer,(d->>'priority')::integer,4);
  if best is not null and (private.pomodoist_blocking_day(d,zone)<=today or ranks ? target) and target_rank>best then
   reasons:=reasons||'"priority"'::jsonb;
   select ids||coalesce(array_agg(key),'{}') into ids from jsonb_each_text(ranks) where value::integer=best;
  end if;
 end if;
 return jsonb_build_object('allowed',reasons='[]','reasons',reasons,'blockingTaskIds',(select coalesce(jsonb_agg(distinct x),'[]') from unnest(ids) x));
end$$;
create function private.pomodoist_blocking_validate_graph(g jsonb) returns void language plpgsql set search_path='' as $$
declare n record; p text; pred jsonb; ancestors text[];
begin
 for n in select * from jsonb_each(g) where coalesce(value->>'isDeleted','false')<>'true' loop
  foreach p in array private.pomodoist_blocking_predecessors(n.value) loop
   pred:=g->p;
   -- Tombstoned references are retained for deletion undo, but have no effect.
   if pred->>'isDeleted'='true' then continue; end if;
   if pred is null or p=n.key or pred->>'scopeId' is distinct from n.value->>'scopeId'
    or n.value->>'scopeId' is not null and pred->>'projectId' is distinct from n.value->>'projectId' then
    raise exception using errcode='22023',message='Invalid task dependency scope'; end if;
   with recursive parents(id) as (select n.value->>'parentId' union select g->a.id->>'parentId' from parents a where g->a.id->>'parentId' is not null)
    select coalesce(array_agg(id),'{}') into ancestors from parents;
   if p=any(ancestors) or p=any(array(with recursive descendants(id) as (select n.key union select t.key from descendants a join jsonb_each(g) t on t.value->>'parentId'=a.id) select id from descendants)) or n.key=any(private.pomodoist_blocking_path(g,p,'{}',false)) then
    raise exception using errcode='22023',message='Task dependencies cannot contain cycles or ancestor links'; end if;
  end loop;
 end loop;
end$$;

create function private.pomodoist_blocking_lock() returns trigger language plpgsql security definer set search_path='' as $$
declare actor uuid; g jsonb; prefs jsonb; queue text; key text; urgent text; snapshot jsonb; completed jsonb;
begin
 if tg_table_schema='public' then
  if new.app_id<>'pomodoist' or new.entity_type not in ('task','task_blocking') then return new; end if;
  perform pg_advisory_xact_lock(hashtextextended('pomodoist-blocking:actor:'||new.user_id::text,0));
 else
  if new.entity_type<>'task' then return new; end if;
  perform pg_advisory_xact_lock(hashtextextended('pomodoist-blocking:scope:'||new.scope_id::text,0));
 end if;
 if new.entity_type='task' and new.deleted_at is null and new.data->>'status'='completed' and (tg_op='INSERT' or old.data->>'status' is distinct from 'completed') then
  if tg_table_schema='public' then actor:=new.user_id; queue:=private.pomodoist_blocking_queue(new.data||jsonb_build_object('scopeId',null));
  else
   actor:=coalesce(nullif(current_setting('pomodoist.blocking_actor',true),'')::uuid,auth.uid());
   if actor is null then select owner_id into actor from private.pomodoist_scopes where id=new.scope_id; end if;
   queue:=private.pomodoist_blocking_queue(new.data||jsonb_build_object('scopeId',new.scope_id));
  end if;
  key:=actor::text||':'||queue;
  snapshot:=coalesce(nullif(current_setting('pomodoist.blocking_urgent_snapshot',true),'')::jsonb,'{}');
  if not(snapshot ? key) then
   prefs:=private.pomodoist_blocking_preferences(actor);
   g:=private.pomodoist_blocking_graph(actor);
   urgent:=private.pomodoist_blocking_selected(g,prefs,actor::text,queue);
   if private.pomodoist_blocking_day(g->urgent,coalesce(prefs#>>'{settings,timeZone}','UTC'))>(current_timestamp at time zone coalesce(prefs#>>'{settings,timeZone}','UTC'))::date then urgent:=null; end if;
   perform set_config('pomodoist.blocking_urgent_snapshot',(snapshot||jsonb_build_object(key,urgent))::text,true);
  end if;
  completed:=coalesce(nullif(current_setting('pomodoist.blocking_completed_ids',true),'')::jsonb,'[]');
  perform set_config('pomodoist.blocking_completed_ids',(completed||to_jsonb(new.entity_id))::text,true);
 end if;
 return new;
end$$;
create trigger pomodoist_task_blocking_lock before insert or update on public.sync_entities for each row execute function private.pomodoist_blocking_lock();
create trigger pomodoist_task_blocking_lock before insert or update on private.pomodoist_shared_entities for each row execute function private.pomodoist_blocking_lock();

create function private.pomodoist_blocking_check() returns trigger language plpgsql security definer set search_path='' as $$
declare actor uuid; g jsonb; prefs jsonb; d jsonb; result jsonb; id text; zone text; queue text; snapshot jsonb; completed text[];
begin
 if tg_table_schema='public' then
  if new.app_id<>'pomodoist' or new.entity_type not in ('task','task_blocking') then return null; end if;
  actor:=new.user_id;
 else
  if new.entity_type<>'task' then return null; end if;
  actor:=coalesce(nullif(current_setting('pomodoist.blocking_actor',true),'')::uuid,auth.uid());
  if actor is null then select owner_id into actor from private.pomodoist_scopes where id=new.scope_id; end if;
 end if;
 g:=private.pomodoist_blocking_graph(actor); prefs:=private.pomodoist_blocking_preferences(actor);
 if new.entity_type='task_blocking' then
  if new.deleted_at is not null then return null; end if;
  d:=prefs->new.entity_id;
  if new.entity_id='settings' then
   zone:=d->>'timeZone';
   if jsonb_typeof(d->'priorityCascadeEnabled') is distinct from 'boolean' or zone is null or not exists(select 1 from pg_timezone_names where name=zone)
    or (d-array['id','userId','updatedAt','priorityCascadeEnabled','timeZone','schemaVersion','commandType'])<>'{}' then
    raise exception using errcode='22023',message='Invalid task blocking settings'; end if;
  else
   if new.entity_id<>'personal' and new.entity_id not like 'project:%' then raise exception using errcode='22023',message='Invalid urgent queue'; end if;
   if (d-array['id','userId','updatedAt','taskId','seriesId','repeatWithSeries','schemaVersion','commandType'])<>'{}'
    or jsonb_typeof(d->'repeatWithSeries') is distinct from 'boolean' then raise exception using errcode='22023',message='Invalid urgent selection'; end if;
   if d->>'taskId' is not null and (g->(d->>'taskId') is null or not private.pomodoist_blocking_own(g->(d->>'taskId'),actor::text)
    or private.pomodoist_blocking_queue(g->(d->>'taskId'))<>new.entity_id) then
    raise exception using errcode='42501',message='Only your assigned tasks can be urgent'; end if;
   if d->>'seriesId' is not null and d->>'seriesId' is distinct from coalesce(private.pomodoist_blocking_schedule(g->(d->>'taskId'))#>>'{recurrence,seriesId}',private.pomodoist_blocking_schedule(g->(d->>'taskId'))->>'recurrenceSeriesId') then
    raise exception using errcode='22023',message='Invalid urgent recurrence series'; end if;
  end if;
  return null;
 end if;
 if new.deleted_at is null and (tg_op='INSERT' or old.deleted_at is distinct from new.deleted_at or old.data->'isDeleted' is distinct from new.data->'isDeleted' or old.data->'prerequisiteIdsJson' is distinct from new.data->'prerequisiteIdsJson' or old.data->'parentId' is distinct from new.data->'parentId' or old.data->'projectId' is distinct from new.data->'projectId') then
  perform private.pomodoist_blocking_validate_graph(g);
 end if;
 if new.deleted_at is null and new.data->>'status'='completed' and (tg_op='INSERT' or old.data->>'status' is distinct from 'completed') then
  id:=new.entity_id;
  if g->id->>'status'<>'completed' then return null; end if;
  if exists(with recursive descendants(id) as (select id union select n.key from descendants a join jsonb_each(g) n on n.value->>'parentId'=a.id)
   select 1 from descendants a where private.pomodoist_blocking_open(g->a.id)) then
   raise exception using errcode='22023',message='task_blocked',detail='Complete the entire branch atomically'; end if;
  queue:=private.pomodoist_blocking_queue(g->id);
  snapshot:=coalesce(nullif(current_setting('pomodoist.blocking_urgent_snapshot',true),'')::jsonb,'{}');
  if snapshot ? (actor::text||':'||queue) then prefs:=prefs||jsonb_build_object(queue,jsonb_build_object('taskId',snapshot->(actor::text||':'||queue),'repeatWithSeries',false)); end if;
  select coalesce(array_agg(value),'{}') into completed from jsonb_array_elements_text(coalesce(nullif(current_setting('pomodoist.blocking_completed_ids',true),'')::jsonb,'[]')) where g->value->>'status'='completed';
  result:=private.pomodoist_task_availability(g,prefs,actor::text,id,completed);
  if result->>'allowed'<>'true' then raise exception using errcode='22023',message='task_blocked',detail=result::text; end if;
 end if;
 return null;
end$$;
-- Deferred checks see the complete atomic batch, including internal prerequisites.
create constraint trigger pomodoist_task_blocking_check after insert or update on public.sync_entities deferrable initially deferred for each row execute function private.pomodoist_blocking_check();
create constraint trigger pomodoist_task_blocking_check after insert or update on private.pomodoist_shared_entities deferrable initially deferred for each row execute function private.pomodoist_blocking_check();

-- Preserve the shared merge's field validation and trusted actor context.
do $$
declare definition text; needle text;
begin
 definition:=pg_get_functiondef('private.pomodoist_shared_apply(uuid,uuid,text,jsonb)'::regprocedure);
 if strpos(definition,'''deadlineJson''')=0 then raise exception 'Unexpected shared task field contract'; end if;
 definition:=replace(definition,'''deadlineJson''','''deadlineJson'',''prerequisiteIdsJson''');
 definition:=replace(definition,'begin','begin'||chr(10)||' perform set_config(''pomodoist.blocking_actor'',p_actor::text,true);');
 execute definition;
 -- Telegram delegates to this writer; change only its entity allowlist.
 definition:=pg_get_functiondef('public.push_pomodoist_mcp_changes(uuid,uuid,jsonb)'::regprocedure);
 needle:=E'        ''habit_check_in''\n      )';
 if strpos(definition,needle)=0 then raise exception 'Unexpected MCP entity allowlist'; end if;
 execute replace(definition,needle,E'        ''habit_check_in'',\n        ''task_blocking''\n      )');
end$$;

do $$declare f record; begin
 for f in select oid::regprocedure name from pg_proc where pronamespace='private'::regnamespace and (proname like 'pomodoist_blocking_%' or proname='pomodoist_task_availability') loop
  execute format('revoke all on function %s from public,anon,authenticated,service_role',f.name);
 end loop;
end$$;

-- One RPC transaction preserves branch atomicity across transport-sized chunks.
alter function private.pomodoist_collaboration(jsonb) rename to pomodoist_collaboration_without_task_blocking;
revoke all on function private.pomodoist_collaboration_without_task_blocking(jsonb) from public,anon,authenticated,service_role;
create function private.pomodoist_collaboration(p_request jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); scope uuid; root text; g jsonb; branch text[]; ids text[]; op jsonb; ops jsonb; chunk jsonb; response jsonb; applied jsonb:='[]'; offset_value integer:=0;
begin
 if p_request->>'action' is distinct from 'completeBranch' then return private.pomodoist_collaboration_without_task_blocking(p_request); end if;
 if actor is null or not exists(select 1 from auth.users where id=actor and not coalesce(is_anonymous,false))
  or not exists(select 1 from auth.sessions where user_id=actor and id::text=auth.jwt()->>'session_id' and (not_after is null or not_after>now())) then
  raise exception using errcode='42501',message='An active authenticated session is required'; end if;
 if octet_length(p_request::text)>1000000 or jsonb_typeof(p_request->'operations') is distinct from 'array' then raise exception using errcode='22023',message='Invalid completion batch'; end if;
 perform pg_advisory_xact_lock(hashtextextended('pomodoist-file-lifecycle',0));
 perform pg_advisory_xact_lock(hashtextextended('pomodoist-google-calendar:'||actor::text,0));
 scope:=nullif(p_request->>'scopeId','')::uuid;
 if scope is not null then perform pg_advisory_xact_lock(hashtextextended('pomodoist-blocking:scope:'||scope::text,0)); end if;
 perform pg_advisory_xact_lock(hashtextextended('pomodoist-blocking:actor:'||actor::text,0));
 root:=p_request->>'rootTaskId'; ops:=p_request->'operations'; g:=private.pomodoist_blocking_graph(actor);
 if g->root is null or g->root->>'scopeId' is distinct from scope::text then raise exception using errcode='42501',message='Task unavailable'; end if;
 with recursive descendants(id) as (select root union select n.key from descendants d join jsonb_each(g) n on n.value->>'parentId'=d.id)
  select array_agg(id) into branch from descendants;
 select coalesce(array_agg(value->>'entityId'),'{}') into ids from jsonb_array_elements(ops) where value->>'entityType'='task';
 if exists(select 1 from unnest(branch) id where private.pomodoist_blocking_open(g->id) and not(id=any(ids))) then
  raise exception using errcode='22023',message='task_blocked',detail='Branch changed; synchronize before completing it'; end if;
 for op in select value from jsonb_array_elements(ops) loop
  if op->>'operation'<>'upsert' or op->>'entityType' not in ('task','task_completion','task_kanban_status')
   or not(case when op->>'entityType'='task_completion' then op#>>'{payload,taskId}' else op->>'entityId' end=any(branch))
   or op->>'entityType'='task' and op#>>'{payload,status}' is distinct from 'completed' then
   raise exception using errcode='22023',message='Invalid completion batch'; end if;
 end loop;
 if scope is null then
  return private.push_changes_for_user(actor,'pomodoist',p_request->>'deviceId',ops);
 end if;
 while offset_value<jsonb_array_length(ops) loop
  select jsonb_agg(value order by ordinality) into chunk from jsonb_array_elements(ops) with ordinality where ordinality>offset_value and ordinality<=offset_value+200;
  response:=private.pomodoist_collaboration_without_task_blocking(p_request||jsonb_build_object('action','push','operations',chunk));
  if jsonb_array_length(response->'conflicts')>0 or jsonb_array_length(response->'rejected')>0 then
   raise exception using errcode='22023',message='task_blocked',detail=response::text; end if;
  applied:=applied||response->'applied'; offset_value:=offset_value+200;
 end loop;
 return jsonb_build_object('applied',applied,'conflicts','[]'::jsonb,'rejected','[]'::jsonb);
end$$;
revoke all on function private.pomodoist_collaboration(jsonb) from public,anon;
grant execute on function private.pomodoist_collaboration(jsonb) to authenticated,service_role;
notify pgrst, 'reload schema';

do $$declare definition text; begin
 definition:=pg_get_functiondef('private.pomodoist_mcp_task_json(text,jsonb)'::regprocedure);
 if strpos(definition,'''dueJson''')=0 then raise exception 'Unexpected MCP task projection'; end if;
 execute replace(definition,'''dueJson'', p_data', '''prerequisiteIdsJson'', coalesce(p_data->''prerequisiteIdsJson'',''"[]"''::jsonb), ''dueJson'', p_data');
end$$;

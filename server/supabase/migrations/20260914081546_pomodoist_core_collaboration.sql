begin;

-- Canonical shared data is accessible only through the checked RPC below.
create table private.pomodoist_scopes (
  id uuid primary key default gen_random_uuid(), root_project_id text not null,
  owner_id uuid not null references auth.users(id) on delete restrict,
  revision bigint not null default 0, history_unlimited boolean not null default false,
  grace_ends_at timestamptz, public_token text unique, created_at timestamptz not null default now()
);
create table private.pomodoist_members (
  scope_id uuid not null references private.pomodoist_scopes on delete cascade,
  user_id uuid not null references auth.users on delete cascade,
  role text not null check (role in ('administrator','member','observer')),
  joined_at timestamptz not null default now(), primary key(scope_id,user_id)
);
create index pomodoist_members_user on private.pomodoist_members(user_id);
create table private.pomodoist_shared_preferences (
  scope_id uuid not null, user_id uuid not null,
  entity_type text not null, entity_id text not null, data jsonb not null, updated_at timestamptz not null default now(),
  primary key(scope_id,user_id,entity_type,entity_id),
  foreign key(scope_id,user_id) references private.pomodoist_members(scope_id,user_id) on delete cascade
);
create table private.pomodoist_shared_entities (
  scope_id uuid not null references private.pomodoist_scopes on delete cascade,
  entity_type text not null check(entity_type in ('project','section','task','label','task_label','task_kanban_status','task_completion','comment','activity','focus_interval','attachment')),
  entity_id text not null, data jsonb not null, field_revision jsonb not null default '{}',
  server_revision bigint not null, deleted_at timestamptz, updated_at timestamptz not null default now(),
  primary key(scope_id,entity_type,entity_id)
);
create unique index pomodoist_shared_focus_unique on private.pomodoist_shared_entities(scope_id,(data->>'createdBy'),(data->>'startedAt'))
  where entity_type='focus_interval' and deleted_at is null;
create unique index pomodoist_shared_completion_unique on private.pomodoist_shared_entities(scope_id,(data->>'taskId'),(data->>'completedAt'))
  where entity_type='task_completion' and deleted_at is null;
create unique index pomodoist_shared_system_label on private.pomodoist_shared_entities(scope_id,(data->>'systemKey'))
  where entity_type='label' and deleted_at is null and data->>'systemKey' is not null;
create index pomodoist_shared_cursor on private.pomodoist_shared_entities(scope_id,server_revision);
create table private.pomodoist_shared_receipts (
  scope_id uuid not null references private.pomodoist_scopes on delete cascade,
  user_id uuid not null, op_id text not null, request jsonb not null, result jsonb not null,
  primary key(scope_id,user_id,op_id)
);
-- Permanent transfer ledger outlives deleted scopes and old personal tombstones.
create table private.pomodoist_transferred_entities (
  user_id uuid not null, entity_type text not null, entity_id text not null, scope_id uuid not null,
  primary key(user_id,entity_type,entity_id)
);
create table private.pomodoist_recurrence_successors (
  scope_id uuid not null references private.pomodoist_scopes on delete cascade,
  source_id text not null, occurrence_key text not null, successor_id text not null,
  primary key(scope_id,source_id), unique(scope_id,source_id,occurrence_key)
);
create table private.pomodoist_invitations (
  id uuid primary key default gen_random_uuid(), scope_id uuid not null references private.pomodoist_scopes on delete cascade,
  token text not null unique default encode(extensions.gen_random_bytes(32),'hex'),
  email text, role text not null check(role in ('member','observer')),
  created_by uuid not null, expires_at timestamptz not null default now()+interval '7 days',
  revoked_at timestamptz, accepted_by uuid, accepted_at timestamptz, created_at timestamptz not null default now()
);
create index pomodoist_invites_scope on private.pomodoist_invitations(scope_id);
create table private.pomodoist_notifications (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users on delete cascade,
  scope_id uuid references private.pomodoist_scopes on delete cascade,
  kind text not null, data jsonb not null default '{}', read_at timestamptz, created_at timestamptz not null default now()
);
create index pomodoist_notifications_user on private.pomodoist_notifications(user_id,created_at);
create table private.pomodoist_uploads (
  id uuid primary key, scope_id uuid not null references private.pomodoist_scopes on delete cascade,
  task_id text not null, user_id uuid not null, name text not null, content_type text not null,
  bytes bigint not null check(bytes between 1 and 20000000), object_path text not null unique,
  expires_at timestamptz not null default now()+interval '2 hours', finished_at timestamptz, deleted_at timestamptz
);
create index pomodoist_uploads_user on private.pomodoist_uploads(user_id,finished_at);
create table private.pomodoist_upload_months (
  user_id uuid not null, month date not null, bytes bigint not null default 0 check(bytes between 0 and 1000000000),
  primary key(user_id,month)
);
create table private.pomodoist_upload_years (
  user_id uuid not null, year integer not null, bytes bigint not null default 0 check(bytes between 0 and 5000000000),
  primary key(user_id,year)
);
create table private.pomodoist_personal_history (
  user_id uuid primary key references auth.users on delete cascade,
  history_unlimited boolean not null, grace_ends_at timestamptz
);
create table private.pomodoist_storage_deletions (
  object_path text primary key, created_at timestamptz not null default now()
);

do $$ declare t text; begin
  foreach t in array array['pomodoist_scopes','pomodoist_members','pomodoist_shared_preferences','pomodoist_shared_entities','pomodoist_shared_receipts',
    'pomodoist_transferred_entities','pomodoist_recurrence_successors','pomodoist_invitations','pomodoist_notifications','pomodoist_uploads',
    'pomodoist_upload_months','pomodoist_upload_years','pomodoist_personal_history','pomodoist_storage_deletions'] loop
    execute format('alter table private.%I enable row level security',t);
    execute format('revoke all on private.%I from public, anon, authenticated',t);
  end loop;
end $$;

do $$ begin
  if to_regclass('storage.buckets') is not null then
    insert into storage.buckets(id,name,public,file_size_limit)
    values ('pomodoist-shared','pomodoist-shared',false,20000000)
    on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit;
  end if;
end $$;
-- No client Storage policies: only the Edge service can issue scoped signed URLs.

create function private.pomodoist_collaboration_hint(p_scope uuid,p_user uuid default null)
returns void language plpgsql security definer set search_path='' as $$
declare u uuid; begin
  for u in select user_id from private.pomodoist_members where scope_id=p_scope union select p_user where p_user is not null loop
    begin
      perform realtime.send(jsonb_build_object('appId','pomodoist','scopeId',p_scope,'deviceId','collaboration-server'),
        'changed','sync:'||u::text||':pomodoist',true);
    exception when others then null; -- A failed hint must never undo a durable mutation.
    end;
  end loop;
end $$;

create function private.pomodoist_shared_put(p_scope uuid,p_type text,p_id text,p_data jsonb,p_deleted timestamptz default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r bigint; clocks jsonb; old_data jsonb; begin
  update private.pomodoist_scopes set revision=revision+1 where id=p_scope returning revision into r;
  select data,field_revision into old_data,clocks from private.pomodoist_shared_entities
    where scope_id=p_scope and entity_type=p_type and entity_id=p_id;
  select coalesce(jsonb_object_agg(key,case when old_data->key is distinct from value
    then to_jsonb(r) else coalesce(clocks->key,to_jsonb(r)) end),'{}') into clocks from jsonb_each(p_data);
  insert into private.pomodoist_shared_entities(scope_id,entity_type,entity_id,data,field_revision,server_revision,deleted_at)
    values(p_scope,p_type,p_id,p_data,clocks,r,p_deleted)
  on conflict(scope_id,entity_type,entity_id) do update set data=excluded.data,field_revision=excluded.field_revision,
    server_revision=excluded.server_revision,deleted_at=excluded.deleted_at,updated_at=now();
  return jsonb_build_object('entityType',p_type,'entityId',p_id,'data',p_data,'serverRevision',r,'deletedAt',p_deleted,'updatedAt',now());
end $$;

create function private.pomodoist_collaboration_event(p_scope uuid,p_actor uuid,p_kind text,p_entity text,p_data jsonb default '{}')
returns void language plpgsql security definer set search_path='' as $$
begin
  perform private.pomodoist_shared_put(p_scope,'activity',gen_random_uuid()::text,
    jsonb_build_object('scopeId',p_scope,'createdBy',p_actor,'kind',p_kind,'entityId',p_entity,'createdAt',now())||p_data);
  if p_kind in ('discussion','assignment') then
    insert into private.pomodoist_notifications(user_id,scope_id,kind,data)
      select m.user_id,p_scope,p_kind,jsonb_build_object('actorId',p_actor,'entityId',p_entity)||p_data
      from private.pomodoist_members m join private.pomodoist_shared_entities t on t.scope_id=m.scope_id and t.entity_type='task'
        and t.entity_id=case when p_kind='discussion' then p_data->>'taskId' else p_entity end
      where m.scope_id=p_scope and m.user_id<>p_actor and (
        t.data->'assigneeIds' ? m.user_id::text or (p_kind='discussion' and (
          t.data->>'createdBy'=m.user_id::text or exists(select 1 from private.pomodoist_shared_entities c where c.scope_id=p_scope
            and c.entity_type='comment' and c.data->>'taskId'=t.entity_id and c.data->>'createdBy'=m.user_id::text and c.deleted_at is null))));
  elsif p_kind in ('access.role','access.transfer') then
    insert into private.pomodoist_notifications(user_id,scope_id,kind,data)
      select user_id,p_scope,p_kind,jsonb_build_object('actorId',p_actor,'entityId',p_entity)
      from private.pomodoist_members where scope_id=p_scope and user_id::text=p_entity and user_id<>p_actor;
  elsif p_kind='access.remove' then
    insert into private.pomodoist_notifications(user_id,scope_id,kind,data)
      select id,null,p_kind,jsonb_build_object('scopeId',p_scope) from auth.users where id::text=p_entity;
  end if;
  perform private.pomodoist_collaboration_hint(p_scope);
end $$;

create function private.pomodoist_history_refresh(p_scope uuid default null,p_user uuid default null)
returns void language plpgsql security definer set search_path='' as $$
declare paid boolean; begin
  if p_scope is not null then
    select exists(select 1 from private.pomodoist_members where scope_id=p_scope
      and public.has_active_pomodoist_paid_entitlement(user_id)) into paid;
    update private.pomodoist_scopes set grace_ends_at=case when paid then null
      when history_unlimited then coalesce(grace_ends_at,now()+interval '30 days') else grace_ends_at end,
      history_unlimited=paid where id=p_scope;
  end if;
  if p_user is not null and exists(select 1 from auth.users where id=p_user) then
    paid:=public.has_active_pomodoist_paid_entitlement(p_user);
    insert into private.pomodoist_personal_history(user_id,history_unlimited) values(p_user,paid)
    on conflict(user_id) do update set grace_ends_at=case when paid then null
      when private.pomodoist_personal_history.history_unlimited then coalesce(private.pomodoist_personal_history.grace_ends_at,now()+interval '30 days')
      else private.pomodoist_personal_history.grace_ends_at end,history_unlimited=paid;
  end if;
end $$;

-- All personal writers (including older clients, MCP and integrations) pass this guard.
create function private.pomodoist_transfer_guard() returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.app_id <> 'pomodoist' then return new; end if;
  if new.deleted_at is null and exists(select 1 from private.pomodoist_transferred_entities
      where user_id=new.user_id and entity_type=new.entity_type and entity_id=new.entity_id) then
    raise exception using errcode='42501',message='Entity was transferred to a shared scope';
  end if;
  if new.deleted_at is null and new.entity_type in ('project','task','section') and exists(select 1 from private.pomodoist_transferred_entities where user_id=new.user_id
      and entity_type='project' and entity_id=case when new.entity_type='project' then new.data->>'parentId' else new.data->>'projectId' end) then
    raise exception using errcode='42501',message='Personal writes cannot target shared projects';
  end if;
  if new.deleted_at is null and new.entity_type in ('task_label','task_kanban_status','task_completion')
    and exists(select 1 from private.pomodoist_transferred_entities where user_id=new.user_id and entity_type='task' and entity_id=new.data->>'taskId') then
    raise exception using errcode='42501',message='Personal content writes cannot target transferred tasks'; end if;
  if new.entity_type='task' and jsonb_typeof(new.data)='object' then
    new.data:=jsonb_set(new.data,'{createdBy}',coalesce(case when tg_op='UPDATE' then old.data->'createdBy' end,to_jsonb(new.user_id::text)));
    if new.data->>'status'='completed' and (tg_op='INSERT' or old.data->>'status' is distinct from 'completed') then
      new.data:=new.data||jsonb_build_object('completedBy',new.user_id);
    end if;
  end if;
  return new;
end $$;
create trigger pomodoist_transfer_guard before insert or update on public.sync_entities
  for each row execute function private.pomodoist_transfer_guard();

update public.sync_entities set data=jsonb_set(data,'{createdBy}',to_jsonb(user_id::text)),
  server_revision=nextval('public.sync_revision_seq'),updated_at=now()
  where app_id='pomodoist' and entity_type='task' and jsonb_typeof(data)='object' and not(data ? 'createdBy');

create function private.pomodoist_members_json(p_scope uuid) returns jsonb language sql security definer set search_path='' as $$
  select coalesce(jsonb_agg(jsonb_build_object('userId',m.user_id,'role',m.role,'displayName',coalesce(p.display_name,'Member')) order by m.joined_at),'[]')
  from private.pomodoist_members m left join public.profiles p on p.id=m.user_id where m.scope_id=p_scope;
$$;
create function private.pomodoist_preferences_json(p_user uuid,p_scope uuid default null) returns jsonb language sql security definer set search_path='' as $$
  select coalesce(jsonb_agg(jsonb_build_object('scopeId',scope_id,'entityType',entity_type,'entityId',entity_id,'data',data,'updatedAt',updated_at)),'[]')
    from private.pomodoist_shared_preferences where user_id=p_user and (p_scope is null or scope_id=p_scope);
$$;
create function private.pomodoist_scope_json(p_scope uuid,p_user uuid) returns jsonb language sql security definer set search_path='' as $$
  select jsonb_build_object('id',s.id,'rootProjectId',s.root_project_id,'ownerId',s.owner_id,'role',m.role,
    'revision',s.revision,'historyUnlimited',s.history_unlimited,'graceEndsAt',s.grace_ends_at,
    'publicToken',case when m.role='administrator' then s.public_token end)
  from private.pomodoist_scopes s join private.pomodoist_members m on m.scope_id=s.id where s.id=p_scope and m.user_id=p_user;
$$;

create function private.pomodoist_shared_apply(p_scope uuid,p_actor uuid,p_role text,p_op jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  typ text:=p_op->>'entityType'; eid text:=p_op->>'entityId'; op text:=p_op->>'operation';
  payload jsonb:=p_op->'payload'; base bigint:=(p_op->>'baseRevision')::bigint;
  e private.pomodoist_shared_entities%rowtype; s private.pomodoist_scopes%rowtype;
  d jsonb; result jsonb; conflicts jsonb:='[]'; k text; v jsonb; parent text; assignee text; c record;
  changed boolean; allowed text[]; focus_started timestamptz; focus_completed timestamptz; focus_seconds integer;
begin
  payload:=payload-array['commandType','isFavorite','isCollapsed','dayOrder','viewStyle','completedFocusIntervals','totalFocusSeconds'];
  select * into s from private.pomodoist_scopes where id=p_scope;
  if p_role not in ('administrator','member') then raise exception using errcode='42501',message='Editor role required'; end if;
  if coalesce(typ,'') not in ('project','section','task','label','task_label','task_kanban_status','task_completion','comment','focus_interval') or coalesce(eid,'')='' or length(eid)>200
    or coalesce(op,'') not in ('upsert','delete','assign') or jsonb_typeof(payload) is distinct from 'object'
    or base is null or base<0 or base>s.revision or coalesce(p_op->>'opId','')='' or length(p_op->>'opId')>200
    or nullif(p_op->>'clientUpdatedAt','')::timestamptz is null then
    raise exception using errcode='22023',message='Invalid shared operation';
  end if;
  select * into e from private.pomodoist_shared_entities where scope_id=p_scope and entity_type=typ and entity_id=eid;
  if e.deleted_at is not null then
    return jsonb_build_object('opId',p_op->>'opId','status','rejected','code','deleted','error','Deletion wins','serverRevision',e.server_revision);
  end if;
  if typ='comment' and e.entity_id is not null and e.data->>'createdBy'<>p_actor::text
    and not (op='delete' and p_role='administrator') then
    raise exception using errcode='42501',message='Only the author may edit a comment';
  end if;
  if typ='focus_interval' and op='upsert' and e.entity_id is not null and e.data->>'createdBy'=p_actor::text
    and e.data->>'taskId'=payload->>'taskId'
    and coalesce((e.data->>'durationSeconds')::integer,(e.data->>'plannedSeconds')::integer)=coalesce((payload->>'durationSeconds')::integer,(payload->>'plannedSeconds')::integer)
    and private.pomodoist_history_timestamp(e.data->>'startedAt',null)=private.pomodoist_history_timestamp(payload->>'startedAt',null) then
    return jsonb_build_object('opId',p_op->>'opId','status','applied','entityType',typ,'entityId',eid,'data',e.data,
      'serverRevision',e.server_revision,'deletedAt',e.deleted_at,'updatedAt',e.updated_at);
  end if;
  if typ in ('focus_interval','task_completion') and (e.entity_id is not null or op<>'upsert') then
    raise exception using errcode='42501',message='Completed focus contributions are immutable';
  end if;
  if typ='label' and e.entity_id is not null and (payload ? 'systemKey') and payload->'systemKey' is distinct from e.data->'systemKey' then
    raise exception using errcode='42501',message='System status identity is immutable'; end if;
  if typ='project' and eid=s.root_project_id and (op='delete' or (payload ? 'parentId' and payload->>'parentId' is not null)) then
    raise exception using errcode='42501',message='Shared root cannot be moved or deleted with a content operation';
  end if;
  if typ='task' and op='upsert' and payload->>'recurrenceSourceId' is not null then
    if not exists(select 1 from private.pomodoist_shared_entities where scope_id=p_scope and entity_type='task'
      and entity_id=payload->>'recurrenceSourceId' and deleted_at is null)
      or length(coalesce(payload->>'occurrenceKey','')) not between 1 and 200 then
      raise exception using errcode='22023',message='Invalid recurrence source or occurrence'; end if;
    select successor_id into parent from private.pomodoist_recurrence_successors where scope_id=p_scope and source_id=payload->>'recurrenceSourceId';
    if parent is not null and parent<>eid then
      raise exception using errcode='40001',message='A successor already exists for this recurrence source'; end if;
    insert into private.pomodoist_recurrence_successors values(p_scope,payload->>'recurrenceSourceId',payload->>'occurrenceKey',eid) on conflict do nothing;
  end if;
  d:=coalesce(e.data,'{}');
  if op='delete' then
    if e.entity_id is null then raise exception using errcode='22023',message='Entity not found'; end if;
    if typ='project' then
      parent:=coalesce(d->>'parentId',s.root_project_id);
      for c in select * from private.pomodoist_shared_entities where scope_id=p_scope and deleted_at is null
        and ((entity_type='project' and data->>'parentId'=eid) or (entity_type in ('task','section') and data->>'projectId'=eid)) loop
        perform private.pomodoist_shared_put(p_scope,c.entity_type,c.entity_id,
          c.data||jsonb_build_object(case when c.entity_type='project' then 'parentId' else 'projectId' end,parent));
      end loop;
    elsif typ='section' then
      for c in select * from private.pomodoist_shared_entities where scope_id=p_scope and entity_type='task' and data->>'sectionId'=eid and deleted_at is null loop
        perform private.pomodoist_shared_put(p_scope,'task',c.entity_id,c.data||jsonb_build_object('sectionId',null));
      end loop;
    elsif typ='label' then
      if d->>'systemKey' in ('backlog','done') then raise exception using errcode='42501',message='Protected shared status cannot be deleted'; end if;
      for c in select * from private.pomodoist_shared_entities where scope_id=p_scope and entity_type in ('task_label','task_kanban_status') and data->>'labelId'=eid and deleted_at is null loop
        perform private.pomodoist_shared_put(p_scope,c.entity_type,c.entity_id,c.data,now());
      end loop;
    elsif typ='task' then
      -- Subtasks remain in the same project and inherit the removed task's parent.
      for c in select * from private.pomodoist_shared_entities where scope_id=p_scope and entity_type='task'
        and deleted_at is null and data->>'parentId'=eid loop
        perform private.pomodoist_shared_put(p_scope,'task',c.entity_id,c.data||jsonb_build_object('parentId',d->'parentId'));
      end loop;
    end if;
    result:=private.pomodoist_shared_put(p_scope,typ,eid,d,now());
  elsif op='assign' then
    if typ<>'task' or e.entity_id is null or jsonb_typeof(payload->'add') is distinct from 'array'
      or jsonb_typeof(payload->'remove') is distinct from 'array' then raise exception using errcode='22023',message='Invalid assignment operation'; end if;
    for assignee in select jsonb_array_elements_text(payload->'add') loop
      if not exists(select 1 from private.pomodoist_members where scope_id=p_scope and user_id::text=assignee and role<>'observer') then
        raise exception using errcode='22023',message='Assignee must be an accepted editor';
      end if;
    end loop;
    select coalesce(jsonb_agg(to_jsonb(x) order by x),'[]') into v from (
      select jsonb_array_elements_text(coalesce(d->'assigneeIds','[]')) x union select jsonb_array_elements_text(payload->'add')
      except select jsonb_array_elements_text(payload->'remove')) a;
    d:=d||jsonb_build_object('assigneeIds',v); result:=private.pomodoist_shared_put(p_scope,typ,eid,d);
  else
    allowed:=case typ
      when 'task' then array['id','schemaVersion','content','description','projectId','parentId','priority','orderKey','dueJson','deadlineJson',
        'sectionId','recurrenceSourceId','occurrenceKey','durationSeconds','estimatedFocusIntervals','status','completedAt','createdAt','updatedAt','labelIds','labelIdsJson','repeatJson',
        'recurrenceJson','isDeleted','createdBy','scopeId','assigneeIds','completedBy','userId']
      when 'project' then array['id','schemaVersion','name','description','parentId','color','icon','orderKey','isArchived','createdAt','updatedAt','isDeleted','createdBy','scopeId','userId']
      when 'label' then array['id','schemaVersion','name','color','icon','orderKey','kind','systemKey','createdAt','updatedAt','isDeleted','createdBy','scopeId','userId']
      when 'section' then array['id','schemaVersion','name','projectId','orderKey','isArchived','createdAt','updatedAt','isDeleted','createdBy','scopeId','userId']
      when 'task_label' then array['id','schemaVersion','taskId','labelId','kind','changedAt','createdAt','updatedAt','isDeleted','scopeId','userId']
      when 'task_kanban_status' then array['id','schemaVersion','taskId','labelId','kind','changedAt','createdAt','updatedAt','isDeleted','scopeId','userId']
      when 'task_completion' then array['id','schemaVersion','taskId','userId','completedAt','snapshotJson','createdAt','scopeId']
      when 'comment' then array['id','taskId','body','mentions','createdAt','updatedAt','createdBy','scopeId']
      when 'focus_interval' then array['id','schemaVersion','taskId','projectId','runId','type','status','plannedSeconds','durationSeconds','startedAt','pausedAt','pausedTotalSeconds','completedAt','stoppedAt','sequenceNumber','createdAt','updatedAt','isDeleted','createdBy','scopeId','userId'] end;
    for k,v in select * from jsonb_each(payload) loop
      if not (k=any(allowed)) then raise exception using errcode='22023',message='Unsupported shared field: '||k; end if;
      if k in ('recurrenceSourceId','occurrenceKey') and e.entity_id is not null and e.data->k is distinct from v then
        raise exception using errcode='42501',message='Recurrence source is immutable'; end if;
      if k in ('userId','id','scopeId','createdBy','createdAt','completedBy','completedAt','updatedAt') then continue; end if;
      if k='assigneeIds' and e.entity_id is not null then
        if v is distinct from d->k then raise exception using errcode='22023',message='Use assignment add/remove operations'; end if;
        continue;
      end if;
      if coalesce((e.field_revision->>k)::bigint,0)>base and e.data->k is distinct from v then conflicts:=conflicts||to_jsonb(k); end if;
    end loop;
    if jsonb_array_length(conflicts)>0 then
      return jsonb_build_object('opId',p_op->>'opId','status','conflict','fields',conflicts,'current',e.data,'data',e.data,
        'serverRevision',e.server_revision,'entityType',typ,'entityId',eid);
    end if;
    d:=d||(payload-array['userId','id','scopeId','createdBy','createdAt','completedBy','completedAt','updatedAt']);
    d:=d||jsonb_build_object('id',eid,'scopeId',p_scope,'createdBy',coalesce(e.data->>'createdBy',p_actor::text),
      'createdAt',coalesce(e.data->'createdAt',to_jsonb(now())),'updatedAt',now());
    if d->>'isDeleted'='true' then raise exception using errcode='22023',message='Use a delete operation'; end if;
    if typ in ('task','project','label','section') then
      k:=case when typ='task' then 'content' else 'name' end;
      if jsonb_typeof(d->k) is distinct from 'string' or length(btrim(d->>k)) not between 1 and 20000 then
        raise exception using errcode='22023',message='Missing or invalid entity title'; end if;
    end if;
    if typ='task' and (coalesce(d->>'status','open') not in ('open','completed')
      or (d ? 'priority' and ((d->>'priority')::integer not between 1 and 4))) then
      raise exception using errcode='22023',message='Invalid task status or priority'; end if;
    if typ='project' then
      parent:=d->>'parentId';
      if eid<>s.root_project_id and (parent is null or not exists(select 1 from private.pomodoist_shared_entities
        where scope_id=p_scope and entity_type='project' and entity_id=parent and deleted_at is null)) then
        raise exception using errcode='22023',message='Project parent must be in the same shared scope';
      end if;
      if exists(with recursive ancestors as (
        select entity_id,data->>'parentId' parent_id from private.pomodoist_shared_entities where scope_id=p_scope and entity_type='project' and entity_id=parent
        union select e2.entity_id,e2.data->>'parentId' from private.pomodoist_shared_entities e2 join ancestors a on e2.entity_id=a.parent_id
          where e2.scope_id=p_scope and e2.entity_type='project') select 1 from ancestors where entity_id=eid) then
        raise exception using errcode='22023',message='Project cycle';
      end if;
    elsif typ='task' then
      if not exists(select 1 from private.pomodoist_shared_entities where scope_id=p_scope and entity_type='project'
        and entity_id=d->>'projectId' and deleted_at is null) then raise exception using errcode='22023',message='Task project must be in the same shared scope'; end if;
      if e.entity_id is not null and e.data->>'projectId' is distinct from d->>'projectId' and not(payload ? 'sectionId') then
        d:=d||jsonb_build_object('sectionId',null);
      end if;
      if d->>'sectionId' is not null and not exists(select 1 from private.pomodoist_shared_entities where scope_id=p_scope
        and entity_type='section' and entity_id=d->>'sectionId' and deleted_at is null and data->>'projectId'=d->>'projectId') then
        raise exception using errcode='22023',message='Section must belong to the task project'; end if;
      parent:=d->>'parentId';
      if parent is not null and not exists(select 1 from private.pomodoist_shared_entities where scope_id=p_scope and entity_type='task'
        and entity_id=parent and deleted_at is null and data->>'projectId'=d->>'projectId') then
        raise exception using errcode='22023',message='Subtask parent must belong to the same project';
      end if;
      if exists(with recursive ancestors as (
        select entity_id,data->>'parentId' parent_id from private.pomodoist_shared_entities where scope_id=p_scope and entity_type='task' and entity_id=parent
        union select e2.entity_id,e2.data->>'parentId' from private.pomodoist_shared_entities e2 join ancestors a on e2.entity_id=a.parent_id
          where e2.scope_id=p_scope and e2.entity_type='task') select 1 from ancestors where entity_id=eid) then
        raise exception using errcode='22023',message='Task cycle';
      end if;
      if jsonb_typeof(coalesce(d->'assigneeIds','[]'))<>'array' then raise exception using errcode='22023',message='Invalid assignees'; end if;
      for assignee in select jsonb_array_elements_text(coalesce(d->'assigneeIds','[]')) loop
        if not exists(select 1 from private.pomodoist_members where scope_id=p_scope and user_id::text=assignee and role<>'observer') then
          raise exception using errcode='22023',message='Assignee must be an accepted editor';
        end if;
      end loop;
      d:=d||jsonb_build_object('assigneeIds',coalesce(d->'assigneeIds','[]'));
      if d->>'status'='completed' and e.data->>'status' is distinct from 'completed' then
        d:=d||jsonb_build_object('completedBy',p_actor,'completedAt',now());
      elsif d->>'status' is distinct from 'completed' then d:=d||jsonb_build_object('completedBy',null,'completedAt',null); end if;
      -- Moving a task moves its complete subtask tree, preserving the same scope.
      if e.entity_id is not null and e.data->>'projectId' is distinct from d->>'projectId' then
        for c in with recursive children as (
          select * from private.pomodoist_shared_entities where scope_id=p_scope and entity_type='task' and data->>'parentId'=eid and deleted_at is null
          union select t.* from private.pomodoist_shared_entities t join children p on t.data->>'parentId'=p.entity_id
            where t.scope_id=p_scope and t.entity_type='task' and t.deleted_at is null) select * from children loop
          perform private.pomodoist_shared_put(p_scope,'task',c.entity_id,c.data||jsonb_build_object('projectId',d->>'projectId','sectionId',null));
        end loop;
      end if;
    elsif typ='section' then
      if not exists(select 1 from private.pomodoist_shared_entities where scope_id=p_scope and entity_type='project' and entity_id=d->>'projectId' and deleted_at is null) then
        raise exception using errcode='22023',message='Section project must belong to the shared scope'; end if;
      if e.entity_id is not null and e.data->>'projectId' is distinct from d->>'projectId' then
        for c in select * from private.pomodoist_shared_entities where scope_id=p_scope and entity_type='task'
          and data->>'sectionId'=eid and deleted_at is null loop
          perform private.pomodoist_shared_put(p_scope,'task',c.entity_id,c.data||jsonb_build_object('sectionId',null));
        end loop;
      end if;
    elsif typ in ('comment','focus_interval','task_label','task_kanban_status','task_completion') then
      if not exists(select 1 from private.pomodoist_shared_entities where scope_id=p_scope and entity_type='task'
        and entity_id=d->>'taskId' and deleted_at is null) then raise exception using errcode='22023',message='Task is inaccessible'; end if;
      if e.entity_id is not null and d->>'taskId' is distinct from e.data->>'taskId' then raise exception using errcode='22023',message='Discussion cannot be moved'; end if;
      if typ='comment' then
        if jsonb_typeof(d->'body') is distinct from 'string' or length(btrim(d->>'body'))=0 or length(d->>'body')>20000 then
          raise exception using errcode='22023',message='Comment must contain 1 to 20000 characters'; end if;
        if jsonb_typeof(coalesce(d->'mentions','[]'))<>'array' then raise exception using errcode='22023',message='Invalid mentions'; end if;
        for assignee in select jsonb_array_elements_text(coalesce(d->'mentions','[]')) loop
          if not exists(select 1 from private.pomodoist_members where scope_id=p_scope and user_id::text=assignee) then
            raise exception using errcode='22023',message='Mention must name an accepted member'; end if;
        end loop;
      elsif typ in ('task_label','task_kanban_status') then
        if (typ='task_kanban_status' and eid<>d->>'taskId')
          or (typ='task_label' and eid<>(d->>'taskId')||':'||(d->>'labelId')) then
          raise exception using errcode='22023',message='Invalid label relation identity'; end if;
        if not exists(select 1 from private.pomodoist_shared_entities where scope_id=p_scope and entity_type='label' and entity_id=d->>'labelId' and deleted_at is null) then
          raise exception using errcode='22023',message='Label must belong to the shared scope'; end if;
      elsif typ='task_completion' then
        if e.entity_id is not null then raise exception using errcode='42501',message='Completion records are immutable'; end if;
        select data into v from private.pomodoist_shared_entities where scope_id=p_scope and entity_type='task' and entity_id=d->>'taskId';
        if v->>'status' is distinct from 'completed' or v->>'completedBy' is distinct from p_actor::text then
          raise exception using errcode='42501',message='Only the completing actor may record completion'; end if;
        d:=d||jsonb_build_object('userId',p_actor,'completedAt',v->'completedAt','snapshotJson',v);
      else
        d:=d||jsonb_build_object('userId',p_actor);
        focus_seconds:=coalesce((d->>'durationSeconds')::integer,(d->>'plannedSeconds')::integer);
        focus_started:=private.pomodoist_history_timestamp(payload->>'startedAt',null);
        focus_completed:=private.pomodoist_history_timestamp(payload->>'completedAt',null);
        if focus_seconds is null or focus_seconds not between 1 and 86400 or focus_started is null or focus_completed is null
          or focus_completed>now()+interval '5 minutes' or focus_started>focus_completed-focus_seconds*interval '1 second'
          or coalesce(d->>'type','work')<>'work' or coalesce(d->>'status','completed')<>'completed' then
          raise exception using errcode='22023',message='Invalid completed focus interval'; end if;
        d:=d||jsonb_build_object('durationSeconds',focus_seconds,'startedAt',focus_started,'completedAt',focus_completed);
      end if;
    end if;
    result:=private.pomodoist_shared_put(p_scope,typ,eid,d);
  end if;
  if typ='focus_interval' then
    select jsonb_build_object('totalFocusSeconds',coalesce(sum(coalesce((data->>'durationSeconds')::bigint,(data->>'plannedSeconds')::bigint)),0),'completedFocusIntervals',count(*)) into v
      from private.pomodoist_shared_entities where scope_id=p_scope and entity_type='focus_interval' and data->>'taskId'=d->>'taskId' and deleted_at is null;
    select data into payload from private.pomodoist_shared_entities where scope_id=p_scope and entity_type='task' and entity_id=d->>'taskId';
    perform private.pomodoist_shared_put(p_scope,'task',d->>'taskId',payload||v);
  end if;
  perform private.pomodoist_collaboration_event(p_scope,p_actor,case when op='assign' then 'assignment' when typ='comment' then 'discussion' else typ||'.'||op end,eid,
    case when typ='comment' then jsonb_build_object('taskId',d->>'taskId') else '{}'::jsonb end);
  if typ='task' and op='upsert' and e.entity_id is null and jsonb_array_length(coalesce(d->'assigneeIds','[]'))>0 then
    perform private.pomodoist_collaboration_event(p_scope,p_actor,'assignment',eid);
  end if;
  if typ='comment' and op='upsert' then
    insert into private.pomodoist_notifications(user_id,scope_id,kind,data)
      select value::uuid,p_scope,'mention',jsonb_build_object('taskId',d->>'taskId','commentId',eid,'actorId',p_actor)
      from jsonb_array_elements_text(coalesce(d->'mentions','[]')) where value<>p_actor::text;
  end if;
  return result||jsonb_build_object('opId',p_op->>'opId','status','applied');
end $$;

create function private.pomodoist_collaboration(p_request jsonb)
returns jsonb language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare
  actor uuid:=auth.uid(); action text:=p_request->>'action'; scope uuid; role_name text;
  s private.pomodoist_scopes%rowtype; invitation private.pomodoist_invitations%rowtype;
  upload private.pomodoist_uploads%rowtype; rec record; result jsonb; d jsonb; rows jsonb;
  applied jsonb:='[]'; conflicts jsonb:='[]'; rejected jsonb:='[]'; operation jsonb; receipt record;
  target uuid; ids text[]; task_ids text[]; token text; since bigint; cursor_value bigint; more boolean;
  paid boolean; amount bigint; held bigint; used_month bigint; used_year bigint; month_start date; yr integer; object_size bigint;
begin
  if octet_length(p_request::text)>1000000 then raise exception using errcode='22023',message='Request is too large'; end if;
  if jsonb_typeof(p_request) is distinct from 'object' then raise exception using errcode='22023',message='Expected request object'; end if;
  if action='publicRead' then
    select * into s from private.pomodoist_scopes where public_token=p_request->>'token' and length(p_request->>'token')=64;
    if not found then raise exception using errcode='42501',message='Public link is unavailable'; end if;
    select coalesce(jsonb_agg(jsonb_build_object('id',entity_id,'entityType',entity_type,
      'data',(select coalesce(jsonb_object_agg(k,v),'{}') from jsonb_each(e.data) a(k,v)
        where k in ('name','content','description','parentId','projectId','taskId','body','dueJson','deadlineJson','status','priority','orderKey','createdAt','updatedAt','completedAt'))
        ||jsonb_build_object('creatorName',coalesce((select display_name from public.profiles where id::text=e.data->>'createdBy'),'Member'),
          'assigneeNames',coalesce((select jsonb_agg(coalesce(p.display_name,'Member')) from public.profiles p
            where p.id::text in(select jsonb_array_elements_text(coalesce(e.data->'assigneeIds','[]')))),'[]')))
      order by e.server_revision),'[]') into rows from private.pomodoist_shared_entities e
      where scope_id=s.id and entity_type in ('project','task','comment') and deleted_at is null
      and (entity_type<>'comment' or exists(select 1 from private.pomodoist_shared_entities t where t.scope_id=s.id
        and t.entity_type='task' and t.entity_id=e.data->>'taskId' and t.deleted_at is null));
    return jsonb_build_object('scopeId',s.id,'rootProjectId',s.root_project_id,'entities',rows);
  end if;
  -- Deleted users and revoked sessions must not retain access through unexpired JWTs.
  if actor is null or not exists(select 1 from auth.users where id=actor and not coalesce(is_anonymous,false))
    or not exists(select 1 from auth.sessions where user_id=actor and id::text=auth.jwt()->>'session_id'
      and (not_after is null or not_after>now())) then
    raise exception using errcode='42501',message='An active authenticated session is required';
  end if;
  if action in ('state','notifications') then
    for rec in select scope_id from private.pomodoist_members where user_id=actor loop
      perform private.pomodoist_history_refresh(rec.scope_id);
    end loop;
    perform private.pomodoist_history_refresh(null,actor);
    select coalesce(jsonb_agg(jsonb_build_object('id',id,'scopeId',scope_id,'kind',kind,'data',data,'readAt',read_at,'createdAt',created_at)
      order by created_at desc),'[]') into rows from (select * from private.pomodoist_notifications where user_id=actor order by created_at desc limit 200) n;
    if action='notifications' then return jsonb_build_object('notifications',rows); end if;
    return jsonb_build_object('userId',actor,'scopes',coalesce((select jsonb_agg(private.pomodoist_scope_json(scope_id,actor))
      from private.pomodoist_members where user_id=actor),'[]'),'notifications',rows,
      'preferences',private.pomodoist_preferences_json(actor),
      'invitations',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'scopeId',i.scope_id,'role',i.role,'token',i.token,'expiresAt',i.expires_at))
        from private.pomodoist_invitations i join auth.users u on lower(u.email)=i.email where u.id=actor
        and u.email_confirmed_at is not null and i.revoked_at is null and i.accepted_at is null and i.expires_at>now()),'[]'),
      'personalHistory',(select jsonb_build_object('historyUnlimited',history_unlimited,'graceEndsAt',grace_ends_at)
        from private.pomodoist_personal_history where user_id=actor));
  elsif action='readNotification' then
    update private.pomodoist_notifications set read_at=coalesce(read_at,now()) where id=(p_request->>'notificationId')::uuid and user_id=actor;
    return jsonb_build_object('ok',true);
  elsif action='share' then
    perform pg_advisory_xact_lock(hashtextextended('pomodoist-google-calendar:'||actor::text,0));
    if p_request->>'rootProjectId'='inbox' then raise exception using errcode='22023',message='Inbox cannot be shared'; end if;
    select coalesce(max(server_revision),0) into cursor_value from public.sync_entities where user_id=actor and app_id='pomodoist';
    if p_request->>'expectedRevision' is null or (p_request->>'expectedRevision')::bigint<>cursor_value then
      raise exception using errcode='40001',message='Complete personal sync before sharing'; end if;
    if not exists(select 1 from public.sync_entities where user_id=actor and app_id='pomodoist' and entity_type='project'
      and entity_id=p_request->>'rootProjectId' and deleted_at is null) then raise exception using errcode='22023',message='Personal project not found'; end if;
    with recursive tree as (
      select entity_id from public.sync_entities where user_id=actor and app_id='pomodoist' and entity_type='project' and entity_id=p_request->>'rootProjectId' and deleted_at is null
      union select e.entity_id from public.sync_entities e join tree t on e.data->>'parentId'=t.entity_id
        where e.user_id=actor and e.app_id='pomodoist' and e.entity_type='project' and e.deleted_at is null)
    select array_agg(entity_id) into ids from tree;
    if exists(select 1 from public.sync_entities e join private.pomodoist_transferred_entities t on t.user_id=e.user_id
      and t.entity_type=e.entity_type and t.entity_id=e.entity_id where e.user_id=actor and e.app_id='pomodoist'
      and e.entity_type='project' and e.data->>'parentId'=any(ids)) then
      raise exception using errcode='22023',message='A shared root cannot contain another shared root'; end if;
    select array_agg(entity_id) into task_ids from public.sync_entities where user_id=actor and app_id='pomodoist'
      and entity_type='task' and data->>'projectId'=any(ids);
    insert into private.pomodoist_scopes(root_project_id,owner_id) values(p_request->>'rootProjectId',actor) returning * into s;
    insert into private.pomodoist_members(scope_id,user_id,role) values(s.id,actor,'administrator');
    insert into private.pomodoist_shared_preferences(scope_id,user_id,entity_type,entity_id,data)
      select s.id,actor,'scope',s.id::text,jsonb_build_object('rootParentId',data->'parentId') from public.sync_entities
      where user_id=actor and app_id='pomodoist' and entity_type='project' and entity_id=s.root_project_id;
    for rec in select * from public.sync_entities where user_id=actor and app_id='pomodoist'
      and ((entity_type='project' and entity_id=any(ids)) or (entity_type='task' and entity_id=any(task_ids))) loop
      insert into private.pomodoist_shared_preferences(scope_id,user_id,entity_type,entity_id,data)
        values(s.id,actor,rec.entity_type,case when rec.entity_type='label' then s.id::text||':'||rec.entity_id else rec.entity_id end,
          (select coalesce(jsonb_object_agg(key,value),'{}') from jsonb_each(rec.data) where key in ('isFavorite','isCollapsed','dayOrder','viewStyle','viewPreferences','reminders')))
        on conflict(scope_id,user_id,entity_type,entity_id) do nothing;
      d:=(rec.data-array['userId','dayOrder','isCollapsed','isFavorite','reminderJson','reminders','viewPreferences','viewStyle','completedFocusIntervals','totalFocusSeconds'])
        ||jsonb_build_object('scopeId',s.id,'createdBy',coalesce(rec.data->>'createdBy',actor::text));
      if rec.entity_type='project' and rec.entity_id=s.root_project_id then d:=d||jsonb_build_object('parentId',null); end if;
      if rec.entity_type='task' then
        d:=d||jsonb_build_object('assigneeIds','[]'::jsonb,'completedBy',case when d->>'status'='completed' then actor else null end);
        if d->>'parentId' is not null and not(d->>'parentId'=any(coalesce(task_ids,array[]::text[]))) then d:=d||jsonb_build_object('parentId',null); end if;
      end if;
      perform private.pomodoist_shared_put(s.id,rec.entity_type,rec.entity_id,d,rec.deleted_at);
      update public.sync_entities set deleted_at=coalesce(deleted_at,now()),server_revision=nextval('public.sync_revision_seq'),updated_at=now()
        where user_id=actor and app_id='pomodoist' and entity_type=rec.entity_type and entity_id=rec.entity_id;
      insert into private.pomodoist_transferred_entities values(actor,rec.entity_type,rec.entity_id,s.id);
    end loop;
    for rec in select * from public.sync_entities where user_id=actor and app_id='pomodoist' and deleted_at is null
      and ((entity_type='section' and data->>'projectId'=any(ids))
        or (entity_type in ('task_label','task_kanban_status','task_completion') and data->>'taskId'=any(task_ids))
        or (entity_type='focus_interval' and data->>'taskId'=any(task_ids) and data->>'type'='work' and data->>'status'='completed')
        or (entity_type='label' and entity_id in(select data->>'labelId' from public.sync_entities where user_id=actor
          and app_id='pomodoist' and entity_type in ('task_label','task_kanban_status') and data->>'taskId'=any(task_ids))) or (entity_type='label' and data->>'kind'='kanbanStatus')) loop
      insert into private.pomodoist_shared_preferences(scope_id,user_id,entity_type,entity_id,data)
        values(s.id,actor,rec.entity_type,case when rec.entity_type='label' then s.id::text||':'||rec.entity_id else rec.entity_id end,
          (select coalesce(jsonb_object_agg(key,value),'{}') from jsonb_each(rec.data) where key in ('isFavorite','isCollapsed','dayOrder','viewStyle','viewPreferences','reminders')))
        on conflict(scope_id,user_id,entity_type,entity_id) do nothing;
      d:=(rec.data-array['userId','dayOrder','isCollapsed','isFavorite'])||jsonb_build_object('scopeId',s.id,'createdBy',actor);
      if rec.entity_type in ('task_completion','focus_interval') then d:=d||jsonb_build_object('userId',actor); end if;
      if rec.entity_type='focus_interval' then
        d:=d||jsonb_build_object('durationSeconds',coalesce((d->>'durationSeconds')::integer,(d->>'plannedSeconds')::integer));
      end if;
      if rec.entity_type='label' then
        d:=d||jsonb_build_object('id',s.id::text||':'||rec.entity_id);
        perform private.pomodoist_shared_put(s.id,'label',s.id::text||':'||rec.entity_id,d);
      elsif rec.entity_type in ('task_label','task_kanban_status') then
        d:=d||jsonb_build_object('labelId',s.id::text||':'||(rec.data->>'labelId'));
        d:=d||jsonb_build_object('id',case when rec.entity_type='task_label'
          then (d->>'taskId')||':'||(d->>'labelId') else rec.entity_id end);
        perform private.pomodoist_shared_put(s.id,rec.entity_type,
          case when rec.entity_type='task_label' then (d->>'taskId')||':'||(d->>'labelId') else rec.entity_id end,d);
      else perform private.pomodoist_shared_put(s.id,rec.entity_type,rec.entity_id,d); end if;
      if rec.entity_type not in ('label','focus_interval') then
        update public.sync_entities set deleted_at=now(),server_revision=nextval('public.sync_revision_seq'),updated_at=now()
          where user_id=actor and app_id='pomodoist' and entity_type=rec.entity_type and entity_id=rec.entity_id;
        insert into private.pomodoist_transferred_entities values(actor,rec.entity_type,rec.entity_id,s.id);
      end if;
    end loop;
    for rec in select * from private.pomodoist_shared_entities where scope_id=s.id and entity_type='task' loop
      select jsonb_build_object('totalFocusSeconds',coalesce(sum(coalesce((data->>'durationSeconds')::bigint,(data->>'plannedSeconds')::bigint)),0),
        'completedFocusIntervals',count(*)) into d from private.pomodoist_shared_entities where scope_id=s.id and entity_type='focus_interval'
        and data->>'taskId'=rec.entity_id and deleted_at is null and data->>'type'='work' and data->>'status'='completed';
      perform private.pomodoist_shared_put(s.id,'task',rec.entity_id,rec.data||d,rec.deleted_at);
    end loop;
    perform private.pomodoist_history_refresh(s.id);
    perform private.pomodoist_collaboration_event(s.id,actor,'shared',s.root_project_id);
    return jsonb_build_object('scope',private.pomodoist_scope_json(s.id,actor));
  elsif action='accept' then
    select i.scope_id into scope from private.pomodoist_invitations i where i.token=p_request->>'token';
  else scope:=(p_request->>'scopeId')::uuid;
  end if;
  select * into s from private.pomodoist_scopes where id=scope for update;
  if not found then raise exception using errcode='42501',message='Shared scope is inaccessible'; end if;
  if action='accept' then
    select i.* into invitation from private.pomodoist_invitations i where i.token=p_request->>'token' and i.scope_id=scope for update;
    if invitation.revoked_at is not null or invitation.expires_at<=now() or
      (invitation.email is not null and not exists(select 1 from auth.users where id=actor and lower(email)=invitation.email and email_confirmed_at is not null))
      or (invitation.accepted_by is not null and invitation.accepted_by<>actor) then
      raise exception using errcode='42501',message='Invitation is unavailable for this account'; end if;
    if exists(select 1 from private.pomodoist_members where scope_id=scope and user_id=actor) then
      return jsonb_build_object('scope',private.pomodoist_scope_json(scope,actor)); end if;
    insert into private.pomodoist_members(scope_id,user_id,role) values(scope,actor,invitation.role) on conflict do nothing;
    if invitation.email is not null then update private.pomodoist_invitations set accepted_by=actor,accepted_at=coalesce(accepted_at,now()) where id=invitation.id; end if;
    perform private.pomodoist_history_refresh(scope);
    perform private.pomodoist_collaboration_event(scope,actor,'member.joined',actor::text);
    return jsonb_build_object('scope',private.pomodoist_scope_json(scope,actor));
  end if;
  select role into role_name from private.pomodoist_members where scope_id=scope and user_id=actor;
  if role_name is null then raise exception using errcode='42501',message='Shared scope is inaccessible'; end if;
  perform private.pomodoist_history_refresh(scope);
  if action='preferences' then
    if coalesce(p_request->>'entityType','') not in ('scope','project','task','label','section')
      or coalesce(p_request->>'entityId','')='' or jsonb_typeof(p_request->'data') is distinct from 'object'
      or exists(select 1 from jsonb_object_keys(p_request->'data') k where k not in ('isFavorite','isCollapsed','dayOrder','reminders','viewStyle','viewPreferences','rootParentId')) then
      raise exception using errcode='22023',message='Invalid private preferences'; end if;
    if p_request->>'entityType'='scope' then
      if p_request->>'entityId'<>scope::text then raise exception using errcode='22023',message='Invalid scope preference identity'; end if;
    elsif not exists(select 1 from private.pomodoist_shared_entities where scope_id=scope and entity_type=p_request->>'entityType'
      and entity_id=p_request->>'entityId' and deleted_at is null) then raise exception using errcode='42501',message='Preference entity is inaccessible'; end if;
    if p_request->'data' ? 'rootParentId' then
      if p_request->>'entityType'<>'scope' then raise exception using errcode='22023',message='Root placement is a scope preference'; end if;
      if p_request->'data'->>'rootParentId' is not null and not exists(select 1 from public.sync_entities where user_id=actor and app_id='pomodoist'
        and entity_type='project' and entity_id=p_request->'data'->>'rootParentId' and deleted_at is null) then
        raise exception using errcode='22023',message='Root parent must be an accessible personal project'; end if;
    end if;
    insert into private.pomodoist_shared_preferences(scope_id,user_id,entity_type,entity_id,data)
      values(scope,actor,p_request->>'entityType',p_request->>'entityId',p_request->'data')
      on conflict(scope_id,user_id,entity_type,entity_id) do update
      set data=private.pomodoist_shared_preferences.data||excluded.data,updated_at=now();
    perform private.pomodoist_collaboration_hint(null,actor);
    return jsonb_build_object('preferences',private.pomodoist_preferences_json(actor,scope));
  end if;
  if action='members' then return jsonb_build_object('members',private.pomodoist_members_json(scope),
    'invitations',case when role_name='administrator' then coalesce((select jsonb_agg(jsonb_build_object('id',id,'email',email,'role',role,'expiresAt',expires_at,'revokedAt',revoked_at,'acceptedAt',accepted_at))
      from private.pomodoist_invitations where scope_id=scope),'[]') else '[]'::jsonb end);
  elsif action in ('pull','export') then
    since:=coalesce((p_request->>'sinceRevision')::bigint,0);
    if since<0 then raise exception using errcode='22023',message='Invalid cursor'; end if;
    with page as (select * from private.pomodoist_shared_entities where scope_id=scope and server_revision>since order by server_revision limit 501),
      limited as (select * from page order by server_revision limit 500)
    select coalesce(jsonb_agg(jsonb_build_object('entityType',entity_type,'entityId',entity_id,'data',data,'serverRevision',server_revision,
      'deletedAt',deleted_at,'updatedAt',updated_at) order by server_revision),'[]'),coalesce(max(server_revision),s.revision),
      (select count(*)>500 from page) into rows,cursor_value,more from limited;
    return jsonb_build_object('changes',rows,'nextCursor',cursor_value,'hasMore',more,'members',private.pomodoist_members_json(scope),
      'scope',private.pomodoist_scope_json(scope,actor),'preferences',private.pomodoist_preferences_json(actor,scope));
  elsif action='push' then
    if jsonb_typeof(p_request->'operations') is distinct from 'array' or jsonb_array_length(p_request->'operations')>200 then
      raise exception using errcode='22023',message='Expected at most 200 operations'; end if;
    for operation in select value from jsonb_array_elements(p_request->'operations') loop
      begin
        select stored.request,stored.result into receipt from private.pomodoist_shared_receipts stored
          where stored.scope_id=scope and stored.user_id=actor and stored.op_id=operation->>'opId';
        if found then
          if receipt.request<>operation then raise exception using errcode='22023',message='Operation ID was reused with different content'; end if;
          result:=receipt.result;
        else
          result:=private.pomodoist_shared_apply(scope,actor,role_name,operation);
          insert into private.pomodoist_shared_receipts values(scope,actor,operation->>'opId',operation,result);
        end if;
      exception when others then result:=jsonb_build_object('opId',operation->>'opId','status','rejected','code',sqlstate,'error',sqlerrm);
      end;
      if result->>'status'='applied' then applied:=applied||jsonb_build_array(result);
      elsif result->>'status'='conflict' then conflicts:=conflicts||jsonb_build_array(result);
      else rejected:=rejected||jsonb_build_array(result); end if;
    end loop;
    return jsonb_build_object('applied',applied,'conflicts',conflicts,'rejected',rejected);
  elsif action in ('invite','role','remove','transfer','delete','publicLink') and role_name<>'administrator' then
    raise exception using errcode='42501',message='Administrator role required';
  end if;
  if action='invite' then
    if p_request->>'invitationId' is not null and p_request->>'revoke'='true' then
      update private.pomodoist_invitations set revoked_at=coalesce(revoked_at,now()) where scope_id=scope and id=(p_request->>'invitationId')::uuid;
      return jsonb_build_object('ok',true);
    end if;
    if coalesce(p_request->>'role','member') not in ('member','observer') then raise exception using errcode='22023',message='Invitation role must be member or observer'; end if;
    if p_request->>'email' is not null and (length(p_request->>'email')>254 or (p_request->>'email')!~'^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$') then
      raise exception using errcode='22023',message='Invalid invitation email'; end if;
    if (select count(*) from private.pomodoist_invitations where scope_id=scope and created_at>now()-interval '1 hour')>=50 then
      raise exception using errcode='54000',message='Invitation rate limit exceeded'; end if;
    insert into private.pomodoist_invitations(scope_id,email,role,created_by)
      values(scope,lower(p_request->>'email'),coalesce(p_request->>'role','member'),actor) returning * into invitation;
    insert into private.pomodoist_notifications(user_id,scope_id,kind,data) select id,scope,'invitation',jsonb_build_object('invitationId',invitation.id)
      from auth.users where lower(email)=invitation.email;
    perform private.pomodoist_collaboration_event(scope,actor,'invitation.created',invitation.id::text);
    return jsonb_build_object('id',invitation.id,'token',invitation.token,'email',invitation.email,'role',invitation.role,'expiresAt',invitation.expires_at);
  elsif action in ('role','remove','leave','transfer') then
    target:=case when action='leave' then actor else (p_request->>'userId')::uuid end;
    if not exists(select 1 from private.pomodoist_members where scope_id=scope and user_id=target) then raise exception using errcode='22023',message='Member not found'; end if;
    if action='transfer' then
      if actor<>s.owner_id then raise exception using errcode='42501',message='Only the owner may transfer ownership'; end if;
      update private.pomodoist_members set role='administrator' where scope_id=scope and user_id=target;
      update private.pomodoist_scopes set owner_id=target where id=scope;
    else
      if target=s.owner_id then raise exception using errcode='42501',message='Owner must transfer ownership or delete the shared root'; end if;
      if action='role' then
        if coalesce(p_request->>'role','') not in ('administrator','member','observer') then raise exception using errcode='22023',message='Invalid role'; end if;
        update private.pomodoist_members set role=p_request->>'role' where scope_id=scope and user_id=target;
      else
        delete from private.pomodoist_members where scope_id=scope and user_id=target;
        delete from private.pomodoist_notifications where scope_id=scope and user_id=target;
      end if;
      if action<>'role' or p_request->>'role'='observer' then
        for rec in select * from private.pomodoist_shared_entities where scope_id=scope and entity_type='task' and data->'assigneeIds' ? target::text loop
          perform private.pomodoist_shared_put(scope,'task',rec.entity_id,rec.data||jsonb_build_object('assigneeIds',(rec.data->'assigneeIds')-target::text),rec.deleted_at);
        end loop;
      end if;
    end if;
    perform private.pomodoist_history_refresh(scope);
    perform private.pomodoist_collaboration_hint(scope,target);
    perform private.pomodoist_collaboration_event(scope,actor,'access.'||action,target::text);
    return jsonb_build_object('ok',true,'members',case when action='leave' then '[]'::jsonb else private.pomodoist_members_json(scope) end);
  elsif action='delete' then
    if actor<>s.owner_id then raise exception using errcode='42501',message='Only the owner may delete the shared root'; end if;
    for rec in select * from private.pomodoist_uploads where scope_id=scope and deleted_at is null loop
      if rec.finished_at is not null then
        update private.pomodoist_upload_years set bytes=bytes-rec.bytes where user_id=rec.user_id and year=extract(year from rec.finished_at at time zone 'UTC')::integer;
      end if;
      insert into private.pomodoist_storage_deletions(object_path) values(rec.object_path) on conflict do nothing;
    end loop;
    perform private.pomodoist_collaboration_hint(scope);
    delete from private.pomodoist_scopes where id=scope;
    return jsonb_build_object('ok',true);
  elsif action='publicLink' then
    if jsonb_typeof(p_request->'enabled') is distinct from 'boolean' then raise exception using errcode='22023',message='Expected enabled boolean'; end if;
    token:=case when (p_request->>'enabled')::boolean then encode(extensions.gen_random_bytes(32),'hex') else null end;
    update private.pomodoist_scopes set public_token=token where id=scope;
    return jsonb_build_object('token',token);
  end if;
  if action='reserveUpload' then
    if role_name='observer' or not public.has_active_pomodoist_paid_entitlement(actor) then raise exception using errcode='42501',message='Pro editor required to upload'; end if;
    amount:=(p_request->>'bytes')::bigint;
    if amount is null or amount not between 1 and 20000000 or length(coalesce(p_request->>'name','')) not between 1 and 255
      or length(coalesce(p_request->>'contentType','')) not between 1 and 200 then raise exception using errcode='22023',message='Invalid attachment'; end if;
    if not exists(select 1 from private.pomodoist_shared_entities where scope_id=scope and entity_type='task'
      and entity_id=p_request->>'taskId' and deleted_at is null) then raise exception using errcode='42501',message='Task is inaccessible'; end if;
    perform pg_advisory_xact_lock(hashtextextended('pomodoist-uploads:'||actor::text,0));
    select * into upload from private.pomodoist_uploads where id=(p_request->>'uploadId')::uuid;
    if found then
      if upload.user_id<>actor or upload.scope_id<>scope or upload.task_id<>p_request->>'taskId' or upload.bytes<>amount
        or upload.name<>p_request->>'name' or upload.content_type<>p_request->>'contentType' or upload.deleted_at is not null
        or (upload.finished_at is null and upload.expires_at<=now()) then
        raise exception using errcode='22023',message='Upload ID is unavailable'; end if;
    else
      month_start:=date_trunc('month',now() at time zone 'UTC')::date; yr:=extract(year from now() at time zone 'UTC');
      select coalesce(sum(bytes),0) into held from private.pomodoist_uploads where user_id=actor and finished_at is null and deleted_at is null and expires_at>now();
      select coalesce((select bytes from private.pomodoist_upload_months where user_id=actor and month=month_start),0) into used_month;
      select coalesce((select bytes from private.pomodoist_upload_years where user_id=actor and year=yr),0) into used_year;
      if used_month+held+amount>1000000000 or used_year+held+amount>5000000000 then raise exception using errcode='54000',message='Attachment quota exceeded'; end if;
      insert into private.pomodoist_uploads(id,scope_id,task_id,user_id,name,content_type,bytes,object_path)
        values((p_request->>'uploadId')::uuid,scope,p_request->>'taskId',actor,p_request->>'name',p_request->>'contentType',amount,
          scope::text||'/'||actor::text||'/'||(p_request->>'uploadId')) returning * into upload;
    end if;
    return jsonb_build_object('uploadId',upload.id,'objectPath',upload.object_path,'expiresAt',upload.expires_at,'finished',upload.finished_at is not null);
  elsif action in ('finishUpload','download','deleteAttachment') then
    select * into upload from private.pomodoist_uploads where scope_id=scope
      and id=coalesce(p_request->>'uploadId',p_request->>'attachmentId')::uuid for update;
    if not found or upload.deleted_at is not null then raise exception using errcode='42501',message='Attachment is inaccessible'; end if;
    if not exists(select 1 from private.pomodoist_shared_entities where scope_id=scope and entity_type='task'
      and entity_id=upload.task_id and (deleted_at is null or (action in ('download','deleteAttachment') and data<>'{}'::jsonb))) then raise exception using errcode='42501',message='Task is inaccessible'; end if;
    if action='download' then
      if upload.finished_at is null then raise exception using errcode='42501',message='Attachment is unfinished'; end if;
      return jsonb_build_object('objectPath',upload.object_path,'name',upload.name,'attachmentId',upload.id);
    end if;
    if action='finishUpload' and upload.finished_at is not null and upload.user_id=actor then
      select data into d from private.pomodoist_shared_entities where scope_id=scope and entity_type='attachment' and entity_id=upload.id::text;
      return jsonb_build_object('attachment',d);
    end if;
    if role_name='observer' then raise exception using errcode='42501',message='Editor role required'; end if;
    perform pg_advisory_xact_lock(hashtextextended('pomodoist-uploads:'||upload.user_id::text,0));
    if action='deleteAttachment' then
      if upload.finished_at is not null then
        update private.pomodoist_upload_years set bytes=bytes-upload.bytes where user_id=upload.user_id
          and year=extract(year from upload.finished_at at time zone 'UTC')::integer;
      end if;
      update private.pomodoist_uploads set deleted_at=now() where id=upload.id;
      insert into private.pomodoist_storage_deletions(object_path) values(upload.object_path) on conflict do nothing;
      select data into d from private.pomodoist_shared_entities where scope_id=scope and entity_type='attachment' and entity_id=upload.id::text;
      if d is not null then perform private.pomodoist_shared_put(scope,'attachment',upload.id::text,d,now()); end if;
      return jsonb_build_object('ok',true,'objectPath',upload.object_path);
    end if;
    if upload.user_id<>actor or not public.has_active_pomodoist_paid_entitlement(actor) then raise exception using errcode='42501',message='Pro uploader required'; end if;
    if upload.finished_at is null then
      if upload.expires_at<=now() then raise exception using errcode='22023',message='Upload reservation expired'; end if;
      select (metadata->>'size')::bigint into object_size from storage.objects where bucket_id='pomodoist-shared' and name=upload.object_path and metadata->>'mimetype'=upload.content_type;
      if object_size is null or object_size<>upload.bytes or object_size>20000000 then raise exception using errcode='22023',message='Uploaded object size does not match reservation'; end if;
      month_start:=date_trunc('month',now() at time zone 'UTC')::date; yr:=extract(year from now() at time zone 'UTC');
      select coalesce(sum(bytes),0) into held from private.pomodoist_uploads where user_id=actor and id<>upload.id
        and finished_at is null and deleted_at is null and expires_at>now();
      insert into private.pomodoist_upload_months(user_id,month) values(actor,month_start) on conflict do nothing;
      insert into private.pomodoist_upload_years(user_id,year) values(actor,yr) on conflict do nothing;
      select bytes into used_month from private.pomodoist_upload_months where user_id=actor and month=month_start for update;
      select bytes into used_year from private.pomodoist_upload_years where user_id=actor and year=yr for update;
      if used_month+held+upload.bytes>1000000000 or used_year+held+upload.bytes>5000000000 then raise exception using errcode='54000',message='Attachment quota exceeded for completion period'; end if;
      update private.pomodoist_upload_months set bytes=bytes+upload.bytes where user_id=actor and month=month_start;
      update private.pomodoist_upload_years set bytes=bytes+upload.bytes where user_id=actor and year=yr;
      update private.pomodoist_uploads set finished_at=now() where id=upload.id returning * into upload;
      d:=jsonb_build_object('id',upload.id,'scopeId',scope,'taskId',upload.task_id,'createdBy',actor,
        'name',upload.name,'contentType',upload.content_type,'bytes',upload.bytes,'createdAt',upload.finished_at);
      perform private.pomodoist_shared_put(scope,'attachment',upload.id::text,d);
      perform private.pomodoist_collaboration_event(scope,actor,'attachment.created',upload.id::text,jsonb_build_object('taskId',upload.task_id));
    end if;
    select data into d from private.pomodoist_shared_entities where scope_id=scope and entity_type='attachment' and entity_id=upload.id::text;
    return jsonb_build_object('attachment',d);
  end if;
  raise exception using errcode='22023',message='Unknown collaboration action';
end $$;

create function public.pomodoist_collaboration(p_request jsonb) returns jsonb
language sql security invoker set search_path='' as $$ select private.pomodoist_collaboration(p_request); $$;

create function private.pomodoist_member_deleted() returns trigger language plpgsql security definer set search_path='' as $$
declare item record; begin
  if exists(select 1 from private.pomodoist_scopes where id=old.scope_id) then
    for item in select * from private.pomodoist_shared_entities where scope_id=old.scope_id and entity_type='task' and data->'assigneeIds' ? old.user_id::text loop
      perform private.pomodoist_shared_put(old.scope_id,'task',item.entity_id,item.data||jsonb_build_object('assigneeIds',(item.data->'assigneeIds')-old.user_id::text),item.deleted_at);
    end loop;
    perform private.pomodoist_history_refresh(old.scope_id);
    perform private.pomodoist_collaboration_hint(old.scope_id,old.user_id);
  end if;
  return null;
end $$;
create trigger pomodoist_member_deleted after delete on private.pomodoist_members for each row execute function private.pomodoist_member_deleted();

-- Entitlement writes update the grace transition immediately, including member removal.
create function private.pomodoist_history_entitlement_changed() returns trigger language plpgsql security definer set search_path='' as $$
declare u uuid; r record; begin
  u:=case when tg_op='DELETE' then old.user_id else new.user_id end;
  perform private.pomodoist_history_refresh(null,u);
  for r in select scope_id from private.pomodoist_members where user_id=u loop
    perform private.pomodoist_history_refresh(r.scope_id);
    perform private.pomodoist_collaboration_hint(r.scope_id);
  end loop;
  return null;
end $$;
insert into private.pomodoist_personal_history(user_id,history_unlimited)
  select id,public.has_active_pomodoist_paid_entitlement(id) from auth.users;
create trigger pomodoist_history_entitlement_changed after insert or update or delete on public.user_entitlements
  for each row execute function private.pomodoist_history_entitlement_changed();

create function private.pomodoist_history_timestamp(p_value text,p_fallback timestamptz) returns timestamptz
language plpgsql set search_path='' as $$ begin
  if p_value~'^[0-9]+$' then return to_timestamp(p_value::numeric/1000); end if;
  return coalesce(nullif(p_value,'')::timestamptz,p_fallback);
exception when others then return p_fallback; end $$;

-- Replaces the existing 90-day personal cron implementation with 365 days and grace.
create or replace function public.prune_pomodoist_free_task_history() returns integer
language plpgsql security definer set search_path='' as $$
declare r record; scope_rec record; deleted integer:=0; n integer; begin
  for r in select id from auth.users loop perform private.pomodoist_history_refresh(null,r.id); end loop;
  delete from public.sync_entities e using private.pomodoist_personal_history h
    where e.user_id=h.user_id and e.app_id='pomodoist' and e.entity_type='task' and not h.history_unlimited
      and not exists(select 1 from private.pomodoist_transferred_entities transferred where transferred.user_id=e.user_id
        and transferred.entity_type=e.entity_type and transferred.entity_id=e.entity_id)
      and (h.grace_ends_at is null or h.grace_ends_at<=now())
      and ((e.deleted_at is not null and e.deleted_at<now()-interval '365 days') or (e.data->>'status'='completed'
        and private.pomodoist_history_timestamp(e.data->>'completedAt',e.updated_at)<now()-interval '365 days'));
  get diagnostics deleted=row_count;
  for scope_rec in select id from private.pomodoist_scopes for update loop
    perform private.pomodoist_history_refresh(scope_rec.id);
    -- Retain tombstone identities and revisions permanently; remove aged content only.
    -- This permits every stale client to purge cached history without resurrection.
    for r in select e.* from private.pomodoist_shared_entities e join private.pomodoist_scopes s on s.id=e.scope_id
      where e.scope_id=scope_rec.id and e.entity_type='task' and e.data<>'{}'::jsonb and not s.history_unlimited
      and (s.grace_ends_at is null or s.grace_ends_at<=now())
      and ((e.deleted_at is not null and e.deleted_at<now()-interval '365 days') or (e.data->>'status'='completed'
        and private.pomodoist_history_timestamp(e.data->>'completedAt',e.updated_at)<now()-interval '365 days')) loop
      -- Earlier purges in this pass may already have promoted this task.
      select current_task.* into r from private.pomodoist_shared_entities current_task
        where current_task.scope_id=r.scope_id and current_task.entity_type='task' and current_task.entity_id=r.entity_id;
      declare surviving_child record; promoted_parent text; begin
        select parent.entity_id into promoted_parent from private.pomodoist_shared_entities parent
          where parent.scope_id=r.scope_id and parent.entity_type='task' and parent.entity_id=r.data->>'parentId'
            and parent.deleted_at is null and parent.data->>'projectId'=r.data->>'projectId';
        for surviving_child in select * from private.pomodoist_shared_entities where scope_id=r.scope_id and entity_type='task'
          and data->>'parentId'=r.entity_id and deleted_at is null loop
          perform private.pomodoist_shared_put(r.scope_id,'task',surviving_child.entity_id,
            surviving_child.data||jsonb_build_object('parentId',promoted_parent));
        end loop;
      end;
      delete from private.pomodoist_shared_receipts where scope_id=r.scope_id and request->>'entityId'=r.entity_id;
      perform private.pomodoist_shared_put(r.scope_id,'task',r.entity_id,'{}',coalesce(r.deleted_at,now()));
      deleted:=deleted+1;
      -- Task-associated records receive tombstones through the same revision sequence.
      declare child record; begin
        for child in select * from private.pomodoist_shared_entities where scope_id=r.scope_id and data->>'taskId'=r.entity_id loop
          delete from private.pomodoist_shared_receipts where scope_id=r.scope_id and request->>'entityType'=child.entity_type and request->>'entityId'=child.entity_id;
          perform private.pomodoist_shared_put(r.scope_id,child.entity_type,child.entity_id,'{}',now());
        end loop;
      end;
      declare f record; begin
        for f in select * from private.pomodoist_uploads where scope_id=r.scope_id and task_id=r.entity_id and deleted_at is null loop
          if f.finished_at is not null then update private.pomodoist_upload_years set bytes=bytes-f.bytes
            where user_id=f.user_id and year=extract(year from f.finished_at at time zone 'UTC')::integer; end if;
          update private.pomodoist_uploads set deleted_at=now() where id=f.id;
          insert into private.pomodoist_storage_deletions(object_path) values(f.object_path) on conflict do nothing;
        end loop;
      end;
      perform private.pomodoist_collaboration_hint(r.scope_id);
    end loop;
  end loop;
  insert into private.pomodoist_storage_deletions(object_path) select object_path from private.pomodoist_uploads
    where finished_at is null and expires_at<=now() on conflict do nothing;
  return deleted;
end $$;

-- Storage deletion is performed through Storage API, never by deleting metadata rows.
create function private.pomodoist_collaboration_storage_cleanup(p_deleted text[] default array[]::text[]) returns jsonb
language plpgsql security definer set search_path='' as $$ begin
  if current_setting('request.jwt.claims',true)::jsonb->>'role' is distinct from 'service_role' then
    raise exception using errcode='42501',message='Service role required'; end if;
  delete from private.pomodoist_storage_deletions where object_path=any(p_deleted);
  return jsonb_build_object('paths',coalesce((select jsonb_agg(object_path) from
    (select object_path from private.pomodoist_storage_deletions order by created_at limit 100) q),'[]'));
end $$;

create function public.pomodoist_collaboration_storage_cleanup(p_deleted text[] default array[]::text[]) returns jsonb
language sql security invoker set search_path='' as $$ select private.pomodoist_collaboration_storage_cleanup(p_deleted); $$;
revoke all on function private.pomodoist_collaboration_storage_cleanup(text[]) from public,anon,authenticated;
grant execute on function private.pomodoist_collaboration_storage_cleanup(text[]) to service_role;

-- Default function privileges must not expose privileged implementation helpers.
revoke all on function public.prune_pomodoist_free_task_history() from public,anon,authenticated;
revoke all on function public.pomodoist_collaboration_storage_cleanup(text[]) from public,anon,authenticated;
grant execute on function public.pomodoist_collaboration_storage_cleanup(text[]) to service_role;
do $$ declare f record; begin
  for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='private' and p.proname in ('pomodoist_collaboration_hint','pomodoist_shared_put','pomodoist_collaboration_event',
      'pomodoist_history_refresh','pomodoist_transfer_guard','pomodoist_preferences_json','pomodoist_members_json','pomodoist_scope_json','pomodoist_shared_apply',
      'pomodoist_collaboration','pomodoist_member_deleted','pomodoist_history_entitlement_changed','pomodoist_history_timestamp') loop
    execute format('revoke all on function %s from public,anon,authenticated',f.signature);
  end loop;
end $$;
revoke all on function public.pomodoist_collaboration(jsonb) from public,anon,authenticated;
-- Anonymous public-link reads stay behind the service-role Edge function; the
-- private schema and its entrypoints must not be resolvable by anon.
grant execute on function private.pomodoist_collaboration(jsonb),public.pomodoist_collaboration(jsonb) to authenticated,service_role;
CREATE OR REPLACE FUNCTION private.pull_changes(p_app_id text, p_device_id text, p_since_revision bigint DEFAULT 0, p_limit integer DEFAULT 500)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user_id uuid := auth.uid();
  v_limit integer := least(greatest(coalesce(p_limit, 500), 1), 1000);
  v_changes jsonb;
  v_next_cursor bigint;
  v_has_more boolean;
  v_server_revision bigint;
  v_has_pomodoist_paid_entitlement boolean := false;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  insert into public.sync_devices (
    user_id,
    app_id,
    device_id,
    last_seen_cursor,
    last_seen_at
  )
  values (
    v_user_id,
    p_app_id,
    p_device_id,
    coalesce(p_since_revision, 0),
    timezone('utc', now())
  )
  on conflict (user_id, app_id, device_id) do update
  set last_seen_cursor = excluded.last_seen_cursor,
      last_seen_at = excluded.last_seen_at
  where public.sync_devices.last_seen_cursor
          is distinct from excluded.last_seen_cursor
     or public.sync_devices.last_seen_at
          < excluded.last_seen_at - interval '5 minutes';

  if p_app_id = 'pomodoist' then
    perform private.pomodoist_history_refresh(null,v_user_id);
    select history_unlimited or coalesce(grace_ends_at>now(),false) into v_has_pomodoist_paid_entitlement
      from private.pomodoist_personal_history where user_id=v_user_id;
  end if;

  select coalesce(max(server_revision), 0)
  into v_server_revision
  from public.sync_entities
  where user_id = v_user_id
    and app_id = p_app_id;

  if coalesce(p_since_revision, 0) > v_server_revision then
    return jsonb_build_object(
      'nextCursor', v_server_revision,
      'hasMore', false,
      'changes', '[]'::jsonb
    );
  end if;

  with page as (
    select *
    from public.sync_entities
    where user_id = v_user_id
      and app_id = p_app_id
      and server_revision > coalesce(p_since_revision, 0)
      and (
        deleted_at is null
        or deleted_at > timezone('utc', now()) - interval '90 days'
        or exists(select 1 from private.pomodoist_transferred_entities t where t.user_id=v_user_id
          and t.entity_type=public.sync_entities.entity_type and t.entity_id=public.sync_entities.entity_id)
        or (
          entity_type = 'task'
          and (v_has_pomodoist_paid_entitlement or deleted_at > now()-interval '365 days')
        )
      )
    order by server_revision asc
    limit v_limit + 1
  ),
  limited as (
    select *
    from page
    order by server_revision asc
    limit v_limit
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'entityType', entity_type,
      'entityId', entity_id,
      'serverRevision', server_revision,
      'deletedAt', deleted_at,
      'data', data,
      'updatedAt', updated_at
    ) order by server_revision asc), '[]'::jsonb),
    coalesce(max(server_revision), v_server_revision),
    (select count(*) > v_limit from page)
  into v_changes, v_next_cursor, v_has_more
  from limited;

  return jsonb_build_object(
    'nextCursor', v_next_cursor,
    'hasMore', coalesce(v_has_more, false),
    'changes', v_changes
  );
end;
$function$;


notify pgrst,'reload schema';
commit;

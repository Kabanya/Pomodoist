begin;

-- The owner can make a shared scope private again. Sharing moved the personal rows
-- into the collaboration tables: it tombstoned them in public.sync_entities without
-- touching data and recorded the transfer in private.pomodoist_transferred_entities,
-- whose guard rejects personal writes. Unshare merges the live shared rows back into
-- those tombstones, clears the ledger, then drops the scope, so the project and its
-- content return to the owner's personal account while the other participants are
-- evicted with a notification. The rest of the dispatcher is carried over unchanged
-- from 20260916000000_pomodoist_core_collaboration_share_revision.sql.
create or replace function private.pomodoist_collaboration(p_request jsonb)
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
        from private.pomodoist_personal_history where user_id=actor),
      'personalRevision',coalesce((select max(server_revision) from public.sync_entities where user_id=actor and app_id='pomodoist'),0));
  elsif action='readNotification' then
    update private.pomodoist_notifications set read_at=coalesce(read_at,now()) where id=(p_request->>'notificationId')::uuid and user_id=actor;
    return jsonb_build_object('ok',true);
  elsif action='share' then
    perform pg_advisory_xact_lock(hashtextextended('pomodoist-google-calendar:'||actor::text,0));
    if p_request->>'rootProjectId'='inbox' then raise exception using errcode='22023',message='Inbox cannot be shared'; end if;
    select coalesce(max(server_revision),0) into cursor_value from public.sync_entities where user_id=actor and app_id='pomodoist';
    if p_request->>'expectedRevision' is null or (p_request->>'expectedRevision')::bigint<>cursor_value then
      raise exception using errcode='22023',message='Complete personal sync before sharing'; end if;
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
  elsif action='unshare' and actor<>s.owner_id then
    raise exception using errcode='42501',message='Only the owner may make the project private';
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
  elsif action='unshare' then
    select coalesce(jsonb_agg(jsonb_build_object('entityType',c.entity_type,'entityId',c.entity_id,'data',
      (c.personal||(c.shared-array['scopeId','assigneeIds','completedBy','totalFocusSeconds','completedFocusIntervals']))
        ||jsonb_build_object('id',c.entity_id,'userId',actor::text,'assigneeIds',coalesce(c.personal->'assigneeIds','[]'::jsonb))
        ||case c.entity_type when 'task' then jsonb_build_object('completedBy',case when c.shared->>'status'='completed' then actor::text end)
          when 'task_label' then jsonb_build_object('labelId',c.personal->>'labelId')
          when 'task_kanban_status' then jsonb_build_object('labelId',c.personal->>'labelId')
          when 'project' then case when c.entity_id=s.root_project_id then jsonb_build_object('parentId',c.personal->'parentId') else '{}'::jsonb end
          else '{}'::jsonb end)),'[]') into rows
      from (select e.entity_type,e.entity_id,e.data personal,x.data shared from public.sync_entities e
        join private.pomodoist_transferred_entities t on t.user_id=e.user_id and t.entity_type=e.entity_type
          and t.entity_id=e.entity_id and t.scope_id=scope
        join private.pomodoist_shared_entities x on x.scope_id=scope and x.entity_type=e.entity_type and x.deleted_at is null
          and x.entity_id=case when e.entity_type='task_label'
            then e.data->>'taskId'||':'||scope::text||':'||(e.data->>'labelId') else e.entity_id end
        where e.user_id=actor and e.app_id='pomodoist' and e.deleted_at is not null) c;
    delete from private.pomodoist_transferred_entities where scope_id=scope;
    insert into public.sync_entities(user_id,app_id,entity_type,entity_id,server_revision,client_updated_at,deleted_at,data,created_at,updated_at)
      select actor,'pomodoist',v->>'entityType',v->>'entityId',nextval('public.sync_revision_seq'),now(),null,v->'data',now(),now()
      from jsonb_array_elements(rows) v
      on conflict (user_id,app_id,entity_type,entity_id) do update set deleted_at=null,server_revision=excluded.server_revision,
        updated_at=now(),data=excluded.data;
    insert into private.pomodoist_notifications(user_id,scope_id,kind,data)
      select user_id,null,'access.unshare',jsonb_build_object('scopeId',scope) from private.pomodoist_members
      where scope_id=scope and user_id<>actor;
    perform private.pomodoist_collaboration_hint(scope);
    for rec in select * from private.pomodoist_uploads where scope_id=scope and deleted_at is null loop
      if rec.finished_at is not null then
        update private.pomodoist_upload_years set bytes=bytes-rec.bytes where user_id=rec.user_id and year=extract(year from rec.finished_at at time zone 'UTC')::integer;
      end if;
      insert into private.pomodoist_storage_deletions(object_path) values(rec.object_path) on conflict do nothing;
    end loop;
    delete from private.pomodoist_scopes where id=scope;
    return jsonb_build_object('ok',true,'restored',jsonb_array_length(rows),'rootProjectId',s.root_project_id);
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

notify pgrst,'reload schema';
commit;

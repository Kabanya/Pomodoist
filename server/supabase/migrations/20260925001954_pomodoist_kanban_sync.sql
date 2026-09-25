-- Preserve shared Kanban revisions, live assignments, and completion history.
CREATE OR REPLACE FUNCTION private.pomodoist_shared_apply(p_scope uuid, p_actor uuid, p_role text, p_op jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  typ text:=p_op->>'entityType'; eid text:=p_op->>'entityId'; op text:=p_op->>'operation';
  payload jsonb:=p_op->'payload'; base bigint:=(p_op->>'baseRevision')::bigint;
  e private.pomodoist_shared_entities%rowtype; s private.pomodoist_scopes%rowtype;
  d jsonb; result jsonb; conflicts jsonb:='[]'; k text; v jsonb; parent text; assignee text; c record;
  changed boolean; allowed text[]; focus_started timestamptz; focus_completed timestamptz; focus_seconds integer;
begin
  payload:=payload-array['schemaVersion','commandType','isFavorite','isCollapsed','dayOrder','viewStyle','completedFocusIntervals','totalFocusSeconds'];
  -- Legacy clients include this local ordering clock on task/label patches.
  if typ not in ('task_label','task_kanban_status') then payload:=payload-'changedAt'; end if;
  select * into s from private.pomodoist_scopes where id=p_scope;
  if p_role not in ('administrator','member') then raise exception using errcode='42501',message='Editor role required'; end if;
  if coalesce(typ,'') not in ('project','section','task','label','task_label','task_kanban_status','task_completion','comment','focus_interval') or coalesce(eid,'')='' or length(eid)>200
    or coalesce(op,'') not in ('upsert','delete','assign') or jsonb_typeof(payload) is distinct from 'object'
    or base is null or base<0 or base>s.revision or coalesce(p_op->>'opId','')='' or length(p_op->>'opId')>200
    or nullif(p_op->>'clientUpdatedAt','')::timestamptz is null then
    raise exception using errcode='22023',message='Invalid shared operation';
  end if;
  select * into e from private.pomodoist_shared_entities where scope_id=p_scope and entity_type=typ and entity_id=eid;
  -- A status relation uses the task ID forever. A fresh assignment may restore
  -- a relation tombstoned by an older server, but never a deleted task/label.
  if e.deleted_at is not null and not (typ='task_kanban_status' and op='upsert' and base>=e.server_revision) then
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
        if c.entity_type='task_kanban_status' then
          select data into v from private.pomodoist_shared_entities where scope_id=p_scope
            and entity_type='task' and entity_id=c.data->>'taskId' and deleted_at is null;
          if v is not null then
            select entity_id into parent from private.pomodoist_shared_entities where scope_id=p_scope
              and entity_type='label' and deleted_at is null and data->>'kind'='kanbanStatus'
              and data->>'systemKey'=case when v->>'status'='completed' then 'done' else 'backlog' end;
            if parent is null then raise exception using errcode='22023',message='Shared workflow anchor is missing'; end if;
            perform private.pomodoist_shared_put(p_scope,c.entity_type,c.entity_id,
              c.data||jsonb_build_object('labelId',parent,'changedAt',now(),'updatedAt',now()));
            continue;
          end if;
        end if;
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
      if k in ('userId','id','scopeId','createdBy','createdAt','completedBy','completedAt','updatedAt','changedAt') then continue; end if;
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
        -- task.complete precedes the Done assignment in the client's queue.
        -- Capture the canonical workflow status before that assignment arrives.
        select label.entity_id into parent from private.pomodoist_shared_entities assignment
          join private.pomodoist_shared_entities label on label.scope_id=assignment.scope_id
            and label.entity_type='label' and label.entity_id=assignment.data->>'labelId'
          where assignment.scope_id=p_scope and assignment.entity_type='task_kanban_status'
            and assignment.entity_id=d->>'taskId' and assignment.deleted_at is null
            and label.deleted_at is null and label.data->>'kind'='kanbanStatus'
            and label.data->>'systemKey' is distinct from 'done';
        d:=d||jsonb_build_object('userId',p_actor,'completedAt',v->'completedAt',
          'snapshotJson',v||jsonb_build_object('version',1,'kanban',jsonb_build_object('previousStatusLabelId',parent)));
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


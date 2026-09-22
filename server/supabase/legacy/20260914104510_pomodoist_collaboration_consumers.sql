-- Reuse the collaboration dispatcher after resolving the existing MCP OAuth session.
-- Only the service role can enter; no caller-supplied user ID is accepted.
create function private.pomodoist_collaboration_mcp(
  p_subject uuid, p_session_id uuid, p_client_id uuid, p_request jsonb
) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid; previous_claims text; response jsonb; begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode='42501',message='Service role required'; end if;
  actor:=public.resolve_pomodoist_mcp_session(p_subject,p_session_id,p_client_id);
  if actor is null then raise exception using errcode='42501',message='MCP session is unavailable'; end if;
  previous_claims:=current_setting('request.jwt.claims',true);
  -- Bind the dispatcher to the already-validated session, preserving its live membership checks.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'session_id',p_session_id,'role','authenticated')::text,true);
  begin
    response:=private.pomodoist_collaboration(p_request);
    if p_request->>'action'='state' then
      response:=response||jsonb_build_object('personalRevision',coalesce((select max(server_revision)
        from public.sync_entities where user_id=actor and app_id='pomodoist'),0));
    end if;
  exception when others then
    perform set_config('request.jwt.claims',coalesce(previous_claims,''),true);
    raise;
  end;
  perform set_config('request.jwt.claims',coalesce(previous_claims,''),true);
  return response;
end $$;
create function public.pomodoist_collaboration_mcp(
  p_subject uuid,p_session_id uuid,p_client_id uuid,p_request jsonb
) returns jsonb language sql security invoker set search_path='' as $$
  select private.pomodoist_collaboration_mcp(p_subject,p_session_id,p_client_id,p_request);
$$;
revoke all on function private.pomodoist_collaboration_mcp(uuid,uuid,uuid,jsonb),
  public.pomodoist_collaboration_mcp(uuid,uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function private.pomodoist_collaboration_mcp(uuid,uuid,uuid,jsonb),
  public.pomodoist_collaboration_mcp(uuid,uuid,uuid,jsonb) to service_role;

-- Check ownership before deleting any account storage. The owner FK remains the final guard.
create function private.pomodoist_account_deletion_check(p_user_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode='42501',message='Service role required'; end if;
  return jsonb_build_object('ownedScopes',coalesce((select jsonb_agg(jsonb_build_object('scopeId',id,'rootProjectId',root_project_id))
    from private.pomodoist_scopes where owner_id=p_user_id),'[]'));
end $$;
create function public.pomodoist_account_deletion_check(p_user_id uuid)
returns jsonb language sql security invoker set search_path='' as $$
  select private.pomodoist_account_deletion_check(p_user_id);
$$;
revoke all on function private.pomodoist_account_deletion_check(uuid),public.pomodoist_account_deletion_check(uuid) from public,anon,authenticated;
grant execute on function private.pomodoist_account_deletion_check(uuid),public.pomodoist_account_deletion_check(uuid) to service_role;

-- Legacy personal task authors are their owning account, including offline client snapshots.
update public.sync_entities set data=data||jsonb_build_object('createdBy',user_id)
where app_id='pomodoist' and entity_type='task' and data->>'createdBy' is null;

CREATE OR REPLACE FUNCTION private.pomodoist_mcp_task_json(p_id text, p_data jsonb) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $$
  select pg_catalog.jsonb_build_object(
    'id', p_id,
    'createdBy', p_data->'createdBy',
    'completedBy', p_data->'completedBy',
    'assigneeIds', coalesce(p_data->'assigneeIds','[]'::jsonb),
    'scopeId', p_data->'scopeId',
    'content', p_data -> 'content',
    'description', p_data -> 'description',
    'projectId', p_data -> 'projectId',
    'parentId', p_data -> 'parentId',
    'priority', p_data -> 'priority',
    'dueJson', p_data -> 'dueJson',
    'status', p_data -> 'status',
    'estimatedFocusIntervals', p_data -> 'estimatedFocusIntervals',
    'completedFocusIntervals', p_data -> 'completedFocusIntervals',
    'totalFocusSeconds', p_data -> 'totalFocusSeconds',
    'orderKey', p_data -> 'orderKey',
    'dayOrder', p_data -> 'dayOrder',
    'createdAt', p_data -> 'createdAt',
    'updatedAt', p_data -> 'updatedAt',
    'completedAt', p_data -> 'completedAt'
  );
$$;

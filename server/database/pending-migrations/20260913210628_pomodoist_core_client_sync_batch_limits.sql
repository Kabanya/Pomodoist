-- RELEASE GATE: apply only after clients with automatic HTTP 413 splitting ship.
create or replace function private.push_changes(p_app_id text, p_device_id text, p_operations jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then raise exception 'Authentication required'; end if;
  if p_operations is not null and pg_catalog.jsonb_typeof(p_operations) <> 'array' then
    raise exception using errcode = '22023', message = 'Invalid sync batch: expected an array';
  end if;
  if pg_catalog.jsonb_array_length(p_operations) > 1000
     or pg_catalog.octet_length(p_operations::text) > 8388608 then
    raise exception using errcode = 'PT413', message = 'Sync batch exceeds server limits';
  end if;
  return private.push_changes_for_user(v_user_id, p_app_id, p_device_id, p_operations);
end;
$$;

notify pgrst, 'reload schema';

begin;
select plan(1);
insert into auth.users(id,email,aud,role,created_at,updated_at) values
 ('ab920000-0000-4000-8000-000000000001','habit-icons@example.test','authenticated','authenticated',now(),now());

do $$
declare
  account_id uuid := 'ab920000-0000-4000-8000-000000000001';
  habit_id text := 'ab920000-0000-4000-8000-000000000010';
  payload jsonb := jsonb_build_object('id',habit_id,'userId','local-user','title','Read','projectId',null,'reminderMinutes',480,
    'scheduleHistory',jsonb_build_array(jsonb_build_object('effectiveFrom','2026-10-06','startDate','2026-10-06','endDate',null,
      'weekdays',jsonb_build_array(1,2,3,4,5,6,7),'targetPerDay',2)),
    'createdAt','2026-10-06T12:00:00Z','updatedAt','2026-10-06T12:00:00Z','isDeleted',false);
  value jsonb;
  partial boolean;
  candidate jsonb;
  op jsonb;
  stored jsonb;
begin
  perform private.validate_pomodoist_habit_payload('habit',habit_id,account_id,payload,false);
  foreach value in array array['null'::jsonb,'"bookOpen"'::jsonb,'"👍🏽"'::jsonb,'"🇷🇺"'::jsonb,'"👨‍👩‍👧‍👦"'::jsonb,to_jsonb(repeat('😀',32))] loop
    foreach partial in array array[false,true] loop
      candidate := case when partial then jsonb_build_object('icon',value) else payload || jsonb_build_object('icon',value) end;
      perform private.validate_pomodoist_habit_payload('habit',habit_id,account_id,candidate,partial);
    end loop;
  end loop;
  foreach value in array array['""'::jsonb,'"   "'::jsonb,'1'::jsonb,'true'::jsonb,'[]'::jsonb,'{}'::jsonb,to_jsonb(repeat('😀',33))] loop
    foreach partial in array array[false,true] loop
      candidate := case when partial then jsonb_build_object('icon',value) else payload || jsonb_build_object('icon',value) end;
      begin
        perform private.validate_pomodoist_habit_payload('habit',habit_id,account_id,candidate,partial);
        raise exception 'Invalid icon accepted: %',value;
      exception when sqlstate '22023' then
        if sqlerrm <> 'Invalid habit icon' then raise; end if;
      end;
    end loop;
  end loop;
  op := jsonb_build_object('opId','sign-create','entityType','habit','entityId',habit_id,'operation','upsert',
    'payload',payload || '{"icon":"📚","schemaVersion":1,"commandType":"habit.create"}'::jsonb,'clientUpdatedAt','2026-10-06T12:00:00Z');
  perform private.push_changes_for_user(account_id,'pomodoist','habit-icons',jsonb_build_array(op));
  -- Full legacy writes omit icon and must not erase its field clock or value.
  perform private.push_changes_for_user(account_id,'pomodoist','habit-icons',jsonb_build_array(op || jsonb_build_object(
    'opId','sign-legacy','payload',payload || '{"title":"Read again"}'::jsonb,'clientUpdatedAt','2026-10-06T12:01:00Z')));
  select data into stored from public.sync_entities where user_id=account_id and app_id='pomodoist' and entity_type='habit' and entity_id=habit_id;
  if stored->>'icon' <> '📚' or stored->>'title' <> 'Read again' then raise exception 'Legacy write erased sign'; end if;
  perform private.push_changes_for_user(account_id,'pomodoist','habit-icons',jsonb_build_array(op || jsonb_build_object(
    'opId','sign-change','payload','{"icon":"bookOpen","updatedAt":"2026-10-06T12:02:00Z"}'::jsonb,'clientUpdatedAt','2026-10-06T12:02:00Z')));
  select data into stored from public.sync_entities where user_id=account_id and app_id='pomodoist' and entity_type='habit' and entity_id=habit_id;
  if stored->>'icon' <> 'bookOpen' or stored->'scheduleHistory' <> payload->'scheduleHistory'
    or stored->>'reminderMinutes' <> '480' or stored->>'title' <> 'Read again' then
    raise exception 'Icon patch changed other habit fields';
  end if;
  perform private.push_changes_for_user(account_id,'pomodoist','habit-icons',jsonb_build_array(op || jsonb_build_object(
    'opId','sign-reset','payload','{"icon":null}'::jsonb,'clientUpdatedAt','2026-10-06T12:03:00Z')));
  select data into stored from public.sync_entities where user_id=account_id and app_id='pomodoist' and entity_type='habit' and entity_id=habit_id;
  if stored->'icon' is distinct from 'null'::jsonb then raise exception 'Icon reset was lost'; end if;
  -- Invalid patches still fail before receipt creation, even when stale.
  begin
    perform private.push_changes_for_user(account_id,'pomodoist','habit-icons',jsonb_build_array(op || jsonb_build_object(
      'opId','sign-invalid','payload','{"icon":42}'::jsonb,'clientUpdatedAt','2000-01-01T00:00:00Z')));
    raise exception 'Invalid stale icon accepted';
  exception when sqlstate '22023' then
    if sqlerrm <> 'Invalid habit icon' then raise; end if;
  end;
  if exists(select 1 from public.sync_operation_receipts where user_id=account_id and op_id='sign-invalid') then
    raise exception 'Invalid icon persisted an operation receipt';
  end if;
end;
$$;
select pass('habit icons validate Unicode length and retain field merge, legacy compatibility and explicit reset');
select * from finish();
rollback;

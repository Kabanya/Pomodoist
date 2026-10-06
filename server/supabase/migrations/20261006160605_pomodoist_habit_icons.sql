-- Deploy before clients with Drift schema 11. Legacy payloads retain their icon.
create or replace function private.validate_pomodoist_habit_payload(p_type text,p_id text,p_user_id uuid,p_data jsonb,p_partial boolean) returns void
language plpgsql set search_path = '' as $$
declare version jsonb; key text; weekdays jsonb; effective date; last_effective date; start_day date; end_day date; stamp text; quota record; quota_total numeric;
begin
  if p_type not in ('habit','habit_check_in') then return; end if;
  if p_id !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    or ((not p_partial or p_data ? 'id') and p_data->>'id' is distinct from p_id)
    or pg_catalog.jsonb_typeof(p_data) is distinct from 'object'
    or ((not p_partial or p_data ? 'userId') and (p_data->>'userId' not in ('local-user',p_user_id::text) or p_data->>'userId' is null))
    or ((not p_partial or p_data ? 'isDeleted') and (pg_catalog.jsonb_typeof(p_data->'isDeleted') is distinct from 'boolean' or p_data->>'isDeleted' <> 'false')) then
    raise exception using errcode='22023', message='Invalid habit identity';
  end if;
  for key in select pg_catalog.jsonb_object_keys(p_data) loop
    if not (key = any(case p_type when 'habit' then array['id','userId','title','icon','projectId','reminderMinutes','scheduleHistory','createdAt','updatedAt','isDeleted']
      else array['id','userId','habitId','day','createdAt','updatedAt','isDeleted','dayPeriod'] end)) then
      raise exception using errcode='22023', message='Invalid habit field';
    end if;
  end loop;
  foreach key in array array['createdAt','updatedAt'] loop
    if p_partial and not (p_data ? key) then continue; end if;
    stamp := p_data->>key;
    if pg_catalog.jsonb_typeof(p_data->key) is distinct from 'string' or stamp !~ '(Z|[+-][0-9]{2}:[0-9]{2})$' then
      raise exception using errcode='22023', message='Invalid habit timestamp';
    end if;
    begin perform stamp::timestamptz;
    exception when others then raise exception using errcode='22023', message='Invalid habit timestamp'; end;
  end loop;
  if p_type='habit' then
    if p_data ? 'icon' and p_data->'icon' <> 'null'::jsonb and (
      pg_catalog.jsonb_typeof(p_data->'icon') is distinct from 'string'
      or pg_catalog.btrim(p_data->>'icon') = ''
      or pg_catalog.char_length(p_data->>'icon') > 32
    ) then
      raise exception using errcode='22023', message='Invalid habit icon';
    end if;
    if (not p_partial or p_data ? 'title') and (pg_catalog.jsonb_typeof(p_data->'title') is distinct from 'string' or pg_catalog.btrim(p_data->>'title')=''
      or pg_catalog.char_length(p_data->>'title')>200) then
      raise exception using errcode='22023', message='Invalid habit title';
    end if;
    if p_data->'reminderMinutes' is not null and p_data->'reminderMinutes' <> 'null'::jsonb and
      (pg_catalog.jsonb_typeof(p_data->'reminderMinutes') <> 'number' or (p_data->>'reminderMinutes') !~ '^[0-9]+$'
        or (p_data->>'reminderMinutes')::numeric > 1439) then
      raise exception using errcode='22023', message='Invalid habit reminder';
    end if;
    if not p_partial or p_data ? 'scheduleHistory' then
    if pg_catalog.jsonb_typeof(p_data->'scheduleHistory') is distinct from 'array' or pg_catalog.jsonb_array_length(p_data->'scheduleHistory')=0 then
      raise exception using errcode='22023', message='Invalid habit schedule';
    end if;
    for version in select value from pg_catalog.jsonb_array_elements(p_data->'scheduleHistory') loop
      if pg_catalog.jsonb_typeof(version) is distinct from 'object' or exists(select 1 from pg_catalog.jsonb_object_keys(version) k where k not in ('effectiveFrom','startDate','endDate','weekdays','targetPerDay','dayPeriod','periodTargets')) then
        raise exception using errcode='22023', message='Invalid habit schedule';
      end if;
      effective:=private.pomodoist_habit_date(version->'effectiveFrom');
      start_day:=private.pomodoist_habit_date(version->'startDate');end_day:=null;
      if version->'endDate' is not null and version->'endDate' <> 'null'::jsonb then end_day:=private.pomodoist_habit_date(version->'endDate'); end if;
      if (last_effective is not null and effective<=last_effective) or (end_day is not null and end_day<start_day)
        or pg_catalog.jsonb_typeof(version->'targetPerDay') is distinct from 'number'
        or coalesce(version->>'targetPerDay','') !~ '^[0-9]+$' then
        raise exception using errcode='22023', message='Invalid habit schedule';
      end if;
      if (version->>'targetPerDay')::numeric not between 1 and 99 then
        raise exception using errcode='22023', message='Invalid habit schedule';
      end if;
      if version ? 'dayPeriod' and (
        pg_catalog.jsonb_typeof(version->'dayPeriod') is distinct from 'string'
        or version->>'dayPeriod' not in ('automatic','anytime','morning','afternoon','evening','night')) then
        raise exception using errcode='22023', message='Invalid habit day period';
      end if;
      if version ? 'periodTargets' then
        if pg_catalog.jsonb_typeof(version->'periodTargets') is distinct from 'object'
          or version->'periodTargets' = '{}'::jsonb
          or (version ? 'dayPeriod' and version->>'dayPeriod' <> 'automatic') then
          raise exception using errcode='22023', message='Invalid habit period targets';
        end if;
        quota_total := 0;
        for quota in select * from pg_catalog.jsonb_each(version->'periodTargets') loop
          if quota.key not in ('morning','afternoon','evening','night')
            or pg_catalog.jsonb_typeof(quota.value) is distinct from 'number'
            or (quota.value #>> '{}') !~ '^[0-9]+$' then
            raise exception using errcode='22023', message='Invalid habit period targets';
          end if;
          if (quota.value #>> '{}')::numeric not between 1 and 99 then
            raise exception using errcode='22023', message='Invalid habit period targets';
          end if;
          quota_total := quota_total + (quota.value #>> '{}')::numeric;
        end loop;
        if quota_total <> (version->>'targetPerDay')::numeric then
          raise exception using errcode='22023', message='Invalid habit period targets';
        end if;
      end if;
      last_effective:=effective;weekdays:=version->'weekdays';
      if pg_catalog.jsonb_typeof(weekdays) is distinct from 'array' then raise exception using errcode='22023', message='Invalid habit weekdays'; end if;
      if pg_catalog.jsonb_array_length(weekdays) not between 1 and 7
        or exists(select 1 from pg_catalog.jsonb_array_elements(weekdays) d where pg_catalog.jsonb_typeof(d)<>'number' or d::text !~ '^[1-7]$')
        or (select count(distinct d) from pg_catalog.jsonb_array_elements(weekdays) d) <> pg_catalog.jsonb_array_length(weekdays) then
        raise exception using errcode='22023', message='Invalid habit weekdays';
      end if;
    end loop;
    end if;
    if p_data->'projectId' is not null and p_data->'projectId' <> 'null'::jsonb and
      (pg_catalog.jsonb_typeof(p_data->'projectId')<>'string' or p_data->>'projectId'='') then
      raise exception using errcode='22023', message='Habit project must belong to the same account and be personal';
    end if;
  else
    if p_data ? 'dayPeriod' and (
      pg_catalog.jsonb_typeof(p_data->'dayPeriod') is distinct from 'string'
      or p_data->>'dayPeriod' not in ('anytime','morning','afternoon','evening','night')) then
      raise exception using errcode='22023', message='Invalid check-in day period';
    end if;
    if not p_partial or p_data ? 'day' then perform private.pomodoist_habit_date(p_data->'day'); end if;
    if (not p_partial or p_data ? 'habitId') and pg_catalog.jsonb_typeof(p_data->'habitId') is distinct from 'string' then
      raise exception using errcode='22023', message='Invalid check-in habit';
    end if;
  end if;
end;
$$;

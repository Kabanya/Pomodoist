begin;
\ir hosted-mode.inc

select plan(3);

select ok(
  has_table_privilege('service_role', 'public.user_app_installs', 'SELECT')
  and has_table_privilege('service_role', 'public.sync_entities', 'SELECT')
  and has_table_privilege('service_role', 'public.profiles', 'SELECT')
  and has_table_privilege('service_role', 'public.sync_operations', 'SELECT')
  and has_table_privilege('service_role', 'public.sync_devices', 'SELECT')
  and has_table_privilege('service_role', 'public.sync_devices', 'UPDATE')
  and has_table_privilege('service_role', 'public.user_entitlements', 'SELECT')
  and has_table_privilege('service_role', 'public.user_entitlements', 'INSERT')
  and has_table_privilege('service_role', 'public.user_entitlements', 'UPDATE'),
  'clean replay preserves the exact service-role table access used by live sync'
);

select ok(
  not has_table_privilege(
    'service_role',
    'public.user_app_installs',
    'INSERT'
  )
  and not has_table_privilege(
    'service_role',
    'public.user_app_installs',
    'UPDATE'
  )
  and not has_table_privilege(
    'service_role',
    'public.user_app_installs',
    'DELETE'
  )
  and not has_table_privilege('service_role', 'public.sync_entities', 'INSERT')
  and not has_table_privilege('service_role', 'public.sync_entities', 'UPDATE')
  and not has_table_privilege('service_role', 'public.sync_entities', 'DELETE')
  and not has_table_privilege('service_role', 'public.profiles', 'INSERT')
  and not has_table_privilege('service_role', 'public.profiles', 'UPDATE')
  and not has_table_privilege('service_role', 'public.profiles', 'DELETE')
  and not has_table_privilege('service_role', 'public.sync_operations', 'INSERT')
  and not has_table_privilege('service_role', 'public.sync_operations', 'UPDATE')
  and not has_table_privilege('service_role', 'public.sync_operations', 'DELETE')
  and not has_table_privilege('service_role', 'public.sync_devices', 'INSERT')
  and not has_table_privilege('service_role', 'public.sync_devices', 'DELETE')
  and not has_table_privilege('service_role', 'public.user_entitlements', 'DELETE'),
  'service-role replay repair grants no unused table mutation privileges'
);

select ok(
  not exists (
    select 1
    from information_schema.role_table_grants
    where grantee = 'pomodoist_mcp'
      and table_schema = 'public'
      and table_name in (
        'user_app_installs',
        'sync_entities',
        'profiles',
        'sync_operations',
        'sync_devices',
        'user_entitlements'
      )
  ),
  'the MCP token role has no account or sync table privilege'
);

select * from finish();
rollback;

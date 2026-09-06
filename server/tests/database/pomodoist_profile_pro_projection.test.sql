begin;
\ir hosted-mode.inc

select plan(14);

select has_column(
  'public',
  'profiles',
  'pomodoist_is_pro',
  'profiles exposes the stored Pomodoist Pro projection'
);

select ok(
  not has_column_privilege(
    'authenticated',
    'public.profiles',
    'pomodoist_is_pro',
    'UPDATE'
  )
  and has_column_privilege(
    'authenticated',
    'public.profiles',
    'display_name',
    'UPDATE'
  )
  and has_column_privilege(
    'authenticated',
    'public.profiles',
    'avatar_url',
    'UPDATE'
  ),
  'clients can edit profile presentation but cannot grant themselves Pro'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'private.reconcile_pomodoist_profile_pro()',
    'EXECUTE'
  ),
  'clients cannot run the privileged reconciliation function'
);

select ok(
  not has_function_privilege(
    'public',
    'public.get_account_overview()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.get_account_overview()',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.get_account_overview()',
    'EXECUTE'
  ),
  'account overview requires an authenticated session'
);

insert into auth.users (id, email, aud, role, created_at, updated_at)
values
  (
    '11111111-1111-4111-8111-111111111111',
    'profile-pro-a@example.com',
    'authenticated',
    'authenticated',
    now(),
    now()
  ),
  (
    '22222222-2222-4222-8222-222222222222',
    'profile-pro-b@example.com',
    'authenticated',
    'authenticated',
    now(),
    now()
  );

select is(
  (
    select pomodoist_is_pro
    from public.profiles
    where id = '11111111-1111-4111-8111-111111111111'
  ),
  false,
  'new profiles default to non-Pro'
);

insert into public.user_entitlements (
  user_id,
  app_id,
  entitlement_id,
  source,
  purchase_type,
  status,
  product_id,
  store,
  valid_from,
  valid_until
)
values (
  '11111111-1111-4111-8111-111111111111',
  'pomodoist',
  'appstore:test-subscription',
  'app_store',
  'subscription',
  'active',
  'pomodoist.pro.monthly',
  'app_store',
  now(),
  now() + interval '1 month'
);

select is(
  (
    select pomodoist_is_pro
    from public.profiles
    where id = '11111111-1111-4111-8111-111111111111'
  ),
  true,
  'an active App Store entitlement activates the profile immediately'
);

insert into public.user_entitlements (
  user_id,
  app_id,
  entitlement_id,
  source,
  purchase_type,
  status,
  product_id,
  store,
  valid_from
)
values (
  '11111111-1111-4111-8111-111111111111',
  'pomodoist',
  'stripe:test-lifetime',
  'stripe',
  'lifetime',
  'active',
  'pomodoist.pro.lifetime',
  'stripe',
  now()
);

update public.profiles
set pomodoist_is_pro = false
where id = '11111111-1111-4111-8111-111111111111';

select private.reconcile_pomodoist_profile_pro();

select is(
  (
    select pomodoist_is_pro
    from public.profiles
    where id = '11111111-1111-4111-8111-111111111111'
  ),
  true,
  'backfill reconciliation restores Pro for an existing active entitlement'
);

update public.user_entitlements
set status = 'expired',
    valid_until = now() - interval '1 second'
where entitlement_id = 'appstore:test-subscription';

select is(
  (
    select pomodoist_is_pro
    from public.profiles
    where id = '11111111-1111-4111-8111-111111111111'
  ),
  true,
  'expiring one source keeps Pro while another source is active'
);

update public.user_entitlements
set status = 'revoked',
    valid_until = now()
where entitlement_id = 'stripe:test-lifetime';

select is(
  (
    select pomodoist_is_pro
    from public.profiles
    where id = '11111111-1111-4111-8111-111111111111'
  ),
  false,
  'revoking the final active source removes Pro immediately'
);

update public.user_entitlements
set status = 'active',
    valid_until = null
where entitlement_id = 'stripe:test-lifetime';

delete from public.user_entitlements
where entitlement_id = 'stripe:test-lifetime';

select is(
  (
    select pomodoist_is_pro
    from public.profiles
    where id = '11111111-1111-4111-8111-111111111111'
  ),
  false,
  'deleting the final active source removes Pro immediately'
);

update public.profiles
set pomodoist_is_pro = true
where id = '22222222-2222-4222-8222-222222222222';

select private.reconcile_pomodoist_profile_pro();

select is(
  (
    select pomodoist_is_pro
    from public.profiles
    where id = '22222222-2222-4222-8222-222222222222'
  ),
  false,
  'daily reconciliation repairs a stale projection'
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '11111111-1111-4111-8111-111111111111',
  true
);

create temporary table profile_pro_overview on commit drop as
select public.get_account_overview() as value;

reset role;

select is(
  (
    select value #>> '{profile,pomodoistIsPro}'
    from profile_pro_overview
  ),
  'false',
  'account overview returns profile.pomodoistIsPro'
);

select is(
  (
    select schedule
    from cron.job
    where jobname = 'pomodoist-profile-pro-reconcile'
  ),
  '37 3 * * *',
  'daily reconciliation is scheduled for 03:37 UTC'
);

select is(
  (
    select command
    from cron.job
    where jobname = 'pomodoist-profile-pro-reconcile'
  ),
  'select private.reconcile_pomodoist_profile_pro();',
  'the cron job runs only the projection reconciliation'
);

select * from finish();
rollback;

begin;
\ir hosted-mode.inc

select plan(13);

select has_table('private', 'pomodoist_stripe_customers', 'Stripe customer table exists');
select has_table('private', 'pomodoist_stripe_claims', 'Stripe claim table exists');
select has_table('private', 'pomodoist_stripe_events', 'Stripe event table exists');

select ok(
  not has_table_privilege('anon', 'private.pomodoist_stripe_customers', 'SELECT')
  and not has_table_privilege('authenticated', 'private.pomodoist_stripe_claims', 'SELECT')
  and not has_table_privilege('authenticated', 'private.pomodoist_stripe_events', 'INSERT'),
  'Stripe ownership and webhook tables are not exposed to clients'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.pomodoist_stripe_checkout_context(uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.pomodoist_stripe_checkout_context(uuid)',
    'EXECUTE'
  )
  and has_function_privilege(
    'service_role',
    'public.record_pomodoist_stripe_event(text,text,timestamptz,text,text,uuid,text,text,text,timestamptz,timestamptz,boolean,jsonb)',
    'EXECUTE'
  ),
  'only the service role can use Stripe billing RPCs'
);

insert into auth.users (id, email, aud, role, created_at, updated_at)
values (
  '11111111-1111-4111-8111-111111111111',
  'stripe-policy-test@example.com',
  'authenticated',
  'authenticated',
  '2026-08-01 00:00:00+00',
  '2026-08-01 00:00:00+00'
);

select is(
  public.link_pomodoist_stripe_customer(
    '11111111-1111-4111-8111-111111111111',
    'cus_test'
  ),
  'cus_test',
  'the first Stripe customer is linked to the account'
);

select is(
  public.link_pomodoist_stripe_customer(
    '11111111-1111-4111-8111-111111111111',
    'cus_racing_request'
  ),
  'cus_test',
  'a racing customer creation keeps the original customer'
);

select is(
  public.pomodoist_stripe_checkout_context(
    '11111111-1111-4111-8111-111111111111'
  )->>'stripeCustomerId',
  'cus_test',
  'checkout context returns the private customer mapping'
);

select is(
  public.record_pomodoist_stripe_event(
    'evt_paid',
    'checkout.session.completed',
    '2026-08-01 12:00:00+00',
    'pi_test',
    'cus_test',
    '11111111-1111-4111-8111-111111111111',
    'pomodoist.pro.lifetime',
    'lifetime',
    'active',
    '2026-08-01 12:00:00+00',
    null,
    false,
    '{"paymentStatus":"paid"}'::jsonb
  )->>'applied',
  'true',
  'a paid Stripe event is applied atomically'
);

select is(
  (
    select source || ':' || status
    from public.user_entitlements
    where user_id = '11111111-1111-4111-8111-111111111111'
      and entitlement_id = 'stripe:pi_test'
  ),
  'stripe:active',
  'the Stripe event provisions the shared Pomodoist entitlement'
);

select is(
  public.record_pomodoist_stripe_event(
    'evt_paid',
    'checkout.session.completed',
    '2026-08-01 12:00:00+00',
    'pi_test',
    'cus_test',
    '11111111-1111-4111-8111-111111111111',
    'pomodoist.pro.lifetime',
    'lifetime',
    'active',
    '2026-08-01 12:00:00+00',
    null,
    false,
    '{}'::jsonb
  )->>'applied',
  'false',
  'webhook replay is idempotent'
);

select is(
  public.record_pomodoist_stripe_event(
    'evt_subscription_checkout',
    'checkout.session.completed',
    '2026-08-01 12:05:00+00',
    'sub_stale_intro',
    'cus_test',
    '11111111-1111-4111-8111-111111111111',
    'pomodoist.pro.monthly',
    'subscription',
    'active',
    '2026-08-01 12:00:00+00',
    '2026-09-01 12:00:00+00',
    false,
    '{"stripeStatus":"active"}'::jsonb
  )->>'applied',
  'true',
  'a subscription checkout creates the current claim'
);

select public.record_pomodoist_stripe_event(
  'evt_subscription_invoice_paid',
  'invoice.paid',
  '2026-08-01 12:00:00+00',
  'sub_stale_intro',
  'cus_test',
  '11111111-1111-4111-8111-111111111111',
  'pomodoist.pro.monthly',
  'subscription',
  'active',
  '2026-08-01 12:00:00+00',
  '2026-09-01 12:00:00+00',
  true,
  '{"stripeStatus":"active"}'::jsonb
);

select ok(
  public.pomodoist_stripe_checkout_context(
    '11111111-1111-4111-8111-111111111111'
  )->>'firstSubscriptionPaidAt' is not null,
  'a stale paid invoice still consumes the one-time intro discount'
);

select * from finish();
rollback;

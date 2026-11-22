-- Keep each qualifying payment. A claim's latest plan alone cannot distinguish
-- a trial from a payment or retain an annual purchase after a plan change.
create table private.pomodoist_custom_model_payments (
  store text not null check (store in ('app_store', 'stripe')),
  claim_id text not null,
  payment_id text not null,
  product_id text not null check (product_id in (
    'pomodoist.pro.monthly', 'pomodoist.pro.annual',
    'pomodoist.pro.lifetime', 'pomodoist.pro.lifetime.launch'
  )),
  valid_until timestamptz,
  revoked boolean not null,
  observed_at timestamptz not null,
  primary key (store, claim_id, payment_id),
  check (product_id <> 'pomodoist.pro.monthly' or valid_until is not null)
);
alter table private.pomodoist_custom_model_payments enable row level security;
revoke all on private.pomodoist_custom_model_payments from public, anon, authenticated;
grant select, insert, update on private.pomodoist_custom_model_payments to service_role;

create function private.record_custom_model_apple_payment(p public.pomodoist_purchase_claims)
returns void language sql security invoker set search_path = '' as $$
  -- Revocation notifications can omit pricing. Match an existing receipt
  -- by its verified transaction identifier before considering a new grant.
  update private.pomodoist_custom_model_payments
  set revoked = true, observed_at = p.latest_signed_at
  where store = 'app_store' and claim_id = p.original_transaction_id
    and payment_id = p.latest_transaction_id and p.revoked_at is not null
    and observed_at <= p.latest_signed_at;

  insert into private.pomodoist_custom_model_payments as payments
    (store, claim_id, payment_id, product_id, valid_until, revoked, observed_at)
  select 'app_store', p.original_transaction_id, p.latest_transaction_id, p.product_id,
    p.expires_at, p.revoked_at is not null or
      (p.product_id = 'pomodoist.pro.monthly' and p.raw_claims @> '{"isUpgraded":true}'),
    to_timestamp((p.raw_claims->>'signedDate')::double precision / 1000)
  where p.raw_claims->>'inAppOwnershipType' = 'PURCHASED'
    and (p.raw_claims->>'offerDiscountType') is distinct from 'FREE_TRIAL'
    and jsonb_typeof(p.raw_claims->'signedDate') = 'number'
    and jsonb_typeof(p.raw_claims->'price') = 'number'
    and (p.raw_claims->>'price')::numeric > 0
    and (p.product_id <> 'pomodoist.pro.monthly' or p.expires_at is not null)
  on conflict (store, claim_id, payment_id) do update
  set revoked = excluded.revoked, valid_until = excluded.valid_until,
      observed_at = excluded.observed_at
  where excluded.observed_at > payments.observed_at
    or (excluded.observed_at = payments.observed_at and excluded.revoked);
$$;

create function private.capture_custom_model_apple_payment() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
  perform private.record_custom_model_apple_payment(new);
  return new;
end;
$$;
-- The existing verified purchase RPC attempts an INSERT for every transaction,
-- even when it is too old to replace the original chain's current entitlement.
create trigger capture_custom_model_apple_payment
  before insert on public.pomodoist_purchase_claims
  for each row execute function private.capture_custom_model_apple_payment();
revoke all on function private.record_custom_model_apple_payment(public.pomodoist_purchase_claims),
  private.capture_custom_model_apple_payment() from public, anon, authenticated;
grant execute on function private.record_custom_model_apple_payment(public.pomodoist_purchase_claims),
  private.capture_custom_model_apple_payment() to service_role;
select private.record_custom_model_apple_payment(c) from public.pomodoist_purchase_claims c;

-- The Edge Function validates the invoice, actual charge and invoice line
-- before supplying this receipt. Ownership is resolved from the existing
-- claim on every read, including when a webhook and its replay arrive out of order.
create function public.record_pomodoist_custom_model_stripe_payment(
  p_subscription_id text, p_payment_id text, p_product_id text,
  p_valid_until timestamptz, p_refunded boolean
) returns void language sql security invoker set search_path = '' as $$
  insert into private.pomodoist_custom_model_payments as payments
    (store, claim_id, payment_id, product_id, valid_until, revoked, observed_at)
  values ('stripe', p_subscription_id, p_payment_id, p_product_id, p_valid_until, p_refunded, now())
  on conflict (store, claim_id, payment_id) do update
  set revoked = payments.revoked or excluded.revoked;
$$;
revoke all on function public.record_pomodoist_custom_model_stripe_payment(text,text,text,timestamptz,boolean)
  from public, anon, authenticated;
grant execute on function public.record_pomodoist_custom_model_stripe_payment(text,text,text,timestamptz,boolean)
  to service_role;

-- Preserve lifetime refunds if an older Checkout event is replayed with
-- the same one-second Stripe event timestamp as its refund.
create function private.record_custom_model_stripe_lifetime(c private.pomodoist_stripe_claims)
returns void language sql security invoker set search_path = '' as $$
  insert into private.pomodoist_custom_model_payments as payments
    (store, claim_id, payment_id, product_id, valid_until, revoked, observed_at)
  select 'stripe', c.stripe_object_id, c.stripe_object_id, c.product_id, null,
    c.status = 'revoked', c.latest_event_created_at
  where c.purchase_type = 'lifetime' and (c.status = 'revoked' or
    (c.status = 'active' and c.raw_payload->>'paymentStatus' = 'paid'
     and coalesce((c.raw_payload->>'amountTotal')::numeric, 1) > 0))
  on conflict (store, claim_id, payment_id) do update
  set revoked = payments.revoked or excluded.revoked;
$$;
create function private.capture_custom_model_stripe_lifetime() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
  perform private.record_custom_model_stripe_lifetime(new);
  return null;
end;
$$;
create trigger capture_custom_model_stripe_lifetime
  after insert or update on private.pomodoist_stripe_claims
  for each row when (new.purchase_type = 'lifetime')
  execute function private.capture_custom_model_stripe_lifetime();
revoke all on function private.record_custom_model_stripe_lifetime(private.pomodoist_stripe_claims),
  private.capture_custom_model_stripe_lifetime() from public, anon, authenticated;
grant execute on function private.record_custom_model_stripe_lifetime(private.pomodoist_stripe_claims),
  private.capture_custom_model_stripe_lifetime() to service_role;
select private.record_custom_model_stripe_lifetime(c) from private.pomodoist_stripe_claims c
  where c.purchase_type = 'lifetime';

create function private.pomodoist_custom_model_access() returns jsonb
language sql stable security definer set search_path = '' as $$
  with owned as (
    -- Apple signs the expiry and revocation of each individual payment.
    -- A fresh refund of an older transaction may be the chain's latest
    -- notification even while a different monthly payment is still valid.
    select p.product_id, p.valid_until
    from public.pomodoist_purchase_claims c
    join private.pomodoist_custom_model_payments p
      on p.store = 'app_store' and p.claim_id = c.original_transaction_id
    where c.linked_user_id = (select auth.uid()) and not p.revoked
    union all
    select p.product_id, case when c.status = 'active' and c.product_id = p.product_id
      then least(p.valid_until, c.valid_until) end
    from private.pomodoist_stripe_claims c
    join private.pomodoist_custom_model_payments p
      on p.store = 'stripe' and p.claim_id = c.stripe_object_id
    where c.user_id = (select auth.uid()) and not p.revoked
  )
  select jsonb_build_object(
    'permanent', coalesce(bool_or(product_id in ('pomodoist.pro.annual',
      'pomodoist.pro.lifetime', 'pomodoist.pro.lifetime.launch')), false),
    'validUntil', max(valid_until) filter
      (where product_id = 'pomodoist.pro.monthly' and valid_until > now())
  ) from owned;
$$;
create function api_v1.pomodoist_custom_model_access() returns jsonb
language sql stable security invoker set search_path = '' as $$
  select private.pomodoist_custom_model_access();
$$;
revoke all on function private.pomodoist_custom_model_access(),
  api_v1.pomodoist_custom_model_access() from public, anon, authenticated, service_role;
grant execute on function private.pomodoist_custom_model_access(),
  api_v1.pomodoist_custom_model_access() to authenticated;

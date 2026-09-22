-- One campaign across all subscription products and chains for an Apple customer.
create table private.pomodoist_subscription_offers (
  environment text not null check (environment in ('Production', 'Sandbox')),
  app_transaction_id text not null check (app_transaction_id ~ '^[0-9]{1,128}$'),
  campaign_id text not null check (campaign_id = 'return-2026-v1'),
  redeemed boolean not null default false,
  lease_until timestamptz,
  nonce uuid,
  product_id text,
  primary key (environment, app_transaction_id, campaign_id)
);
alter table private.pomodoist_subscription_offers enable row level security;
revoke all on private.pomodoist_subscription_offers from public, anon, authenticated;
grant select, insert, update on private.pomodoist_subscription_offers to service_role;

create function public.pomodoist_subscription_offer_state(
  p_environment text, p_app_transaction_id text, p_campaign_id text,
  p_original_transaction_ids text[], p_user_id uuid, p_redeemed boolean,
  p_product_id text, p_nonce uuid, p_timestamp bigint, p_signature_max_age_seconds integer
) returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  v_row private.pomodoist_subscription_offers%rowtype;
  v_now timestamptz := clock_timestamp();
begin
  if p_environment is null or p_environment not in ('Production', 'Sandbox')
    or p_app_transaction_id is null or p_app_transaction_id !~ '^[0-9]{1,128}$'
    or p_campaign_id is distinct from 'return-2026-v1'
    or coalesce(cardinality(p_original_transaction_ids), 0) not between 1 and 2000
    or p_redeemed is null
    or p_signature_max_age_seconds is null or p_signature_max_age_seconds not between 1 and 604800
    or (p_product_id is not null and (
      p_product_id not in ('pomodoist.pro.monthly', 'pomodoist.pro.annual')
      or p_nonce is null or p_timestamp is null
      or abs(extract(epoch from v_now) * 1000 - p_timestamp) > 60000
    )) then raise exception 'invalid_offer_state'; end if;

  insert into private.pomodoist_subscription_offers(environment, app_transaction_id, campaign_id)
  values (p_environment, p_app_transaction_id, p_campaign_id) on conflict do nothing;
  select * into v_row from private.pomodoist_subscription_offers
    where environment = p_environment and app_transaction_id = p_app_transaction_id
      and campaign_id = p_campaign_id for update;

  -- Redemption evidence is monotonic, including subsequent refunds/revocations.
  if p_redeemed then
    update private.pomodoist_subscription_offers set redeemed = true
      where environment = p_environment and app_transaction_id = p_app_transaction_id and campaign_id = p_campaign_id;
    v_row.redeemed := true;
  end if;
  if v_row.redeemed then return jsonb_build_object('code', 'already_redeemed'); end if;

  if p_user_id is not null and exists (
    select 1 from public.pomodoist_purchase_claims c where c.environment = p_environment
      and c.original_transaction_id = any(p_original_transaction_ids)
      and c.linked_user_id is not null and c.linked_user_id <> p_user_id
  ) then return jsonb_build_object('code', 'purchase_already_linked'); end if;

  -- Optional account auth can only restrict eligibility. Also exclude a linked
  -- account's current Stripe/lifetime entitlement for an accountless proof.
  if (p_user_id is not null and public.has_active_pomodoist_paid_entitlement(p_user_id))
    or exists (
      select 1 from public.pomodoist_purchase_claims c
      where c.environment = p_environment and c.original_transaction_id = any(p_original_transaction_ids)
        and c.linked_user_id is not null
        and public.has_active_pomodoist_paid_entitlement(c.linked_user_id)
    ) then return jsonb_build_object('code', 'not_eligible'); end if;

  if v_row.lease_until > v_now then
    return jsonb_build_object('code', 'offer_pending', 'retryAfter', to_char(v_row.lease_until at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'));
  end if;
  if p_product_id is not null then
    -- The operator must configure an Apple-confirmed V2 maximum lifetime.
    -- No cancellation unlock; add five minutes for clock skew/propagation.
    update private.pomodoist_subscription_offers
    set lease_until = to_timestamp(p_timestamp / 1000.0) + make_interval(secs => p_signature_max_age_seconds + 300),
        nonce = p_nonce, product_id = p_product_id
    where environment = p_environment and app_transaction_id = p_app_transaction_id and campaign_id = p_campaign_id;
  end if;
  return jsonb_build_object('code', 'eligible');
end;
$$;
revoke all on function public.pomodoist_subscription_offer_state(text,text,text,text[],uuid,boolean,text,uuid,bigint,integer) from public, anon, authenticated;
grant execute on function public.pomodoist_subscription_offer_state(text,text,text,text[],uuid,boolean,text,uuid,bigint,integer) to service_role;

-- Existing authenticated purchase ingestion and Apple notification ingestion both
-- write purchase_claims. Capture verified redemptions there without linking users.
create function private.capture_pomodoist_return_offer() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
  if new.environment in ('Production', 'Sandbox')
    and new.raw_claims ->> 'appTransactionId' ~ '^[0-9]{1,128}$'
    and new.raw_claims ->> 'offerIdentifier' in ('return_monthly_2026_v1', 'return_annual_2026_v1') then
    insert into private.pomodoist_subscription_offers(environment, app_transaction_id, campaign_id, redeemed)
    values(new.environment, new.raw_claims ->> 'appTransactionId', 'return-2026-v1', true)
    on conflict (environment, app_transaction_id, campaign_id) do update set redeemed = true;
  end if;
  return new;
end;
$$;
revoke all on function private.capture_pomodoist_return_offer() from public, anon, authenticated;
grant execute on function private.capture_pomodoist_return_offer() to service_role;
create trigger pomodoist_capture_return_offer after insert or update on public.pomodoist_purchase_claims
for each row execute function private.capture_pomodoist_return_offer();

-- Preserve any confirmed redemption recorded before this migration was installed.
insert into private.pomodoist_subscription_offers(environment, app_transaction_id, campaign_id, redeemed)
select distinct environment, raw_claims ->> 'appTransactionId', 'return-2026-v1', true
from public.pomodoist_purchase_claims
where environment in ('Production', 'Sandbox') and raw_claims ->> 'appTransactionId' ~ '^[0-9]{1,128}$'
  and raw_claims ->> 'offerIdentifier' in ('return_monthly_2026_v1', 'return_annual_2026_v1')
on conflict (environment, app_transaction_id, campaign_id) do update set redeemed = true;

-- Run only in the isolated fixture database created by subscription_offers_check.sh.
do $$
begin
  assert not has_table_privilege('anon', 'private.pomodoist_subscription_offers', 'SELECT');
  assert not has_table_privilege('authenticated', 'private.pomodoist_subscription_offers', 'UPDATE');
  assert not has_function_privilege('authenticated', 'public.pomodoist_subscription_offer_state(text,text,text,text[],uuid,boolean,text,uuid,bigint,integer)', 'EXECUTE');
  assert (select relrowsecurity from pg_class where oid = 'private.pomodoist_subscription_offers'::regclass);
end $$;
set role service_role;
do $$
declare v_result jsonb; v_before timestamptz; v_issued bigint;
-- 86400 is a local fixture value, not a claimed Apple V2 expiration.
begin
  v_result := public.pomodoist_subscription_offer_state('Sandbox','12345','return-2026-v1',array['100'],null,false,null,null,null,86400);
  assert v_result->>'code' = 'eligible';
  assert not (select redeemed from private.pomodoist_subscription_offers where app_transaction_id = '12345');
  v_result := public.pomodoist_subscription_offer_state('Sandbox','12345','return-2026-v1',array['100'],null,false,'pomodoist.pro.monthly',gen_random_uuid(),(extract(epoch from clock_timestamp())*1000)::bigint,86400);
  assert v_result->>'code' = 'eligible';
  select lease_until into v_before from private.pomodoist_subscription_offers where app_transaction_id = '12345';
  assert v_before > clock_timestamp() + make_interval(secs => 86400);
  v_result := public.pomodoist_subscription_offer_state('Sandbox','12345','return-2026-v1',array['100'],null,false,'pomodoist.pro.annual',gen_random_uuid(),(extract(epoch from clock_timestamp())*1000)::bigint,86400);
  assert v_result->>'code' = 'offer_pending';
  assert (v_result->>'retryAfter')::timestamptz = v_before;
  -- Merely checking again (including after a client cancellation) cannot release it.
  v_result := public.pomodoist_subscription_offer_state('Sandbox','12345','return-2026-v1',array['100'],null,false,null,null,null,86400);
  assert v_result->>'code' = 'offer_pending';
  assert not (select redeemed from private.pomodoist_subscription_offers where app_transaction_id = '12345');
  -- Failed transactions do not consume a campaign; an expired lease permits retry.
  update private.pomodoist_subscription_offers set lease_until = now() - interval '1 minute' where app_transaction_id = '12345';
  v_result := public.pomodoist_subscription_offer_state('Sandbox','12345','return-2026-v1',array['100'],null,false,'pomodoist.pro.annual',gen_random_uuid(),(extract(epoch from clock_timestamp())*1000)::bigint,86400);
  assert v_result->>'code' = 'eligible';
  -- Confirmed Apple notification/purchase record consumes the group, even if revoked later.
  insert into public.pomodoist_purchase_claims values('100','Sandbox',null,'{"appTransactionId":"12345","offerIdentifier":"return_annual_2026_v1"}');
  v_result := public.pomodoist_subscription_offer_state('Sandbox','12345','return-2026-v1',array['100'],null,false,null,null,null,86400);
  assert v_result->>'code' = 'already_redeemed';
  update public.pomodoist_purchase_claims set raw_claims = '{}' where original_transaction_id = '100';
  assert (select redeemed from private.pomodoist_subscription_offers where app_transaction_id = '12345');
  v_result := public.pomodoist_subscription_offer_state('Production','12345','return-2026-v1',array['100'],null,false,null,null,null,86400);
  assert v_result->>'code' = 'eligible';
  -- History redemption survives even without a notification.
  v_result := public.pomodoist_subscription_offer_state('Production','12345','return-2026-v1',array['100'],null,true,null,null,null,86400);
  assert v_result->>'code' = 'already_redeemed';
end $$;
reset role;
insert into public.user_entitlements values('11111111-1111-4111-8111-111111111111',true);
insert into public.pomodoist_purchase_claims values('200','Sandbox','11111111-1111-4111-8111-111111111111','{}');
set role service_role;
do $$
begin
  assert public.pomodoist_subscription_offer_state('Sandbox','444','return-2026-v1',array['200'],null,false,null,null,null,86400)->>'code' = 'not_eligible';
  assert public.pomodoist_subscription_offer_state('Sandbox','444','return-2026-v1',array['200'],'22222222-2222-4222-8222-222222222222',false,null,null,null,86400)->>'code' = 'purchase_already_linked';
end $$;
reset role;

-- The database independently rejects absent or invalid bounds, even for service calls.
set role service_role;
do $$
declare v_bound integer; v_issued bigint;
begin
  foreach v_bound in array array[null, 0, -1, 604801] loop
    begin
      perform public.pomodoist_subscription_offer_state('Sandbox','777','return-2026-v1',array['100'],null,false,null,null,null,v_bound);
      raise exception 'unexpected_valid_bound';
    exception when raise_exception then
      assert sqlerrm = 'invalid_offer_state';
    end;
  end loop;
  v_issued := (extract(epoch from clock_timestamp())*1000)::bigint;
  perform public.pomodoist_subscription_offer_state('Sandbox','777','return-2026-v1',array['100'],null,false,'pomodoist.pro.monthly',gen_random_uuid(),v_issued,3600);
  assert (select lease_until from private.pomodoist_subscription_offers where app_transaction_id = '777')
    = to_timestamp(v_issued / 1000.0) + make_interval(secs => 3900);
end $$;
reset role;

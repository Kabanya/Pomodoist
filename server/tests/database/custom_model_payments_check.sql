-- Run on a disposable database with the custom-model migration installed.
\set ON_ERROR_STOP on
begin;
insert into auth.users(id,email,aud,role,created_at,updated_at) values
  ('33000000-0000-4000-8000-000000000001','custom-model-test@example.com','authenticated','authenticated',now(),now());
select set_config('request.jwt.claim.sub', '33000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claims','{"sub":"33000000-0000-4000-8000-000000000001"}',true);
select public.link_pomodoist_stripe_customer(auth.uid(), 'cus_model');
select public.record_pomodoist_stripe_event('evt_trial', 'invoice.paid', now(), 'sub_model', 'cus_model',
  auth.uid(), 'pomodoist.pro.monthly', 'subscription','active',now(),now()+interval '1 month',false,'{}');
create function pg_temp.check_model(expected_permanent boolean, expected_monthly boolean) returns void
language plpgsql as $$
declare result jsonb := api_v1.pomodoist_custom_model_access();
begin
  if not (result @> jsonb_build_object('permanent',expected_permanent))
     or ((result->>'validUntil') is not null) <> expected_monthly then
    raise exception 'Unexpected custom model grant %', result;
  end if;
end;
$$;
select pg_temp.check_model(false, false);
select public.record_pomodoist_custom_model_stripe_payment('sub_model','invoice-payment-1','pomodoist.pro.monthly',now()+interval '1 month',false);
select pg_temp.check_model(false, true);
select public.record_pomodoist_custom_model_stripe_payment('sub_model','invoice-payment-2','pomodoist.pro.annual',now()-interval '2 years',false);
select pg_temp.check_model(true, true);
select public.record_pomodoist_custom_model_stripe_payment('sub_model','invoice-payment-2','pomodoist.pro.annual',now()-interval '2 years',true);
select public.record_pomodoist_custom_model_stripe_payment('sub_model','invoice-payment-2','pomodoist.pro.annual',now()-interval '2 years',false);
select pg_temp.check_model(false, true);
select public.record_pomodoist_custom_model_stripe_payment('sub_model','invoice-payment-1','pomodoist.pro.monthly',now()+interval '1 month',true);
select pg_temp.check_model(false, false);
-- A duplicate paid event with the same timestamp cannot undo a full refund.
select public.record_pomodoist_stripe_event('evt_lifetime', 'checkout.session.completed', now(), 'pi_model', 'cus_model',
  auth.uid(), 'pomodoist.pro.lifetime.launch', 'lifetime','active',now(),null,false,'{"paymentStatus":"paid","amountTotal":8999}');
select pg_temp.check_model(true, false);
select public.record_pomodoist_stripe_event('evt_refund', 'charge.refunded', now(), 'pi_model', 'cus_model',
  auth.uid(), 'pomodoist.pro.lifetime.launch', 'lifetime','revoked',null,now(),false,'{}');
select public.record_pomodoist_stripe_event('evt_lifetime_delayed', 'checkout.session.async_payment_succeeded', now(), 'pi_model', 'cus_model',
  auth.uid(), 'pomodoist.pro.lifetime.launch', 'lifetime','active',now(),null,false,'{"paymentStatus":"paid","amountTotal":8999}');
select pg_temp.check_model(false, false);
create function pg_temp.apple(tx text, sku text, price integer, signed_at timestamptz, revoked boolean default false) returns void
language sql as $$
  select public.record_pomodoist_purchase('original-model',tx,sku,'Production','subscription',now()-interval '3 years',
    now()-interval '2 years',case when revoked then signed_at end,null,signed_at,
    jsonb_build_object('price',price,'signedDate',floor(extract(epoch from signed_at)*1000),
      'inAppOwnershipType','PURCHASED'),auth.uid());
$$;
select pg_temp.apple('annual-trial','pomodoist.pro.annual',0,now()-interval '1 year');
select pg_temp.check_model(false, false);
-- An older annual payment arrives after the newer trial snapshot.
select pg_temp.apple('annual-paid','pomodoist.pro.annual',29990,now()-interval '2 years');
select pg_temp.check_model(true, false);
select pg_temp.apple('annual-paid-2','pomodoist.pro.annual',29990,now()-interval '13 months');
select pg_temp.apple('annual-paid','pomodoist.pro.annual',null,now()-interval '1 day',true);
select pg_temp.check_model(true, false);
select pg_temp.apple('annual-paid-2','pomodoist.pro.annual',29990,now()-interval '1 day',true);
select pg_temp.apple('annual-paid-2','pomodoist.pro.annual',29990,now()-interval '13 months');
select pg_temp.check_model(false, false);
select public.record_pomodoist_purchase('original-model','active-monthly','pomodoist.pro.monthly','Production','subscription',
  now()-interval '1 day',now()+interval '29 days',null,null,now(),
  jsonb_build_object('price',4990,'signedDate',floor(extract(epoch from now())*1000),'inAppOwnershipType','PURCHASED'),auth.uid());
select pg_temp.apple('annual-paid-2','pomodoist.pro.annual',29990,now()+interval '1 second',true);
select pg_temp.check_model(false, true);
select pg_temp.apple('annual-paid-3','pomodoist.pro.annual',29990,now());
set local role authenticated;
select pg_temp.check_model(true, true);
select set_config('request.jwt.claim.sub', '33000000-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claims','{"sub":"33000000-0000-4000-8000-000000000002"}',true);
select pg_temp.check_model(false, false);
do $$ begin
  if has_function_privilege('authenticated','public.record_pomodoist_custom_model_stripe_payment(text,text,text,timestamptz,boolean)','execute')
    or has_function_privilege('anon','api_v1.pomodoist_custom_model_access()','execute')
    or has_table_privilege('authenticated','private.pomodoist_custom_model_payments','select') then
    raise exception 'Invalid custom model receipt permissions';
  end if;
end $$;
rollback;

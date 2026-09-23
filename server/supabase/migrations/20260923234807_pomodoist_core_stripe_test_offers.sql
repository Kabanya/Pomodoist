-- Test offer Checkout serialization, shared by all products for an account.
-- Only the service role can reserve/release; clients never supply these values.
create table private.pomodoist_stripe_checkouts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  reservation_id uuid not null default gen_random_uuid(),
  input jsonb not null check (jsonb_typeof(input) = 'object'),
  expires_at timestamptz not null default (now() + interval '40 minutes')
);
alter table private.pomodoist_stripe_checkouts enable row level security;
revoke all on private.pomodoist_stripe_checkouts from public, anon, authenticated;
grant select, insert, delete on private.pomodoist_stripe_checkouts to service_role;

create function public.reserve_pomodoist_stripe_checkout(p_user_id uuid, p_input jsonb)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare v_row private.pomodoist_stripe_checkouts;
begin
  -- The unique user key serializes monthly/yearly/lifetime attempts together.
  insert into private.pomodoist_stripe_checkouts(user_id, input)
  values (p_user_id, p_input) on conflict (user_id) do nothing;
  select * into strict v_row from private.pomodoist_stripe_checkouts
    where user_id = p_user_id;
  return jsonb_build_object('id', v_row.reservation_id, 'input', v_row.input,
    'expiresAt', extract(epoch from v_row.expires_at)::bigint);
end;
$$;

-- A wall-clock timeout alone must never release a completed/processing payment.
-- Caller first verifies the old session and fresh Stripe history.
create function public.release_pomodoist_stripe_checkout(p_user_id uuid, p_reservation_id uuid)
returns void language sql security invoker set search_path = '' as $$
  delete from private.pomodoist_stripe_checkouts
    where user_id = p_user_id and reservation_id = p_reservation_id;
$$;
revoke all on function public.reserve_pomodoist_stripe_checkout(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.release_pomodoist_stripe_checkout(uuid, uuid) from public, anon, authenticated;
grant execute on function public.reserve_pomodoist_stripe_checkout(uuid, jsonb) to service_role;
grant execute on function public.release_pomodoist_stripe_checkout(uuid, uuid) to service_role;

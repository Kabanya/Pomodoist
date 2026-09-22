-- Switch a linked Telegram identity to a fresh guest without moving or deleting
-- data from the Pomodoist account it was linked to.
begin;
set local role postgres;

create function public.unlink_pomodoist_telegram(
  p_telegram_user_id bigint,
  p_expected_user_id uuid,
  p_guest_user_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_account public.pomodoist_telegram_accounts%rowtype;
  v_now timestamptz := pg_catalog.timezone('utc', pg_catalog.now());
begin
  if p_telegram_user_id <= 0
    or p_expected_user_id is null
    or p_guest_user_id is null
    or p_expected_user_id = p_guest_user_id
    or not exists (
      select 1 from public.profiles where id = p_guest_user_id
    )
  then
    raise exception using errcode = '22023', message = 'Invalid Telegram unlink';
  end if;

  select * into v_account
  from public.pomodoist_telegram_accounts
  where telegram_user_id = p_telegram_user_id
  for update;

  if not found
    or v_account.user_id is distinct from p_expected_user_id
    or v_account.linked_at is null
  then
    raise exception using errcode = '40001', message = 'Telegram mapping changed';
  end if;

  update public.pomodoist_telegram_accounts
  set user_id = p_guest_user_id,
      guest_user_id = p_guest_user_id,
      linked_at = null,
      updated_at = v_now
  where telegram_user_id = p_telegram_user_id;

  delete from public.pomodoist_telegram_link_attempts
  where telegram_user_id = p_telegram_user_id;

  return pg_catalog.jsonb_build_object(
    'telegramUserId', v_account.telegram_user_id::text,
    'userId', p_guest_user_id::text,
    'guestUserId', p_guest_user_id::text,
    'clientId', v_account.client_id::text,
    'linked', false
  );
end;
$$;

revoke all on function public.unlink_pomodoist_telegram(bigint,uuid,uuid)
from public, anon, authenticated, pomodoist_mcp;
grant execute on function public.unlink_pomodoist_telegram(bigint,uuid,uuid)
to service_role;

notify pgrst, 'reload schema';
commit;

#!/usr/bin/env bash
# Disposable database only; never applies a migration to the application DB.
set -euo pipefail
container=${1:?Usage: stripe_offers_check.sh pomodoist-selfhost-<local-test-container>}
case "$container" in pomodoist-selfhost-*) ;; *) echo 'Expected an explicit local test container.' >&2; exit 1;; esac
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
test_db="stripe_offer_check_$$"
result_dir=$(mktemp -d "${TMPDIR:-/tmp}/pomodoist-stripe-check.XXXXXX")
cleanup() { docker exec "$container" dropdb -U postgres --if-exists "$test_db" >/dev/null; rm -rf "$result_dir"; }
trap cleanup EXIT
docker exec "$container" createdb -U postgres "$test_db"
sql() { docker exec -i "$container" psql -X -q -U postgres -d "$test_db" -v ON_ERROR_STOP=1 "$@"; }
sql <<'SQL'
create schema private;
create schema auth;
grant usage on schema private to service_role;
create table auth.users(id uuid primary key);
insert into auth.users values ('00000000-0000-4000-8000-000000000001');
SQL
sql < "$script_dir/../../supabase/migrations/20260923234807_pomodoist_core_stripe_test_offers.sql"
sql <<'SQL'
do $$ begin
  if has_function_privilege('anon','public.reserve_pomodoist_stripe_checkout(uuid,jsonb)','execute')
    or has_function_privilege('authenticated','public.release_pomodoist_stripe_checkout(uuid,uuid)','execute')
    or has_table_privilege('authenticated','private.pomodoist_stripe_checkouts','select') then
    raise exception 'Checkout reservation exposed to a client role';
  end if;
end $$;
SQL
# Two product requests race on one account. Both must receive the same record.
sql -At <<'SQL' > "$result_dir/first" &
begin;
set local role service_role;
select public.reserve_pomodoist_stripe_checkout('00000000-0000-4000-8000-000000000001','{"productId":"monthly"}')->>'id';
select pg_sleep(1);
commit;
SQL
first_pid=$!
sql -At <<'SQL' > "$result_dir/second" &
set role service_role;
select public.reserve_pomodoist_stripe_checkout('00000000-0000-4000-8000-000000000001','{"productId":"annual"}')->>'id';
SQL
second_pid=$!
wait "$first_pid"
wait "$second_pid"
python3 - "$result_dir" <<'PY'
import pathlib, sys
values = [[line for line in (pathlib.Path(sys.argv[1])/name).read_text().splitlines() if line] for name in ('first','second')]
assert len(values[0]) == len(values[1]) == 1 and values[0] == values[1], values
PY
sql <<'SQL'
set role service_role;
do $$ declare old_id uuid; new_id uuid; begin
  select reservation_id into old_id from private.pomodoist_stripe_checkouts;
  perform public.release_pomodoist_stripe_checkout('00000000-0000-4000-8000-000000000001',gen_random_uuid());
  if not exists(select 1 from private.pomodoist_stripe_checkouts) then raise exception 'Stale release deleted a reservation'; end if;
  perform public.release_pomodoist_stripe_checkout('00000000-0000-4000-8000-000000000001',old_id);
  select (public.reserve_pomodoist_stripe_checkout('00000000-0000-4000-8000-000000000001','{"productId":"annual"}')->>'id')::uuid into new_id;
  if old_id = new_id then raise exception 'Canceled checkout was reused'; end if;
  perform public.release_pomodoist_stripe_checkout('00000000-0000-4000-8000-000000000001',old_id);
  if not exists(select 1 from private.pomodoist_stripe_checkouts where reservation_id = new_id) then raise exception 'Old release deleted new checkout'; end if;
end $$;
SQL
printf 'Stripe SQL ACL, cross-product concurrency and cancellation checks passed.\n'

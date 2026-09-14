#!/usr/bin/env bash
# Isolated SQL/concurrency check. Requires an existing local Supabase Postgres container.
set -euo pipefail
container=${1:?Usage: subscription_offers_check.sh pomodoist-selfhost-<local-test-container>}
case "$container" in pomodoist-selfhost-*) ;; *) echo 'Expected an explicit local test container.' >&2; exit 1;; esac
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
test_db="offer_check_$$"
result_dir=$(mktemp -d "${TMPDIR:-/tmp}/pomodoist-offer-check.XXXXXX")
cleanup() { docker exec "$container" dropdb -U postgres --if-exists "$test_db" >/dev/null; rm -rf "$result_dir"; }
trap cleanup EXIT
docker exec "$container" createdb -U postgres "$test_db"
sql() { docker exec -i "$container" psql -X -q -U postgres -d "$test_db" -v ON_ERROR_STOP=1 "$@"; }
# Minimal dependency fixture: unrelated Auth/Realtime schema is deliberately absent.
sql <<'SQL'
create schema private;
grant usage on schema private to service_role;
create table public.pomodoist_purchase_claims (
  original_transaction_id text primary key, environment text, linked_user_id uuid, raw_claims jsonb
);
create table public.user_entitlements (user_id uuid, active boolean);
create function public.has_active_pomodoist_paid_entitlement(p_user_id uuid) returns boolean language sql as $$
 select exists(select 1 from public.user_entitlements where user_id = p_user_id and active);
$$;
grant select, insert, update on public.pomodoist_purchase_claims to service_role;
grant select on public.user_entitlements to service_role;
SQL
sql < "$script_dir/../../supabase/migrations/20260913203151_pomodoist_subscription_offers.sql"
sql < "$script_dir/subscription_offers_check.inc"
# Hold the first row lock while a second SKU attempts issuance. Exactly one wins.
sql -At <<'SQL' > "$result_dir/first" &
begin;
set local role service_role;
select public.pomodoist_subscription_offer_state('Production','80001','return-2026-v1',array['100'],null,false,'pomodoist.pro.monthly',gen_random_uuid(),(extract(epoch from clock_timestamp())*1000)::bigint,86400)->>'code';
select pg_sleep(1);
commit;
SQL
first_pid=$!
sql -At <<'SQL' > "$result_dir/second" &
set role service_role;
select public.pomodoist_subscription_offer_state('Production','80001','return-2026-v1',array['100'],null,false,'pomodoist.pro.annual',gen_random_uuid(),(extract(epoch from clock_timestamp())*1000)::bigint,86400)->>'code';
SQL
second_pid=$!
wait "$first_pid"
wait "$second_pid"
python3 - "$result_dir" <<'PY'
import pathlib, sys
paths = [pathlib.Path(sys.argv[1], name) for name in ('first', 'second')]
values = [line.strip() for path in paths for line in path.read_text().splitlines() if line.strip()]
for path in paths: path.unlink()
assert sorted(values) == ['eligible', 'offer_pending'], values
print('SQL checks and concurrent cross-SKU reservation passed.')
PY

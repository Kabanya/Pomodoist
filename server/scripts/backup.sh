#!/bin/sh
set -eu

server_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
backup_dir=${1:-"$server_dir/backups"}
umask 077
mkdir -p "$backup_dir"
backup_file="$backup_dir/pomodoist-$(date -u +%Y%m%dT%H%M%SZ).tar.gz"
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/pomodoist-backup.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM

LC_ALL=C
source_ledger="$work_dir/source-migrations"
for migration in "$server_dir"/supabase/migrations/*.sql; do
  [ -f "$migration" ] || continue
  checksum=$(openssl dgst -sha256 "$migration" | awk '{print $NF}')
  printf '%s|%s\n' "$(basename "$migration" .sql)" "$checksum"
done > "$source_ledger"
[ -s "$source_ledger" ] || { echo "No migrations found" >&2; exit 1; }
docker compose --project-directory "$server_dir" --env-file "$server_dir/.env" \
  -f "$server_dir/compose.yaml" exec -T db psql -X -U postgres -d postgres \
  -AtF '|' -c 'select version, checksum from pomodoist_meta.schema_migrations order by version' \
  > "$work_dir/installed-migrations"
cmp -s "$source_ledger" "$work_dir/installed-migrations" || {
  echo "Database migration ledger does not match the checked-in migrations" >&2
  exit 1
}
release_fingerprint=$(
  { cat "$source_ledger"; cat "$server_dir/compose.yaml"; } |
    openssl dgst -sha256 | awk '{print $NF}'
)

printf '%s%s\n' '-- pomodoist-release-fingerprint: ' "$release_fingerprint" \
  > "$work_dir/database.sql"
docker compose --project-directory "$server_dir" --env-file "$server_dir/.env" \
  -f "$server_dir/compose.yaml" exec -T db \
  pg_dump -U supabase_admin --data-only --disable-triggers \
    --schema=auth --schema=public --schema=private --schema=billing \
    --schema=pomodoist_meta --schema=vault postgres \
  >> "$work_dir/database.sql"
docker compose --project-directory "$server_dir" --env-file "$server_dir/.env" \
  -f "$server_dir/compose.yaml" cp \
  db:/etc/postgresql-custom/pgsodium_root.key "$work_dir/pgsodium_root.key" >/dev/null
tar -C "$work_dir" -czf "$backup_file" database.sql pgsodium_root.key

tar -tzf "$backup_file" >/dev/null
tar -tvzf "$backup_file" | awk '
  substr($1, 1, 1) != "-" { invalid = 1 }
  END { exit(invalid || NR != 2) }
'
echo "$backup_file"

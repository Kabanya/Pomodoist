#!/bin/sh
set -eu

server_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
backup_file=${1:-}
confirmation=${2:-}

if [ ! -f "$backup_file" ] || [ "$confirmation" != "--replace-current-database" ]; then
  echo "Usage: make restore BACKUP=/absolute/path/to/backup.tar.gz CONFIRM=--replace-current-database" >&2
  exit 2
fi

compose() {
  docker compose --project-directory "$server_dir" --env-file "$server_dir/.env" -f "$server_dir/compose.yaml" "$@"
}

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/pomodoist-restore.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
members=$(tar -tzf "$backup_file")
[ "$members" = "database.sql
pgsodium_root.key" ] || {
  echo "Backup must contain only database.sql and pgsodium_root.key" >&2
  exit 1
}
tar -tvzf "$backup_file" | awk '
  substr($1, 1, 1) != "-" { invalid = 1 }
  END { exit(invalid || NR != 2) }
' || {
  echo "Backup members must be regular files" >&2
  exit 1
}
tar -C "$work_dir" -xzf "$backup_file"
if [ "$(wc -c < "$work_dir/pgsodium_root.key" | tr -d ' ')" != 64 ] ||
  ! grep -Eq '^[0-9a-f]{64}$' "$work_dir/pgsodium_root.key"; then
  echo "Backup contains an invalid Vault root key" >&2
  exit 1
fi

LC_ALL=C
source_ledger="$work_dir/source-migrations"
for migration in "$server_dir"/supabase/migrations/*.sql; do
  [ -f "$migration" ] || continue
  checksum=$(openssl dgst -sha256 "$migration" | awk '{print $NF}')
  printf '%s|%s\n' "$(basename "$migration" .sql)" "$checksum"
done > "$source_ledger"
[ -s "$source_ledger" ] || { echo "No migrations found" >&2; exit 1; }
compose exec -T db psql -X -U postgres -d postgres -AtF '|' \
  -c 'select version, checksum from pomodoist_meta.schema_migrations order by version' \
  > "$work_dir/installed-migrations"
cmp -s "$source_ledger" "$work_dir/installed-migrations" || {
  echo "Current database migration ledger does not match this server release" >&2
  exit 1
}
current_fingerprint=$(
  { cat "$source_ledger"; cat "$server_dir/compose.yaml"; } |
    openssl dgst -sha256 | awk '{print $NF}'
)
backup_fingerprint=$(sed -n 's/^-- pomodoist-release-fingerprint: //p' \
  "$work_dir/database.sql" | head -1)
if [ -z "$backup_fingerprint" ] || \
  [ "$backup_fingerprint" != "$current_fingerprint" ]; then
  echo "Backup release fingerprint does not match this Pomodoist server release" >&2
  exit 1
fi

web_was_running=false
if compose ps --status running --services | grep -qx web; then
  web_was_running=true
fi

compose stop web functions gateway realtime rest auth
compose cp db:/etc/postgresql-custom/pgsodium_root.key \
  "$work_dir/current_pgsodium_root.key" >/dev/null 2>&1
[ "$(wc -c < "$work_dir/current_pgsodium_root.key" | tr -d ' ')" = 64 ] &&
  grep -Eq '^[0-9a-f]{64}$' "$work_dir/current_pgsodium_root.key" || {
  echo "Current Vault root key is invalid; restore was not started" >&2
  exit 1
}
compose exec -T db sh -c 'umask 077; cat > /etc/postgresql-custom/pgsodium_root.key' \
  < "$work_dir/pgsodium_root.key"
compose restart db
compose up -d --wait db
if {
  cat <<'SQL'
do $$
declare
  tables text;
begin
  select string_agg(format('%I.%I', n.nspname, c.relname), ', ')
  into tables
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where c.relkind in ('r', 'p')
    and not c.relispartition
    and (
      n.nspname in ('auth', 'public', 'private', 'billing', 'pomodoist_meta')
      or (n.nspname = 'vault' and c.relname = 'secrets')
    );
  if tables is not null then
    execute 'truncate table ' || tables || ' restart identity cascade';
  end if;
end;
$$;
SQL
  cat "$work_dir/database.sql"
} | compose exec -T db psql --quiet --single-transaction \
  -v ON_ERROR_STOP=1 -U supabase_admin -d postgres; then
  :
else
  compose exec -T db sh -c \
    'umask 077; cat > /etc/postgresql-custom/pgsodium_root.key' \
    < "$work_dir/current_pgsodium_root.key"
  compose restart db
  compose up -d --wait db
  echo "Restore failed; the previous database and Vault key were retained" >&2
  exit 1
fi
compose up -d --wait db auth realtime migrate rest gateway functions
if [ "$web_was_running" = true ]; then
  compose up -d --wait web
fi
echo "Restored $backup_file"

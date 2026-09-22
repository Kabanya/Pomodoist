#!/bin/sh
set -eu

psql_base="psql -v ON_ERROR_STOP=1 -h ${PGHOST:-db} -U postgres -d postgres"
root=/opt/pomodoist
baseline=20260922162731_pomodoist_initial
$psql_base <<'SQL'
create schema if not exists pomodoist_meta;
revoke all on schema pomodoist_meta from public, anon, authenticated;
create table if not exists pomodoist_meta.schema_migrations (
  version text primary key,
  checksum text not null,
  applied_at timestamptz not null default now()
);
revoke all on pomodoist_meta.schema_migrations from public, anon, authenticated;
SQL

# Refuse unknown versions and edited applied files before executing any migration.
installed=$($psql_base -AtF '|' -c 'select version,checksum from pomodoist_meta.schema_migrations order by version')
printf '%s\n' "$installed" | while IFS='|' read -r version checksum; do
  [ -n "$version" ] || continue
  case "$version" in *[!a-zA-Z0-9_]*) echo 'Invalid migration version' >&2; exit 1;; esac
  source="$root/migrations/$version.sql"
  [ -f "$source" ] || source="$root/legacy/$version.sql"
  [ -f "$source" ] || { echo "Unknown applied migration: $version" >&2; exit 1; }
  expected=$(sha256sum "$source" | awk '{print $1}')
  [ "$checksum" = "$expected" ] || { echo "Applied migration changed: $version" >&2; exit 1; }
done

apply_directory() {
  found=false
  for migration in "$1"/*.sql; do
    [ -f "$migration" ] || continue
    found=true
    version=$(basename "$migration" .sql)
    checksum=$(sha256sum "$migration" | awk '{print $1}')
    applied=$($psql_base -Atc "select checksum from pomodoist_meta.schema_migrations where version = '$version'")
    if [ -n "$applied" ]; then
      [ "$applied" = "$checksum" ] || { echo "Applied migration changed: $version" >&2; exit 1; }
      continue
    fi
    echo "Applying $version"
    record="insert into pomodoist_meta.schema_migrations(version,checksum) values ('$version','$checksum')"
    if [ "$1" = "$root/migrations" ]; then
      # Active files have no transaction boundaries: SQL and receipt commit together.
      $psql_base --single-transaction -f "$migration" -c "$record"
    else
      # Immutable legacy files retain their original transaction boundaries.
      $psql_base -f "$migration"
      $psql_base -c "$record" >/dev/null
    fi
  done
  $found || { echo "No SQL migrations found in $1" >&2; exit 1; }
}

adopted=$($psql_base -Atc "select count(*) from pomodoist_meta.schema_migrations where version='$baseline'")
if [ -n "$installed" ] && [ "$adopted" = 0 ]; then
  # Existing independent servers finish their own immutable legacy chain. This
  # runner is never used to upgrade the hosted production database.
  apply_directory "$root/legacy"
  actual=$($psql_base -Atf "$root/application-fingerprint.sql")
  expected=$(cat "$root/legacy/schema.md5")
  [ "$actual" = "$expected" ] || { echo 'Legacy schema differs from the verified baseline; adoption refused.' >&2; exit 1; }
  checksum=$(sha256sum "$root/migrations/$baseline.sql" | awk '{print $1}')
  # Update only bookkeeping, atomically. Existing tables and user rows stay put.
  {
    echo 'begin; lock table pomodoist_meta.schema_migrations in access exclusive mode;'
    for migration in "$root/legacy"/*.sql; do
      version=$(basename "$migration" .sql)
      printf "delete from pomodoist_meta.schema_migrations where version='%s';\n" "$version"
    done
    printf "insert into pomodoist_meta.schema_migrations(version,checksum) values ('%s','%s');\n" "$baseline" "$checksum"
    echo 'commit;'
  } | $psql_base >/dev/null
  echo "Adopted $baseline without recreating data"
fi

apply_directory "$root/migrations"
$psql_base -f "$root/enable-selfhost.sql"

#!/bin/sh
set -eu

psql_base="psql -v ON_ERROR_STOP=1 -h db -U postgres -d postgres"
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

found=false
for migration in /opt/pomodoist/migrations/*.sql; do
  [ -f "$migration" ] || continue
  found=true
  version=$(basename "$migration" .sql)
  checksum=$(sha256sum "$migration" | awk '{print $1}')
  applied=$($psql_base -Atc "select checksum from pomodoist_meta.schema_migrations where version = '$version'")
  if [ -n "$applied" ]; then
    [ "$applied" = "$checksum" ] || {
      echo "Applied migration changed: $version" >&2
      exit 1
    }
    continue
  fi
  echo "Applying $version"
  $psql_base -f "$migration"
  $psql_base -c "insert into pomodoist_meta.schema_migrations(version, checksum) values ('$version', '$checksum')" >/dev/null
done

$found || {
  echo "No SQL migrations found" >&2
  exit 1
}

$psql_base -f /opt/pomodoist/enable-selfhost.sql

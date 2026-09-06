#!/usr/bin/env bash
set -euo pipefail

container=${1:?Usage: PGPASSWORD=... tests/database/run.sh pomodoist-selfhost-<db-container>}
case "$container" in
  pomodoist-selfhost-*) ;;
  *) echo 'Refusing a target outside the explicit local pomodoist-selfhost-* Docker namespace.' >&2; exit 1 ;;
esac
: "${PGPASSWORD:?Set PGPASSWORD to the local test database password}"
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

docker exec "$container" psql -X -U supabase_admin -d postgres \
  -v ON_ERROR_STOP=1 -c 'create extension if not exists pgtap with schema extensions;'
docker run --rm --name "pomodoist-selfhost-schema-tests-$$" \
  --network "container:$container" --env PGPASSWORD \
  --volume "$script_dir:/tests:ro" \
  public.ecr.aws/supabase/pg_prove:3.36 \
  pg_prove -h 127.0.0.1 -p 5432 -U postgres -d postgres --ext .sql -r /tests

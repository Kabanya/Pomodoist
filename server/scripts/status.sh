#!/bin/sh
set -eu

server_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
env_file="$server_dir/.env"
get_env() {
  sed -n "s/^$1=//p" "$env_file"
}
anon_key=$(get_env ANON_KEY)
supabase_url=$(get_env SUPABASE_PUBLIC_URL)
site_url=$(get_env SITE_URL)

docker compose --project-directory "$server_dir" --env-file "$server_dir/.env" -f "$server_dir/compose.yaml" ps
curl -fsS -H "apikey: $anon_key" "$supabase_url/auth/v1/health" >/dev/null
if docker compose --project-directory "$server_dir" --env-file "$server_dir/.env" \
  -f "$server_dir/compose.yaml" ps --status running --services | grep -qx web; then
  curl -fsS "$site_url/healthz" >/dev/null
  echo "API and web health checks passed."
else
  echo "API health check passed; web is not running."
fi

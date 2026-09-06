#!/bin/sh
set -eu

server_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
env_file="$server_dir/.env"
[ -f "$env_file" ] || {
  echo "Run make setup first" >&2
  exit 1
}

get_env() {
  sed -n "s/^$1=//p" "$env_file"
}

api_url=$(get_env SUPABASE_PUBLIC_URL)
anon_key=$(get_env ANON_KEY)
[ -n "$api_url" ] && [ -n "$anon_key" ] || {
  echo "SUPABASE_PUBLIC_URL and ANON_KEY are required" >&2
  exit 1
}

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/pomodoist-smoke.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
password=$(openssl rand -base64 24)
stamp=$(date +%s)-$$

request() {
  method=$1
  path=$2
  output=$3
  authorization=$4
  body=${5:-}
  if [ -n "$body" ]; then
    curl --silent --show-error --output "$output" --write-out '%{http_code}' \
      --request "$method" -H "apikey: $anon_key" \
      -H "Authorization: Bearer $authorization" -H 'Content-Type: application/json' \
      --data "$body" "$api_url$path"
  else
    curl --silent --show-error --output "$output" --write-out '%{http_code}' \
      --request "$method" -H "apikey: $anon_key" \
      -H "Authorization: Bearer $authorization" "$api_url$path"
  fi
}

first_email="smoke-$stamp-a@example.invalid"
first_signup=$(jq -nc --arg email "$first_email" --arg password "$password" \
  '{email:$email,password:$password}')
code=$(request POST /auth/v1/signup "$work_dir/first-signup.json" "$anon_key" "$first_signup")
[ "$code" = 200 ] || { echo "First account registration failed (HTTP $code)" >&2; exit 1; }
first_user=$(jq -er '.user.id' "$work_dir/first-signup.json")

login_body=$(jq -nc --arg email "$first_email" --arg password "$password" \
  '{email:$email,password:$password}')
code=$(request POST '/auth/v1/token?grant_type=password' "$work_dir/first-login.json" "$anon_key" "$login_body")
[ "$code" = 200 ] || { echo "First account login failed (HTTP $code)" >&2; exit 1; }
first_token=$(jq -er '.access_token' "$work_dir/first-login.json")

code=$(request GET "/rest/v1/profiles?select=id,pomodoist_is_pro&id=eq.$first_user" \
  "$work_dir/profile.json" "$first_token")
[ "$code" = 200 ] || { echo "Profile query failed (HTTP $code)" >&2; exit 1; }
jq -e --arg id "$first_user" \
  'length == 1 and .[0].id == $id and .[0].pomodoist_is_pro == true' \
  "$work_dir/profile.json" >/dev/null

entity_id="smoke-task-$stamp"
operation_id="smoke-op-$stamp"
now=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
push_body=$(jq -nc --arg entity "$entity_id" --arg operation "$operation_id" --arg now "$now" '{
  p_app_id:"pomodoist",
  p_device_id:"smoke-device-a",
  p_operations:[{
    opId:$operation,
    entityType:"task",
    entityId:$entity,
    operation:"upsert",
    clientUpdatedAt:$now,
    payload:{title:"Self-host smoke task",status:"pending"}
  }]
}')
code=$(request POST /rest/v1/rpc/push_changes "$work_dir/push.json" "$first_token" "$push_body")
[ "$code" = 200 ] || { echo "Authenticated sync push failed (HTTP $code)" >&2; exit 1; }
jq -e --arg entity "$entity_id" \
  '.applied | length == 1 and .[0].entityId == $entity' "$work_dir/push.json" >/dev/null

pull_body='{"p_app_id":"pomodoist","p_device_id":"smoke-device-b","p_since_revision":0,"p_limit":500}'
code=$(request POST /rest/v1/rpc/pull_changes "$work_dir/pull.json" "$first_token" "$pull_body")
[ "$code" = 200 ] || { echo "Authenticated sync pull failed (HTTP $code)" >&2; exit 1; }
jq -e --arg entity "$entity_id" \
  '.changes | any(.entityId == $entity and .data.title == "Self-host smoke task")' \
  "$work_dir/pull.json" >/dev/null

code=$(request POST /rest/v1/rpc/pull_changes "$work_dir/anon-pull.json" "$anon_key" "$pull_body")
[ "$code" = 400 ] || { echo "Anonymous sync was not rejected (HTTP $code)" >&2; exit 1; }
jq -e '.message == "Authentication required"' "$work_dir/anon-pull.json" >/dev/null

second_email="smoke-$stamp-b@example.invalid"
second_signup=$(jq -nc --arg email "$second_email" --arg password "$password" \
  '{email:$email,password:$password}')
code=$(request POST /auth/v1/signup "$work_dir/second-signup.json" "$anon_key" "$second_signup")
[ "$code" = 200 ] || { echo "Second account registration failed (HTTP $code)" >&2; exit 1; }
code=$(request POST '/auth/v1/token?grant_type=password' "$work_dir/second-login.json" "$anon_key" "$second_signup")
[ "$code" = 200 ] || { echo "Second account login failed (HTTP $code)" >&2; exit 1; }
second_token=$(jq -er '.access_token' "$work_dir/second-login.json")
code=$(request POST /rest/v1/rpc/pull_changes "$work_dir/second-pull.json" "$second_token" "$pull_body")
[ "$code" = 200 ] || { echo "Second account sync pull failed (HTTP $code)" >&2; exit 1; }
jq -e '.changes | length == 0' "$work_dir/second-pull.json" >/dev/null

echo "Registration, login, sync round-trip, anonymous denial, and tenant isolation passed."

#!/bin/sh
set -eu

server_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
compose="$server_dir/compose.yaml"
example="$server_dir/.env.example"

for path in \
  docker/db/Dockerfile \
  docker/gateway/Dockerfile \
  docker/gateway/kong.yml \
  docker/functions/Dockerfile \
  docker/functions/main/index.ts \
  database/enable-selfhost.sql \
  supabase/migrations \
  supabase/functions; do
  [ -e "$server_dir/$path" ] || {
    echo "Missing $path" >&2
    exit 1
  }
done

rendered=$(docker compose --project-directory "$server_dir" --env-file "$example" -f "$compose" config)
services=$(docker compose --project-directory "$server_dir" --env-file "$example" -f "$compose" config --services)
for service in db auth rest realtime migrate gateway functions web; do
  printf '%s\n' "$services" | grep -qx "$service" || {
    echo "Missing service: $service" >&2
    exit 1
  }
done

if grep -ERn 'app-test\.pomodoist\.com|app\.pomodoist\.com|supabase-test\.pomodoist\.com|supabase\.co' \
  "$compose" "$example" "$server_dir/docker" "$server_dir/scripts" "$server_dir/README.md" 2>/dev/null; then
  echo "Hosted production endpoint found in self-host packaging" >&2
  exit 1
fi

printf '%s\n' "$rendered" | grep -Fq 'host_ip: 127.0.0.1'
printf '%s\n' "$rendered" | grep -Fq 'published: "55421"'
printf '%s\n' "$rendered" | grep -Fq 'published: "58080"'
if printf '%s\n' "$rendered" | grep -Eq 'image: [^ ]+:latest([[:space:]]|$)'; then
  echo "Unpinned latest image found" >&2
  exit 1
fi
if printf '%s\n' "$rendered" | grep -E '^    container_name:' | grep -Ev 'pomodoist-selfhost-'; then
  echo "Container name escapes pomodoist-selfhost prefix" >&2
  exit 1
fi

fixture=$(mktemp -d "${TMPDIR:-/tmp}/pomodoist-bootstrap.XXXXXX")
trap 'rm -rf "$fixture"' EXIT HUP INT TERM
fixture_repository="$fixture/repository"
fixture_server="$fixture_repository/server"
mkdir -p "$fixture_server/scripts"
cp "$example" "$fixture_server/.env.example"
cp "$server_dir/scripts/bootstrap.sh" "$fixture_server/scripts/bootstrap.sh"
cp "$server_dir/scripts/refresh-release.sh" "$fixture_server/scripts/refresh-release.sh"
output=$(sh "$fixture_server/scripts/bootstrap.sh")
[ "$output" = 'Created server/.env with fresh secrets (mode 600).' ]
for key in POSTGRES_PASSWORD JWT_SECRET JWT_KEYS JWT_JWKS ANON_KEY SERVICE_ROLE_KEY SECRET_KEY_BASE REALTIME_DB_ENC_KEY POMODOIST_RELEASE; do
  value=$(sed -n "s/^$key=//p" "$fixture_server/.env")
  [ -n "$value" ]
  [ "$value" != 'generate-with-make-setup' ]
  if printf '%s' "$output" | grep -Fq "$value"; then
    echo "bootstrap printed $key" >&2
    exit 1
  fi
done
jq -e 'length == 2 and any(.[]; .alg == "ES256" and .kty == "EC" and has("d"))' \
  <<EOF >/dev/null
$(sed -n 's/^JWT_KEYS=//p' "$fixture_server/.env")
EOF
jq -e '.keys | length == 2 and any(.[]; .alg == "ES256" and .kty == "EC" and (has("d") | not))' \
  <<EOF >/dev/null
$(sed -n 's/^JWT_JWKS=//p' "$fixture_server/.env")
EOF

sed '/^POMODOIST_RELEASE=/d' "$fixture_server/.env" > "$fixture/env-before-release-refresh"
archive_release=$(sed -n 's/^POMODOIST_RELEASE=//p' "$fixture_server/.env")
expected_release=$(openssl rand -hex 20)
mkdir -p "$fixture/bin"
cat > "$fixture/bin/git" <<EOF
#!/bin/sh
printf '%s\n' '$expected_release'
EOF
chmod 755 "$fixture/bin/git"
: > "$fixture_repository/.git"
refresh_output=$(PATH="$fixture/bin:$PATH" sh "$fixture_server/scripts/refresh-release.sh")
[ "$refresh_output" = 'Updated server release metadata.' ]
[ "$(sed -n 's/^POMODOIST_RELEASE=//p' "$fixture_server/.env")" = "$expected_release" ]
sed '/^POMODOIST_RELEASE=/d' "$fixture_server/.env" > "$fixture/env-after-release-refresh"
cmp -s "$fixture/env-before-release-refresh" "$fixture/env-after-release-refresh"
mode=$(stat -c %a "$fixture_server/.env" 2>/dev/null || stat -f %Lp "$fixture_server/.env")
[ "$mode" = 600 ]
rm -f "$fixture_repository/.git"
awk -v release="$archive_release" '
  /^POMODOIST_RELEASE=/ { print "POMODOIST_RELEASE=" release; next }
  { print }
' "$fixture_server/.env" > "$fixture_server/.env.archive"
chmod 600 "$fixture_server/.env.archive"
mv "$fixture_server/.env.archive" "$fixture_server/.env"
sh "$fixture_server/scripts/refresh-release.sh" >/dev/null
[ "$(sed -n 's/^POMODOIST_RELEASE=//p' "$fixture_server/.env")" = "$archive_release" ]

echo "Self-host configuration is valid."

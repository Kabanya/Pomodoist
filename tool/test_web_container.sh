#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
image="pomodoist-web-container-test:$$"
release=0123456789abcdef0123456789abcdef01234567
containers=""
test_root=$(mktemp -d "${TMPDIR:-/tmp}/pomodoist-web-container.XXXXXX")
build_context="$test_root/context"
oauth_source="$repo_root/web/GoogleOAuth.env"
oauth_source_checksum=
if [ -f "$oauth_source" ]; then
  oauth_source_checksum=$(cksum <"$oauth_source")
fi

cleanup() {
  for container in $containers; do
    docker rm -f "$container" >/dev/null 2>&1 || true
  done
  docker image rm -f "$image" >/dev/null 2>&1 || true
  rm -rf "$test_root"
}
trap cleanup EXIT INT TERM

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_header() {
  url=$1
  pattern=$2
  curl --fail --silent --show-error --head "$url" | tr -d '\r' | grep -Eiq "$pattern" ||
    fail "$url did not include header matching $pattern"
}

wait_for_http() {
  url=$1
  attempts=0
  until curl --fail --silent --show-error "$url" >/dev/null 2>&1; do
    attempts=$((attempts + 1))
    [ "$attempts" -lt 40 ] || fail "$url did not become healthy"
    sleep 0.25
  done
}

container_url() {
  container=$1
  port=$(docker port "$container" 8080/tcp | sed -n '1s/.*://p')
  [ -n "$port" ] || fail "could not resolve published port for $container"
  printf 'http://127.0.0.1:%s' "$port"
}

run_remote() {
  name=$1
  environment=$2
  web_url=$3
  supabase_url=$4
  google_client=$5

  containers="$containers $name"
  docker run --detach --rm --name "$name" --publish 127.0.0.1::8080 \
    --env "POMODOIST_ENVIRONMENT=$environment" \
    --env "POMODOIST_RELEASE=$release" \
    --env "POMODOIST_WEB_URL=$web_url" \
    --env "SUPABASE_URL=$supabase_url" \
    --env 'SUPABASE_ANON_KEY=public-anon-key' \
    --env "GOOGLE_WEB_CLIENT_ID=$google_client" \
    --env 'TURNSTILE_SITE_KEY=1x00000000000000000000AA' \
    --env 'SENTRY_DSN=https://public@o12345.ingest.sentry.io/42' \
    "$image" >/dev/null
}

mkdir -p "$build_context"
(cd "$repo_root" && tar \
  --exclude='./.git' \
  --exclude='./.dart_tool' \
  --exclude='./.env' \
  --exclude='./.env.*' \
  --exclude='./.superpowers' \
  --exclude='./build' \
  --exclude='./.worktrees' \
  --exclude='./web/GoogleOAuth.env' \
  -cf - .) | tar -xf - -C "$build_context"
printf '%s\n' 'oauth-env-must-never-ship' >"$build_context/web/GoogleOAuth.env"

assert_rejected_billing_channel() {
  channel=$1
  log="$test_root/billing-channel-$channel.log"
  channel_arg=""
  if [ "$channel" != missing ]; then
    channel_arg="--build-arg POMODOIST_BILLING_CHANNEL=$channel"
  fi
  if docker build \
    --file "$build_context/deploy/web/Dockerfile" \
    --target builder \
    --build-arg "RELEASE_SHA=$release" \
    $channel_arg \
    "$build_context" >"$log" 2>&1; then
    fail "web image accepted POMODOIST_BILLING_CHANNEL=$channel"
  fi
  grep -q 'POMODOIST_BILLING_CHANNEL must be stripe' "$log" || {
    cat "$log" >&2
    fail "web image rejected $channel for an unexpected reason"
  }
}

assert_rejected_billing_channel missing
assert_rejected_billing_channel storekit

# This is deliberately the only image build in this test. Both environments
# below must run from the exact same image ID.
docker build \
  --file "$build_context/deploy/web/Dockerfile" \
  --build-arg "RELEASE_SHA=$release" \
  --build-arg POMODOIST_BILLING_CHANNEL=stripe \
  --tag "$image" \
  "$build_context"
image_id=$(docker image inspect "$image" --format '{{.Id}}')

docker run --rm \
  --env POMODOIST_ENVIRONMENT=staging \
  --env "POMODOIST_RELEASE=$release" \
  --env POMODOIST_WEB_URL=https://app-test.pomodoist.com \
  --env SUPABASE_URL=https://supabase-test.pomodoist.com \
  --env SUPABASE_ANON_KEY=public-anon-key \
  --env TURNSTILE_SITE_KEY=1x00000000000000000000AA \
  "$image" nginx -t >/dev/null

unicode_separators=$(printf '\342\200\250\342\200\251')
malicious_google_client="client\"</script>\nline${unicode_separators}tail"

staging_name="pomodoist-web-staging-$$"
run_remote \
  "$staging_name" \
  staging \
  https://app-test.pomodoist.com \
  https://supabase-test.pomodoist.com \
  "$malicious_google_client"
staging_url=$(container_url "$staging_name")
wait_for_http "$staging_url/healthz"

aasa="$test_root/apple-app-site-association"
curl --fail --silent --show-error \
  "$staging_url/.well-known/apple-app-site-association" >"$aasa"
python3 - "$aasa" <<'PY'
import json
import pathlib
import sys

text = pathlib.Path(sys.argv[1]).read_text()
assert json.loads(text) == {
    "applinks": {
        "apps": [],
        "details": [{
            "appID": "4VK836929S.com.finchforge.pomodoist",
            "paths": ["/purchase-success"],
        }],
    },
    "webcredentials": {
        "apps": ["4VK836929S.com.finchforge.pomodoist"],
    },
}
PY
assert_header \
  "$staging_url/.well-known/apple-app-site-association" \
  '^Content-Type: application/json( *;.*)?$'

access_marker=nginx-access-state-must-not-appear
curl --fail --silent --show-error \
  "$staging_url/auth/challenge?state=$access_marker" >/dev/null
if docker logs "$staging_name" 2>&1 | grep -q "$access_marker"; then
  fail 'CAPTCHA challenge query appeared in nginx access logs'
fi

node "$repo_root/tool/test_web_browser.mjs" "$staging_url/login" ||
  fail 'Chrome/Chromium is required and the headless browser smoke failed'

staging_config="$test_root/staging-config.js"
staging_version="$test_root/staging-version.json"
curl --fail --silent --show-error "$staging_url/config.js" >"$staging_config"
curl --fail --silent --show-error "$staging_url/version.json" >"$staging_version"

python3 - "$staging_config" "$staging_version" "$malicious_google_client" <<'PY'
import json
import pathlib
import sys

config_text = pathlib.Path(sys.argv[1]).read_text()
prefix = "window.pomodoistRuntimeConfig = "
assert config_text.startswith(prefix) and config_text.endswith(";\n")
config = json.loads(config_text[len(prefix):-2])
assert set(config) == {
    "environment", "release", "webAppUrl", "supabaseUrl",
    "supabaseAnonKey", "googleWebClientId", "turnstileSiteKey", "sentryDsn",
}
assert config["environment"] == "staging"
assert config["googleWebClientId"] == sys.argv[3]
assert "</script>" not in config_text
assert "\u2028" not in config_text and "\u2029" not in config_text
assert "\\u2028" in config_text and "\\u2029" in config_text

version_text = pathlib.Path(sys.argv[2]).read_text()
version = json.loads(version_text)
assert version == {"environment": "staging", "release": config["release"]}
assert "forbidden" not in version_text
PY

for route in login register today login-callback auth/challenge; do
  curl --fail --silent --show-error "$staging_url/$route" | grep -q '<title>pomodoist</title>' ||
    fail "SPA route /$route did not return the Flutter index"
done

telegram_html="$test_root/telegram.html"
curl --fail --silent --show-error "$staging_url/telegram/" >"$telegram_html"
grep -q 'id="app"' "$telegram_html" || fail '/telegram/ did not serve the Mini App'
grep -q 'https://telegram.org/js/telegram-web-app.js' "$telegram_html" ||
  fail 'Telegram SDK script is missing'
if grep -Eq 'main\.dart\.js|flutter_bootstrap\.js' "$telegram_html"; then
  fail 'main.dart.js must not load in Telegram'
fi
telegram_redirect=$(curl --silent --output /dev/null --write-out '%{http_code}' \
  "$staging_url/telegram")
[ "$telegram_redirect" = 308 ] || fail "/telegram returned $telegram_redirect instead of 308"

asset_status=$(curl --silent --output /dev/null --write-out '%{http_code}' \
  "$staging_url/assets/does-not-exist.png")
[ "$asset_status" = 404 ] || fail "missing asset returned $asset_status instead of 404"
worker_status=$(curl --silent --output /dev/null --write-out '%{http_code}' \
  "$staging_url/flutter_service_worker.js")
[ "$worker_status" = 404 ] || fail "service worker must be disabled, got $worker_status"
source_map_status=$(curl --silent --output /dev/null --write-out '%{http_code}' \
  "$staging_url/main.dart.js.map")
[ "$source_map_status" = 404 ] || fail "source maps must not be public, got $source_map_status"

assert_header "$staging_url/healthz" '^Cache-Control: no-store$'
assert_header "$staging_url/config.js" '^Cache-Control: no-store$'
assert_header "$staging_url/version.json" '^Cache-Control: no-store$'
assert_header "$staging_url/login" '^Cache-Control: no-store$'
assert_header "$staging_url/flutter_bootstrap.js" '^Cache-Control: no-store$'
assert_header "$staging_url/main.dart.js" '^Cache-Control: no-cache$'
main_etag=$(curl --fail --silent --head "$staging_url/main.dart.js" |
  sed -n 's/^[Ee][Tt][Aa][Gg]: *//p' | tr -d '\r')
[ -n "$main_etag" ] || fail 'main.dart.js must include an ETag'
revalidated_status=$(curl --silent --output /dev/null --write-out '%{http_code}' \
  --header "If-None-Match: $main_etag" "$staging_url/main.dart.js")
[ "$revalidated_status" = 304 ] ||
  fail "main.dart.js revalidation returned $revalidated_status instead of 304"
assert_header "$staging_url/healthz" '^X-Content-Type-Options: nosniff$'
assert_header "$staging_url/healthz" '^Referrer-Policy: strict-origin-when-cross-origin$'
assert_header "$staging_url/healthz" "script-src .*'wasm-unsafe-eval'"
assert_header "$staging_url/healthz" 'connect-src .*https://fonts\.gstatic\.com'
assert_header "$staging_url/healthz" 'connect-src .*https://o12345\.ingest\.sentry\.io'
assert_header "$staging_url/healthz" '^X-Frame-Options: SAMEORIGIN$'
if curl --fail --silent --head "$staging_url/healthz" | grep -qi 'telegram\.org'; then
  fail 'ordinary Flutter Web CSP must not allow Telegram'
fi
assert_header "$staging_url/telegram/" 'script-src .*https://telegram\.org'
assert_header "$staging_url/telegram/" "frame-ancestors 'self' https://web\.telegram\.org https://\*\.telegram\.org"
if curl --fail --silent --head "$staging_url/telegram/" | grep -qi '^X-Frame-Options:'; then
  fail 'X-Frame-Options must be omitted for the Telegram Mini App'
fi
if curl --fail --silent --head "$staging_url/healthz" | grep -q 'public@'; then
  fail 'Sentry public key must not appear in response headers'
fi
if curl --fail --silent "$staging_url/GoogleOAuth.env" >/dev/null 2>&1; then
  fail 'GoogleOAuth.env must return 404'
fi
docker exec "$staging_name" sh -c \
  'test ! -e /usr/share/nginx/html/GoogleOAuth.env &&
   test ! -e /usr/share/nginx/html/GoogleOAuth.env.example &&
   test ! -e /usr/share/nginx/html/drift_worker.dart &&
   test ! -e /usr/share/nginx/html/.last_build_id &&
   ! find /usr/share/nginx/html -type f -name "*.map" | grep -q . &&
   ! grep -R "oauth-env-must-never-ship" /usr/share/nginx/html &&
   ! grep -RE "POMODOIST_TELEGRAM_BOT_TOKEN|SUPABASE_SERVICE_ROLE_KEY" /usr/share/nginx/html/telegram' ||
  fail 'web-only source/config leaked into the runtime image'

production_name="pomodoist-web-production-$$"
run_remote \
  "$production_name" \
  production \
  https://app.pomodoist.com \
  https://ewauihswbwduvklrozke.supabase.co \
  ''
production_url=$(container_url "$production_name")
wait_for_http "$production_url/healthz"

production_config="$test_root/production-config.js"
production_version="$test_root/production-version.json"
curl --fail --silent --show-error "$production_url/config.js" >"$production_config"
curl --fail --silent --show-error "$production_url/version.json" >"$production_version"
cmp -s "$staging_config" "$production_config" && fail 'runtime configs must differ'
cmp -s "$staging_version" "$production_version" && fail 'version files must differ'
[ "$(docker image inspect "$image" --format '{{.Id}}')" = "$image_id" ] ||
  fail 'image changed between staging and production runs'

expect_startup_failure() {
  label=$1
  shift
  if docker run --rm "$@" "$image" nginx -t >/dev/null 2>&1; then
    fail "$label unexpectedly started"
  fi
}

common_env="--env POMODOIST_RELEASE=$release --env SUPABASE_ANON_KEY=public-anon-key --env TURNSTILE_SITE_KEY=1x00000000000000000000AA"
expect_startup_failure 'missing Turnstile site key' \
  --env POMODOIST_ENVIRONMENT=staging \
  --env POMODOIST_RELEASE="$release" \
  --env POMODOIST_WEB_URL=https://app-test.pomodoist.com \
  --env SUPABASE_URL=https://supabase-test.pomodoist.com \
  --env SUPABASE_ANON_KEY=public-anon-key
# shellcheck disable=SC2086
expect_startup_failure 'missing environment' $common_env \
  --env POMODOIST_WEB_URL=https://app-test.pomodoist.com \
  --env SUPABASE_URL=https://supabase-test.pomodoist.com \
  --env TURNSTILE_SITE_KEY=1x00000000000000000000AA
# shellcheck disable=SC2086
expect_startup_failure 'missing anon key' \
  --env POMODOIST_ENVIRONMENT=staging \
  --env POMODOIST_RELEASE="$release" \
  --env POMODOIST_WEB_URL=https://app-test.pomodoist.com \
  --env SUPABASE_URL=https://supabase-test.pomodoist.com
# shellcheck disable=SC2086
expect_startup_failure 'invalid staging URL' $common_env \
  --env POMODOIST_ENVIRONMENT=staging \
  --env POMODOIST_WEB_URL=https://evil.example \
  --env SUPABASE_URL=https://supabase-test.pomodoist.com
# shellcheck disable=SC2086
expect_startup_failure 'invalid production Supabase host' $common_env \
  --env POMODOIST_ENVIRONMENT=production \
  --env POMODOIST_WEB_URL=https://app.pomodoist.com \
  --env SUPABASE_URL=https://evil.example
# shellcheck disable=SC2086
expect_startup_failure 'release mismatch' \
  --env POMODOIST_ENVIRONMENT=staging \
  --env POMODOIST_RELEASE=ffffffffffffffffffffffffffffffffffffffff \
  --env POMODOIST_WEB_URL=https://app-test.pomodoist.com \
  --env SUPABASE_URL=https://supabase-test.pomodoist.com \
  --env SUPABASE_ANON_KEY=public-anon-key \
  --env TURNSTILE_SITE_KEY=1x00000000000000000000AA
expect_startup_failure 'hostless Sentry DSN' \
  --env POMODOIST_ENVIRONMENT=staging \
  --env POMODOIST_RELEASE="$release" \
  --env POMODOIST_WEB_URL=https://app-test.pomodoist.com \
  --env SUPABASE_URL=https://supabase-test.pomodoist.com \
  --env SUPABASE_ANON_KEY=public-anon-key \
  --env TURNSTILE_SITE_KEY=1x00000000000000000000AA \
  --env 'SENTRY_DSN=https://?token'
expect_startup_failure 'unsupported Sentry host' \
  --env POMODOIST_ENVIRONMENT=staging \
  --env POMODOIST_RELEASE="$release" \
  --env POMODOIST_WEB_URL=https://app-test.pomodoist.com \
  --env SUPABASE_URL=https://supabase-test.pomodoist.com \
  --env SUPABASE_ANON_KEY=public-anon-key \
  --env TURNSTILE_SITE_KEY=1x00000000000000000000AA \
  --env 'SENTRY_DSN=https://public@sentry.example.test/42'
multiline_sentry_dsn='https://evil.example/1
https://public@o123.ingest.sentry.io/42'
expect_startup_failure 'multiline Sentry DSN' \
  --env POMODOIST_ENVIRONMENT=staging \
  --env POMODOIST_RELEASE="$release" \
  --env POMODOIST_WEB_URL=https://app-test.pomodoist.com \
  --env SUPABASE_URL=https://supabase-test.pomodoist.com \
  --env SUPABASE_ANON_KEY=public-anon-key \
  --env TURNSTILE_SITE_KEY=1x00000000000000000000AA \
  --env "SENTRY_DSN=$multiline_sentry_dsn"
carriage_return=$(printf '\r')
horizontal_tab=$(printf '\t')
expect_startup_failure 'carriage-return Sentry DSN' \
  --env POMODOIST_ENVIRONMENT=staging \
  --env POMODOIST_RELEASE="$release" \
  --env POMODOIST_WEB_URL=https://app-test.pomodoist.com \
  --env SUPABASE_URL=https://supabase-test.pomodoist.com \
  --env SUPABASE_ANON_KEY=public-anon-key \
  --env TURNSTILE_SITE_KEY=1x00000000000000000000AA \
  --env "SENTRY_DSN=https://evil.example/1${carriage_return}https://public@o123.ingest.sentry.io/42"
expect_startup_failure 'CRLF Sentry DSN' \
  --env POMODOIST_ENVIRONMENT=staging \
  --env POMODOIST_RELEASE="$release" \
  --env POMODOIST_WEB_URL=https://app-test.pomodoist.com \
  --env SUPABASE_URL=https://supabase-test.pomodoist.com \
  --env SUPABASE_ANON_KEY=public-anon-key \
  --env TURNSTILE_SITE_KEY=1x00000000000000000000AA \
  --env "SENTRY_DSN=https://evil.example/1${carriage_return}
https://public@o123.ingest.sentry.io/42"
expect_startup_failure 'tab-containing Sentry DSN' \
  --env POMODOIST_ENVIRONMENT=staging \
  --env POMODOIST_RELEASE="$release" \
  --env POMODOIST_WEB_URL=https://app-test.pomodoist.com \
  --env SUPABASE_URL=https://supabase-test.pomodoist.com \
  --env SUPABASE_ANON_KEY=public-anon-key \
  --env TURNSTILE_SITE_KEY=1x00000000000000000000AA \
  --env "SENTRY_DSN=https://public@o123.ingest.sentry.io/42${horizontal_tab}ignored"

if [ -n "$oauth_source_checksum" ] &&
  [ "$(cksum <"$oauth_source")" != "$oauth_source_checksum" ]; then
  fail 'preexisting web/GoogleOAuth.env was modified'
fi

printf 'Pomodoist web container integration checks passed.\n'

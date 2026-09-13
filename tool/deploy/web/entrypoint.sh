#!/bin/sh
set -eu

fail() {
  printf 'Pomodoist runtime config error: %s\n' "$1" >&2
  exit 1
}

validate_selfhosted_url() {
  value=$1
  field=$2
  if printf '%s' "$value" | grep -Eq \
    '^https://([A-Za-z0-9.-]+|\[[0-9A-Fa-f:]+\])(:[0-9]+)?(/[^?#[:cntrl:][:space:]]*)?$'; then
    return
  fi
  if printf '%s' "$value" | grep -Eq \
    '^http://(localhost|127\.0\.0\.1|\[::1\])(:[0-9]+)?(/[^?#[:cntrl:][:space:]]*)?$'; then
    return
  fi
  fail "$field must use HTTPS or loopback HTTP"
}

url_origin() {
  printf '%s' "$1" |
    sed -E 's#^(https?://(\[[^]]+\]|[^/:]+)(:[0-9]+)?).*$#\1#'
}

[ -n "${POMODOIST_ENVIRONMENT:-}" ] || fail 'POMODOIST_ENVIRONMENT is required'
[ -n "${POMODOIST_RELEASE:-}" ] || fail 'POMODOIST_RELEASE is required'
[ -n "${POMODOIST_WEB_URL:-}" ] || fail 'POMODOIST_WEB_URL is required'
[ -n "${SUPABASE_URL:-}" ] || fail 'SUPABASE_URL is required'
[ -n "${SUPABASE_ANON_KEY:-}" ] || fail 'SUPABASE_ANON_KEY is required'

printf '%s' "$POMODOIST_RELEASE" | grep -Eq '^[0-9a-f]{40}$' ||
  fail 'POMODOIST_RELEASE must be a full lowercase Git SHA'
image_release=$(sed -n '1p' /usr/share/nginx/image-release)
[ "$POMODOIST_RELEASE" = "$image_release" ] ||
  fail 'POMODOIST_RELEASE does not match this image'

case "$POMODOIST_ENVIRONMENT" in
  staging)
    [ -n "${TURNSTILE_SITE_KEY:-}" ] || fail 'TURNSTILE_SITE_KEY is required'
    case "$POMODOIST_WEB_URL" in
      https://app-test.pomodoist.com) ;;
      *) fail 'staging requires the approved web URL' ;;
    esac
    case "$SUPABASE_URL" in
      https://supabase-test.pomodoist.com) ;;
      *) fail 'staging requires the approved Supabase URL' ;;
    esac
    ;;
  production)
    [ -n "${TURNSTILE_SITE_KEY:-}" ] || fail 'TURNSTILE_SITE_KEY is required'
    [ "$POMODOIST_WEB_URL" = 'https://app.pomodoist.com' ] ||
      fail 'production requires the approved web URL'
    [ "$SUPABASE_URL" = 'https://ewauihswbwduvklrozke.supabase.co' ] ||
      fail 'production requires the approved Supabase URL'
    ;;
  selfhosted)
    validate_selfhosted_url "$POMODOIST_WEB_URL" POMODOIST_WEB_URL
    validate_selfhosted_url "$SUPABASE_URL" SUPABASE_URL
    ;;
  *) fail 'POMODOIST_ENVIRONMENT must be staging, production, or selfhosted' ;;
esac

sentry_origin=
if [ -n "${SENTRY_DSN:-}" ]; then
  sentry_without_controls=$(printf '%s' "$SENTRY_DSN" |
    LC_ALL=C tr -d '[:cntrl:]')
  [ "$SENTRY_DSN" = "$sentry_without_controls" ] ||
    fail 'SENTRY_DSN must not contain control characters'
  if [ "$POMODOIST_ENVIRONMENT" = selfhosted ]; then
    if ! printf '%s' "$SENTRY_DSN" | grep -Eq \
      '^https://[A-Za-z0-9]+@([A-Za-z0-9.-]+|\[[0-9A-Fa-f:]+\])(:[0-9]+)?(/[^?#[:cntrl:][:space:]]*)?/[0-9]+$' &&
      ! printf '%s' "$SENTRY_DSN" | grep -Eq \
        '^http://[A-Za-z0-9]+@(localhost|127\.0\.0\.1|\[::1\])(:[0-9]+)?(/[^?#[:cntrl:][:space:]]*)?/[0-9]+$'; then
      fail 'SENTRY_DSN must be a public HTTPS or loopback HTTP Sentry DSN'
    fi
    sentry_origin=$(printf '%s' "$SENTRY_DSN" |
      sed -E 's#^(https?://)[^@/]+@(\[[^]]+\]|[^/:]+)(:[0-9]+)?.*$#\1\2\3#')
  else
    sentry_host=$(printf '%s' "$SENTRY_DSN" | sed -n \
      's#^https://[A-Za-z0-9][A-Za-z0-9]*@\(o[0-9][0-9]*\.ingest\.sentry\.io\)/[0-9][0-9]*$#\1#p')
    [ -n "$sentry_host" ] ||
      fail 'SENTRY_DSN must be a public Sentry Cloud DSN'
    sentry_origin="https://$sentry_host"
  fi
fi

supabase_origin=$(url_origin "$SUPABASE_URL")
case "$supabase_origin" in
  https://*) supabase_ws_origin="wss://${supabase_origin#https://}" ;;
  http://*) supabase_ws_origin="ws://${supabase_origin#http://}" ;;
esac
turnstile_origin=
if [ -n "${TURNSTILE_SITE_KEY:-}" ]; then
  turnstile_origin=https://challenges.cloudflare.com
fi

sed \
  -e "s|__SUPABASE_HTTP_ORIGIN__|$supabase_origin|g" \
  -e "s|__SUPABASE_WS_ORIGIN__|$supabase_ws_origin|g" \
  -e "s|__SENTRY_ORIGIN__|$sentry_origin|g" \
  -e "s|__TURNSTILE_ORIGIN__|$turnstile_origin|g" \
  /etc/nginx/pomodoist-security-headers.conf.template \
  >/tmp/pomodoist-security-headers.conf

config_tmp=/usr/share/nginx/html/.config.js.tmp
version_tmp=/usr/share/nginx/html/.version.json.tmp

/usr/local/bin/jq -cn \
  --arg environment "$POMODOIST_ENVIRONMENT" \
  --arg release "$POMODOIST_RELEASE" \
  --arg webAppUrl "$POMODOIST_WEB_URL" \
  --arg supabaseUrl "$SUPABASE_URL" \
  --arg supabaseAnonKey "$SUPABASE_ANON_KEY" \
  --arg turnstileSiteKey "${TURNSTILE_SITE_KEY:-}" \
  --arg sentryDsn "${SENTRY_DSN:-}" \
  '{environment: $environment, release: $release, webAppUrl: $webAppUrl,
    supabaseUrl: $supabaseUrl, supabaseAnonKey: $supabaseAnonKey,
    turnstileSiteKey: $turnstileSiteKey, sentryDsn: $sentryDsn}' |
  /usr/local/bin/jq -Rr \
    'gsub("<"; "\\u003c") | gsub("\u2028"; "\\u2028") | gsub("\u2029"; "\\u2029") |
     "window.pomodoistRuntimeConfig = \(.) ;"' |
  sed 's/ = / = /; s/ ;$/;/' >"$config_tmp"

/usr/local/bin/jq -cn \
  --arg environment "$POMODOIST_ENVIRONMENT" \
  --arg release "$POMODOIST_RELEASE" \
  '{environment: $environment, release: $release}' >"$version_tmp"

mv "$config_tmp" /usr/share/nginx/html/config.js
mv "$version_tmp" /usr/share/nginx/html/version.json

exec "$@"

#!/bin/sh
set -eu

fail() {
  printf 'Pomodoist runtime config error: %s\n' "$1" >&2
  exit 1
}

[ -n "${POMODOIST_ENVIRONMENT:-}" ] || fail 'POMODOIST_ENVIRONMENT is required'
[ -n "${POMODOIST_RELEASE:-}" ] || fail 'POMODOIST_RELEASE is required'
[ -n "${POMODOIST_WEB_URL:-}" ] || fail 'POMODOIST_WEB_URL is required'
[ -n "${SUPABASE_URL:-}" ] || fail 'SUPABASE_URL is required'
[ -n "${SUPABASE_ANON_KEY:-}" ] || fail 'SUPABASE_ANON_KEY is required'
[ -n "${TURNSTILE_SITE_KEY:-}" ] || fail 'TURNSTILE_SITE_KEY is required'

printf '%s' "$POMODOIST_RELEASE" | grep -Eq '^[0-9a-f]{40}$' ||
  fail 'POMODOIST_RELEASE must be a full lowercase Git SHA'
image_release=$(sed -n '1p' /usr/share/nginx/image-release)
[ "$POMODOIST_RELEASE" = "$image_release" ] ||
  fail 'POMODOIST_RELEASE does not match this image'

case "$POMODOIST_ENVIRONMENT" in
  staging)
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
    [ "$POMODOIST_WEB_URL" = 'https://app.pomodoist.com' ] ||
      fail 'production requires the approved web URL'
    [ "$SUPABASE_URL" = 'https://ewauihswbwduvklrozke.supabase.co' ] ||
      fail 'production requires the approved Supabase URL'
    ;;
  *) fail 'POMODOIST_ENVIRONMENT must be staging or production' ;;
esac

sentry_origin=
if [ -n "${SENTRY_DSN:-}" ]; then
  sentry_without_controls=$(printf '%s' "$SENTRY_DSN" |
    LC_ALL=C tr -d '[:cntrl:]')
  [ "$SENTRY_DSN" = "$sentry_without_controls" ] ||
    fail 'SENTRY_DSN must not contain control characters'
  sentry_host=$(printf '%s' "$SENTRY_DSN" | sed -n \
    's#^https://[A-Za-z0-9][A-Za-z0-9]*@\(o[0-9][0-9]*\.ingest\.sentry\.io\)/[0-9][0-9]*$#\1#p')
  [ -n "$sentry_host" ] ||
    fail 'SENTRY_DSN must be a public Sentry Cloud DSN'
  sentry_origin="https://$sentry_host"
fi

sed "s|__SENTRY_ORIGIN__|$sentry_origin|g" \
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
  --arg googleWebClientId "${GOOGLE_WEB_CLIENT_ID:-}" \
  --arg turnstileSiteKey "${TURNSTILE_SITE_KEY:-}" \
  --arg sentryDsn "${SENTRY_DSN:-}" \
  '{environment: $environment, release: $release, webAppUrl: $webAppUrl,
    supabaseUrl: $supabaseUrl, supabaseAnonKey: $supabaseAnonKey,
    googleWebClientId: $googleWebClientId,
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

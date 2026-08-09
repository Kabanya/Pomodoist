#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
sentry_cli_image='getsentry/sentry-cli:2.57.0@sha256:f2c99e93ccdaf7b934ba804946ea90405eb2b1b9fdb3aa42bcbb501641c6f01f'
release=0123456789abcdef0123456789abcdef01234567
test_root=$(mktemp -d "${TMPDIR:-/tmp}/pomodoist-sentry-artifacts.XXXXXX")
image="pomodoist-sentry-artifacts:$$"
container=

cleanup() {
  if [ -n "$container" ]; then docker rm -f "$container" >/dev/null 2>&1 || true; fi
  docker image rm -f "$image" >/dev/null 2>&1 || true
  rm -rf "$test_root"
}
trap cleanup EXIT INT TERM

SENTRY_RELEASE=$release "$repo_root/tool/export_web_sourcemaps.sh" "$test_root/export"
docker build \
  --file "$repo_root/deploy/web/Dockerfile" \
  --build-arg "RELEASE_SHA=$release" \
  --build-arg POMODOIST_BILLING_CHANNEL=stripe \
  --tag "$image" \
  "$repo_root" >/dev/null

container=$(docker create "$image")
docker cp "$container:/usr/share/nginx/html/main.dart.js" "$test_root/runtime.js"
if docker cp "$container:/usr/share/nginx/html/main.dart.js.map" \
  "$test_root/public.map" >/dev/null 2>&1; then
  printf 'Source map leaked into the runtime image\n' >&2
  exit 1
fi

verification=$(python3 "$repo_root/tool/verify_sentry_artifacts.py" \
  "$test_root/runtime.js" \
  "$test_root/export/artifacts/main.dart.js" \
  "$test_root/export/artifacts/main.dart.js.map" \
  "$repo_root")
printf '%s\n' "$verification"
position=$(printf '%s\n' "$verification" | sed -n 's/^resolve-position=//p')
line=${position%:*}
column=${position#*:}
test -n "$line" && test -n "$column"

resolve_output=$(docker run --rm \
  --volume "$test_root/export/artifacts:/work:ro" \
  "$sentry_cli_image" sourcemaps resolve /work/main.dart.js.map \
  --line "$line" --column "$column")
printf '%s\n' "$resolve_output"
printf '%s\n' "$resolve_output" | grep -Fq '../../../lib/main.dart'
printf '%s\n' "$resolve_output" | grep -Fq 'Future<void> main()'

printf 'Sentry artifact identity and resolution checks passed.\n'

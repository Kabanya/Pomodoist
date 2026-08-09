#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output=${1:-"$repo_root/build/sentry-sourcemaps"}
release=${SENTRY_RELEASE:-$(git -C "$repo_root" rev-parse HEAD)}

printf '%s' "$release" | grep -Eq '^[0-9a-f]{40}$' || {
  printf 'SENTRY_RELEASE must be a full lowercase Git SHA\n' >&2
  exit 1
}

if [ -d "$output" ] &&
  [ -n "$(find "$output" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
  printf 'Source-map output directory must be empty: %s\n' "$output" >&2
  exit 1
fi
mkdir -p "$output"
docker build \
  --file "$repo_root/deploy/web/Dockerfile" \
  --build-arg "RELEASE_SHA=$release" \
  --build-arg POMODOIST_BILLING_CHANNEL=stripe \
  --target sentry-source-maps \
  --output "type=local,dest=$output" \
  "$repo_root"

test "$(sed -n '1p' "$output/release")" = "$release"
test -f "$output/artifacts/main.dart.js"
test -f "$output/artifacts/main.dart.js.map"

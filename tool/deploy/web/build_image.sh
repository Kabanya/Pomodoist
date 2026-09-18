#!/bin/sh
set -eu

# Build the web image the same way the Coolify webhook does: one image from
# tool/deploy/web/Dockerfile, environment-independent, tagged with the commit
# that is being deployed.
#
# Usage: tool/deploy/web/build_image.sh [tag]
#   tag defaults to pomodoist-web:<RELEASE_SHA>
#
# RELEASE_SHA comes from the environment when set (the deployment runner passes
# it) and otherwise from the current commit, so the image always carries the
# identity the container is expected to report back.

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$repo_root"

. "$repo_root/tool/deploy/web/build-args.env"

release=${RELEASE_SHA:-$(git rev-parse HEAD)}
printf '%s' "$release" | grep -Eq '^[0-9a-f]{40}$' || {
  printf 'RELEASE_SHA must be a full lowercase Git SHA\n' >&2
  exit 1
}

tag=${1:-"pomodoist-web:$release"}

printf 'Building %s from %s\n' "$tag" "$release" >&2
docker build \
  --file "$repo_root/tool/deploy/web/Dockerfile" \
  --build-arg "RELEASE_SHA=$release" \
  --build-arg "POMODOIST_BILLING_CHANNEL=$POMODOIST_BILLING_CHANNEL" \
  --tag "$tag" \
  "$repo_root"

#!/bin/sh
# Writes the Apple App Site Association for one deployment environment.
#
# The image is built once and serves staging, production and self-hosted, so the
# association cannot be baked in at build time: the entrypoint regenerates it at
# container start from the same POMODOIST_ENVIRONMENT that config.js carries.
# Staging has to advertise the staging app id, otherwise app-test.pomodoist.com
# would hand universal links to the production build.
#
# Usage: generate_aasa.sh <environment> <output-file>
set -eu

environment=${1:-}
output=${2:-}
if [ -z "$environment" ] || [ -z "$output" ]; then
  printf 'usage: %s <environment> <output-file>\n' "$0" >&2
  exit 1
fi

team_id=4VK836929S

case "$environment" in
  production) app_id="$team_id.com.finchforge.pomodoist" ;;
  staging) app_id="$team_id.com.finchforge.pomodoist.stg" ;;
  # Development builds are installed through Xcode and self-hosted instances run
  # on a domain no app claims, so neither has an association to publish.
  development | selfhosted) app_id='' ;;
  *)
    printf 'Pomodoist AASA error: unknown environment %s\n' "$environment" >&2
    exit 1
    ;;
esac

if [ -z "$app_id" ]; then
  association='{"applinks":{"apps":[],"details":[]},"webcredentials":{"apps":[]}}'
else
  association=$(printf \
    '{"applinks":{"apps":[],"details":[{"appID":"%s","paths":["/purchase-success"]}]},"webcredentials":{"apps":["%s"]}}' \
    "$app_id" "$app_id")
fi

mkdir -p "$(dirname "$output")"
association_tmp="$output.tmp"
printf '%s\n' "$association" >"$association_tmp"
mv "$association_tmp" "$output"

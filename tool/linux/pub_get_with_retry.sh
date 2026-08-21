#!/usr/bin/env bash

set -euo pipefail

flutter="${1:-flutter}"
retry_delay="${POMODOIST_PUB_GET_RETRY_DELAY_SECONDS:-10}"

for attempt in 1 2 3; do
  if "$flutter" pub get; then
    exit 0
  fi

  if [[ "$attempt" -eq 3 ]]; then
    echo 'flutter pub get failed after three attempts.' >&2
    exit 69
  fi

  echo "flutter pub get attempt $attempt failed; retrying in ${retry_delay}s." >&2
  sleep "$retry_delay"
done

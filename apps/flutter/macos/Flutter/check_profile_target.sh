#!/bin/sh
set -eu

case "${FLUTTER_TARGET:-lib/main.dart}" in
  tool/pomo_resource_profile.dart|*/tool/pomo_resource_profile.dart)
    if [ "$SYMROOT" = "$(cd "$PROJECT_DIR/.." && pwd)/build/profile-harness/macos/Build/Products" ]; then
      exit 0
    fi
    echo 'error: Run the Pomo resource profiler with tool/macos/run-resource-profile.sh.' >&2
    exit 1
    ;;
  tool/*|*/tool/*)
    echo 'error: Flutter tool entrypoints cannot build the macOS app. Run motion profilers in Chrome.' >&2
    exit 1
    ;;
esac

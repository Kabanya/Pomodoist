#!/usr/bin/env bash
# SDK-level smoke test only: does not claim authenticated feature/device QA.
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
if [[ $# -gt 1 ]]; then
  echo 'Usage: bash tool/android/smoke_test.sh [development|staging|production]' >&2
  exit 64
fi
# The installed package, the APK path and the deep-link scheme all follow from
# the flavor, so a build can never be smoke-tested as a different flavor.
flavor=${1:-production}
case "$flavor" in
  development) package=com.finchforge.pomodoist.dev; scheme=pomodoist-dev ;;
  staging) package=com.finchforge.pomodoist.stg; scheme=pomodoist-stg ;;
  production) package=com.finchforge.pomodoist; scheme=pomodoist ;;
  *)
    echo "Unknown Android flavor: $flavor" >&2
    exit 64
    ;;
esac
cd "$repo_root/apps/flutter"
adb install -r "build/app/outputs/flutter-apk/app-$flavor-release.apk"
adb logcat -c
start_activity() {
  local result
  result=$(adb shell am start -W "$@")
  printf '%s\n' "$result"
  grep -q 'Status: ok' <<< "$result"
  sleep 3
  adb shell pidof "$package" >/dev/null
}
start_activity -n "$package/.MainActivity"
adb shell input keyevent KEYCODE_HOME
start_activity -n "$package/.MainActivity"
for host in focus login-callback google-calendar-connected captcha-callback; do
  start_activity -a android.intent.action.VIEW -d "$scheme://$host" -p "$package"
done
# Exercise a cold-start deep link, not only delivery to an existing Activity.
adb shell am force-stop "$package"
start_activity -a android.intent.action.VIEW -d "$scheme://focus" -p "$package"
if adb logcat -d -b crash | grep -Fq "Process: $package"; then
  echo 'The Android process crashed during smoke testing.' >&2
  exit 1
fi
echo "Android install/launch/resume/deep-link smoke checks passed for the $flavor flavor."

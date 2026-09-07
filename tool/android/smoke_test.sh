#!/usr/bin/env bash
# SDK-level smoke test only: does not claim authenticated feature/device QA.
set -euo pipefail
package=com.finchforge.pomodoist
adb install -r build/app/outputs/flutter-apk/app-release.apk
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
  start_activity -a android.intent.action.VIEW -d "pomodoist://$host" -p "$package"
done
# Exercise a cold-start deep link, not only delivery to an existing Activity.
adb shell am force-stop "$package"
start_activity -a android.intent.action.VIEW -d 'pomodoist://focus' -p "$package"
if adb logcat -d -b crash | grep -Fq "Process: $package"; then
  echo 'The Android process crashed during smoke testing.' >&2
  exit 1
fi
echo 'Android install/launch/resume/deep-link smoke checks passed.'

#!/usr/bin/env bash
# Produces APK + AAB with identical versioning, public configuration and signing.
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$repo_root"
config=${1:-.env.android.json}
if [[ $# -gt 1 ]]; then
  echo 'Usage: bash tool/android/build_release.sh [CONFIG.json]' >&2
  exit 64
fi
python3 tool/android/validate_config.py "$config"
release=${POMODOIST_RELEASE:-$(git rev-parse HEAD)}
if [[ ! "$release" =~ ^[0-9a-f]{40}$ ]]; then
  echo 'POMODOIST_RELEASE must be a full Git commit SHA.' >&2
  exit 64
fi
pubspec_version=$(awk '/^version:/ {sub(/\r$/, ""); print $2; exit}' pubspec.yaml)
version=${ANDROID_BUILD_NAME:-${pubspec_version%+*}}
build_number=${ANDROID_BUILD_NUMBER:-${pubspec_version##*+}}
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$ ]]; then
  echo 'Android version must be X.Y.Z or X.Y.Z-rc.N.' >&2
  exit 64
fi
if [[ ! "$build_number" =~ ^[1-9][0-9]{0,9}$ ]] || (( build_number > 2100000000 )); then
  echo 'ANDROID_BUILD_NUMBER must be in 1..2100000000 and increase for each Play upload.' >&2
  exit 64
fi
flutter pub get --enforce-lockfile
common=(--release --obfuscate "--build-name=$version" "--build-number=$build_number"
  "--dart-define-from-file=$config" "--dart-define=POMODOIST_RELEASE=$release"
  --dart-define=POMODOIST_BILLING_CHANNEL=storekit)
flutter build apk "${common[@]}" --split-debug-info=build/android/symbols/apk
flutter build appbundle "${common[@]}" --split-debug-info=build/android/symbols/appbundle
bash tool/android/verify_artifacts.sh
output=build/android/release
mkdir -p "$output"
cp build/app/outputs/flutter-apk/app-release.apk "$output/Pomodoist-Android.apk"
cp build/app/outputs/bundle/release/app-release.aab "$output/Pomodoist-Android.aab"
(
  cd "$output"
  sha256sum Pomodoist-Android.apk Pomodoist-Android.aab > SHA256SUMS
  sha256sum --check SHA256SUMS
)
python3 - "$output/release.json" "$version" "$build_number" "$release" <<'PY'
import json
from pathlib import Path
import sys
Path(sys.argv[1]).write_text(json.dumps({
    'applicationId': 'com.finchforge.pomodoist', 'versionName': sys.argv[2],
    'versionCode': int(sys.argv[3]), 'commit': sys.argv[4],
}, indent=2) + '\n')
PY
printf 'Signed Android artifacts: %s/%s\n' "$repo_root" "$output"

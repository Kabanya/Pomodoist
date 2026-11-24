#!/usr/bin/env bash
# With no argument, build the committed source in a temporary directory.
# F-Droid uses the two explicit phases in its disposable build checkout.
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$repo_root"
flutter_bin=$(command -v "${FLUTTER_BIN:-flutter}") || {
  echo 'Set FLUTTER_BIN or put the pinned Flutter SDK on PATH.' >&2
  exit 1
}
flutter_bin=$(realpath -- "$flutter_bin")
config="$repo_root/tool/android/fdroid-production.json"
app="$repo_root/apps/flutter"
apk=apps/flutter/build/app/outputs/flutter-apk/app-production-release.apk

check_flutter_version() {
  local expected
  expected=$(python3 -c 'import json; print(json.load(open(".fvmrc"))["flutter"])')
  "$flutter_bin" --version --machine | python3 -c '
import json, sys
actual = json.load(sys.stdin)["frameworkVersion"]
if actual != sys.argv[1]:
    sys.exit(f"F-Droid requires Flutter {sys.argv[1]}; found {actual}.")
' "$expected"
}

case "${1:-}" in
  --prepare)
    check_flutter_version
    python3 tool/android/validate_config.py "$config"
    python3 - "$config" <<'PYTHON'
import json
from pathlib import Path
import sys

if json.loads(Path(sys.argv[1]).read_text()).get('SENTRY_DSN'):
    raise SystemExit('The F-Droid production configuration must leave Sentry disabled.')
PYTHON
    python3 tool/android/prepare_fdroid.py "$app"
    cd "$app"
    "$flutter_bin" pub get --enforce-lockfile
    # pub get writes a debug plugin registrant. Generate release configuration
    # before the source scan so the build can use --no-pub without test plugins.
    "$flutter_bin" build apk --release --flavor production --config-only
    ;;
  --build-prepared)
    check_flutter_version
    release=${POMODOIST_RELEASE:-$(git rev-parse HEAD)}
    if [[ ! $release =~ ^[0-9a-f]{40}$ ]]; then
      echo 'POMODOIST_RELEASE must be a full Git commit SHA.' >&2
      exit 1
    fi
    cd "$app"
    python3 - <<'PY'
import json
from pathlib import Path
plugins = json.loads(Path('.flutter-plugins-dependencies').read_text())
android = {plugin['name'] for plugin in plugins['plugins']['android']}
unexpected = android & {'in_app_purchase_android', 'thermion_flutter'}
if unexpected or not Path('third_party/fdroid/sqlite/sqlite3.c').is_file():
    raise SystemExit('Run the F-Droid preparation phase before building.')
PY
    ORG_GRADLE_PROJECT_pomodoistFdroid=true "$flutter_bin" build apk \
      --no-pub --release --flavor production --target lib/main.dart \
      --dart-define=POMODOIST_FDROID=true \
      --dart-define="POMODOIST_RELEASE=$release" \
      --dart-define-from-file="$config"
    ;;
  '')
    release=$(git rev-parse HEAD)
    scratch=$(mktemp -d -t pomodoist-fdroid.XXXXXXXX)
    trap 'rm -rf -- "$scratch"' EXIT
    # Use the committed version and skip the desktop-only LFS model.
    GIT_LFS_SKIP_SMUDGE=1 git archive "$release" | tar -xf - -C "$scratch"
    export FLUTTER_BIN="$flutter_bin" POMODOIST_RELEASE="$release"
    bash "$scratch/tool/android/build_fdroid.sh" --prepare
    bash "$scratch/tool/android/build_fdroid.sh" --build-prepared
    output=build/flutter/android/fdroid/Pomodoist-FDroid-unsigned.apk
    install -D -m 0644 "$scratch/$apk" "$output"
    printf 'Unsigned F-Droid APK: %s/%s\n' "$repo_root" "$output"
    ;;
  *)
    echo 'Usage: bash tool/android/build_fdroid.sh [--prepare|--build-prepared]' >&2
    exit 64
    ;;
esac

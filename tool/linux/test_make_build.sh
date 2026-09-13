#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(cd -- "$script_dir/../.." && pwd -P)"
test_root="$(mktemp -d)"
trap 'find "$test_root" -depth -delete' EXIT

fake_flutter="$test_root/flutter"
fake_dart="$test_root/dart"
fake_appimage_builder="$test_root/build-appimage"
command_log="$test_root/commands.log"

write_fake_command() {
  local destination="$1"

  printf '%s\n' '#!/usr/bin/env bash' > "$destination"
  printf '%s\n' 'set -euo pipefail' >> "$destination"
  printf '%s\n' 'for name in http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY; do' >> "$destination"
  printf '%s\n' '  if printenv "$name" > /dev/null 2>&1; then' >> "$destination"
  printf '%s\n' '    echo "Linux build leaked proxy variable: $name" >&2' >> "$destination"
  printf '%s\n' '    exit 1' >> "$destination"
  printf '%s\n' '  fi' >> "$destination"
  printf '%s\n' 'done' >> "$destination"
  printf '%s\n' 'printf "%s" "$(basename -- "$0")" >> "$POMODOIST_NETWORK_TEST_LOG"' >> "$destination"
  printf '%s\n' 'printf " %s" "$@" >> "$POMODOIST_NETWORK_TEST_LOG"' >> "$destination"
  printf '%s\n' 'printf "\n" >> "$POMODOIST_NETWORK_TEST_LOG"' >> "$destination"
  printf '%s\n' 'if [[ "$(basename -- "$0")" == flutter && "${1:-}" == pub && "${2:-}" == get ]]; then' >> "$destination"
  printf '%s\n' '  attempt="$(grep -Fxc "flutter pub get" "$POMODOIST_NETWORK_TEST_LOG")"' >> "$destination"
  printf '%s\n' '  if (( attempt <= ${POMODOIST_NETWORK_TEST_PUB_GET_FAILURES:-0} )); then' >> "$destination"
  printf '%s\n' '    exit 69' >> "$destination"
  printf '%s\n' '  fi' >> "$destination"
  printf '%s\n' 'fi' >> "$destination"
  chmod 755 "$destination"
}

write_fake_command "$fake_flutter"
write_fake_command "$fake_dart"
write_fake_command "$fake_appimage_builder"

http_proxy=http://127.0.0.1:47922 \
https_proxy=http://127.0.0.1:47922 \
all_proxy=socks5://127.0.0.1:47922 \
HTTP_PROXY=http://127.0.0.1:47922 \
HTTPS_PROXY=http://127.0.0.1:47922 \
ALL_PROXY=socks5://127.0.0.1:47922 \
POMODOIST_NETWORK_TEST_LOG="$command_log" \
POMODOIST_NETWORK_TEST_PUB_GET_FAILURES=2 \
POMODOIST_PUB_GET_RETRY_DELAY_SECONDS=0 \
  make --silent --no-print-directory -C "$project_root" \
    linux-appimage \
    DART="$fake_dart" \
    FLUTTER="$fake_flutter" \
    LINUX_CONFIG="$test_root/production.json" \
    POMODOIST_RELEASE=0123456789abcdef0123456789abcdef01234567 \
    POMODOIST_APPIMAGE_BUILDER="$fake_appimage_builder"

test "$(wc -l < "$command_log")" -eq 6
test "$(sed -n '1p' "$command_log")" = 'flutter pub get'
test "$(sed -n '2p' "$command_log")" = 'flutter pub get'
test "$(sed -n '3p' "$command_log")" = 'flutter pub get'
grep -Eq '^dart tool/desktop_release_config\.dart --config .+/production\.json$' "$command_log"
grep -Eq '^flutter build linux --release ' "$command_log"
! grep -Eq '^flutter build linux .*--no-pub' "$command_log"
test "$(sed -n '6p' "$command_log")" = 'build-appimage '

# Check SDK selection/quoting and root-relative defines without running a build.
spaced_repo="$test_root/repo with spaces"
mkdir -p "$spaced_repo/.fvm/flutter_sdk/bin"
spaced_repo="$(cd -- "$spaced_repo" && pwd -P)"
cp "$project_root/Makefile" "$spaced_repo/Makefile"
cp "$fake_flutter" "$spaced_repo/.fvm/flutter_sdk/bin/flutter"
cp "$fake_dart" "$spaced_repo/.fvm/flutter_sdk/bin/dart"
make --silent --no-print-directory -n -C "$spaced_repo" \
  analyze setup-env linux-release \
  POMODOIST_RELEASE=0123456789abcdef0123456789abcdef01234567 \
  LINUX_CONFIG='config with spaces.json' > "$test_root/spaced-commands"
grep -Fq "\"$spaced_repo/.fvm/flutter_sdk/bin/flutter\" analyze" "$test_root/spaced-commands"
grep -Fq "\"$spaced_repo/.fvm/flutter_sdk/bin/dart\" tool/env_setup.dart" "$test_root/spaced-commands"
grep -Fq -- "--dart-define-from-file=\"$spaced_repo/config with spaces.json\"" "$test_root/spaced-commands"

echo 'Linux make build network contract passed.'

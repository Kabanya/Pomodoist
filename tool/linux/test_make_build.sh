#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(cd -- "$script_dir/../.." && pwd -P)"
test_root="$(mktemp -d)"
trap 'find "$test_root" -depth -delete' EXIT

fake_flutter="$test_root/flutter"
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
  printf '%s\n' 'basename -- "$0" >> "$POMODOIST_NETWORK_TEST_LOG"' >> "$destination"
  chmod 755 "$destination"
}

write_fake_command "$fake_flutter"
write_fake_command "$fake_appimage_builder"

http_proxy=http://127.0.0.1:47922 \
https_proxy=http://127.0.0.1:47922 \
all_proxy=socks5://127.0.0.1:47922 \
HTTP_PROXY=http://127.0.0.1:47922 \
HTTPS_PROXY=http://127.0.0.1:47922 \
ALL_PROXY=socks5://127.0.0.1:47922 \
POMODOIST_NETWORK_TEST_LOG="$command_log" \
  make --silent --no-print-directory -C "$project_root" \
    build-linux-appimage \
    FLUTTER="$fake_flutter" \
    POMODOIST_APPIMAGE_BUILDER="$fake_appimage_builder"

test "$(wc -l < "$command_log")" -eq 2
grep -Fqx 'flutter' "$command_log"
grep -Fqx 'build-appimage' "$command_log"

echo 'Linux make build network contract passed.'

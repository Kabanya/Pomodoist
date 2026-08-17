#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT

bundle="$test_root/source bundle"
data_home="$test_root/data home"
bin_home="$test_root/bin home"
install_dir="$data_home/pomodoist"

mkdir -p "$bundle/data" "$bundle/lib"
printf '#!/usr/bin/env sh\nexit 0\n' > "$bundle/pomodoist"
chmod 755 "$bundle/pomodoist"
printf 'asset\n' > "$bundle/data/example.txt"
printf 'library\n' > "$bundle/lib/example.so"

POMODOIST_LINUX_BUNDLE="$bundle" \
POMODOIST_INSTALL_DIR="$install_dir" \
XDG_DATA_HOME="$data_home" \
XDG_BIN_HOME="$bin_home" \
  "$script_dir/install.sh"

test -x "$install_dir/pomodoist"
test "$(cat "$install_dir/data/example.txt")" = 'asset'
test "$(cat "$install_dir/lib/example.so")" = 'library'
test -L "$bin_home/pomodoist"
test "$(readlink "$bin_home/pomodoist")" = "$install_dir/pomodoist"

desktop_file="$data_home/applications/com.finchforge.pomodoist.desktop"
icon_file="$data_home/icons/hicolor/512x512/apps/com.finchforge.pomodoist.png"
test -f "$desktop_file"
test -f "$icon_file"
test -f "$install_dir/.pomodoist-install"
grep -Fqx "Exec=\"$install_dir/pomodoist\" %u" "$desktop_file"
grep -Fqx 'Icon=com.finchforge.pomodoist' "$desktop_file"
grep -Fqx 'MimeType=x-scheme-handler/pomodoist;' "$desktop_file"

original_install="$test_root/original install"
protected_dir="$test_root/protected data"
mv -- "$install_dir" "$original_install"
mkdir -p -- "$protected_dir"
printf 'must survive\n' > "$protected_dir/keep"
ln -s -- "$protected_dir" "$install_dir"
if POMODOIST_LINUX_BUNDLE="$bundle" \
  POMODOIST_INSTALL_DIR="$install_dir" \
  XDG_DATA_HOME="$data_home" \
  XDG_BIN_HOME="$bin_home" \
  "$script_dir/install.sh" > /dev/null 2>&1; then
  echo 'install.sh unexpectedly followed a symlinked install target' >&2
  exit 1
fi
test "$(cat "$protected_dir/keep")" = 'must survive'
rm -- "$install_dir"
mv -- "$original_install" "$install_dir"

outside_data_home="$test_root/outside data home"
if POMODOIST_LINUX_BUNDLE="$bundle" \
  POMODOIST_INSTALL_DIR="$outside_data_home" \
  XDG_DATA_HOME="$data_home" \
  XDG_BIN_HOME="$bin_home" \
  "$script_dir/install.sh" > /dev/null 2>&1; then
  echo 'install.sh unexpectedly accepted a target outside XDG_DATA_HOME' >&2
  exit 1
fi
test ! -e "$outside_data_home"

rm -- "$bin_home/pomodoist"
printf 'do not replace\n' > "$bin_home/pomodoist"
printf 'keep existing install\n' > "$install_dir/existing-marker"
if POMODOIST_LINUX_BUNDLE="$bundle" \
  POMODOIST_INSTALL_DIR="$install_dir" \
  XDG_DATA_HOME="$data_home" \
  XDG_BIN_HOME="$bin_home" \
  "$script_dir/install.sh" > /dev/null 2>&1; then
  echo 'install.sh unexpectedly replaced a non-symlink launcher' >&2
  exit 1
fi
test "$(cat "$install_dir/existing-marker")" = 'keep existing install'

missing_bundle="$test_root/missing"
if POMODOIST_LINUX_BUNDLE="$missing_bundle" \
  POMODOIST_INSTALL_DIR="$test_root/should-not-exist" \
  XDG_DATA_HOME="$data_home" \
  XDG_BIN_HOME="$bin_home" \
  "$script_dir/install.sh" > /dev/null 2>&1; then
  echo 'install.sh unexpectedly accepted a missing bundle' >&2
  exit 1
fi
test ! -e "$test_root/should-not-exist"

echo 'Linux user installer contract passed.'

#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(cd -- "$script_dir/../.." && pwd -P)"

bundle="${POMODOIST_LINUX_BUNDLE:-$project_root/build/linux/x64/release/bundle}"
data_home="${XDG_DATA_HOME:-${HOME:?HOME is required}/.local/share}"
bin_home="${XDG_BIN_HOME:-${HOME:?HOME is required}/.local/bin}"
install_dir="${POMODOIST_INSTALL_DIR:-$data_home/pomodoist}"
desktop_dir="$data_home/applications"
icon_dir="$data_home/icons/hicolor/512x512/apps"
desktop_id='com.finchforge.pomodoist'
install_marker='.pomodoist-install'

if [[ ! -x "$bundle/pomodoist" || ! -d "$bundle/data" || ! -d "$bundle/lib" ]]; then
  echo "Invalid Pomodoist Linux bundle: $bundle" >&2
  echo 'Build it first with: make linux-release' >&2
  exit 66
fi

if [[ "$data_home" != /* || "$bin_home" != /* || "$install_dir" != /* ]]; then
  echo 'Linux installation paths must be absolute.' >&2
  exit 64
fi

data_home="$(realpath -m -- "$data_home")"
bin_home="$(realpath -m -- "$bin_home")"
if [[ -L "$install_dir" ]]; then
  echo "Refusing symlinked installation directory: $install_dir" >&2
  exit 73
fi
install_dir="$(realpath -m -- "$install_dir")"
case "$install_dir" in
  "$data_home"/*) ;;
  *)
    echo "Installation directory must be inside XDG_DATA_HOME: $data_home" >&2
    exit 64
    ;;
esac
if [[ -e "$install_dir" ]]; then
  if [[ ! -d "$install_dir" ]]; then
    echo "Refusing non-directory installation target: $install_dir" >&2
    exit 73
  fi
  if [[ ! -f "$install_dir/$install_marker" ]] &&
    ! { [[ "$install_dir" == "$data_home/pomodoist" ]] &&
      [[ -x "$install_dir/pomodoist" ]] && [[ -d "$install_dir/data" ]] &&
      [[ -d "$install_dir/lib" ]]; }; then
    echo "Refusing to replace an unowned directory: $install_dir" >&2
    exit 73
  fi
fi

install_parent="$(dirname -- "$install_dir")"
mkdir -p -- "$install_parent" "$bin_home" "$desktop_dir" "$icon_dir"

if [[ -e "$bin_home/pomodoist" && ! -L "$bin_home/pomodoist" ]]; then
  echo "Refusing to replace non-symlink: $bin_home/pomodoist" >&2
  exit 73
fi

stage_dir="$(mktemp -d -- "$install_parent/.pomodoist-install.XXXXXX")"
cleanup() {
  if [[ -n "$stage_dir" && -d "$stage_dir" ]]; then
    find "$stage_dir" -depth -delete
  fi
}
trap cleanup EXIT

cp -a -- "$bundle/." "$stage_dir/"
test -x "$stage_dir/pomodoist"
printf 'Pomodoist Linux user installation\n' > "$stage_dir/$install_marker"

backup_dir=''
if [[ -d "$install_dir" ]]; then
  backup_dir="$(mktemp -d -- "$install_parent/.pomodoist-backup.XXXXXX")"
  rmdir -- "$backup_dir"
  mv -- "$install_dir" "$backup_dir"
fi
if ! mv -- "$stage_dir" "$install_dir"; then
  if [[ -n "$backup_dir" && -d "$backup_dir" ]]; then
    mv -- "$backup_dir" "$install_dir"
  fi
  exit 1
fi
stage_dir=''
if [[ -n "$backup_dir" ]]; then
  find "$backup_dir" -depth -delete
fi

ln -sfn -- "$install_dir/pomodoist" "$bin_home/pomodoist"

escaped_exec="$(printf '%s' "$install_dir/pomodoist" | sed 's/[&|\\]/\\&/g')"
sed "s|@EXECUTABLE@|$escaped_exec|g" \
  "$project_root/linux/packaging/$desktop_id.desktop.in" \
  > "$desktop_dir/$desktop_id.desktop"
chmod 644 "$desktop_dir/$desktop_id.desktop"
install -Dm644 "$project_root/web/icons/Icon-512.png" \
  "$icon_dir/$desktop_id.png"

if command -v update-desktop-database > /dev/null 2>&1; then
  update-desktop-database "$desktop_dir" > /dev/null 2>&1 || true
fi

printf 'Pomodoist installed to %s\n' "$install_dir"
printf 'Launcher: %s\n' "$bin_home/pomodoist"

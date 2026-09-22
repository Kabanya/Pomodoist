#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(cd -- "$script_dir/../.." && pwd -P)"
app_root="$project_root/apps/flutter"

# shellcheck source=tool/linux/flavor.sh
source "$script_dir/flavor.sh"

flavor="$(pomodoist_flavor_name)"
application_id="$(pomodoist_flavor_application_id "$flavor")"
install_name="$(pomodoist_flavor_install_name "$flavor")"
icon_source="$(pomodoist_flavor_icon_path "$flavor" "$app_root")"

bundle="${POMODOIST_LINUX_BUNDLE:-$(pomodoist_flavor_bundle_dir "$flavor" "$app_root")}"
data_home="${XDG_DATA_HOME:-${HOME:?HOME is required}/.local/share}"
bin_home="${XDG_BIN_HOME:-${HOME:?HOME is required}/.local/bin}"
install_dir="${POMODOIST_INSTALL_DIR:-$data_home/$install_name}"
desktop_dir="$data_home/applications"
icon_dir="$data_home/icons/hicolor/512x512/apps"
desktop_id="$application_id"
install_marker='.pomodoist-install'

if [[ ! -x "$bundle/pomodoist" || ! -d "$bundle/data" || ! -d "$bundle/lib" ]]; then
  echo "Invalid Pomodoist Linux bundle: $bundle" >&2
  echo 'Build it first with: make linux-release' >&2
  exit 66
fi

if [[ ! -f "$icon_source" ]]; then
  echo "Flavor icon is missing: $icon_source" >&2
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
    ! { [[ "$install_dir" == "$data_home/$install_name" ]] &&
      [[ -x "$install_dir/pomodoist" ]] && [[ -d "$install_dir/data" ]] &&
      [[ -d "$install_dir/lib" ]]; }; then
    echo "Refusing to replace an unowned directory: $install_dir" >&2
    exit 73
  fi
fi

install_parent="$(dirname -- "$install_dir")"
mkdir -p -- "$install_parent" "$bin_home" "$desktop_dir" "$icon_dir"

if [[ -e "$bin_home/$install_name" && ! -L "$bin_home/$install_name" ]]; then
  echo "Refusing to replace non-symlink: $bin_home/$install_name" >&2
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

ln -sfn -- "$install_dir/pomodoist" "$bin_home/$install_name"

pomodoist_flavor_render_template \
  "$flavor" "$app_root/linux/packaging/app.desktop.in" \
  "$install_dir/pomodoist" '' '' 'pomodoist' \
  > "$desktop_dir/$desktop_id.desktop"
chmod 644 "$desktop_dir/$desktop_id.desktop"
install -Dm644 "$icon_source" \
  "$icon_dir/$desktop_id.png"

if command -v update-desktop-database > /dev/null 2>&1; then
  update-desktop-database "$desktop_dir" > /dev/null 2>&1 || true
fi

printf 'Pomodoist installed to %s\n' "$install_dir"
printf 'Flavor: %s (%s)\n' "$flavor" "$application_id"
printf 'Launcher: %s\n' "$bin_home/$install_name"

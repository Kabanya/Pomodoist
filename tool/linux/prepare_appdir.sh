#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(cd -- "$script_dir/../.." && pwd -P)"

bundle="${POMODOIST_LINUX_BUNDLE:-$project_root/build/linux/x64/release/bundle}"
appdir="${POMODOIST_APPDIR:-$project_root/build/linux/appimage/Pomodoist.AppDir}"
version="${POMODOIST_VERSION:-}"
release_date="${POMODOIST_RELEASE_DATE:-}"
plugin_dir="${POMODOIST_GSTREAMER_PLUGIN_DIR:-}"
scanner="${POMODOIST_GSTREAMER_SCANNER:-}"
plugin_search_roots="${POMODOIST_GSTREAMER_PLUGIN_SEARCH_ROOTS:-/usr/lib:/usr/lib64}"
scanner_search_roots="${POMODOIST_GSTREAMER_SCANNER_SEARCH_ROOTS:-/usr/lib:/usr/libexec}"
desktop_id='com.finchforge.pomodoist'

if [[ ! -x "$bundle/pomodoist" || ! -d "$bundle/data" || ! -d "$bundle/lib" ]]; then
  echo "Invalid Pomodoist Linux bundle: $bundle" >&2
  echo 'Build it first with: make build-linux-release' >&2
  exit 66
fi

if [[ -z "$version" ]]; then
  version="$(awk '/^version:[[:space:]]*/ {sub(/^[^:]*:[[:space:]]*/, ""); sub(/\+.*/, ""); print; exit}' "$project_root/pubspec.yaml")"
fi
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
  echo "Invalid Pomodoist version for AppImage metadata: $version" >&2
  exit 64
fi
if [[ -z "$release_date" ]]; then
  release_date="$(git -C "$project_root" show -s --format=%cs HEAD)"
fi
if [[ ! "$release_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "Invalid Pomodoist release date for AppImage metadata: $release_date" >&2
  exit 64
fi

if [[ -z "$plugin_dir" ]] && command -v pkg-config > /dev/null 2>&1; then
  plugin_dir="$(pkg-config --variable=pluginsdir gstreamer-1.0 2>/dev/null || true)"
fi
if [[ -z "$plugin_dir" || ! -d "$plugin_dir" ]]; then
  IFS=':' read -r -a search_roots <<< "$plugin_search_roots"
  for search_root in "${search_roots[@]}"; do
    [[ -d "$search_root" ]] || continue
    plugin_candidate="$(find "$search_root" -type f \
      -path '*/gstreamer-1.0/libgstcoreelements.so' -print -quit \
      2>/dev/null || true)"
    if [[ -n "$plugin_candidate" ]]; then
      plugin_dir="${plugin_candidate%/*}"
      break
    fi
  done
fi
if [[ -z "$plugin_dir" || ! -d "$plugin_dir" ]]; then
  echo 'GStreamer plugin directory is required to package timer sounds.' >&2
  exit 69
fi

if [[ -z "$scanner" ]]; then
  scanner="$plugin_dir/gst-plugin-scanner"
  if [[ ! -x "$scanner" ]] && command -v pkg-config > /dev/null 2>&1; then
    scanner_dir="$(pkg-config --variable=pluginscannerdir gstreamer-1.0 2>/dev/null || true)"
    scanner="$scanner_dir/gst-plugin-scanner"
  fi
fi
if [[ ! -x "$scanner" ]]; then
  IFS=':' read -r -a search_roots <<< "$scanner_search_roots"
  for search_root in "${search_roots[@]}"; do
    [[ -d "$search_root" ]] || continue
    scanner="$(find "$search_root" -type f -name gst-plugin-scanner -executable \
      -print -quit 2>/dev/null || true)"
    [[ -n "$scanner" ]] && break
  done
fi
if [[ ! -x "$scanner" ]]; then
  echo "GStreamer plugin scanner is missing: $scanner" >&2
  exit 69
fi

gstreamer_plugins=(
  libgstaudioconvert.so
  libgstaudiofx.so
  libgstaudioresample.so
  libgstautodetect.so
  libgstcoreelements.so
  libgstplayback.so
  libgstpulseaudio.so
  libgsttypefindfunctions.so
  libgstvolume.so
  libgstwavparse.so
)
for plugin in "${gstreamer_plugins[@]}"; do
  if [[ ! -f "$plugin_dir/$plugin" ]]; then
    echo "Required GStreamer plugin is missing: $plugin_dir/$plugin" >&2
    exit 69
  fi
done

if [[ "$appdir" != /* ]]; then
  appdir="$project_root/$appdir"
fi
appdir="$(realpath -m -- "$appdir")"
case "$appdir" in
  /|"${HOME:-}"|"$project_root")
    echo "Refusing unsafe AppDir path: $appdir" >&2
    exit 64
    ;;
esac
if [[ -d "$appdir" ]] && [[ -n "$(find "$appdir" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
  echo "AppDir must not already contain files: $appdir" >&2
  exit 73
fi

mkdir -p -- \
  "$appdir/usr/bin" \
  "$appdir/usr/lib/pomodoist" \
  "$appdir/usr/lib/gstreamer-1.0" \
  "$appdir/usr/share/applications" \
  "$appdir/usr/share/icons/hicolor/512x512/apps" \
  "$appdir/usr/share/metainfo"

cp -a -- "$bundle/." "$appdir/usr/lib/pomodoist/"
ln -s -- '../lib/pomodoist/pomodoist' "$appdir/usr/bin/pomodoist"
install -Dm755 "$project_root/linux/packaging/AppRun" "$appdir/AppRun"

sed 's|@EXECUTABLE@|pomodoist|g' \
  "$project_root/linux/packaging/$desktop_id.desktop.in" \
  > "$appdir/$desktop_id.desktop"
install -Dm644 "$appdir/$desktop_id.desktop" \
  "$appdir/usr/share/applications/$desktop_id.desktop"

install -Dm644 "$project_root/web/icons/Icon-512.png" \
  "$appdir/$desktop_id.png"
install -Dm644 "$project_root/web/icons/Icon-512.png" \
  "$appdir/usr/share/icons/hicolor/512x512/apps/$desktop_id.png"
ln -s -- "$desktop_id.png" "$appdir/.DirIcon"

sed -e "s|@VERSION@|$version|g" -e "s|@RELEASE_DATE@|$release_date|g" \
  "$project_root/linux/packaging/$desktop_id.metainfo.xml.in" \
  > "$appdir/usr/share/metainfo/$desktop_id.appdata.xml"

for plugin in "${gstreamer_plugins[@]}"; do
  install -Dm755 "$plugin_dir/$plugin" \
    "$appdir/usr/lib/gstreamer-1.0/$plugin"
done
install -Dm755 "$scanner" \
  "$appdir/usr/lib/gstreamer-1.0/gst-plugin-scanner"

printf 'Prepared Pomodoist AppDir at %s\n' "$appdir"

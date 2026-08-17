#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT

bundle="$test_root/release bundle"
appdir="$test_root/Pomodoist AppDir"
plugin_search_root="$test_root/plugin root"
plugin_dir="$plugin_search_root/usr/lib/x86_64-linux-gnu/gstreamer-1.0"
scanner_search_root="$test_root/scanner root"
scanner_dir="$scanner_search_root/usr/lib/x86_64-linux-gnu/gstreamer1.0"
fake_bin="$test_root/fake bin"

mkdir -p -- "$bundle/data" "$bundle/lib" "$plugin_dir" "$scanner_dir" "$fake_bin"
printf '#!/usr/bin/env sh\n' > "$bundle/pomodoist"
printf 'printf "argument=%%s\\n" "$1"\n' >> "$bundle/pomodoist"
printf 'printf "appdir=%%s\\n" "$APPDIR"\n' >> "$bundle/pomodoist"
printf 'printf "ld-library-path=%%s\\n" "$LD_LIBRARY_PATH"\n' >> "$bundle/pomodoist"
printf 'printf "gst-plugin-path=%%s\\n" "$GST_PLUGIN_SYSTEM_PATH_1_0"\n' >> "$bundle/pomodoist"
chmod 755 "$bundle/pomodoist"
printf 'asset\n' > "$bundle/data/example.txt"
printf 'library\n' > "$bundle/lib/example.so"

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
  printf 'plugin %s\n' "$plugin" > "$plugin_dir/$plugin"
done
printf '#!/usr/bin/env sh\nexit 0\n' > "$scanner_dir/gst-plugin-scanner"
chmod 755 "$scanner_dir/gst-plugin-scanner"
printf '#!/usr/bin/env sh\nprintf "/missing/scanner/directory\\n"\n' \
  > "$fake_bin/pkg-config"
chmod 755 "$fake_bin/pkg-config"

PATH="$fake_bin:$PATH" \
POMODOIST_LINUX_BUNDLE="$bundle" \
POMODOIST_APPDIR="$appdir" \
POMODOIST_VERSION=1.0.0 \
POMODOIST_RELEASE_DATE=2026-08-17 \
POMODOIST_GSTREAMER_PLUGIN_SEARCH_ROOTS="$plugin_search_root" \
POMODOIST_GSTREAMER_SCANNER_SEARCH_ROOTS="$scanner_search_root" \
  "$script_dir/prepare_appdir.sh"

test -x "$appdir/AppRun"
test -x "$appdir/usr/lib/pomodoist/pomodoist"
test "$(cat "$appdir/usr/lib/pomodoist/data/example.txt")" = 'asset'
test "$(cat "$appdir/usr/lib/pomodoist/lib/example.so")" = 'library'
test -L "$appdir/usr/bin/pomodoist"
test "$(readlink "$appdir/usr/bin/pomodoist")" = '../lib/pomodoist/pomodoist'

desktop_file="$appdir/com.finchforge.pomodoist.desktop"
metadata_file="$appdir/usr/share/metainfo/com.finchforge.pomodoist.appdata.xml"
test -f "$desktop_file"
test -f "$appdir/com.finchforge.pomodoist.png"
test -f "$appdir/usr/share/applications/com.finchforge.pomodoist.desktop"
test -f "$appdir/usr/share/icons/hicolor/512x512/apps/com.finchforge.pomodoist.png"
grep -Fqx 'Exec="pomodoist" %u' "$desktop_file"
grep -Fq '<release version="1.0.0" date="2026-08-17"/>' "$metadata_file"
desktop-file-validate "$desktop_file"
appstreamcli validate --no-net "$metadata_file"

for plugin in "${gstreamer_plugins[@]}"; do
  test -f "$appdir/usr/lib/gstreamer-1.0/$plugin"
done
test -x "$appdir/usr/lib/gstreamer-1.0/gst-plugin-scanner"

runtime_output="$(
  env -u APPDIR -u LD_LIBRARY_PATH -u GST_PLUGIN_SYSTEM_PATH_1_0 \
    "$appdir/AppRun" 'pomodoist://focus'
)"
grep -Fqx 'argument=pomodoist://focus' <<< "$runtime_output"
grep -Fqx "appdir=$appdir" <<< "$runtime_output"
grep -Fqx \
  "ld-library-path=$appdir/usr/lib/pomodoist/lib:$appdir/usr/lib" \
  <<< "$runtime_output"
grep -Fqx "gst-plugin-path=$appdir/usr/lib/gstreamer-1.0" <<< "$runtime_output"

invalid_appdir="$test_root/invalid AppDir"
if POMODOIST_LINUX_BUNDLE="$test_root/missing bundle" \
  POMODOIST_APPDIR="$invalid_appdir" \
  POMODOIST_VERSION=1.0.0 \
  POMODOIST_RELEASE_DATE=2026-08-17 \
  POMODOIST_GSTREAMER_PLUGIN_DIR="$plugin_dir" \
  "$script_dir/prepare_appdir.sh" > /dev/null 2>&1; then
  echo 'prepare_appdir.sh unexpectedly accepted a missing Flutter bundle' >&2
  exit 1
fi
test ! -e "$invalid_appdir"

printf '#!/usr/bin/env bash\nexit 128\n' > "$fake_bin/git"
printf '#!/usr/bin/env bash\nexit 0\n' > "$fake_bin/linuxdeploy"
printf '#!/usr/bin/env bash\n' > "$fake_bin/appimagetool"
printf 'test "${SOURCE_DATE_EPOCH:-}" = "1786924800"\n' >> "$fake_bin/appimagetool"
printf 'case " $* " in *" --no-appstream "*) ;; *) exit 2 ;; esac\n' \
  >> "$fake_bin/appimagetool"
printf 'output="${@: -1}"\n: > "$output"\nchmod 755 "$output"\n' \
  >> "$fake_bin/appimagetool"
chmod 755 "$fake_bin/git" "$fake_bin/linuxdeploy" "$fake_bin/appimagetool"
printf 'runtime\n' > "$test_root/runtime-x86_64"

source_archive_output="$test_root/source archive output"
env -u SOURCE_DATE_EPOCH \
PATH="$fake_bin:$PATH" \
POMODOIST_LINUX_BUNDLE="$bundle" \
POMODOIST_APPIMAGE_OUTPUT_DIR="$source_archive_output" \
POMODOIST_VERSION=1.0.0 \
POMODOIST_RELEASE_DATE=2026-08-17 \
POMODOIST_GSTREAMER_PLUGIN_DIR="$plugin_dir" \
POMODOIST_GSTREAMER_SCANNER="$scanner_dir/gst-plugin-scanner" \
POMODOIST_LINUXDEPLOY="$fake_bin/linuxdeploy" \
POMODOIST_APPIMAGETOOL="$fake_bin/appimagetool" \
POMODOIST_APPIMAGE_RUNTIME="$test_root/runtime-x86_64" \
  "$script_dir/build_appimage.sh"
test -x "$source_archive_output/Pomodoist-x86_64.AppImage"
(
  cd -- "$source_archive_output"
  sha256sum --check Pomodoist-x86_64.AppImage.sha256
)

echo 'Linux AppImage AppDir contract passed.'

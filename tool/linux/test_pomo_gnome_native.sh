#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
tmp="$(mktemp -d --suffix=' space')"
trap 'rm -rf -- "$tmp"' EXIT
native="$root/apps/flutter/third_party/multiview_desktop/linux"
engine="${FLUTTER_ENGINE_DIR:-$root/apps/flutter/linux/flutter/ephemeral}"
export CXX="${CXX:-clang++}"
"${CXX:-c++}" -std=c++17 -Wall -Wextra -Werror "$native/tests/pomo_gnome_policy_test.cc" -o "$tmp/policy"
"$tmp/policy"
"${CXX:-c++}" -std=c++17 -Wall -Wextra -Werror $(pkg-config --cflags gtk+-3.0 gio-2.0) -I"$engine" \
  "$native/tests/pomo_gnome_bridge_test.cc" "$native/mvd_linux_gnome.cc" \
  -L"$engine" -Wl,-rpath,"$engine" -lflutter_linux_gtk $(pkg-config --libs gtk+-3.0 gio-2.0) -o "$tmp/bridge"
mkdir -p "$tmp/schemas"
cat > "$tmp/schemas/org.gnome.shell.gschema.xml" <<'SCHEMA'
<schemalist><schema id="org.gnome.shell" path="/org/gnome/shell/">
<key name="enabled-extensions" type="as"><default>['keep@example.com']</default></key>
<key name="disable-user-extensions" type="b"><default>false</default></key>
</schema></schemalist>
SCHEMA
glib-compile-schemas "$tmp/schemas"
GSETTINGS_SCHEMA_DIR="$tmp/schemas" GSETTINGS_BACKEND=memory "$tmp/bridge"
"${CXX:-c++}" -std=c++17 -Wall -Wextra -Werror -ffunction-sections -fdata-sections \
  $(pkg-config --cflags gtk+-3.0 gtk-layer-shell-0 wayland-client epoxy) -I"$engine" -I"$native/include" \
  "$native/tests/pomo_gnome_constraints_test.cc" "$native/mvd_linux_window.cc" "$native/mvd_linux_gnome.cc" "$native/mvd_linux_pomo_popup.cc" \
  -Wl,--gc-sections -L"$engine" -Wl,-rpath,"$engine" -lflutter_linux_gtk \
  $(pkg-config --libs gtk+-3.0 gtk-layer-shell-0 wayland-client x11 epoxy) -o "$tmp/constraints"
GSETTINGS_SCHEMA_DIR="$tmp/schemas" GSETTINGS_BACKEND=memory "$tmp/constraints"
printf 'GNOME native policy, private D-Bus bridge and geometry constraint tests passed.\n'

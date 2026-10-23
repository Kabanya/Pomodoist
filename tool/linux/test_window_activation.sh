#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
native="${MVD_NATIVE_SOURCE:-$root/apps/flutter/third_party/multiview_desktop/linux}"
engine="${FLUTTER_ENGINE_DIR:-$root/apps/flutter/linux/flutter/ephemeral}"
binary="${POMO_FOCUS_TEST_BINARY:-$tmp/window_activation_test}"
"${CXX:-c++}" -std=c++17 -Wall -Wextra -Werror -ffunction-sections -fdata-sections \
  $(pkg-config --cflags gtk+-3.0 gtk-layer-shell-0 wayland-client epoxy) -I"$engine" -I"$native/include" -I"$native" \
  "$root/apps/flutter/third_party/multiview_desktop/linux/tests/window_activation_test.cc" \
  "$native/mvd_linux_window.cc" "$native/mvd_linux_gnome.cc" "$native/mvd_linux_pomo_popup.cc" \
  -Wl,--gc-sections -L"$engine" -Wl,-rpath,"$engine" -lflutter_linux_gtk \
  $(pkg-config --libs gtk+-3.0 gtk-layer-shell-0 wayland-client x11 epoxy) -o "$binary"
if [[ "${1:-}" == --run ]]; then
  # Explicit opt-in: use only an authorized graphical test session with xdotool.
  "$binary"
else
  printf 'Native activation test compiled; pass --run in an authorized X11 test session to execute.\n'
fi

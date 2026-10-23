#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
native="$root/apps/flutter/third_party/multiview_desktop/linux"
binary="${POMO_POPUP_TEST_BINARY:-$(mktemp)}"
if [[ -z "${POMO_POPUP_TEST_BINARY:-}" ]]; then trap 'rm -f -- "$binary"' EXIT; fi
sources=("$native/tests/pomo_popup_test.cc")
flags=()
if [[ "${POMO_CAPTURE_BASELINE:-0}" == 1 ]]; then flags+=(-DPOMO_CAPTURE_BASELINE); fi
if [[ "${POMO_POPUP_BASELINE:-0}" == 1 ]]; then flags+=(-DPOMO_POPUP_BASELINE); else sources+=("$native/mvd_linux_pomo_popup.cc"); fi
"${CXX:-c++}" -std=c++17 -Wall -Wextra -Werror "${flags[@]}" $(pkg-config --cflags gtk+-3.0 gtk-layer-shell-0) \
  "${sources[@]}" $(pkg-config --libs gtk+-3.0 gtk-layer-shell-0) -o "$binary"
if [[ "${POMO_POPUP_BUILD_ONLY:-0}" != 1 ]]; then GDK_BACKEND=x11 xvfb-run -a "$binary" --unit; fi

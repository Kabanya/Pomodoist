#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
"${CXX:-c++}" -std=c++17 -Wall -Wextra -Werror \
  "$root/apps/flutter/third_party/multiview_desktop/linux/tests/gl_binding_test.cc" \
  $(pkg-config --cflags --libs gtk+-3.0 epoxy x11) -o "$tmp/gl_binding_test"
GDK_BACKEND=x11 LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a "$tmp/gl_binding_test"

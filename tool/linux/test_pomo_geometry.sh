#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(cd -- "$script_dir/../.." && pwd -P)"
test_dir="$(mktemp -d)"
trap 'rm -rf -- "$test_dir"' EXIT

# This is a pure C++ geometry/identity unit test; it does not build or start Flutter/GTK.
"${CXX:-c++}" -std=c++17 -Wall -Werror \
  "$project_root/apps/flutter/third_party/multiview_desktop/linux/tests/pomo_geometry_test.cc" \
  -o "$test_dir/pomo_geometry_test"
"$test_dir/pomo_geometry_test"
"${CXX:-c++}" -std=c++17 -Wall -Werror \
  "$project_root/apps/flutter/third_party/multiview_desktop/linux/tests/color_test.cc" \
  -o "$test_dir/color_test"
"$test_dir/color_test"
"${CXX:-c++}" -std=c++17 -Wall -Wextra -Werror \
  "$project_root/apps/flutter/third_party/multiview_desktop/linux/tests/pomo_drag_test.cc" \
  -o "$test_dir/pomo_drag_test"
"$test_dir/pomo_drag_test"
printf 'Linux Pomo geometry, identity, color and drag contract unit tests passed.\n'

#!/usr/bin/env bash

# Verifies the Linux flavor identity table and the identifiers the desktop and
# metainfo templates render from it. Every expectation is a literal so the table
# cannot drift from what the packages advertise; the renderer under test is the
# one prepare_appdir.sh and install.sh use.
#
# The script only needs bash and sed, so it runs on the developer workstations as
# well as in CI.

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
app_root="$(cd -- "$script_dir/../.." && pwd -P)/apps/flutter"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT

# shellcheck source=tool/linux/flavor.sh
source "$script_dir/flavor.sh"

expect() {
  local description="$1"
  local expected="$2"
  local actual="$3"
  if [[ "$actual" != "$expected" ]]; then
    printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' \
      "$description" "$expected" "$actual" >&2
    exit 1
  fi
}

expect_line() {
  local description="$1"
  local expected="$2"
  local file="$3"
  if ! grep -Fqx -- "$expected" "$file"; then
    printf 'FAIL: %s\n  expected line: %s\n  in:            %s\n' \
      "$description" "$expected" "$file" >&2
    exit 1
  fi
}

# The identity table, mirroring lib/domain/models/app_flavor.dart.
expect 'development application id' 'com.finchforge.pomodoist.dev' \
  "$(pomodoist_flavor_application_id development)"
expect 'staging application id' 'com.finchforge.pomodoist.stg' \
  "$(pomodoist_flavor_application_id staging)"
expect 'production application id' 'com.finchforge.pomodoist' \
  "$(pomodoist_flavor_application_id production)"

expect 'development display name' 'Pomodoist Dev' \
  "$(pomodoist_flavor_display_name development)"
expect 'staging display name' 'Pomodoist Stg' \
  "$(pomodoist_flavor_display_name staging)"
expect 'production display name' 'Pomodoist' \
  "$(pomodoist_flavor_display_name production)"

expect 'development url scheme' 'pomodoist-dev' \
  "$(pomodoist_flavor_url_scheme development)"
expect 'staging url scheme' 'pomodoist-stg' \
  "$(pomodoist_flavor_url_scheme staging)"
expect 'production url scheme' 'pomodoist' \
  "$(pomodoist_flavor_url_scheme production)"

expect 'development install name' 'pomodoist-dev' \
  "$(pomodoist_flavor_install_name development)"
expect 'staging install name' 'pomodoist-stg' \
  "$(pomodoist_flavor_install_name staging)"
expect 'production install name' 'pomodoist' \
  "$(pomodoist_flavor_install_name production)"

# Production keeps the published artifact name; the other flavors are suffixed.
expect 'development artifact name' 'Pomodoist-Dev-x86_64.AppImage' \
  "$(pomodoist_flavor_artifact_name development)"
expect 'staging artifact name' 'Pomodoist-Stg-x86_64.AppImage' \
  "$(pomodoist_flavor_artifact_name staging)"
expect 'production artifact name' 'Pomodoist-x86_64.AppImage' \
  "$(pomodoist_flavor_artifact_name production)"

# Flavor resolution. make passes POMODOIST_LINUX_BUNDLE, whose path already names
# the flavor, so an unset flavor must not fall back to production silently.
expect 'default flavor' 'production' "$(pomodoist_flavor_name)"
expect 'uppercase flavor' 'staging' "$(POMODOIST_FLAVOR=STAGING pomodoist_flavor_name)"
expect 'POMODOIST_FLAVOR wins' 'development' \
  "$(POMODOIST_FLAVOR=development pomodoist_flavor_name)"
expect 'bundle path selects the flavor' 'staging' \
  "$(POMODOIST_LINUX_BUNDLE=build/flutter/linux/x64/staging/release/bundle \
    pomodoist_flavor_name)"
expect 'unflavored bundle path stays production' 'production' \
  "$(POMODOIST_LINUX_BUNDLE=build/flutter/linux/x64/release/bundle \
    pomodoist_flavor_name)"

if POMODOIST_FLAVOR=bogus pomodoist_flavor_name > /dev/null 2>&1; then
  echo 'FAIL: an unknown flavor was accepted' >&2
  exit 1
fi
if POMODOIST_FLAVOR=staging \
  POMODOIST_LINUX_BUNDLE=build/flutter/linux/x64/production/release/bundle \
  pomodoist_flavor_name > /dev/null 2>&1; then
  echo 'FAIL: a flavor that disagrees with its bundle path was accepted' >&2
  exit 1
fi

# Flutter adds the flavor segment to the build directory, so each flavor reads its
# own bundle. Production also accepts the unflavored path, which is what a build
# without --flavor produces.
expect 'development bundle dir' \
  "$app_root/build/linux/x64/development/release/bundle" \
  "$(pomodoist_flavor_bundle_dir development "$app_root")"
expect 'staging bundle dir' \
  "$app_root/build/linux/x64/staging/release/bundle" \
  "$(pomodoist_flavor_bundle_dir staging "$app_root")"
case "$(pomodoist_flavor_bundle_dir production "$app_root")" in
  "$app_root/build/linux/x64/production/release/bundle" | \
    "$app_root/build/linux/x64/release/bundle") ;;
  *)
    echo 'FAIL: production resolved to an unexpected bundle directory' >&2
    exit 1
    ;;
esac

# The icon build publishes one 512x512 PNG per flavor; production also accepts
# the unflavored file an unflavored web build leaves behind.
expect 'development icon path' "$app_root/web/icons/development/Icon-512.png" \
  "$(POMODOIST_ICON= pomodoist_flavor_icon_path development "$app_root")"
expect 'staging icon path' "$app_root/web/icons/staging/Icon-512.png" \
  "$(POMODOIST_ICON= pomodoist_flavor_icon_path staging "$app_root")"
case "$(POMODOIST_ICON= pomodoist_flavor_icon_path production "$app_root")" in
  "$app_root/web/icons/production/Icon-512.png" | \
    "$app_root/web/icons/Icon-512.png") ;;
  *)
    echo 'FAIL: production resolved to an unexpected icon path' >&2
    exit 1
    ;;
esac
expect 'icon override' '/tmp/other.png' \
  "$(POMODOIST_ICON=/tmp/other.png pomodoist_flavor_icon_path development "$app_root")"

# The rendered files. The desktop file is what a desktop environment reads, so
# every identifying key is checked per flavor.
for flavor in development staging production; do
  application_id="$(pomodoist_flavor_application_id "$flavor")"
  display_name="$(pomodoist_flavor_display_name "$flavor")"
  url_scheme="$(pomodoist_flavor_url_scheme "$flavor")"
  desktop="$test_root/$flavor.desktop"
  metadata="$test_root/$flavor.appdata.xml"

  pomodoist_flavor_render_template \
    "$flavor" "$app_root/linux/packaging/app.desktop.in" \
    '/opt/pomodoist/pomodoist' '1.2.3' '2026-08-17' 'pomodoist' \
    > "$desktop"
  pomodoist_flavor_render_template \
    "$flavor" "$app_root/linux/packaging/app.metainfo.xml.in" \
    'pomodoist' '1.2.3' '2026-08-17' 'pomodoist' \
    > "$metadata"

  if grep -q '@[A-Z_]*@' "$desktop" "$metadata"; then
    echo "FAIL: $flavor templates contain an unsubstituted placeholder" >&2
    grep -n '@[A-Z_]*@' "$desktop" "$metadata" >&2
    exit 1
  fi

  expect_line "$flavor desktop name" "Name=$display_name" "$desktop"
  expect_line "$flavor desktop icon" "Icon=$application_id" "$desktop"
  expect_line "$flavor desktop wm class" "StartupWMClass=$application_id" "$desktop"
  expect_line "$flavor desktop scheme" \
    "MimeType=x-scheme-handler/$url_scheme;" "$desktop"
  expect_line "$flavor desktop exec" 'Exec="/opt/pomodoist/pomodoist" %u' "$desktop"
  expect_line "$flavor desktop type" 'Type=Application' "$desktop"

  expect_line "$flavor metainfo id" "  <id>$application_id</id>" "$metadata"
  expect_line "$flavor metainfo name" "  <name>$display_name</name>" "$metadata"
  expect_line "$flavor metainfo launchable" \
    "  <launchable type=\"desktop-id\">$application_id.desktop</launchable>" \
    "$metadata"
  expect_line "$flavor metainfo release" \
    '    <release version="1.2.3" date="2026-08-17"/>' "$metadata"
done

# The desktop file name and the icon name are the application id, so three
# side-by-side installs never overwrite each other's entries.
if ! grep -q 'desktop_id="$application_id"' "$script_dir/prepare_appdir.sh"; then
  echo 'FAIL: prepare_appdir.sh does not name the desktop file after the application id' >&2
  exit 1
fi
if ! grep -q 'desktop_id="$application_id"' "$script_dir/install.sh"; then
  echo 'FAIL: install.sh does not name the desktop file after the application id' >&2
  exit 1
fi

# The AppDir, install and launcher names must be pairwise distinct, otherwise a
# flavor would replace another flavor's files.
for first in development staging production; do
  for second in development staging production; do
    if [[ "$first" == "$second" ]]; then
      continue
    fi
    for identity in \
      'pomodoist_flavor_install_name' \
      'pomodoist_flavor_artifact_name' \
      'pomodoist_flavor_url_scheme' \
      'pomodoist_flavor_application_id'; do
      if [[ "$($identity "$first")" == "$($identity "$second")" ]]; then
        echo "FAIL: $first and $second share a $identity value" >&2
        exit 1
      fi
    done
  done
done

# The installer and the AppDir builder must render the templates through the
# shared renderer, and the runner must take its title and application id from the
# flavor, so the identity cannot be hardcoded again in one place.
for script in prepare_appdir.sh install.sh; do
  if ! grep -q 'pomodoist_flavor_render_template' "$script_dir/$script"; then
    echo "FAIL: $script does not use the shared template renderer" >&2
    exit 1
  fi
done
if grep -q "com\.finchforge\.pomodoist" "$script_dir/prepare_appdir.sh" \
  "$script_dir/install.sh" "$script_dir/build_appimage.sh"; then
  echo 'FAIL: a packaging script hardcodes the application id' >&2
  exit 1
fi

runner="$app_root/linux/runner/my_application.cc"
for definition in 'APP_DISPLAY_NAME' 'APPLICATION_ID'; do
  if ! grep -q "$definition" "$runner"; then
    echo "FAIL: the runner does not use $definition" >&2
    exit 1
  fi
done
if ! grep -q 'APP_DISPLAY_NAME=' "$app_root/linux/runner/CMakeLists.txt"; then
  echo 'FAIL: the runner CMake does not define APP_DISPLAY_NAME' >&2
  exit 1
fi

echo 'Linux flavor identity contract passed.'

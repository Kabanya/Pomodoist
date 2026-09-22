#!/usr/bin/env bash

# Flavor identity shared by the Linux build, packaging and installer scripts.
#
# The table mirrors lib/domain/models/app_flavor.dart; change both together.
# The flavor is read from POMODOIST_FLAVOR, then FLAVOR (set by make), then
# FLUTTER_APP_FLAVOR (the define Flutter writes into the CMake configuration),
# then the flavor segment of POMODOIST_LINUX_BUNDLE, and falls back to
# production.
#
# This file is sourced, never executed, and only defines functions.

# Prints the flavor name a Flutter Linux bundle path carries, or fails when the
# path is unflavored. Only the exact paths pomodoist_flavor_bundle_dir builds
# are recognized, so an unrelated directory that happens to be named
# "production" cannot select a flavor.
pomodoist_flavor_from_bundle_dir() {
  case "${1:-}" in
    */linux/x64/development/release/bundle) printf '%s' 'development' ;;
    */linux/x64/staging/release/bundle) printf '%s' 'staging' ;;
    */linux/x64/production/release/bundle) printf '%s' 'production' ;;
    *) return 1 ;;
  esac
}

# Prints the normalized flavor name, or fails on an unrecognized one.
#
# POMODOIST_LINUX_BUNDLE is the fallback signal because make passes it to every
# packaging script and its path already names the flavor. A bundle path that
# names another flavor than the resolved one is refused instead of producing an
# artifact whose identity and binary disagree.
pomodoist_flavor_name() {
  local flavor bundle_flavor
  flavor="${POMODOIST_FLAVOR:-${FLAVOR:-${FLUTTER_APP_FLAVOR:-}}}"
  if [[ -z "$flavor" ]]; then
    flavor="$(pomodoist_flavor_from_bundle_dir "${POMODOIST_LINUX_BUNDLE:-}" || true)"
  fi
  flavor="$(printf '%s' "${flavor:-production}" | tr '[:upper:]' '[:lower:]')"
  case "$flavor" in
    development | staging | production) ;;
    *)
      printf 'Unknown Pomodoist flavor: %s\n' "$flavor" >&2
      return 64
      ;;
  esac
  bundle_flavor="$(pomodoist_flavor_from_bundle_dir "${POMODOIST_LINUX_BUNDLE:-}" || true)"
  if [[ -n "$bundle_flavor" && "$bundle_flavor" != "$flavor" ]]; then
    printf 'Flavor %s does not match the %s bundle: %s\n' \
      "$flavor" "$bundle_flavor" "$POMODOIST_LINUX_BUNDLE" >&2
    return 64
  fi
  printf '%s' "$flavor"
}

# Prints the GTK application identifier of a flavor.
pomodoist_flavor_application_id() {
  case "$1" in
    development) printf '%s' 'com.finchforge.pomodoist.dev' ;;
    staging) printf '%s' 'com.finchforge.pomodoist.stg' ;;
    production) printf '%s' 'com.finchforge.pomodoist' ;;
    *)
      printf 'Unknown Pomodoist flavor: %s\n' "$1" >&2
      return 64
      ;;
  esac
}

# Prints the name shown under the icon and in window titles.
pomodoist_flavor_display_name() {
  case "$1" in
    development) printf '%s' 'Pomodoist Dev' ;;
    staging) printf '%s' 'Pomodoist Stg' ;;
    production) printf '%s' 'Pomodoist' ;;
    *)
      printf 'Unknown Pomodoist flavor: %s\n' "$1" >&2
      return 64
      ;;
  esac
}

# Prints the custom URL scheme deep links are registered under.
pomodoist_flavor_url_scheme() {
  case "$1" in
    development) printf '%s' 'pomodoist-dev' ;;
    staging) printf '%s' 'pomodoist-stg' ;;
    production) printf '%s' 'pomodoist' ;;
    *)
      printf 'Unknown Pomodoist flavor: %s\n' "$1" >&2
      return 64
      ;;
  esac
}

# Prints the name the flavor installs under inside XDG_DATA_HOME and
# XDG_BIN_HOME. The three names are distinct so the installs never overwrite
# each other. They are deliberately not the application identifier: the
# application identifier names the directory the app keeps its database in.
pomodoist_flavor_install_name() {
  case "$1" in
    development) printf '%s' 'pomodoist-dev' ;;
    staging) printf '%s' 'pomodoist-stg' ;;
    production) printf '%s' 'pomodoist' ;;
    *)
      printf 'Unknown Pomodoist flavor: %s\n' "$1" >&2
      return 64
      ;;
  esac
}

# Prints the AppImage file name of a flavor. Production keeps the published
# name; the other flavors are suffixed so both can sit next to it.
pomodoist_flavor_artifact_name() {
  case "$1" in
    development) printf '%s' 'Pomodoist-Dev-x86_64.AppImage' ;;
    staging) printf '%s' 'Pomodoist-Stg-x86_64.AppImage' ;;
    production) printf '%s' 'Pomodoist-x86_64.AppImage' ;;
    *)
      printf 'Unknown Pomodoist flavor: %s\n' "$1" >&2
      return 64
      ;;
  esac
}

# Prints the release bundle directory of a flavor.
#
# Flutter adds a flavor segment to the build directory only when --flavor is
# passed, so a production build without a flavor is accepted from the
# unflavored path. The path is printed even when it is missing, so callers can
# report it in their own error message.
pomodoist_flavor_bundle_dir() {
  local flavor="$1"
  local app_root="$2"
  local flavored="$app_root/build/linux/x64/$flavor/release/bundle"
  local unflavored="$app_root/build/linux/x64/release/bundle"
  if [[ -d "$flavored" ]]; then
    printf '%s' "$flavored"
  elif [[ "$flavor" == production && -d "$unflavored" ]]; then
    printf '%s' "$unflavored"
  else
    printf '%s' "$flavored"
  fi
}

# Prints the 512x512 PNG the Linux packages use as the flavor's icon.
#
# The icon build publishes web/icons/<flavor>/Icon-512.png. Production also
# accepts the unflavored web/icons/Icon-512.png, which is what an unflavored web
# build produces. Set POMODOIST_ICON to package another file, which the packaging
# tests use so they do not depend on the icon build having run. A missing path is
# printed rather than an empty string so callers can report which file they
# expected.
pomodoist_flavor_icon_path() {
  local flavor="$1"
  local app_root="$2"
  local flavored="$app_root/web/icons/$flavor/Icon-512.png"
  local unflavored="$app_root/web/icons/Icon-512.png"
  if [[ -n "${POMODOIST_ICON:-}" ]]; then
    printf '%s' "$POMODOIST_ICON"
  elif [[ -f "$flavored" ]]; then
    printf '%s' "$flavored"
  elif [[ "$flavor" == production && -f "$unflavored" ]]; then
    printf '%s' "$unflavored"
  else
    printf '%s' "$flavored"
  fi
}

# Renders a packaging template with a flavor's identity.
#
# Arguments: flavor, template path, executable, version, release date, binary
# name. The desktop and metainfo templates carry the same placeholders, so one
# renderer keeps them from drifting apart; a placeholder the template does not
# use is simply not substituted. The executable is escaped for sed because it is
# the only value that can come from a path outside this table.
pomodoist_flavor_render_template() {
  local flavor="$1"
  local template="$2"
  local executable="$3"
  local version="$4"
  local release_date="$5"
  local binary_name="$6"

  executable="$(printf '%s' "$executable" | sed 's/[&|\\]/\\&/g')"

  sed -e "s|@APPLICATION_ID@|$(pomodoist_flavor_application_id "$flavor")|g" \
    -e "s|@DISPLAY_NAME@|$(pomodoist_flavor_display_name "$flavor")|g" \
    -e "s|@URL_SCHEME@|$(pomodoist_flavor_url_scheme "$flavor")|g" \
    -e "s|@EXECUTABLE@|$executable|g" \
    -e "s|@VERSION@|$version|g" \
    -e "s|@RELEASE_DATE@|$release_date|g" \
    -e "s|@BINARY_NAME@|$binary_name|g" \
    "$template"
}

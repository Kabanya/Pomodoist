#!/usr/bin/env bash
# Flavor identity shared by the macOS direct-download build and its packaging.
#
# The table mirrors apps/flutter/lib/domain/models/app_flavor.dart and
# tool/windows/flavors.ps1; change all three together. Every value here is
# frozen so a flavor can be recognized by a running build, by its bundle and by
# its .dmg name.
#
# The configuration column is the Direct configuration the build actually runs
# under, e.g. `Release-Direct-Staging`. `build.sh` applies it to xcodebuild,
# because `flutter build macos` has no configuration flag of its own and would
# otherwise build the sandboxed App Store bundle.
#
# The bundle_directory column is where Flutter leaves that bundle. It is derived
# from the raw `--flavor` string, not from the configuration, so it is always
# `Release-<flavor>` - which is why the two columns differ.
#
# This file is sourced, never executed, and only defines data and functions.

# Renders the Xcode configuration for a flavor. The mode is always Direct
# because only the direct-download build is described here.
pomodoist_macos_configuration() {
  case "$1" in
    production) printf 'Release-Direct-Production' ;;
    staging) printf 'Release-Direct-Staging' ;;
    development) printf 'Release-Direct-Development' ;;
    *) return 1 ;;
  esac
}

# Prints one field of a flavor identity. Returns non-zero for an unknown flavor
# or field so a caller under `set -e` stops instead of building a half-identified
# bundle.
pomodoist_macos_flavor_field() {
  local flavor="$1" field="$2"

  case "$flavor" in
    production|staging|development) ;;
    *) return 1 ;;
  esac

  case "$field" in
    display_name)
      case "$flavor" in
        production) printf 'Pomodoist' ;;
        staging) printf 'Pomodoist Stg' ;;
        development) printf 'Pomodoist Dev' ;;
      esac
      ;;
    bundle_id)
      case "$flavor" in
        production) printf 'com.finchforge.pomodoist' ;;
        staging) printf 'com.finchforge.pomodoist.stg' ;;
        development) printf 'com.finchforge.pomodoist.dev' ;;
      esac
      ;;
    url_scheme)
      case "$flavor" in
        production) printf 'pomodoist' ;;
        staging) printf 'pomodoist-stg' ;;
        development) printf 'pomodoist-dev' ;;
      esac
      ;;
    app_group)
      case "$flavor" in
        production) printf 'group.com.pomodoist' ;;
        staging) printf 'group.com.pomodoist.stg' ;;
        development) printf 'group.com.pomodoist.dev' ;;
      esac
      ;;
    entry_point)
      case "$flavor" in
        production) printf 'lib/main.dart' ;;
        staging) printf 'lib/main_staging.dart' ;;
        development) printf 'lib/main_development.dart' ;;
      esac
      ;;
    env_config)
      # Matches the MACOS_<ENVIRONMENT>_CONFIG defaults in the Makefile:
      # production ships the .env.testflight profile, staging .env.staging, and
      # development the local profile.
      case "$flavor" in
        production) printf '.env.testflight' ;;
        staging) printf '.env.staging' ;;
        development) printf '.env.local' ;;
      esac
      ;;
    configuration) pomodoist_macos_configuration "$flavor" ;;
    # Flutter resolves the built bundle through the raw `--flavor` string, so
    # this is `Release-<flavor>` regardless of which configuration built it.
    bundle_directory) printf 'Release-%s' "$flavor" ;;
    # The Xcode scheme Flutter selects, which is the environment name in title
    # case: `Staging`, not `staging`. It names the App Store configuration, which
    # build.sh then overrides; only the case matters here, and only for tools
    # that address the scheme directly rather than through `--flavor`.
    scheme)
      case "$flavor" in
        production) printf 'Production' ;;
        staging) printf 'Staging' ;;
        development) printf 'Development' ;;
      esac
      ;;
    flavors_root) printf 'build/flutter/macos/xcodebuild' ;;
    *)
      return 1
      ;;
  esac
}

# Lists every flavor, one per line, in the order the build should try them.
pomodoist_macos_flavors() {
  printf 'production\nstaging\ndevelopment\n'
}

# Returns the flavor that owns the given entry point, or nothing when no flavor
# claims it. Used to reject a config/entry-point mismatch before Flutter runs.
pomodoist_macos_flavor_for_entry_point() {
  local candidate="$1" flavor
  for flavor in $(pomodoist_macos_flavors); do
    if [[ "$(pomodoist_macos_flavor_field "$flavor" entry_point)" == "$candidate" ]]; then
      printf '%s' "$flavor"
      return 0
    fi
  done
  return 1
}

# Asserts that the named flavor is one this tooling understands, naming the
# accepted values on failure.
pomodoist_macos_require_flavor() {
  local flavor="$1"
  if ! pomodoist_macos_flavor_field "$flavor" bundle_id > /dev/null 2>&1; then
    printf 'Unknown Pomodoist flavor %s. Use production, staging or development.\n' "$flavor" >&2
    return 1
  fi
}

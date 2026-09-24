#!/usr/bin/env bash
# Builds a macOS direct-download distribution: a universal .app inside a .dmg,
# with a SHA-256 sidecar, for download from GitHub Releases.
#
# This is the macOS counterpart of tool/windows/build.ps1. It differs from the
# App Store targets in the Makefile in three ways that matter:
#
#   * Billing is Stripe, not StoreKit. A directly downloaded app is not an App
#     Store purchase, and the app refuses to start when the channel it was
#     built with is missing or contradictory in a release build.
#   * The app is not sandboxed, so it launches without a Mac App Store
#     provisioning profile.
#   * Signing is ad-hoc unless Developer ID credentials are supplied, in which
#     case it signs, notarizes and staples instead. See SIGNING below.
#
# Usage:
#   tool/macos/build.sh [--flavor production|staging|development] [--output DIR]
#
# SIGNING
#
# With no credentials the .dmg is shipped unsigned and Gatekeeper warns about an
# unidentified developer, matching how the Windows installer already ships. Set
# all three of the following to have the script sign with hardened runtime,
# notarize and staple instead:
#
#   POMODOIST_MACOS_SIGNING_IDENTITY  "Developer ID Application: ... (TEAMID)"
#   POMODOIST_MACOS_NOTARY_PROFILE    a `notarytool store-credentials` profile
#
# Nothing else changes: the same command produces either artifact.
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_root=$(cd -- "$script_dir/../.." && pwd -P)
flutter_root="$repo_root/apps/flutter"

# shellcheck source=tool/macos/flavor.sh
. "$script_dir/flavor.sh"

flavor="production"
output_dir=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --flavor)
      flavor="${2:-}"
      shift 2
      ;;
    --output)
      output_dir="${2:-}"
      shift 2
      ;;
    -h|--help)
      sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      exit 64
      ;;
  esac
done

pomodoist_macos_require_flavor "$flavor"

display_name=$(pomodoist_macos_flavor_field "$flavor" display_name)
entry_point=$(pomodoist_macos_flavor_field "$flavor" entry_point)
env_config=$(pomodoist_macos_flavor_field "$flavor" env_config)
scheme=$(pomodoist_macos_flavor_field "$flavor" scheme)
bundle_directory=$(pomodoist_macos_flavor_field "$flavor" bundle_directory)

# CI writes the production profile to a temporary file, because the real
# credentials are repository secrets rather than a committed .env.
env_path="${POMODOIST_MACOS_CONFIG:-$repo_root/$env_config}"
if [[ ! -f "$env_path" ]]; then
  printf 'Missing environment config %s for flavor %s.\n' "$env_path" "$flavor" >&2
  exit 66
fi
if [[ ! -f "$flutter_root/$entry_point" ]]; then
  printf 'Missing entry point %s for flavor %s.\n' "$entry_point" "$flavor" >&2
  exit 66
fi

# The flavor and its entry point must agree, or the app stops at startup with
# "Entrypoint/config mismatch".
declared_flavor=$(pomodoist_macos_flavor_for_entry_point "$entry_point") || {
  printf 'Entry point %s does not belong to any known flavor.\n' "$entry_point" >&2
  exit 65
}
if [[ "$declared_flavor" != "$flavor" ]]; then
  printf 'Flavor %s does not own entry point %s (it belongs to %s).\n' \
    "$flavor" "$entry_point" "$declared_flavor" >&2
  exit 65
fi

# Flutter needs the repository's build/ directory to be the target of the
# project's build and .dart_tool paths.
"$repo_root/tool/link-build.sh"

output_dir="${output_dir:-$repo_root/build/release}"
mkdir -p "$output_dir"

dmg_name="Pomodoist-macOS.dmg"
if [[ "$flavor" != "production" ]]; then
  dmg_name="Pomodoist-macOS-${flavor}.dmg"
fi

printf '==> Building %s (%s) for macOS\n' "$display_name" "$flavor"

# `flutter build macos` drives xcodebuild and, unlike calling xcodebuild
# directly, first assembles the Flutter framework for the chosen configuration.
# Without that step the plugin targets cannot find FlutterMacOS.h.
#
# There is no `--configuration` flag, and `--flavor` is not a way to supply one:
# it selects the Xcode *scheme* of that name, and Flutter reads the
# configuration back out of the scheme's actions. A `--flavor <environment>`
# therefore builds `Release-<Environment>` - sandboxed and StoreKit-billed, the
# opposite of what this script exists to build.
#
# A flavor of its own does not work either, for a reason that only shows up
# after xcodebuild has already succeeded: Flutter resolves the bundle it just
# built from the *raw* `--flavor` string, as `Build/Products/<Mode>-<flavor>/`.
# `--flavor Direct-Staging` sends it looking in `Release-Direct-Staging/` while
# xcodebuild wrote to `Build/Products/Release-Staging/`, and the build fails
# with a missing-path error at the very end.
#
# What does work is Flutter's own escape hatch for Xcode build settings:
# environment variables prefixed `FLUTTER_XCODE_` are forwarded verbatim as
# `k=v` on the xcodebuild command line, where they override the scheme. See
# `environmentVariablesAsXcodeBuildSettings` in the tool's xcodeproj.dart. So
# the flavor stays the plain environment name - which keeps both the scheme and
# Flutter's bundle path resolving - while the entitlements below come from the
# Direct configuration's file.
#
# CODE_SIGN_ENTITLEMENTS is the setting that decides whether the app is
# sandboxed, and it is the one that matters: a sandboxed app is signed against a
# Mac App Store provisioning profile and will not launch for someone who
# downloaded the DMG. Runner/Direct.entitlements is the same file the
# `Release-Direct-<Environment>` configurations use, so the command line and the
# project agree.
#
# POMODOIST_BILLING_CHANNEL is passed as an explicit define as well as through
# the config file, because the file is what .env.testflight fills with storekit
# for the App Store build; the explicit define is applied afterwards and wins.
cd "$flutter_root"
flutter_bin="${POMODOIST_FLUTTER:-flutter}"

# The value must be absolute: xcodebuild resolves it relative to its own build
# directory, not to the project, and silently signs with the project default
# when the path does not resolve.
export FLUTTER_XCODE_CODE_SIGN_ENTITLEMENTS="$flutter_root/macos/Runner/Direct.entitlements"

"$flutter_bin" build macos \
  --release \
  --flavor "$flavor" \
  --target "$entry_point" \
  --dart-define-from-file="$env_path" \
  --dart-define=POMODOIST_BILLING_CHANNEL=stripe

app_path="$flutter_root/build/macos/Build/Products/$bundle_directory/$display_name.app"
if [[ ! -d "$app_path" ]]; then
  printf 'Expected app at %s but it is missing.\n' "$app_path" >&2
  exit 1
fi

printf '==> Verifying the app is not sandboxed\n'
# A positive check for the entitlement that makes a downloaded copy runnable,
# in addition to the negative one below: their absence would mean the override
# never reached xcodebuild, which is exactly the bug this guards against.
entitlements_dump=$(codesign -d --entitlements - "$app_path" 2>/dev/null || true)
if ! grep -q 'com.apple.security.cs.allow-jit' <<< "$entitlements_dump"; then
  printf 'The built app does not carry the Direct entitlements, so the entitlements override did not reach xcodebuild.\n' >&2
  exit 1
fi
if grep -q 'app-sandbox' <<< "$entitlements_dump"; then
  printf 'The built app is sandboxed; a downloaded copy would not launch.\n' >&2
  exit 1
fi

# A signed app can carry a bundle identifier the Xcode project no longer builds
# if the two drift, so it is read back from the project for this flavor rather
# than from flavor.sh - which holds the cross-platform identity table and would
# not notice the Xcode project diverging from it.
show_settings=$(xcodebuild -project "$flutter_root/macos/Runner.xcodeproj" \
  -scheme "$scheme" -configuration "$bundle_directory" -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/^ +PRODUCT_BUNDLE_IDENTIFIER =/ {print $1"="$2}' | sort -u)
expected_bundle_id=$(sed -n 's/^ *PRODUCT_BUNDLE_IDENTIFIER=//p' <<< "$show_settings")

actual_bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
  "$app_path/Contents/Info.plist" 2>/dev/null || true)
if [[ -n "$expected_bundle_id" && "$actual_bundle_id" != "$expected_bundle_id" ]]; then
  printf 'Bundle identifier is %s, but the Xcode project builds %s for %s.\n' \
    "$actual_bundle_id" "$expected_bundle_id" "$flavor" >&2
  exit 1
fi

staging_dir=$(mktemp -d "${TMPDIR:-/tmp}/pomodoist-dmg.XXXXXX")
cleanup() { rm -rf "$staging_dir"; }
trap cleanup EXIT

cp -R "$app_path" "$staging_dir/"
ln -s /Applications "$staging_dir/Applications"

printf '==> Assembling %s\n' "$dmg_name"
dmg_path="$output_dir/$dmg_name"
rm -f "$dmg_path"
hdiutil create \
  -volname "$display_name" \
  -srcfolder "$staging_dir" \
  -ov -format UDZO \
  "$dmg_path" > /dev/null

# Signing, notarization and stapling happen only when credentials are supplied,
# so the same command produces either an unsigned artifact or a notarized one.
signing_identity="${POMODOIST_MACOS_SIGNING_IDENTITY:-}"
notary_profile="${POMODOIST_MACOS_NOTARY_PROFILE:-}"

if [[ -n "$signing_identity" ]]; then
  printf '==> Signing with %s\n' "$signing_identity"
  codesign --force --deep --timestamp --options runtime \
    --sign "$signing_identity" "$app_path"
else
  printf '==> No signing credentials; shipping an unsigned app\n'
  printf '    Gatekeeper will warn about an unidentified developer.\n'
fi

if [[ -n "$signing_identity" && -n "$notary_profile" ]]; then
  printf '==> Notarizing\n'
  xcrun notarytool submit "$dmg_path" \
    --keychain-profile "$notary_profile" \
    --wait
  printf '==> Stapling\n'
  xcrun stapler staple "$dmg_path"
  xcrun stapler validate "$dmg_path"
fi

# The sidecar is written for both a signed and an unsigned artifact, so the
# release gate always finds one. Both the write and the verification happen in
# the output directory, because the sidecar records a bare file name.
(
  cd "$output_dir"
  shasum -a 256 "$dmg_name" | awk '{print $1 "  " $2}' > "$dmg_name.sha256"
  shasum -a 256 -c "$dmg_name.sha256" > /dev/null
)

printf '\nBuilt %s\n' "$dmg_path"
printf 'Checksum %s\n' "$output_dir/$dmg_name.sha256"

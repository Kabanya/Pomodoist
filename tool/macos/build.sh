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
#   * Developer ID signing, notarization and stapling are mandatory.
#
# Usage:
#   tool/macos/build.sh [--flavor production|staging|development] [--output DIR]
#
# SIGNING
#
# Set both credentials before building. No unsigned distribution is produced:
#
#   POMODOIST_MACOS_SIGNING_IDENTITY  "Developer ID Application: ... (TEAMID)"
#   POMODOIST_MACOS_NOTARY_PROFILE    a `notarytool store-credentials` profile
#
# The identity must already be installed with its private key in the Keychain.
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

signing_identity="${POMODOIST_MACOS_SIGNING_IDENTITY:-}"
notary_profile="${POMODOIST_MACOS_NOTARY_PROFILE:-}"
if [[ "$signing_identity" != 'Developer ID Application: '* || -z "$notary_profile" ]]; then
  printf 'Developer ID Application signing identity and notary profile are required.\n' >&2
  exit 64
fi
if ! security find-identity -v -p codesigning | grep -Fq -- "\"$signing_identity\""; then
  printf 'The Developer ID Application identity and private key are missing from the Keychain.\n' >&2
  exit 66
fi
xcrun notarytool history --keychain-profile "$notary_profile" > /dev/null

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
output_dir=$(cd -- "$output_dir" && pwd -P)

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
# Compile without App Store provisioning; the staged copy gets Developer ID.
export FLUTTER_XCODE_CODE_SIGN_IDENTITY='-'
export FLUTTER_XCODE_CODE_SIGN_STYLE=Manual
export FLUTTER_XCODE_DEVELOPMENT_TEAM=''
export FLUTTER_XCODE_PROVISIONING_PROFILE_SPECIFIER=''
export FLUTTER_XCODE_ARCHS='arm64 x86_64'
export FLUTTER_XCODE_ONLY_ACTIVE_ARCH=NO

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

staged_app="$staging_dir/$display_name.app"
# The App Store widget needs its shared container and is omitted from the DMG.
rm -rf "$staged_app/Contents/PlugIns/PomodoistFocusWidgetExtension.appex"
rm -f "$staged_app/Contents/embedded.provisionprofile"

printf '==> Signing with %s\n' "$signing_identity"
# Sign nested code inside out, preserving the main app's Direct entitlements.
while IFS= read -r -d '' binary; do
  if file -b "$binary" | grep -q 'Mach-O'; then
    archs=$(lipo -archs "$binary")
    if [[ "$archs" != *arm64* || "$archs" != *x86_64* ]]; then
      printf 'Missing universal architectures in %s: %s\n' "$binary" "$archs" >&2
      exit 1
    fi
    codesign --force --timestamp --options runtime --sign "$signing_identity" "$binary"
  fi
done < <(find "$staged_app" -type f -print0)
while IFS= read -r -d '' framework; do
  codesign --force --timestamp --options runtime --sign "$signing_identity" "$framework"
done < <(find "$staged_app" -depth -type d -name '*.framework' -print0)
codesign --force --timestamp --options runtime \
  --entitlements "$flutter_root/macos/Runner/Direct.entitlements" \
  --sign "$signing_identity" "$staged_app"
codesign --verify --deep --strict "$staged_app"

printf '==> Assembling %s\n' "$dmg_name"
dmg_path="$output_dir/$dmg_name"
rm -f "$dmg_path" "$dmg_path.sha256"
hdiutil create \
  -volname "$display_name" \
  -srcfolder "$staging_dir" \
  -ov -format UDZO \
  "$dmg_path" > /dev/null

codesign --force --timestamp --sign "$signing_identity" "$dmg_path"
printf '==> Notarizing\n'
xcrun notarytool submit "$dmg_path" \
  --keychain-profile "$notary_profile" \
  --no-wait --no-progress --output-format plist > "$output_dir/notarization-submission.plist"
submission_id=$(/usr/libexec/PlistBuddy -c 'Print :id' "$output_dir/notarization-submission.plist")
printf 'Notarization submission: %s\n' "$submission_id"
# Keep the submission ID if Apple's client fails while waiting; never re-upload
# an existing submission just to recover its result.
xcrun notarytool wait "$submission_id" \
  --keychain-profile "$notary_profile" \
  --no-progress --output-format plist > "$output_dir/notarization.plist"
notary_status=$(/usr/libexec/PlistBuddy -c 'Print :status' "$output_dir/notarization.plist")
if [[ "$notary_status" != Accepted ]]; then
  printf 'Notarization status: %s\n' "$notary_status" >&2
  xcrun notarytool log "$submission_id" --keychain-profile "$notary_profile" \
    "$output_dir/notarization-log.json"
  exit 1
fi
printf '==> Stapling\n'
xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"

# Write the release checksum only after notarization and stapling succeed.
(
  cd "$output_dir"
  shasum -a 256 "$dmg_name" | awk '{print $1 "  " $2}' > "$dmg_name.sha256"
  shasum -a 256 -c "$dmg_name.sha256" > /dev/null
)

printf '\nBuilt %s\n' "$dmg_path"
printf 'Checksum %s\n' "$output_dir/$dmg_name.sha256"

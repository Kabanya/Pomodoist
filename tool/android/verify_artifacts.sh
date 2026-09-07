#!/usr/bin/env bash
# Verify signatures and identity, not just the presence of output files.
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$repo_root"
sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
if [[ -z "$sdk" || ! -d "$sdk/build-tools" ]]; then
  echo 'ANDROID_HOME or ANDROID_SDK_ROOT must point to an Android SDK.' >&2
  exit 64
fi
build_tools=$(find "$sdk/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)
apk=build/app/outputs/flutter-apk/app-release.apk
bundle=build/app/outputs/bundle/release/app-release.aab
test -s "$apk" && test -s "$bundle"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
"$build_tools/apksigner" verify --verbose --print-certs "$apk" > "$work/apk.txt"
if grep -qi 'CN=Android Debug' "$work/apk.txt"; then
  echo 'Refusing an APK signed with an Android Debug certificate.' >&2
  exit 1
fi
"$build_tools/aapt" dump badging "$apk" > "$work/badging.txt"
grep -q "^package: name='com.finchforge.pomodoist' " "$work/badging.txt"
if grep -q '^application-debuggable' "$work/badging.txt"; then
  echo 'The release APK must not be debuggable.' >&2
  exit 1
fi
jarsigner -J-Duser.language=en -J-Duser.country=US -verify "$bundle" > "$work/bundle.txt" 2>&1
# jarsigner can exit successfully for unsigned archives, so inspect its result.
grep -q 'jar verified\.' "$work/bundle.txt"
if grep -qi 'unsigned entries' "$work/bundle.txt"; then
  echo 'The AAB contains entries that are not integrity-checked.' >&2
  exit 1
fi
keytool -J-Duser.language=en -J-Duser.country=US -printcert -jarfile "$bundle" > "$work/cert.txt"
apk_sha=$(sed -n 's/^Signer #1 certificate SHA-256 digest: //p' "$work/apk.txt" | tr -d ':[:space:]' | tr '[:lower:]' '[:upper:]')
bundle_sha=$(sed -n 's/^[[:space:]]*SHA256:[[:space:]]*//p' "$work/cert.txt" | head -n 1 | tr -d ':[:space:]' | tr '[:lower:]' '[:upper:]')
if [[ ! "$apk_sha" =~ ^[0-9A-F]{64}$ || "$apk_sha" != "$bundle_sha" ]]; then
  echo 'APK and AAB must use the same signing certificate.' >&2
  exit 1
fi
if [[ -n "${ANDROID_SIGNING_CERT_SHA256:-}" ]]; then
  expected=$(printf '%s' "$ANDROID_SIGNING_CERT_SHA256" | tr -d ':[:space:]' | tr '[:lower:]' '[:upper:]')
  if [[ "$apk_sha" != "$expected" ]]; then
    echo 'The release signing certificate does not match ANDROID_SIGNING_CERT_SHA256.' >&2
    exit 1
  fi
fi
printf 'Verified APK/AAB identity and signatures. Certificate SHA-256: %s\n' "$apk_sha"

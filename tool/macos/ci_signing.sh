#!/usr/bin/env bash
# Run a CI build with a temporary Developer ID identity and notary profile.
set -euo pipefail
build_umask=$(umask)
umask 077

for name in RUNNER_TEMP POMODOIST_MACOS_CERTIFICATE_P12_BASE64 \
  POMODOIST_MACOS_CERTIFICATE_PASSWORD POMODOIST_MACOS_SIGNING_IDENTITY \
  POMODOIST_MACOS_NOTARY_PROFILE ASC_KEY_ID ASC_ISSUER_ID ASC_PRIVATE_KEY_BASE64; do
  if [[ -z "${!name:-}" ]]; then
    printf '%s is required for CI signing.\n' "$name" >&2
    exit 64
  fi
done
if [[ $# -eq 0 || "$POMODOIST_MACOS_SIGNING_IDENTITY" != 'Developer ID Application: '* ]]; then
  printf 'Expected a build command and a Developer ID Application identity.\n' >&2
  exit 64
fi

previous_default=$(security default-keychain -d user | sed 's/^[[:space:]]*"//; s/"$//')
previous_search=()
while IFS= read -r keychain; do
  previous_search+=("$keychain")
done < <(security list-keychains -d user | sed 's/^[[:space:]]*"//; s/"$//')
signing_dir=$(mktemp -d "$RUNNER_TEMP/pomodoist-signing.XXXXXX")
keychain_path="$signing_dir/signing.keychain-db"

cleanup() {
  status=$?
  trap - EXIT
  security default-keychain -d user -s "$previous_default" || status=1
  security list-keychains -d user -s "${previous_search[@]}" || status=1
  if [[ -f "$keychain_path" ]]; then
    security delete-keychain "$keychain_path" || status=1
  fi
  rm -rf "$signing_dir"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

printf '%s' "$POMODOIST_MACOS_CERTIFICATE_P12_BASE64" | base64 --decode > "$signing_dir/certificate.p12"
printf '%s' "$ASC_PRIVATE_KEY_BASE64" | base64 --decode > "$signing_dir/notary.p8"
keychain_password=$(openssl rand -hex 32)
security create-keychain -p "$keychain_password" "$keychain_path"
security set-keychain-settings -lut 21600 "$keychain_path"
security unlock-keychain -p "$keychain_password" "$keychain_path"
security import "$signing_dir/certificate.p12" -k "$keychain_path" \
  -P "$POMODOIST_MACOS_CERTIFICATE_PASSWORD" \
  -T /usr/bin/codesign -T /usr/bin/security > /dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
  -k "$keychain_password" "$keychain_path" > /dev/null
security list-keychains -d user -s "$keychain_path" "${previous_search[@]}"
security default-keychain -d user -s "$keychain_path"
if ! security find-identity -v -p codesigning "$keychain_path" \
  | grep -Fq -- "\"$POMODOIST_MACOS_SIGNING_IDENTITY\""; then
  printf 'The imported certificate does not contain the required Developer ID identity.\n' >&2
  exit 66
fi
xcrun notarytool store-credentials "$POMODOIST_MACOS_NOTARY_PROFILE" \
  --key "$signing_dir/notary.p8" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" \
  --keychain "$keychain_path" > /dev/null
rm -f "$signing_dir/certificate.p12" "$signing_dir/notary.p8"

umask "$build_umask"
"$@"

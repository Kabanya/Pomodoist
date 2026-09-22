#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(cd -- "$script_dir/../.." && pwd -P)"
app_root="$project_root/apps/flutter"

# shellcheck disable=SC1091
source "$script_dir/appimage-tools.env"

# shellcheck source=tool/linux/flavor.sh
source "$script_dir/flavor.sh"

flavor="$(pomodoist_flavor_name)"
artifact_name="$(pomodoist_flavor_artifact_name "$flavor")"

if [[ "$(uname -m)" != x86_64 ]]; then
  echo 'The current AppImage release target is x86_64.' >&2
  exit 69
fi

for command_name in curl date find install realpath sha256sum; do
  if ! command -v "$command_name" > /dev/null 2>&1; then
    echo "Required AppImage build command is missing: $command_name" >&2
    exit 69
  fi
done

bundle="${POMODOIST_LINUX_BUNDLE:-$(pomodoist_flavor_bundle_dir "$flavor" "$app_root")}"
output_dir="${POMODOIST_APPIMAGE_OUTPUT_DIR:-$app_root/build/linux/appimage}"
tool_dir="${POMODOIST_APPIMAGE_TOOL_DIR:-$project_root/build/appimage-tools}"
version="${POMODOIST_VERSION:-}"
release_date="${POMODOIST_RELEASE_DATE:-}"

if [[ -z "$version" ]]; then
  version="$(awk '/^version:[[:space:]]*/ {sub(/^[^:]*:[[:space:]]*/, ""); sub(/\+.*/, ""); print; exit}' "$app_root/pubspec.yaml")"
fi
if [[ -z "$release_date" ]]; then
  release_date="$(git -C "$project_root" show -s --format=%cs HEAD)"
fi

if [[ "$output_dir" != /* ]]; then
  output_dir="$project_root/$output_dir"
fi
if [[ "$tool_dir" != /* ]]; then
  tool_dir="$project_root/$tool_dir"
fi
output_dir="$(realpath -m -- "$output_dir")"
tool_dir="$(realpath -m -- "$tool_dir")"
case "$output_dir" in
  /|"${HOME:-}"|"$project_root")
    echo "Refusing unsafe AppImage output directory: $output_dir" >&2
    exit 64
    ;;
esac

mkdir -p -- "$output_dir" "$tool_dir"

download_verified() {
  local name="$1"
  local url="$2"
  local expected_sha256="$3"
  local destination="$4"
  local temporary

  if [[ -f "$destination" ]] && \
    printf '%s  %s\n' "$expected_sha256" "$destination" | sha256sum --check --status; then
    printf '%s\n' "$destination"
    return
  fi

  temporary="$(mktemp -- "$tool_dir/.${name}.download.XXXXXX")"
  if ! curl --fail --location --retry 3 --retry-all-errors \
    --connect-timeout 20 --max-time 180 --output "$temporary" "$url"; then
    find "$temporary" -delete
    return 1
  fi
  if ! printf '%s  %s\n' "$expected_sha256" "$temporary" | sha256sum --check --status; then
    echo "Checksum verification failed for $name from $url" >&2
    find "$temporary" -delete
    return 65
  fi
  install -m755 "$temporary" "$destination"
  find "$temporary" -delete
  printf '%s\n' "$destination"
}

linuxdeploy="${POMODOIST_LINUXDEPLOY:-}"
if [[ -z "$linuxdeploy" ]]; then
  linuxdeploy="$(download_verified \
    linuxdeploy "$LINUXDEPLOY_URL" "$LINUXDEPLOY_SHA256" \
    "$tool_dir/linuxdeploy-x86_64.AppImage")"
fi

appimagetool="${POMODOIST_APPIMAGETOOL:-}"
if [[ -z "$appimagetool" ]]; then
  appimagetool="$(download_verified \
    appimagetool "$APPIMAGETOOL_URL" "$APPIMAGETOOL_SHA256" \
    "$tool_dir/appimagetool-x86_64.AppImage")"
fi

runtime="${POMODOIST_APPIMAGE_RUNTIME:-}"
if [[ -z "$runtime" ]]; then
  runtime="$(download_verified \
    appimage-runtime "$APPIMAGE_RUNTIME_URL" "$APPIMAGE_RUNTIME_SHA256" \
    "$tool_dir/runtime-x86_64")"
fi

if [[ ! -x "$linuxdeploy" ]]; then
  echo "linuxdeploy is not executable: $linuxdeploy" >&2
  exit 69
fi
if [[ ! -x "$appimagetool" ]]; then
  echo "appimagetool is not executable: $appimagetool" >&2
  exit 69
fi
if [[ ! -r "$runtime" ]]; then
  echo "AppImage runtime is not readable: $runtime" >&2
  exit 69
fi

staging_root="$(mktemp -d -- "$output_dir/.Pomodoist.AppImage.XXXXXX")"
appdir="$staging_root/Pomodoist.AppDir"
cleanup() {
  find "$staging_root" -depth -delete 2>/dev/null || true
}
trap cleanup EXIT

POMODOIST_LINUX_BUNDLE="$bundle" \
POMODOIST_APPDIR="$appdir" \
POMODOIST_FLAVOR="$flavor" \
POMODOIST_VERSION="$version" \
POMODOIST_RELEASE_DATE="$release_date" \
  "$script_dir/prepare_appdir.sh"

NO_STRIP=1 APPIMAGE_EXTRACT_AND_RUN=1 "$linuxdeploy" \
  --appdir "$appdir" \
  --deploy-deps-only "$appdir/usr"

artifact="$output_dir/$artifact_name"
temporary_artifact="$staging_root/$artifact_name"
source_date_epoch="${SOURCE_DATE_EPOCH:-}"
if [[ -z "$source_date_epoch" ]]; then
  if ! source_date_epoch="$(git -C "$project_root" show -s --format=%ct HEAD 2>/dev/null)"; then
    source_date_epoch="$(date --utc --date="$release_date" +%s)"
  fi
fi
if [[ ! "$source_date_epoch" =~ ^[0-9]+$ ]]; then
  echo "Invalid SOURCE_DATE_EPOCH: $source_date_epoch" >&2
  exit 64
fi

ARCH=x86_64 \
VERSION="$version" \
SOURCE_DATE_EPOCH="$source_date_epoch" \
APPIMAGE_EXTRACT_AND_RUN=1 \
  "$appimagetool" \
    --no-appstream \
    --runtime-file "$runtime" \
    --comp zstd \
    "$appdir" \
    "$temporary_artifact"

test -x "$temporary_artifact"
install -m755 "$temporary_artifact" "$artifact"
(
  cd -- "$output_dir"
  sha256sum "$(basename -- "$artifact")" > "$(basename -- "$artifact").sha256"
)

printf 'Built Pomodoist AppImage (%s flavor): %s\n' "$flavor" "$artifact"
printf 'Checksum: %s.sha256\n' "$artifact"

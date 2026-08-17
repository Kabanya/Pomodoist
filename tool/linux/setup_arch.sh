#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(cd -- "$script_dir/../.." && pwd -P)"

if [[ ! -r /etc/os-release ]]; then
  echo 'Cannot identify this Linux distribution: /etc/os-release is missing.' >&2
  exit 69
fi

# shellcheck disable=SC1091
source /etc/os-release
if [[ "${ID:-}" != arch ]]; then
  echo "This setup command targets Arch Linux; detected: ${ID:-unknown}." >&2
  exit 69
fi

packages=(
  appstream
  base-devel
  clang
  cmake
  curl
  desktop-file-utils
  ffmpeg
  git
  gstreamer
  gst-plugins-base
  gst-plugins-good
  gtk3
  jdk17-openjdk
  libpulse
  libsecret
  ninja
  pkgconf
  xdg-utils
)

mapfile -t missing_packages < <(pacman -T "${packages[@]}" 2>/dev/null || true)
if ((${#missing_packages[@]} > 0)); then
  echo 'Missing Arch packages:' >&2
  printf '  %s\n' "${missing_packages[@]}" >&2
  printf 'Install them with:\n  sudo pacman -S --needed' >&2
  printf ' %q' "${packages[@]}" >&2
  printf '\n' >&2
  exit 69
fi

if ! command -v fvm > /dev/null 2>&1; then
  echo 'FVM is required. Install it from the AUR with: yay -S fvm' >&2
  exit 69
fi

cd -- "$project_root"
fvm install --skip-pub-get
fvm use 3.47.0 --force --skip-pub-get
.fvm/flutter_sdk/bin/flutter config --enable-linux-desktop
.fvm/flutter_sdk/bin/flutter pub get

echo 'Arch Linux setup complete. Run: make run-linux'

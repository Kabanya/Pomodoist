#!/usr/bin/env bash
# Flutter always writes to <project>/build and keeps its compile cache in
# <project>/.dart_tool. Both paths are symlinks to the repository-root build
# directory, so every generated artifact lands under build/ and nothing is left
# next to the sources.
#
# The links cannot be tracked in Git: the repository-root build/ directory is
# ignored, so a fresh checkout would restore dangling links that Flutter cannot
# create or remove. Every entry point therefore repairs the paths before
# Flutter runs. Windows uses tool/windows/link-build.ps1 because Git Bash cannot
# create junctions.
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
flutter_root="$repo_root/apps/flutter"

mkdir -p "$repo_root/build/flutter" "$repo_root/build/dart_tool"

# Substitute an existing path with a symlink to its target. A real directory
# left by an earlier Flutter run and a dangling link both have to go, and the
# dangling link is removed with rm -f because rm -rf cannot follow it.
link_path() {
  local path="$1"
  local target="$2"

  if [[ -L "$path" ]]; then
    [[ "$(readlink "$path")" == "$target" ]] && return 0
    rm -f "$path"
  elif [[ -e "$path" ]]; then
    rm -rf "$path"
  fi

  ln -s "$target" "$path"
}

link_path "$flutter_root/build" '../../build/flutter'
link_path "$flutter_root/.dart_tool" '../../build/dart_tool'

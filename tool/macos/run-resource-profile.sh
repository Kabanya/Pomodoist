#!/bin/sh
set -eu

repo_root=$(cd "$(dirname "$0")/../.." && pwd -P)
export XDG_CONFIG_HOME="$repo_root/build/profile-harness-config"
mkdir -p "$XDG_CONFIG_HOME"
# Scope Flutter's build directory setting to this invocation.
printf '%s\n' '{"build-dir":"build/profile-harness"}' > "$XDG_CONFIG_HOME/settings"

cd "$repo_root/apps/flutter"
exec "$repo_root/.fvm/flutter_sdk/bin/flutter" run --profile -d macos --flavor staging \
  --target tool/pomo_resource_profile.dart --host-vmservice-port "${1:-55291}"

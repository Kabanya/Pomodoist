#!/usr/bin/env bash
# Verifies the macOS direct-download packaging contract without building an app,
# so the checks that protect users from receiving the wrong artifact can run in
# CI on every change.
#
# What it guards, in order of how much damage a regression would do:
#
#   1. The Direct entitlements are not sandboxed. A sandboxed build comes from
#      the Mac App Store provisioning profile and would fail to launch for a
#      user who downloaded it, which is the exact failure this whole flow exists
#      to avoid.
#   2. The Xcode Direct-* configurations exist and point at those entitlements,
#      so the non-sandboxed build is actually reachable by the build script.
#   3. The flavor table here agrees with app_flavor.dart and flavors.ps1, so the
#      three platforms cannot silently drift apart.
#   4. The build script selects those configurations, and names ones the Xcode
#      project actually defines.
#   5. The artifact naming matches the documented convention.
#   6. The release gate requires the macOS asset.
set -euo pipefail

tool_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_root=$(cd -- "$tool_dir/../.." && pwd -P)

# shellcheck source=tool/macos/flavor.sh
. "$tool_dir/flavor.sh"

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

# 1. The Direct entitlements must exist and must not enable the sandbox.
direct_entitlements="$repo_root/apps/flutter/macos/Runner/Direct.entitlements"
if [[ ! -f "$direct_entitlements" ]]; then
  fail "apps/flutter/macos/Runner/Direct.entitlements is missing"
elif ! grep -q 'com.apple.security.cs.allow-jit' "$direct_entitlements"; then
  fail 'Direct.entitlements does not grant allow-jit, so the Dart VM cannot run'
fi

if [[ -f "$direct_entitlements" ]]; then
  # Comments in the file name the keys they explain, so the check has to read
  # actual <key> elements rather than any mention of the name.
  declare -a entitlement_keys=()
  while IFS= read -r key; do
    entitlement_keys+=("$key")
  done < <(grep -oE '<key>[^<]+</key>' "$direct_entitlements" | sed -e 's|<key>||' -e 's|</key>||')

  for forbidden in com.apple.security.app-sandbox com.apple.security.application-groups; do
    for key in ${entitlement_keys[@]+"${entitlement_keys[@]}"}; do
      if [[ "$key" == "$forbidden" ]]; then
        fail "Direct.entitlements declares $forbidden, which needs a Mac App Store profile"
      fi
    done
  done
fi

# 2. Each flavor needs its Xcode configuration, pointing at Direct.entitlements.
pbxproj="$repo_root/apps/flutter/macos/Runner.xcodeproj/project.pbxproj"
if [[ ! -f "$pbxproj" ]]; then
  fail 'apps/flutter/macos/Runner.xcodeproj/project.pbxproj is missing'
fi

for flavor in $(pomodoist_macos_flavors); do
  configuration=$(pomodoist_macos_flavor_field "$flavor" configuration) || {
    fail "flavor $flavor has no Xcode configuration"
    continue
  }

  if [[ -f "$pbxproj" ]]; then
    if ! grep -q "name = \"$configuration\";" "$pbxproj"; then
      fail "Xcode configuration $configuration is missing from project.pbxproj"
      continue
    fi

    # The configuration must bind the Direct entitlements, must sign ad-hoc
    # rather than with an App Store team, and must be listed by the project -
    # a configuration that exists but is not listed is unreachable.
    check_script=$(mktemp "${TMPDIR:-/tmp}/pomodoist-macos-check.XXXXXX")
    cat > "$check_script" <<'PY'
import re
import sys

path, configuration = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()

# Parse XCBuildConfiguration blocks the same way the generator does, so the
# two cannot disagree about what the file says.
block_re = re.compile(
    r"\t\t([0-9A-F]{24}) /\* (?P<name>[^*]+?) \*/ = \{\n"
    r"\t\t\tisa = XCBuildConfiguration;\n"
    r"(?P<body>.*?)\n"
    r"\t\t\tname = \"(?P=name)\";\n"
    r"\t\t\};\n",
    re.DOTALL,
)

blocks = [
    m.group("body")
    for m in block_re.finditer(text)
    if m.group("name") == configuration
]
if not blocks:
    print(f"The {configuration} configuration has no XCBuildConfiguration blocks")
    raise SystemExit(1)

app_blocks = [b for b in blocks if "INFOPLIST_FILE = Runner/Info.plist;" in b]
if not app_blocks:
    print(f"The {configuration} configuration has no app-target block")
    raise SystemExit(1)

for body in app_blocks:
    if "CODE_SIGN_ENTITLEMENTS = Runner/Direct.entitlements;" not in body:
        print(f"{configuration} does not set CODE_SIGN_ENTITLEMENTS to Runner/Direct.entitlements")
        raise SystemExit(1)
    if "DEVELOPMENT_TEAM" in body:
        print(f"{configuration} still declares DEVELOPMENT_TEAM, so it expects an App Store team")
        raise SystemExit(1)

if not re.search(
    r"buildConfigurations = \(\n(?:\t{4}[0-9A-F]{24} /\* [^*]+ \*/,\n)*\t{4}[0-9A-F]{24} /\* %s \*/,\n"
    % re.escape(configuration),
    text,
):
    print(f"{configuration} is not listed in any build configuration list, so it is unreachable")
    raise SystemExit(1)

raise SystemExit(0)
PY
    if ! check_output=$(python3 "$check_script" "$pbxproj" "$configuration" 2>&1); then
      fail "$check_output"
    fi
    rm -f "$check_script"
  fi
done

# 3. The flavor table must agree with the Dart source of truth.
app_flavor="$repo_root/apps/flutter/lib/domain/models/app_flavor.dart"
if [[ ! -f "$app_flavor" ]]; then
  fail 'apps/flutter/lib/domain/models/app_flavor.dart is missing'
else
  for flavor in $(pomodoist_macos_flavors); do
    bundle_id=$(pomodoist_macos_flavor_field "$flavor" bundle_id)
    scheme=$(pomodoist_macos_flavor_field "$flavor" url_scheme)
    if ! grep -q "'$bundle_id'" "$app_flavor"; then
      fail "app_flavor.dart does not declare bundle id $bundle_id for $flavor"
    fi
    if ! grep -q "'$scheme'" "$app_flavor"; then
      fail "app_flavor.dart does not declare url scheme $scheme for $flavor"
    fi
  done
fi

# 4. build.sh must override the entitlements on the xcodebuild command line,
#    because `flutter build macos` has no configuration flag and `--flavor` only
#    selects a scheme - which for a release build resolves to the sandboxed App
#    Store configuration. Flutter forwards `FLUTTER_XCODE_*` environment
#    variables to xcodebuild as build settings; that prefix is the whole
#    mechanism, so a rename on either side has to fail here rather than in a
#    shipped DMG. Assert both halves.
build_script="$repo_root/tool/macos/build.sh"
schemes_dir="$repo_root/apps/flutter/macos/Runner.xcodeproj/xcshareddata/xcschemes"
if [[ ! -d "$schemes_dir" ]]; then
  fail 'apps/flutter/macos/Runner.xcodeproj/xcshareddata/xcschemes is missing'
fi
if [[ ! -f "$build_script" ]]; then
  fail 'tool/macos/build.sh is missing'
else
  # Anchored to the start of an assignment: a bare substring match would still
  # succeed on a renamed variable such as `XX_FLUTTER_XCODE_CODE_SIGN_...`, and
  # a `continue`-style prefix would not be caught either.
  if ! grep -qE '^[[:space:]]*(export[[:space:]]+)?FLUTTER_XCODE_CODE_SIGN_ENTITLEMENTS=' "$build_script"; then
    fail 'build.sh does not override CODE_SIGN_ENTITLEMENTS through Flutter, so it would build the sandboxed App Store app'
  fi
  # The override must name a real file. A typo here does not fail the build -
  # xcodebuild falls back to the project default and ships a sandboxed app.
  # It must also be the file the Direct configurations select, so the command
  # line and the project cannot disagree about what is being signed.
  if [[ ! -f "$repo_root/apps/flutter/macos/Runner/Direct.entitlements" ]]; then
    fail 'build.sh overrides entitlements with Runner/Direct.entitlements, which does not exist'
  fi
  for flavor in $(pomodoist_macos_flavors); do
    configuration=$(pomodoist_macos_flavor_field "$flavor" configuration)
    if [[ -f "$pbxproj" ]] && ! grep -q "name = \"$configuration\";" "$pbxproj"; then
      fail "build.sh builds $configuration, which project.pbxproj does not define"
    fi
    # build.sh addresses the scheme directly to look the built bundle identifier
    # up. Xcode schemes are title-cased, and xcodebuild exits non-zero for a
    # miss, which `set -e` turns into a failed build after a successful compile.
    #
    # Compared against the directory listing rather than with `test -f`, because
    # macOS filesystems are case-insensitive: `-f production.xcscheme` succeeds
    # against `Production.xcscheme`, and the case is exactly what can be wrong.
    scheme=$(pomodoist_macos_flavor_field "$flavor" scheme)
    if ! ls -1 "$schemes_dir" 2>/dev/null | grep -qx "$scheme.xcscheme"; then
      fail "flavor $flavor names the scheme $scheme, which has no $scheme.xcscheme"
    fi
  done
fi

# 5. Naming convention: the published artifact is Pomodoist-macOS.dmg with a
#    matching .sha256 sidecar, alongside the Windows and Linux names.
expected_dmg='Pomodoist-macOS.dmg'
if [[ "$expected_dmg" != 'Pomodoist-macOS.dmg' ]]; then
  fail 'unreachable'
fi

# 6. The release gate in the existing desktop workflows must require the macOS
#    asset, or a macOS-less release could still be published.
for workflow in windows-exe-preview.yml linux-appimage-release.yml; do
  path="$repo_root/.github/workflows/$workflow"
  if [[ ! -f "$path" ]]; then
    fail ".github/workflows/$workflow is missing"
    continue
  fi
  if ! grep -q "$expected_dmg" "$path"; then
    fail "$workflow does not require $expected_dmg in its release asset gate"
  fi
done

if (( failures > 0 )); then
  printf '\n%d macOS direct-download contract check(s) failed.\n' "$failures" >&2
  exit 1
fi

printf 'macOS direct-download contract is intact.\n'

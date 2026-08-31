#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

sha=$(awk '
  $0 == "  app_account:" { found = 1; next }
  found && $1 == "ref:" { print $2; exit }
' pubspec.yaml)
printf '%s\n' "$sha" | grep -Eq '^[0-9a-f]{40}$' ||
  fail 'app_account must be pinned to a commit SHA'
url=https://github.com/Kabanya/app-client-platform.git

for package in app_account app_voice; do
  awk -v package="$package" -v sha="$sha" -v url="$url" '
    $0 == "  " package ":" { found = 1; next }
    found && $0 == "      url: " url { has_url = 1 }
    found && $0 == "      ref: " sha { has_ref = 1 }
    found && $0 == "      path: " package { has_path = 1 }
    found && /^  [^[:space:]]+:/ { exit(has_url && has_ref && has_path ? 0 : 1) }
    END { exit(has_url && has_ref && has_path ? 0 : 1) }
  ' pubspec.yaml || fail "$package must use the pinned public Git dependency"
done

[ ! -e .gitmodules ] || fail '.gitmodules must not be published'
! git ls-files account-sync-platform | grep -q . ||
  fail 'private account-sync-platform must not be published'
[ -f test/fixtures/pomodoist_productivity_parity.json ] ||
  fail 'productivity parity fixture must be local'
! grep -q 'account-sync-platform' test/productivity_parity_test.dart ||
  fail 'productivity test must not read the private checkout'
! grep -q 'account-sync-platform' deploy/web/Dockerfile ||
  fail 'Docker build must not copy a private checkout'
! grep -q 'account-sync-platform' tool/prepare_sentry_sourcemaps.dart ||
  fail 'Sentry embedding must be limited to lib/'
! grep -q 'account-sync-platform' tool/verify_sentry_artifacts.py ||
  fail 'Sentry verification must be limited to lib/'
! grep -Eiq 'account-sync-platform|coolify|service.?role|deployment webhook' Makefile ||
  fail 'Makefile must be client-only'
[ -f LICENSING.md ] || fail 'LICENSING.md must document the distribution model'
grep -Fq 'AGPL-3.0-only' LICENSING.md ||
  fail 'LICENSING.md must preserve the public AGPL license'
grep -Fq 'official Pomodoist client binaries' LICENSING.md ||
  fail 'LICENSING.md must cover official client binaries'
grep -Fq 'FinchForge LLC' LICENSING.md ||
  fail 'LICENSING.md must identify the official distributor'
grep -Fq '[licensing model](LICENSING.md)' README.md ||
  fail 'README must link to LICENSING.md'
! git grep -ni 'signpath' -- \
  ':!tool/test_public_boundary.sh' ':!test/workflow_yaml_test.dart' >/dev/null ||
  fail 'tracked public files must not require SignPath'
if grep -Eiq 'Alternative commercial licenses are available|distributed under separate terms|sublicense, relicense|open-source, commercial, or other license terms|Apple Standard EULA' \
  README.md LICENSING.md CLA.md CONTRIBUTING.md; then
  fail 'client licensing documents must not offer proprietary/commercial terms'
fi
! git grep -nF 'PolyForm Noncommercial' -- ':!tool/test_public_boundary.sh' >/dev/null ||
  fail 'tracked public files must not use the former PolyForm license'
for script in tool/export_web_sourcemaps.sh tool/test_sentry_artifacts.sh; do
  grep -q -- '--build-arg POMODOIST_BILLING_CHANNEL=stripe' "$script" ||
    fail "$script must build with the Stripe billing channel"
done
if grep -REn --include='*.yml' --include='*.yaml' \
  '^[[:space:]]*(-[[:space:]]*)?uses:' .github/workflows |
  grep -Ev 'uses:[[:space:]]+(\./[^[:space:]#]+|[^[:space:]#]+@[0-9a-f]{40})([[:space:]]*#.*)?$'; then
  fail 'GitHub Actions must be pinned to full commit SHAs'
fi
! grep -REq --include='*.yml' --include='*.yaml' \
  '^[[:space:]]+flutter-version:' .github/workflows ||
  fail 'workflows must read the Flutter version from .fvmrc'
if git ls-files | grep -Eq '(^|/)(\.codex|\.env[^/]*|key-[^/]+\.md|screenlog\.0|outputs|design|\.superpowers|supabase/\.temp)(/|$)'; then
  fail 'tracked public files contain a forbidden path'
fi
if git grep -qE '(AKIA[0-9A-Z]{16}|-----BEGIN( [A-Z]+)? PRIVATE KEY-----|rk_(live|test)_[0-9A-Za-z]+|sk_(live|test)_[0-9A-Za-z]+|whsec_[0-9A-Za-z]+|sb_secret_[0-9A-Za-z]+|sntrys_[0-9A-Za-z]+|GOCSPX-[0-9A-Za-z_-]{20,})' -- .; then
  fail 'tracked public files contain a secret'
fi
if git ls-files ':!tool/test_public_boundary.sh' | xargs grep -n 'sslip\.io' >/dev/null; then
  fail 'tracked public files must not contain deprecated sslip aliases'
fi
if git ls-files ':!tool/test_public_boundary.sh' | xargs grep -nE '/Users/|/home/' >/dev/null; then
  fail 'tracked public docs and config must not contain personal absolute paths'
fi

printf 'Public boundary checks passed.\n'

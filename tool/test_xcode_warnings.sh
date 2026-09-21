#!/bin/sh
# Guards the macOS build's warning filter: the file the Makefile pipes into has
# to exist, and it has to drop dependency warnings without dropping errors.
set -eu

filter="$(dirname "$0")/xcode-warnings.awk"
fixture="$(mktemp "${TMPDIR:-/tmp}/xcode-warnings.XXXXXX")"
trap 'rm -f "$fixture"' EXIT

cat >"$fixture" <<'TRANSCRIPT'
            /tmp/dev/project/apps/flutter/macos/Flutter/ephemeral/Packages/.packages/in_app_purchase_storekit-0.4.10+1/Sources/in_app_purchase_storekit_objc/include/in_app_purchase_storekit_objc/FIAObjectTranslator.h:14:40: warning: 'SKProduct' is deprecated: first deprecated in iOS 18.0 - Use Product.
               |
            15 | @interface FIAPaymentQueueHandler
               |                 `- warning: 'SKProduct' is deprecated: first deprecated in iOS 18.0 - Use Product.
               :

            42 warnings generated.
            /tmp/dev/.pub-cache/hosted/pub.dev/audioplayers_darwin-6.4.0/darwin/audioplayers_darwin/Sources/audioplayers_darwin/WrappedMediaPlayer.swift:205:14: warning: main actor-isolated property 'eventHandler' can not be referenced from a Sendable closure
            203 |         }
               |              `- warning: main actor-isolated property 'eventHandler' can not be referenced from a Sendable closure

            /tmp/dev/project/apps/flutter/macos/Flutter/ephemeral/Packages/.packages/foo/Sources/foo/Bar.swift:9:1: error: cannot find 'Thing' in scope
            9 | let x = Thing()
              |         ^~~~~

            /tmp/dev/project/apps/flutter/macos/Runner/MainFlutterWindow.swift:41:9: error: value of type 'Runner' has no member 'bogus'

✓ Built build/macos/Build/Products/Debug/Pomodoist.app
TRANSCRIPT

output="$(awk -f "$filter" "$fixture")"

contains() {
  printf '%s\n' "$output" | grep -qF "$1"
}

reject() {
  contains "$1" && { printf 'FAIL: found %s\n' "$1" >&2; return 1; }
  return 0
}

require() {
  contains "$1" && return 0
  printf 'FAIL: missing %s\n' "$1" >&2
  return 1
}

status=0
reject "'SKProduct' is deprecated" || status=1
reject 'FIAPaymentQueueHandler' || status=1
require 'main actor-isolated property' || status=1
require "error: cannot find 'Thing' in scope" || status=1
require "error: value of type 'Runner' has no member 'bogus'" || status=1
require '42 warnings generated.' || status=1
require 'Built build/macos/Build/Products/Debug/Pomodoist.app' || status=1

if [ "$status" -ne 0 ]; then
  printf '%s\n' '--- filtered output ---' "$output" >&2
  exit 1
fi

# The filter has to stay transparent to its exit status, or pipefail turns a
# successful build into a failure.
printf '' | awk -f "$filter" >/dev/null || { printf 'FAIL: empty input\n' >&2; exit 1; }
printf 'last line without newline' | awk -f "$filter" >/dev/null || { printf 'FAIL: unterminated last line\n' >&2; exit 1; }

printf 'xcode-warnings filter: SPM warnings dropped, errors and result kept\n'

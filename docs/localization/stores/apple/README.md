# Apple storefront release

Current preparation status and upload restriction: [1.1.8 readiness](1.1.8-readiness.md).

Use the local macOS release workflow for Pomodoist's iOS and Mac App Store
listings. It uses [asc](https://github.com/rorkai/App-Store-Connect-CLI) (tested
with 6.3.0), Python 3 and the same private team credentials as the TestFlight
Make targets. Install the CLI with `brew install asc`. Set up the existing
`.env.private` and production TestFlight configuration before making remote
changes. The helper gives asc a temporary private key file and removes it at
exit.

The JSON files in this directory own the App Store text. App information is
shared across iOS and macOS. The version descriptions, keywords and what's-new
text use the same source on both platforms. The English promotional copy keeps
the platform-specific wording from version 1.1.7. The Brazilian Portuguese,
Japanese and Korean descriptions started from the existing translation
drafts one level up. Add `whats-new/<version>.json` with all ten locale entries
for each new release.

| App language | App Store Connect |
| --- | --- |
| English | `en-US` |
| Russian | `ru` |
| German | `de-DE` |
| Spanish | `es-ES` |
| French | `fr-FR` |
| Arabic | `ar-SA` |
| Simplified Chinese | `zh-Hans` |
| Brazilian Portuguese | `pt-BR` |
| Japanese | `ja` |
| Korean | `ko` |

## Screenshot input

### Deterministic local generation

Run on macOS with the pinned Flutter SDK. No signing, store credentials or
App Store Connect requests are involved. Install the pinned rendering tools once:

```sh
(cd tool/apple && npm ci && npx playwright install chromium)
(cd apps/flutter && ../../.fvm/flutter_sdk/bin/flutter pub get)
make app-store-assets APP_STORE_ASSET_ARGS="--verify"
```

The default is ten current iPhone screens with English UI and meaningful English
demo work, composed into 100 covers for all ten shipping languages. Outputs are
under `output/app-store-screenshots/`: `index.html`, `covers.zip`, `manifest.json`,
`raw/iphone/en-US/` and `iphone/<locale>/`. The cover text comes from the existing
ARB translations. `--verify` captures and renders twice in separate temporary
directories and requires identical PNG hashes and text provenance before
replacing outputs. ZIP timestamps and ordering are fixed too.

```sh
# Other Flutter platforms, also across all ten cover languages.
make app-store-assets APP_STORE_ASSET_ARGS="--devices iphone,ipad,mac --verify"

# App UI in each cover's language; demo task/project content stays English.
make app-store-assets APP_STORE_ASSET_ARGS="--ui-locale localized --verify"

# A quick English-only check, written separately from the complete matrix.
make app-store-assets APP_STORE_ASSET_ARGS="--locales en-US --output /tmp/pomodoist-english"
```

`tool/apple/store-screenshots.json` owns locale order, slide routes, captions,
dimensions, safe areas, the fixed capture date and timezone.
`tool/apple/seed_store_demo.py` owns the English demo workspace: four projects,
36 tasks including subtasks and completed work, colored labels, Kanban states,
five habits and 14 days of Focus/check-in history. Reports calculate their values
from these records. The seeder checks referential integrity, interval totals and
idempotence, and refuses databases outside disposable capture directories.

The harness mounts production routes with a fixed clock, text scale, preferences,
safe areas and fonts. It disables sync, purchases, audio and notifications and
never opens an owner's database. Templates are tracked under `tool/apple/templates/`;
generation no longer depends on the ignored design editor or its node_modules.
The lockfile pins Playwright, Sharp and the bundled browser revision. The manifest
records source hashes, macOS, runtime versions and system-font checksums. Byte
identity is verified within the same environment; cross-OS or font/toolchain
changes require fresh verification. These captures are Flutter renders, not a
physical-device or native-keyboard check.

Use the pinned FVM SDK consistently in this checkout. A system Flutter command
can replace the shared package/native-hook cache with an incompatible SDK build.
Finish source edits before `--verify`: changes between the two passes are rejected
and the diagnostic identifies the changed source files or capture text.

The local `$pomodoist-store-assets` skill invokes this workflow. Generation does
not upload anything or authorize store changes. Watch still uses the separate
native capture steps below; it is outside this repeat-verified Flutter command.

Use the existing [Editorial Signal direction](../../../app-store-screenshots.md).
Capture the app with the locale selected and export the localized compositions
to `design/app-store/localized/<device>/<ASC locale>/`. This directory is
local to the checkout. Use `APP_STORE_SCREENSHOTS=/absolute/path` to select
another asset root. Each locale folder must contain only final opaque 8-bit
RGB PNGs named `01-*.png` onwards in store order.

| Device directory | App Store slot | Current series size | PNGs per locale |
| --- | --- | --- | ---: |
| `iphone` | `APP_IPHONE_61` | 1206 × 2622 | 10 |
| `ipad` | `APP_IPAD_PRO_3GEN_129` | 2732 × 2048 | 10 |
| `watch` | `APP_WATCH_SERIES_10` | 416 × 496 | 3 |
| `mac` | `APP_DESKTOP` | 2880 × 1800 | 10 |

These slots match the English 1.1.7 listing. Keep the same Watch dimensions
across all localizations as required by
[Apple](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications).
Review the copy, language inside each app capture, slide order and legibility
before placing exports in the upload directory. The preflight checks file
format, device sizing, ordering by filename, counts, and byte-identical
duplicates. The capture workflow also records rendered text and runs OCR;
these automated checks do not establish linguistic quality or device behavior.

### Native Watch captures (macOS)

For Watch, copy the native target into an ignored build directory and replace
only that copy's entry point. The fixture uses production SwiftUI views with an
offline snapshot and never activates WatchConnectivity. Run from the root:

```sh
python3 - <<'PY'
from pathlib import Path
import shutil
source = Path('apps/flutter')
target = Path('build/localized-watch/source')
for name in ['apple', 'ios/Runner.xcodeproj', 'ios/PomodoistWatch',
             'ios/PomodoistWatchWidgets', 'ios/Flutter']:
    shutil.copytree(source / name, target / name, dirs_exist_ok=True)
for name in ['ios/Runner/PrivacyInfo.xcprivacy',
             'ios/PomodoistFocusWidget/PrivacyInfo.xcprivacy']:
    destination = target / name
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source / name, destination)
shutil.copy2('tool/apple/StoreCaptureWatchApp.swift',
             target / 'ios/PomodoistWatch/PomodoistWatchApp.swift')
PY
xcodebuild -project build/localized-watch/source/ios/Runner.xcodeproj \
  -target PomodoistWatch -configuration Debug -sdk watchsimulator \
  SYMROOT="$PWD/build/localized-watch/products" \
  OBJROOT="$PWD/build/localized-watch/obj" CODE_SIGNING_ALLOWED=NO ARCHS=arm64 build

# Use an installed runtime/device type from `xcrun simctl list`.
xcrun simctl create 'Pomodoist Store Capture 1.1.8' \
  com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-11-46mm \
  com.apple.CoreSimulator.SimRuntime.watchOS-26-5 \
  > build/localized-watch/simulator-id.txt
xcrun simctl boot "$(cat build/localized-watch/simulator-id.txt)"
xcrun simctl bootstatus "$(cat build/localized-watch/simulator-id.txt)" -b
python3 tool/apple/capture_watch_screenshots.py
xcrun simctl shutdown "$(cat build/localized-watch/simulator-id.txt)"

STORE_RENDER_DEVICES=watch STORE_UI_LOCALE=localized node tool/apple/render_localized_screenshots.cjs
```

The Watch renderer reuses the tracked Editorial Signal HTML template and the
pinned `tool/apple` dependencies. Raw PNGs and text provenance are under
`design/app-store/localized/raw/watch/`; final PNGs are under `localized/watch/`. Render checks
cover loaded assets, caption overflow, image proportions, dimensions, sRGB,
opacity and duplicate images. No manual visual browser checks are run.
Use `xcrun swift tool/apple/recognize_screenshot_text.swift <raw.png>` for independent OCR
of the app pixels, including Arabic and CJK glyphs.

## Release commands

`APP_STORE_VERSION` defaults to the marketing version in the Flutter
pubspec. Run commands from the repository root.

```sh
# Offline validation. Lists missing screenshot sets.
make app-store

# Create editable versions with manual release.
make app-store APP_STORE_MODE=draft APP_STORE_APPLY=1

# Review the localization plan, then apply it.
make app-store APP_STORE_MODE=metadata
make app-store APP_STORE_MODE=metadata APP_STORE_APPLY=1

# Once the full matrix is ready, review the screenshot plan and apply it.
make app-store APP_STORE_MODE=screenshots
make app-store APP_STORE_MODE=screenshots APP_STORE_APPLY=1

# Build, validate and upload using the existing production TestFlight targets.
make all-production-testflight

# Attach the exact CFBundleVersion uploaded for this release.
make app-store APP_STORE_MODE=attach APP_STORE_APPLY=1 APP_STORE_BUILD=132

# Read back the version states and screenshots.
make app-store APP_STORE_MODE=status
```

Metadata and screenshot commands preview first and default to read-only.
The uploader keeps complete English sets inherited from the preceding version
and resumes other sets only when the existing images match the local sequence.
Use App Store Connect to review and replace different artwork in an occupied
slot. Keep one operator per release and rerun the dry run after
any partial failure. If asc generates a screenshot failure receipt, inspect it
and the App Store Connect state before resuming.

Use App Store Connect to review each locale and screenshot set, resolve review
requirements, submit the version and release it manually after approval.

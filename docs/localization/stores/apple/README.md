# Apple storefront release

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
duplicates. Language and visual review are manual.

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
make app-store APP_STORE_MODE=attach APP_STORE_APPLY=1 APP_STORE_BUILD=131

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

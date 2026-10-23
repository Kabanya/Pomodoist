# Contributing

Open an issue before starting a substantial change. Keep pull requests focused
and include tests for behavior changes.

For Flutter UI, theme, and animation changes, follow the
[application design system](docs/design-system.md), including its shared
tokens, component boundaries, accessibility rules, and validation scope.

Before a pull request can be accepted, its author must read [CLA.md](CLA.md)
and check the CLA confirmation in the pull request template. Contributions
and official client binaries remain available under `AGPL-3.0-only`.

Run root `make check` for architecture boundaries, Flutter analysis and unit tests.
Direct Flutter commands run from `apps/flutter`. Keep dependencies directed as
described in the [repository architecture](docs/architecture/repository.md).

Local macOS staging targets (`macos-debug-staging`, `macos-profile-staging`,
and `macos-release-staging`) opt into the in-process test StoreKit catalog,
matching staging TestFlight. Purchases in this mode are simulated and do not
validate Apple networking, real payments, or server entitlement verification.
Pro is not automatically unlocked. To intentionally query the staging app's
App Store catalog, pass `MACOS_STAGING_STOREKIT_DEFINES=` to Make. Production
continues to use the remote App Store catalog. Build configuration changes
require rebuilding the app; pushing source does not update an existing binary.

macOS release builds strip local native symbols after generating dSYM files.
The Make targets also save Dart symbols under `build/symbols/macos/<flavor>/dart/`;
native dSYM bundles remain beside the built `.app` in
`build/flutter/macos/Build/Products/Release-<flavor>/`. Archive both sets with the
matching release before rebuilding the same flavor. TestFlight archives also
retain their native symbols under `build/TestFlight/*.xcarchive/dSYMs/`.
The DMG script saves Dart and native symbols under its output directory's
`symbols/<flavor>/` folder. CI retains these separately from public downloads in
the `pomodoist-macos-symbols` artifact for 90 days; keep a durable copy for every
supported release. Dart symbols can be used with `flutter symbolize`.

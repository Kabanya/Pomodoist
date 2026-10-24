# Desktop updates

Pomodoist checks public GitHub releases 10 seconds after startup, every six hours,
and on resume when its last check was more than an hour ago. Automatic checks run
in release builds; Settings → About → Updates also works in debug builds. Checks
never download or execute an installer until the user presses **Update**.

Official updates are enabled only for `POMODOIST_ENVIRONMENT=production`.
Self-hosted, local and staging builds do not check, download or install official
updates, including through manual actions. Their Settings explain this restriction;
self-hosted clients must be rebuilt by their operator to preserve their server
configuration. Production debug builds still support manual checks.

## macOS direct downloads

macOS is distributed separately through a universal `Pomodoist-macOS.dmg` for
Apple Silicon and Intel, with a `Pomodoist-macOS.dmg.sha256` sidecar. Download
these files from [GitHub Releases](https://github.com/Kabanya/Pomodoist/releases),
open the DMG and drag Pomodoist into Applications. Update a direct-download
installation by downloading the newer DMG; there is no native macOS updater.
The direct download uses production configuration and Stripe billing and omits
the Mac App Store focus widget.

The `macOS DMG` workflow runs automatically for new `vX.Y.Z` and `vX.Y.Z-rc.N`
tags. It signs the application, its nested code and the disk image using
Developer ID Application, secure timestamps and Hardened Runtime. Apple
notarization must return `Accepted`, the ticket must be stapled and validated,
and Gatekeeper must accept the DMG and application before the release checksum
is created. Verification also mounts the DMG, checks the app signature, bundle
identity, Direct entitlements, and both architectures. Unsigned or rejected
artifacts are never published.

Windows, Linux and Android keep their existing release requirements and can
publish before macOS finishes. The DMG is attached to the same release once it
passes verification. A release created first by macOS stays draft until the
required assets from the other platforms arrive. Existing release tags are not
moved to add workflow changes.

### Signing configuration

Configure the GitHub environment `macos-production` with these secrets:

| Secret | Value |
| --- | --- |
| `POMODOIST_MACOS_CERTIFICATE_P12_BASE64` | Base64-encoded password-protected P12 containing only the selected Developer ID Application certificate and private key |
| `POMODOIST_MACOS_CERTIFICATE_PASSWORD` | Password protecting that P12 |
| `POMODOIST_MACOS_SIGNING_IDENTITY` | `Developer ID Application: FinchForge, LLC (4VK836929S)` |
| `POMODOIST_MACOS_NOTARY_PROFILE` | `pomodoist-developer-id` |
| `ASC_KEY_ID` | Existing App Store Connect team API key ID |
| `ASC_ISSUER_ID` | Issuer of that team API key |
| `ASC_PRIVATE_KEY_BASE64` | Base64-encoded `.p8` API private key |
| `GOOGLE_DESKTOP_CLIENT_SECRET` | Existing production desktop OAuth configuration |

Export only the selected Developer ID identity, not every identity in the login
Keychain. Set environment variables `WEB_APP_URL`, `TURNSTILE_SITE_KEY` and
`GOOGLE_DESKTOP_CLIENT_ID` from the existing production desktop configuration.
`SENTRY_DSN` is optional. Never commit certificate exports, passwords or private
keys; keep local copies in ignored configuration only.

`tool/macos/ci_signing.sh` imports the identity into a temporary Keychain,
grants the system signing tools access and creates a validated `notarytool`
profile. The wrapper restores the original default Keychain and search list
and removes temporary signing files on success or failure. Apple credentials
are never included in Flutter configuration. The production configuration is
generated from an allowlist, checked with the existing desktop validator and
removed after the build. Local `tool/macos/build.sh` builds can continue using
their existing signing identity and Keychain profile without the CI wrapper.

### Verification and troubleshooting

Run `tool/macos/test_build_contract.sh` for the packaging and CI credential tests.
After workflow changes reach `main`, run
`gh workflow run macos-dmg-release.yml --ref main` for a verification build.
Main-branch runs produce the `pomodoist-macos-dmg` Actions artifact only;
supported release-tag runs attach assets to that tag's release. Download the
published DMG through a browser and test installation and first launch with
normal Gatekeeper settings before treating a release as verified for users.

Missing credentials, a wrong P12 identity, notarization rejection, stapling
failure or Gatekeeper rejection stops publication. Inspect the
`pomodoist-macos-notarization` Actions artifact for the submission receipt,
result and rejection log; diagnostics are retained for 14 days and contain no
signing material. If the client fails while waiting, the receipt preserves the
submission ID. Check it locally with `xcrun notarytool info <id>
--keychain-profile pomodoist-developer-id` before re-uploading. An upload receipt
alone does not prove accepted notarization. The CI build has a 90-minute limit.

Developer ID signing and notarization prevent the unverified-developer and
unverified-software blocks with standard Gatekeeper settings. macOS may still
ask whether to open an app downloaded from the internet on its first launch;
that confirmation is normal and does not mean the app is unverified.

## Channels and assets

Stable is the persistent default. The optional RC switch includes `vX.Y.Z-rc.N`
alongside stable releases. Drafts, alpha/beta tags, manual Windows preview tags,
and stable tags marked as prereleases are excluded. Version precedence is SemVer,
not publication date, string order or Flutter build number. Switching back to
stable never downgrades an installed newer RC.

All release pages are read, with a bounded request deadline. A release must have
an exact matching uploaded asset and SHA-256 metadata or checksum sidecar. The
existing release workflows already publish the required files:

| Process architecture | Windows | Linux |
| --- | --- | --- |
| x64 | `Pomodoist-Setup-x64.exe` or existing `Pomodoist-Setup.exe` | `Pomodoist-x86_64.AppImage` |
| arm64 | `Pomodoist-Setup-arm64.exe` | `Pomodoist-aarch64.AppImage` |

Only x64 assets are currently produced. The updater never mislabels an x64 asset
as native arm64. An x64 process under Windows ARM emulation requests the x64
installer. Native arm64 builds need the explicit arm64 release assets above.

Linux in-place updates apply to the official writable AppImage distribution.
Non-AppImage packages stay under their package manager's control. macOS, iOS,
Android and web do not instantiate a native updater. Existing releases without
this code need one initial installation of an updater-enabled build; the feature
cannot be retroactively added to their running binaries.

## UI and data

The compact bottom-right card shows the version, release notes, **×** and
**Update**. Tags are persisted before their first notification; closing or
restarting does not repeat automatic prompts for that tag. Manual checks can
reopen a dismissed offer. English and Russian copy, light/dark themes, constrained
windows, progress animation, keyboard-accessible controls and reduced motion are
supported. Closing a busy popup hides it but does not stop a requested update.

Downloads use a dedicated client without application account credentials. Failed
automatic checks remain in Settings rather than interrupting work. Manual checks
show an actionable error. Channel changes and duplicate update requests are
blocked while an operation is active.

## Installation and recovery

Downloads stream into a private same-volume staging directory. The declared byte
count and SHA-256 must match; a sidecar must name the exact artifact and agree
with the GitHub digest when both exist. Only HTTPS GitHub release URLs and its
allowlisted download CDNs are accepted. Partial files are never executed.
SHA-256 over GitHub HTTPS detects corruption; it is not independent publisher
signing. The current Windows installer remains unsigned and Windows policy may
block it. No signature verification is claimed.

A bundled helper rechecks the hash, takes an installation lock and acknowledges
readiness before Flutter asks its application exit observers for consent. Once
they agree and the updater is still active, it requests a required native exit.
This avoids treating Windows' provisional `cancel` response to a native cancelable
request as a user veto. An actual veto or disposal while awaiting consent cancels
the helper and leaves the application running.
It never kills another running Pomodoist instance to force an update. Cancellation
or timeout leaves the current executable unchanged.

Linux backs up the original AppImage and atomically renames the verified image
on the same filesystem. Windows backs up the installation directory, runs the
existing per-user Inno installer with the **current** `/DIR`, disables forced
application closure and system reboot, then restarts Pomodoist. It restores the
old directory if installation or launch fails. Neither helper writes to the
application database, preferences, account tokens or application-data directories.

Windows launches PowerShell with Dart's normal process mode (`CREATE_NO_WINDOW`),
not `DETACHED_PROCESS`, which can prevent Windows PowerShell from starting the
script. The helper continues after the application's required native exit; the
application does not wait for the helper to finish. Its output is drained into
`helper-stdout.log` and `helper-stderr.log` while the application is running, so
startup errors before the script's own error handler are retained. Linux keeps
its detached shell helper.

The new Flutter window acknowledges startup through a restricted marker. The
helper restores and relaunches the prior build if no marker arrives. This is a
window/engine health check, not a guarantee that every future database migration
is reversible. Failed staging directories retain `error.log`/`startup.log`, the
installer log and any recovery copy; successful staging is removed by the new
process. A restored build reports the failed update in Settings.

Updater preferences initialize only when used. The existing channel and seen-tag
keys and storage API are unchanged; no preferences or application data migration
is needed.

On abrupt OS power loss, the Linux target is either the old or new complete file;
Windows relies on Inno Setup's installation recovery and the retained `previous`
backup. Do not delete a failed staging directory until recovery is confirmed.

## Verification

Run the pinned SDK through `.fvm/flutter_sdk/bin/flutter`: `analyze`, `test`,
`test --platform chrome test/web/voice_recording_store_test.dart` and
`build web --debug` for the shared code and conditional-import boundary.
Focused tests are named
`test/desktop_update_*_test.dart`.

Run `python3 -m unittest tool/test_desktop_update_helpers.py` on Linux and
`powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool/test_desktop_update_windows.ps1`
on Windows. They execute the exact embedded helper scripts against isolated
fixture executables, including corrupt hashes, cancellation and rollback.
The `Desktop updater` PR workflow also compiles both native desktop targets.
It does not publish releases, install into a user's profile or use production secrets.

Before publishing a stable updater release, smoke-test an update between two
consecutive RC builds on Windows 10/11 and an AppImage desktop session: preserve
a task, settings and login across an update, cancel graceful exit, test a read-only
target, corrupt download and network failure, and confirm stable/RC behavior and
unsigned-installer policy.
Fixture/CI tests do not substitute for that real-device release acceptance pass.
Record code fixes, automated checks and real upgrade results separately; keep
the real-upgrade acceptance criteria in issue #58 open until that pass succeeds.

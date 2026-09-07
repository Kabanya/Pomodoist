# Android builds and release verification

Android uses the shared Flutter task, focus, account, voice and integration flows.
The application ID and Kotlin namespace are `com.finchforge.pomodoist`. The minimum
Android API is 24 (or Flutter's minimum, when higher); compile/target SDK and NDK
come from the Flutter SDK pinned in `.fvmrc`. Keep that pin and `pubspec.lock` in
source control. Android Gradle Plugin 8.11.1, Kotlin 2.2.20, Java 17 and core
library desugaring 2.1.4 are configured in `android/`.

This guide is also the release checklist for issue #50. A successful build does
**not** certify real-device functionality or Google Play approval. Complete the
physical-device matrix below before distributing an official release.

## Local development

Install the pinned Flutter SDK, Java 17, Android SDK command-line/build tools,
GNU Make, Python 3, Bash, and GNU `sort`/`sha256sum` (GNU coreutils on macOS).
On Windows, install Git for Windows so the repository Makefile can use its Bash.
Point `ANDROID_HOME` at the SDK, accept its licenses, and run `flutter doctor -v`.

```sh
make setup-flutter
make android
```

`make setup-flutter` generates the ignored `.env.android` profile from the
`ANDROID__` values in `.env.setup`. `make android` uses that profile, isolates
Gradle state under `build/android/gradle-home`, and writes the debug APK to
`build/app/outputs/flutter-apk/app-debug.apk` on Windows, macOS, and Linux.
Override `ANDROID_CONFIG` to use another dotenv or JSON dart-define file.

Debug builds do not require a production key and can use HTTP development
servers. Only the debug manifest permits cleartext traffic; release/profile use
HTTPS. Emulator host loopback is different from device loopback: configure a
reachable development backend explicitly. Existing installations under
`com.example.pomodoist` are a separate app; export/import data or synchronize an
account before removing them.

## Signing: configure once, retain the key

Generate a dedicated upload key **outside the repository**, not a debug key:

```sh
keytool -genkeypair -v -storetype JKS -keyalg RSA -keysize 3072 \
  -validity 10000 -alias pomodoist-upload \
  -keystore "$HOME/pomodoist-upload.jks"
```

Let `keytool` prompt for passwords. Back up the key and credentials in a secure
secret manager. Never commit a keystore or place credentials in dart-defines.
Copy `android/key.properties.example` to ignored `android/key.properties`, then
set the absolute keystore path, store password, alias and key password. In Java
properties, backslashes need escaping; forward slashes work for Windows paths.
Alternatively supply the four environment variables below (environment wins):

| Environment variable | `android/key.properties` property |
| --- | --- |
| `ANDROID_KEYSTORE_PATH` | `storeFile` |
| `ANDROID_STORE_PASSWORD` | `storePassword` |
| `ANDROID_KEY_ALIAS` | `keyAlias` |
| `ANDROID_KEY_PASSWORD` | `keyPassword` |

Gradle fails release task graphs before building when signing is missing, the key
cannot be unlocked, the certificate has expired, or a standard Android debug
key/certificate is supplied. There is no debug-signing fallback. An explicit
production fingerprint is checked by CI in addition to these guards.

With Play App Signing, the AAB is signed by the **upload key**, and Google signs
installed Play APKs with the **app-signing key**. Register the correct package
and certificate fingerprints with any native OAuth provider you enable. A
sideloaded APK signed with the upload key cannot update a Play installation
signed with a different app-signing key. Keep these distribution channels distinct.

## Produce production APK and AAB

```sh
cp tool/android/production.example.json .env.android.json
# Fill the public Turnstile site key; optionally the public Sentry DSN.
python3 tool/android/validate_config.py .env.android.json
bash tool/android/build_release.sh .env.android.json
```

The default official backend is the existing native-production fallback in
`RuntimePublicConfig`. An override must provide both `SUPABASE_URL` and a public
`SUPABASE_ANON_KEY`; service-role/secret keys are rejected. The configuration
validator also rejects unknown fields, duplicate JSON keys, HTTP endpoints,
development unlocks, local StoreKit testing and embedded server/signing secrets.
All dart-defines can be extracted from the client: they are **not secret storage**.

The script resolves the lockfile, builds both release formats with identical
version/configuration, verifies APK/AAB signatures, rejects a debuggable APK,
compares their signing fingerprints and writes:

```text
build/android/release/Pomodoist-Android.apk
build/android/release/Pomodoist-Android.aab
build/android/release/SHA256SUMS
build/android/release/release.json
build/android/symbols/apk/
build/android/symbols/appbundle/
```

Set `ANDROID_SIGNING_CERT_SHA256` to the expected certificate fingerprint for
an additional local certificate check. Obtain it with `keytool -list -v` against
the upload alias; it is not a password. Keep the matching Dart symbols for crash
symbolication. The AAB is an upload artifact, not an APK that `adb install` accepts.

`versionName` and `versionCode` default to the version in `pubspec.yaml`.
`ANDROID_BUILD_NAME`, `ANDROID_BUILD_NUMBER` and `POMODOIST_RELEASE` can override
them. The release value must be a full Git SHA; versionCode must be a positive
integer no greater than 2100000000 and must increase for each new Play upload.
Rebuilding the same source does not automatically allocate a new Play versionCode.

Equivalent Flutter commands, after validating config and setting signing:

```sh
flutter build apk --release --dart-define-from-file=.env.android.json \
  --dart-define=POMODOIST_RELEASE="$(git rev-parse HEAD)"
flutter build appbundle --release --dart-define-from-file=.env.android.json \
  --dart-define=POMODOIST_RELEASE="$(git rev-parse HEAD)"
bash tool/android/verify_artifacts.sh
```

## GitHub Actions

`Android validation` runs on pull requests and `main`, without production secrets.
It checks packaging/configuration, Android Dart contracts, fails an unsigned
release deliberately, then builds APK/AAB using a disposable non-debug CI key.
It installs the release APK on an API 35 x86_64 emulator and checks process launch,
background/resume, and cold/warm native deep-link delivery. CI-only artifacts are
explicitly labelled **NOT FOR DISTRIBUTION** and retained for three days. This
smoke test does not validate authenticated flows, microphone hardware or layouts.

`Android production release` runs manually or on the same `vX.Y.Z` / `vX.Y.Z-rc.N`
tags as desktop releases. It accepts only commits already in `main`, builds from
the lockfile and verifies the expected certificate. It uploads artifacts to the
workflow run; it does **not** automatically submit to Play or publish a store listing.
A manual `build_number` input overrides versionCode; tag names set versionName.

Create a protected GitHub environment named `android-production` with required
reviewers/trusted branch and tag rules. Configure these environment secrets:

| Secret | Purpose |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Base64 encoding of the existing upload keystore |
| `ANDROID_STORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Upload alias |
| `ANDROID_KEY_PASSWORD` | Private-key password |
| `ANDROID_SIGNING_CERT_SHA256` | Expected upload certificate SHA-256, with or without colons |

Configure environment variables `TURNSTILE_SITE_KEY` (required) and `SENTRY_DSN`
(optional). Use GitHub's secret entry flow; do not paste production keys/passwords
into an issue, PR or chat. Keys are decoded only into the ephemeral runner's temp
directory, never uploaded or cached, and removed in an `always()` cleanup step.
Pinned action revisions and SDK/lockfile versions make inputs reviewable; this
workflow does not claim byte-for-byte determinism of signed archives.

## Android behavior and permission boundaries

Internet access is needed in release for authentication, synchronization, voice
services and Calendar integrations. `RECORD_AUDIO` is declared for the existing
recorder's runtime permission request; microphone hardware is optional so task
management remains installable on tablets without a microphone. Denial must not
prevent manual task entry. No background microphone service, storage-wide access,
contacts permission or Android calendar-provider permission is added.

Notifications use a monochrome drawable retained by the resource shrinker, the
existing runtime notification-permission request, and scheduled/boot receivers.
Task and focus reminders use exact timing only when **Alarms & reminders** access
is already allowed by the user in Android settings; otherwise they use inexact
idle-compatible scheduling. A permission revoked between check and scheduling
falls back to inexact. Daily re-engagement reminders remain inexact. No settings
screen is forced open at startup. Doze/OEM restrictions can still delay reminders;
a force-stopped app must be reopened before expecting background delivery.

Android backups and device transfers exclude local databases, files and
preferences, preventing auth sessions and installation-specific state from being
silently copied. Account sync/export is the supported migration path; local-only
data is lost on uninstall unless exported beforehand.

The `app_links` integration owns native callbacks; Flutter's built-in deep-link
handler is disabled to avoid double consumption. Registered hosts are
`login-callback`, `captcha-callback`, `google-calendar-connected`, `focus` and
`purchase-success`. Existing Dart validation still rejects malformed callbacks.
Keep `pomodoist://login-callback` and `pomodoist://captcha-callback` in the backend's
redirect allowlist and deploy the web CAPTCHA/Calendar callback pages. Google
Calendar uses the existing account/server integration, not the device calendar.

### Account entitlements, not Android StoreKit payments

The existing billing configuration only has `storekit` and `stripe` channels.
Android intentionally uses the **guarded `storekit` channel**: the existing
`applePurchasesSupported` check is false on Android and returns before creating a
StoreKit store or purchase stream. Linked-account entitlements remain independent
and continue to grant access. The Android regression test fails if the native
store is initialized and checks that account access remains active.

The flag name does not mean StoreKit runs on Android. This build does not add
Google Play Billing, expose Stripe checkout, or enable fake local purchases.
Account-based access is retained; payment/store-policy review remains a release
gate rather than a claim of automatic Google Play approval.

## Required physical-device acceptance record

Copy this section into the release issue and record build SHA/version, artifact
checksum, signing fingerprint, device model/Android version and pass/fail evidence.
These boxes are deliberately unchecked until someone performs the checks.

- [ ] Install signed APK on at least one physical phone; cold start, relaunch,
  update from the previous same-signer version; no startup errors.
- [ ] Sign in/out with email and enabled OAuth providers; CAPTCHA success,
  cancel/denial and expired links; cold and warm `pomodoist://login-callback`.
- [ ] Create/edit/complete/schedule/reschedule tasks; Today, Upcoming, Timeline,
  recurrence, projects, labels, search and reports; offline edits and reconnect;
  confirm changes appear on iOS/web with the same account.
- [ ] Start/pause/resume/finish Pomodoro; background/lock/unlock, process recreation,
  time-zone change and return after the interval expired; no timer drift/double finish.
- [ ] Grant/deny/revoke microphone; record/transcribe/create a voice task; cancel,
  interruption/backgrounding, network failure and retry; verify temporary cleanup.
- [ ] Grant/deny notification permission; task/focus reminders while locked and
  after reboot/update; exact permission both granted and denied/revoked; cancel
  or edit a reminder and confirm no stale/duplicate delivery.
- [ ] Connect/disconnect Google Calendar, return to the app, and synchronize edits;
  test every other integration enabled for the account.
- [ ] Existing paid entitlement from another platform appears after sign-in and
  refresh; sign-out removes account access; Android never initiates StoreKit.
- [ ] Phone widths around 360/412 dp and tablet width 800 dp, landscape/split view,
  keyboard, large text, dark theme, system back, gestures, scrolling, drag/drop,
  dialogs and screen insets; no overflow or blocked controls.
- [ ] Test a 16 KB page-size Android environment and inspect Play pre-launch report
  for native-library compatibility; run the AAB through Play internal testing.
- [ ] Review store listing, privacy/Data Safety, microphone use and account/payment
  policies; publish only after the outstanding checks have evidence.

Sources: [Flutter Android releases](https://docs.flutter.dev/deployment/android),
[plugin v21 setup](https://pub.dev/packages/flutter_local_notifications/versions/21.0.0),
[Flutter deep links](https://docs.flutter.dev/ui/navigation/deep-linking),
[Android backup rules](https://developer.android.com/identity/data/autobackup).

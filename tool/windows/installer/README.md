# Windows EXE installer design

Date: 2026-08-17

## Goal

Provide an unsigned Windows distribution that a user can download as one
`Pomodoist-Setup.exe` file, open, and immediately use.

## Selected approach

Use Inno Setup to wrap the complete Flutter Windows release directory in one
per-user installer. A bare Flutter runner cannot be distributed as one file
because it depends on adjacent DLLs and the `data` directory.

The installer:

- supports Windows 10 build 19041 or newer;
- installs without elevation under `{localappdata}\Programs\<display name>`;
- uses the flavor's application ID as its `AppId`, so each flavor has its own
  uninstall entry and can be installed, upgraded and removed on its own;
- replaces application files during upgrades while preserving user data;
- registers the flavor's URL scheme under the current user's `Software\Classes`
  key;
- creates a current-user Start Menu shortcut and an uninstall entry;
- launches Pomodoist after a successful interactive installation;
- has no welcome, directory, program-group, ready, or finish pages;
- produces `build\flutter\windows\installer\<setup base name>.exe` and its
  SHA-256 checksum.

The installer contains the x64 Flutter build. It runs natively on x64 Windows
10/11 and through Windows 11's x64 compatibility on Arm64.

## Flavors

One installer source, `Pomodoist.iss`, builds all three flavors. The values that
differ are never hardcoded there: `build.ps1` reads them from
`tool/windows/flavors.ps1` — the same table the Flutter and CMake builds use —
and passes them to the compiler as `/D` defines.

| | production | staging | development |
| --- | --- | --- | --- |
| Display name | `Pomodoist` | `Pomodoist Stg` | `Pomodoist Dev` |
| Install directory | `Programs\Pomodoist` | `Programs\Pomodoist Stg` | `Programs\Pomodoist Dev` |
| URL scheme | `pomodoist` | `pomodoist-stg` | `pomodoist-dev` |
| Output name | `Pomodoist-Setup.exe` | `Pomodoist-Staging-Setup.exe` | `Pomodoist-Development-Setup.exe` |

Each flavor is packaged from the directory Flutter writes when that flavor is
built, `build\flutter\windows\x64\<flavor>\runner\Release`, so `build.ps1`
defaults `-BuildDirectory` to the directory of the requested flavor and
`-Flavor` selects both the bundle and the identity. Naming the flavor is always
required for a non-production build; omitting it packages production.

`verify-contract.ps1` checks the shared source and cross-checks the flavor table
against `app_flavor.dart`, the Windows CMake flavor block and this script, so a
value that drifts in only one of those places fails before anything is
compiled. `smoke.ps1` and `test_deep_link_forwarding.ps1` take `-Flavor` and
derive the install directory, protocol registry key, shortcut, uninstall entry
and deep link from the same table.

## Release separation

Tag-triggered publication uploads the EXE and Linux AppImage to the same draft
GitHub release and publishes it only after both platforms and checksums exist.
Manual Windows workflow runs remain separate pre-releases. Release notes state
that the EXE is unsigned and may trigger Microsoft Defender SmartScreen.

Production Dart defines come only from the protected `windows-production`
GitHub Environment. Local release builds continue to require an explicit JSON
configuration file and embed the full Git commit SHA.

## Error handling

Packaging stops if the release executable, Flutter runtime, data directory,
icon, valid semantic version, or Inno Setup compiler is missing. Installation
replaces files atomically where Inno Setup supports it and refuses unsupported
Windows versions. Launch is attempted only after the files and registry entries
have been installed successfully.

## Verification

`test.ps1` drives `build.ps1` with a fake compiler and asserts the `/D`
arguments of a production and a staging run, the flavor-specific output name and
checksum, version parsing, compiler discovery, the rejection of an elevated
installer source, and the build script's refusal of an entry point that belongs
to another flavor. `verify-contract.ps1` validates the shared installer source
and cross-checks the flavor table against the Dart model, the Windows CMake
flavor block and the packaging scripts, so a value that drifts in one place
fails before anything is compiled.

CI builds the production Flutter release, compiles the production installer with
the pinned compiler, compiles one non-production flavor as well so that a
display name containing a space is proven against the real compiler, and then
verifies the versions, the unsigned boundary and the checksum. It uploads only
the installer and its checksum, and never installs or launches the EXE.

Local verification with `smoke.ps1 -Flavor <flavor>` installs that flavor
silently, checks the installed files, its protocol registration, its shortcut
identity and uninstall entry, reinstalls over it to prove existing data
survives, forwards a deep link to the running build, and uninstalls it.
`test_deep_link_forwarding.ps1 -Flavor <flavor>` runs the deep-link handoff on
its own against a build of that flavor.

## Known limitation

SmartScreen may show an unknown-publisher warning. An unpackaged Flutter
application can display and schedule Windows notifications, but Windows does
not give it package identity; APIs that cancel already displayed notifications
or enumerate active notifications remain limited.

# Windows EXE installer design

Date: 2026-08-17

## Goal

Provide a temporary unsigned Windows distribution that a user can download as
one `Pomodoist-Setup.exe` file, open, and immediately use. The signed MSIX
bundle remains the stable distribution target and its fail-closed SignPath
workflow is unchanged.

## Selected approach

Use Inno Setup to wrap the complete Flutter Windows release directory in one
per-user installer. A bare Flutter runner cannot be distributed as one file
because it depends on adjacent DLLs and the `data` directory.

The installer:

- supports Windows 10 build 19041 or newer;
- installs without elevation under `{localappdata}\Programs\Pomodoist`;
- uses the stable application ID `com.finchforge.pomodoist`;
- replaces application files during upgrades while preserving user data;
- registers `pomodoist://` under the current user's `Software\Classes` key;
- creates a current-user Start Menu shortcut and an uninstall entry;
- launches Pomodoist after a successful interactive installation;
- has no welcome, directory, program-group, ready, or finish pages;
- produces `build\windows\installer\Pomodoist-Setup.exe` and its SHA-256
  checksum.

The initial preview contains the x64 Flutter build. It runs natively on x64
Windows 10/11 and through Windows 11's x64 compatibility on Arm64. The native
Arm64 artifact continues to be produced by the signed MSIX release pipeline.

## Release separation

Unsigned EXE publication uses a separate manually triggered GitHub Actions
workflow and a GitHub pre-release. It must never publish or replace the stable
`Pomodoist.msixbundle` or `Pomodoist.appinstaller` assets. The release notes
must state that the EXE is unsigned and may trigger Microsoft Defender
SmartScreen.

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

Automated checks validate the installer source and packaging script, including
identity, minimum OS, per-user path, protocol command quoting, output name,
silent pages, post-install launch, and checksum generation. CI builds the
Flutter release, compiles the installer, checks its Authenticode state and
hash, installs it silently, validates files and protocol registration, launches
the installed runner, uninstalls it, and uploads only the installer and
checksum to a pre-release.

Local verification builds the current x64 release, compiles the installer,
opens it normally, waits for the installed `pomodoist.exe` process, and leaves
the application running for manual inspection.

## Known limitation

Until the executable is signed, SmartScreen may show an unknown-publisher
warning. An unpackaged Flutter application can display and schedule Windows
notifications, but Windows does not give it package identity; APIs that cancel
already displayed notifications or enumerate active notifications remain
limited. The signed MSIX distribution removes this limitation.

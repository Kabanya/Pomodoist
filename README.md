<p align="center">
  <img src=".github/assets/github-banner.webp" alt="Pomodoist task manager, focus timer, and productivity reports" width="100%">
</p>

<h1 align="center">Pomodoist</h1>

<p align="center">
  <strong>An open-source task manager with Pomodoro focus sessions and productivity reports.</strong>
</p>

<p align="center">
  <a href="https://github.com/Kabanya/Pomodoist/actions/workflows/validate.yml"><img src="https://github.com/Kabanya/Pomodoist/actions/workflows/validate.yml/badge.svg?branch=main" alt="Validate"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0--only-EF4444" alt="License: AGPL-3.0-only"></a>
</p>

<p align="center">
  <a href="https://pomodoist.com">Website</a> ·
  <a href="https://app.pomodoist.com">Try Web</a> ·
  <a href="https://pomodoist.com/privacy/">Privacy</a> ·
  <a href="https://github.com/Kabanya/Pomodoist/issues/new">Report a bug</a> ·
  <a href="CONTRIBUTING.md">Contribute</a>
</p>

Pomodoist brings task planning, protected focus time, and progress tracking
into one Flutter app. Use it on the web or build it for macOS, iOS and iPadOS,
Android, Linux, Windows, and the web.

## Pomodoist at a glance

<p align="center">
  <img src=".github/assets/screenshots/macos-upcoming-planner.webp" alt="Upcoming planner on macOS in light and dark mode" width="90%">
</p>

- **Plan your work** — organize tasks across inbox, today, upcoming, projects,
  timeline, kanban, priority matrix, and search
- **Protect focus time** — run Pomodoro sessions with deep-focus tracking and
  configurable breaks
- **Review your progress** — understand weekly productivity and focus-time
  trends through built-in reports
- **Work across platforms** — use the same Flutter client on mobile, desktop,
  and web, with optional account, calendar, and voice integrations

## Screenshots

### macOS

<p align="center">
  <a href=".github/assets/screenshots/macos-focus.webp"><img src=".github/assets/screenshots/macos-focus.webp" alt="Pomodoro focus session in the Pomodoist macOS app" width="32%"></a>
  <a href=".github/assets/screenshots/macos-kanban.webp"><img src=".github/assets/screenshots/macos-kanban.webp" alt="Kanban boards in the Pomodoist macOS app" width="32%"></a>
  <a href=".github/assets/screenshots/macos-priority-matrix.webp"><img src=".github/assets/screenshots/macos-priority-matrix.webp" alt="Priority matrix in the Pomodoist macOS app" width="32%"></a>
  <br>
  <sub>Pomodoro Focus · Kanban Boards · Priority Matrix — click to expand</sub>
</p>

<details>
<summary><strong>Mobile screenshots</strong></summary>

<p align="center">
  <img src=".github/assets/screenshots/08-projects.webp" alt="Projects and labels on mobile" width="30%">
  <img src=".github/assets/screenshots/02-focus.webp" alt="Pomodoro focus session on mobile" width="30%">
  <img src=".github/assets/screenshots/10-reports.webp" alt="Productivity reports on mobile" width="30%">
  <br>
  <sub>Projects · Focus · Reports</sub>
</p>

<p align="center">
  <img src=".github/assets/screenshots/05-priority-matrix.webp" alt="Priority matrix on mobile" width="30%">
  <img src=".github/assets/screenshots/06-kanban.webp" alt="Kanban board on mobile" width="30%">
  <br>
  <sub>Priority Matrix · Kanban</sub>
</p>
</details>

## Build from source

Pomodoist is the complete app client, not a stripped-down demo. To run the web
app locally:

```sh
git clone https://github.com/Kabanya/Pomodoist.git
cd Pomodoist
flutter pub get
make web
```

Run the same validation used for contributions:

```sh
make check
```

### Windows

Windows development requires Flutter 3.47.0, Visual Studio with Desktop
development with C++, and Windows SDK 10.0.19041.0 or newer.

```powershell
flutter pub get
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tool\windows\run.ps1
```

Build a clean release with public production configuration copied from
`tool/windows/production-defines.example.json`:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tool\windows\build.ps1 -Configuration Release -Clean `
  -ConfigFile C:\secure\pomodoist-windows-production.json
```

If Visual Studio was upgraded or switched, use `-Clean` once so CMake does not
reuse a generator from the previous installation. Packaging and trusted
signing are performed by the tag-triggered GitHub workflow; public releases
contain `Pomodoist.msixbundle` and `Pomodoist.appinstaller` for Windows 10
2004+ and Windows 11 on x64/ARM64.

<details>
<summary>Develop the shared client packages locally</summary>

The public account and voice packages are pinned to a release commit in
[`Kabanya/app-client-platform`](https://github.com/Kabanya/app-client-platform).
To develop both repositories together, create an ignored
`pubspec_overrides.yaml`:

```yaml
dependency_overrides:
  app_account:
    path: ../app-client-platform/app_account
  app_voice:
    path: ../app-client-platform/app_voice
```
</details>

## Contributing

Bug reports and focused pull requests are welcome. Open an
[issue](https://github.com/Kabanya/Pomodoist/issues/new) before starting a
substantial change, read the [contribution guide](CONTRIBUTING.md), and run
`make check` before submitting a pull request.

## License

Copyright © 2026 FinchForge LLC.

Pomodoist client source and official client binaries are licensed under the
[GNU Affero General Public License v3.0 only](LICENSE) (`AGPL-3.0-only`). See
the [licensing model](LICENSING.md) and
[Code Signing Policy](CODE_SIGNING_POLICY.md). Paid subscriptions cover hosted
services and account entitlements, not a proprietary client license. The name,
logo, and app icon follow the
[trademark policy](TRADEMARKS.md), and contributions require the
[Contributor License Agreement](CLA.md).

## Code signing policy

Free code signing provided by SignPath.io, certificate by SignPath Foundation.
See the public [Code Signing Policy](CODE_SIGNING_POLICY.md), including team
roles, release controls, incident response, and the
[Privacy Policy](https://pomodoist.com/privacy/).

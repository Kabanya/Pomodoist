<p align="center">
  <img src=".github/assets/github-banner.webp" alt="Pomodoist" width="100%">
</p>

<h1 align="center">Pomodoist</h1>

<p align="center">
  A Flutter productivity client for tasks, focus sessions, reports,
  and optional account, voice, and billing integrations.
</p>

## Features

- **Tasks** — upcoming planner, today, inbox, projects, kanban, priority
  matrix, and search
- **Focus Sessions** — pomodoro timer with deep focus tracking and breaks
- **Reports** — weekly productivity charts and focus time stats
- **Cross-platform** — Desktop, macOS, ipadOS, iOS, Android, Linux, Windows, and web

## Screenshots

<p align="center">
  <img src=".github/assets/screenshots/macos-upcoming-planner.webp" alt="Pomodoist on macOS" width="85%">
  <br>
  <sub>macOS</sub>
</p>

<p align="center">
  <img src=".github/assets/screenshots/08-projects.webp" alt="Projects" width="18%">
  <img src=".github/assets/screenshots/02-focus.webp" alt="Focus session" width="18%">
  <img src=".github/assets/screenshots/05-priority-matrix.webp" alt="Priority matrix" width="18%">
  <img src=".github/assets/screenshots/06-kanban.webp" alt="Kanban board" width="18%">
  <img src=".github/assets/screenshots/10-reports.webp" alt="Reports" width="18%">
  <br>
  <sub>Projects · Focus · Priority Matrix · Kanban · Reports</sub>
</p>


## Explore and build Pomodoist

Pomodoist is published as a real cross-platform Flutter client, not a
stripped-down demo. Clone it to explore the architecture, run the app locally,
or build it for any supported platform.

### Quick start

```sh
flutter pub get
make check
make web
```

The shared account and voice client packages are public and pinned to a release
commit in
[`Kabanya/app-client-platform`](https://github.com/Kabanya/app-client-platform).
If you are developing both repositories together, create an ignored
`pubspec_overrides.yaml`:

```yaml
dependency_overrides:
  app_account:
    path: ../app-client-platform/app_account
  app_voice:
    path: ../app-client-platform/app_voice
```

### Public client, private secrets

This repository contains the complete app client and needs no private backend
source or server credentials to build. Runtime configuration accepts only
public endpoints and client values; privileged operations remain server-side.
Source maps are exported separately for symbolication and are never served by
the Nginx runtime image.

## License

This code is source-available under the PolyForm
Noncommercial 1.0.0 license. See [LICENSE](LICENSE).

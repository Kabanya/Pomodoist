# Application monorepo

Pomodoist contains one Flutter package, companion applications, integrations and
a shared server implementation. It does not add Dart packages or microservices
to express internal architecture boundaries.

```text
Pomodoist/
├── apps/
│   ├── flutter/
│   │   ├── lib/
│   │   │   ├── config/      # environments and dependency composition
│   │   │   ├── routing/     # routes and navigation
│   │   │   ├── data/        # repositories and external services
│   │   │   ├── domain/      # models and use cases
│   │   │   ├── ui/          # feature ViewModels and widgets
│   │   │   └── utils/       # framework-independent helpers
│   │   ├── test/
│   │   ├── tool/
│   │   ├── assets/
│   │   ├── web/
│   │   ├── ios/
│   │   ├── macos/
│   │   ├── android/
│   │   ├── linux/
│   │   ├── windows/
│   │   ├── apple/
│   │   ├── StoreKit/
│   │   ├── drift_schemas/
│   │   └── pubspec.yaml
│   ├── telegram-mini-app/
│   └── chrome-extension/
├── server/
│   ├── supabase/functions/
│   ├── supabase/migrations/
│   ├── tests/
│   ├── scripts/
│   └── core-manifest.json
├── tool/
├── docs/
├── .github/
├── .fvmrc
└── Makefile
```

## Dependency direction

Flutter dependencies point inward: widgets use ViewModels, ViewModels use
repository contracts or optional use cases, repositories use services, and
services own external APIs. `config` creates concrete dependencies. Domain
code does not import Flutter, Riverpod, Drift, SDKs, services or UI. See
[Flutter application architecture](flutter-app-architecture.md) for the
canonical contract and
[Flutter MVVM implementation notes](mvvm-implementation.md) for
implementation-specific conventions.

Server adapters validate callers, translate requests and render responses.
Shared server modules never import an endpoint. MCP, OpenClaw, Watch, Telegram
and the Flutter client keep their existing delivery boundaries.

## Build roots

Run the usual `make` commands from the repository root. For direct Flutter
commands, enter `apps/flutter` and use the pinned root SDK:

```sh
../../.fvm/flutter_sdk/bin/flutter pub get --enforce-lockfile
../../.fvm/flutter_sdk/bin/flutter test
```

Generated and private environment files remain outside source architecture.
Flutter always writes to `<project>/build` and keeps its compile cache in
`<project>/.dart_tool`, so `apps/flutter/build` and `apps/flutter/.dart_tool`
are symlinks (junctions on Windows) into the repository-root `build/`: every
generated artifact, including the Dart tool cache, lives under `build/` next to
the companion outputs. The macOS TestFlight archive keeps its Xcode derived
data in `build/TestFlight`.

## Automated boundaries

`make architecture` checks Flutter layer rules, imports, exports, part files,
conditional imports, handwritten Dart/TypeScript cycles, shared-server imports
and manifest closure using Python's standard library. There is no exception list
for the former Flutter layout. `make check` includes this check.

Validation for architecture changes uses static analysis, unit/widget tests and
fully automated repository checks. Platform builds, deployment and publication
are separate release gates.

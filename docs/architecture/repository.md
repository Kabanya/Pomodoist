# Application monorepo

Pomodoist is one Flutter package, companion applications, integrations and a
shared server implementation. It does not introduce additional Dart packages or
microservices.

```text
Pomodoist/
├── apps/
│   ├── flutter/
│   │   ├── lib/
│   │   │   ├── app/          # startup, navigation, dependency composition
│   │   │   ├── core/         # database, sync, platform infrastructure
│   │   │   └── features/     # product behavior and presentation
│   │   ├── test/
│   │   ├── tool/             # Flutter profiles and package-dependent tooling
│   │   ├── assets/
│   │   ├── web/
│   │   ├── ios/              # embeds Watch and widgets
│   │   ├── macos/
│   │   ├── android/
│   │   ├── linux/
│   │   ├── windows/
│   │   ├── apple/            # shared Apple source/resources
│   │   ├── StoreKit/
│   │   ├── drift_schemas/
│   │   └── pubspec.yaml
│   ├── telegram-mini-app/
│   └── chrome-extension/
├── server/
│   ├── supabase/functions/
│   │   ├── _shared/          # product state, task/Focus plans, AI
│   │   ├── pomodoist-ai/
│   │   ├── pomodoist-watch/
│   │   ├── pomodoist-telegram/
│   │   ├── pomodoist-mcp/
│   │   └── pomodoist-transcribe/
│   ├── supabase/migrations/
│   ├── tests/
│   ├── scripts/
│   ├── docker/
│   ├── compose.yaml
│   └── core-manifest.json
├── tool/
│   ├── deploy/web/
│   ├── openclaw/
│   └── tests/fixtures/
├── docs/
├── .github/
├── .fvmrc
└── Makefile
```

## Dependency direction

Flutter presentation calls application behavior, which uses explicit dependencies
and existing repositories. Pure feature rules do not import widgets, the database,
account clients or app composition. `app` creates the dependencies; features do
not create additional database owners. A controller is introduced only where it
owns existing orchestration; empty architectural folders are unnecessary.

Server adapters validate callers, translate requests and render responses.
`_shared/pomodoist_task_commands.ts` and `pomodoist_focus_commands.ts` build sync
operations from product state. `task_decomposition.ts` owns AI prompts, providers,
fallbacks and response validation. `task_decomposition_http.ts` shares the existing
authentication/response boundary between the AI and Watch endpoints. Shared
modules never import an endpoint. Helpers remain flat for the hosted assembler.

MCP and OpenClaw consume the same schema-validated mutation plans. Ordinary MCP
persists through its existing RPC. OpenClaw prepares a durable action, plans,
then atomically commits against the prepared revision and argument hash. A saved
receipt returns before planning. No HTTP interception or fake MCP registration
is involved.

## Build roots

Run the usual `make` commands from the repository root. Make enters
`apps/flutter` for Flutter commands and resolves configuration paths first.
The pinned SDK and generated/private `.env.*` files stay at the repository root.
Flutter outputs live in `apps/flutter/build`; companion packages remain in root
`build/chrome` and `build/telegram`. TestFlight staging and Watch simulator output
also remain under root `build` as their Make variables specify.

For direct commands, enter `apps/flutter` and use the root SDK, for example:

```sh
../../.fvm/flutter_sdk/bin/flutter pub get --enforce-lockfile
../../.fvm/flutter_sdk/bin/flutter test
```

Dart tools that import Flutter or package dependencies live in `apps/flutter/tool`
so the analyzer and IDE resolve the same app package context. From `apps/flutter`,
run `../../.fvm/flutter_sdk/bin/dart tool/prepare_sentry_sourcemaps.dart ...`.
Root Dart scripts use only the Dart standard library; `make analyze` also checks
these scripts with `dart analyze tool`.
The web Docker build keeps the repository and Flutter roots distinct and emits
the same final runtime/source-map artifact locations.

## Automated boundaries

`make architecture` checks handwritten Dart/TypeScript cycles, pure-domain
imports, shared-server imports and flat manifest dependency closure using Python's
standard library. Generated localization import cycles are excluded; there is
no allowlist for handwritten cycles. `make check` includes this check.

Contract fixtures are documented in [tool/tests/README.md](../../tool/tests/README.md).
The refactor's validation scope is unit tests, static analysis and simple fully
automated checks. Manual UI/device testing is outside this implementation.
Release staging and platform build acceptance are separate gates.

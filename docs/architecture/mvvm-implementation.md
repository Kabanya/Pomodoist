# Flutter MVVM architecture

The Flutter client uses MVVM with Riverpod for dependency composition and UI
state. Internal APIs, persisted formats and schemas target the current release;
the application does not carry migration adapters or parallel legacy layers.

## Source layout

```text
apps/flutter/lib/
├── config/                  # dependency registration and environments
├── routing/                 # routes and navigation
├── data/
│   ├── repositories/        # repository contracts and implementations
│   └── services/            # database, network, SDK and platform adapters
├── domain/
│   ├── models/              # immutable application models
│   └── use_cases/           # shared or multi-repository operations
├── ui/
│   ├── core/                # design system, localization and application shell
│   └── <feature>/
│       ├── view_models/     # immutable screen state and typed actions
│       └── widgets/         # screens and presentation components
└── utils/                   # Result and framework-independent helpers
```

## Responsibilities

- Widgets observe a feature ViewModel and send it user actions. Layout,
  animation, text controllers and simple navigation stay in the view. Reusable
  widgets receive data and callbacks.
- ViewModels use Riverpod `Notifier` or `AsyncNotifier`. They acquire private
  dependencies during `build`, publish immutable UI state and never depend on
  another ViewModel.
- Use cases contain shared business rules or coordinate multiple repositories.
  Simple actions call one repository directly.
- Repositories expose domain models, streams for observation and `Result<T>`
  for one-shot asynchronous work. Repositories do not depend on one another.
- Services isolate Drift, HTTP, SDK and platform APIs. Drift rows and external
  SDK types do not appear in public domain contracts.

Riverpod is the composition and UI-state mechanism. `Ref`, `WidgetRef` and
`BuildContext` remain above the data and domain layers. Lower-layer objects use
constructor injection. There is no generic ViewModel base class, command
framework or second dependency-injection package.

The main window and Quick Add window share repository data while each retained
screen instance owns its draft and selection state. Long-running operations
capture stable dependencies, dispose subscriptions with their owner and ignore
results from stale account sessions.

## Storage and synchronization

Drift and transport details live in services and repository implementations.
Task, Kanban, Focus and outbox mutations that belong together run in one
transaction, and a failure rolls the complete operation back. Synchronization
owns queue draining, push/pull, retry, cursor and remote-application behavior.
Other repositories use shared local services rather than depending on the
outbox repository.

## Automated enforcement

`tool/check_architecture.py` resolves imports, exports, conditional directives
and part files. It rejects:

- data or composition access from widgets;
- UI, routing or composition dependencies from data;
- repositories depending on repositories for another data area;
- services depending on repositories;
- Riverpod in lower layers;
- infrastructure or UI in domain code;
- ViewModel-to-ViewModel dependencies;
- infrastructure in ViewModels or public repository contracts;
- missing local imports and handwritten dependency cycles.

`tool/test_architecture.py` verifies these failure cases. The accepted validation
scope is static analysis, unit/widget tests and other fully automated checks.
Manual UI, emulator, device and visual acceptance are outside this work.

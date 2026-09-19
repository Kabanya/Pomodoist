# Flutter application architecture

This document defines the implemented architecture of the Pomodoist Flutter
client on `develop`. It applies the official
[Flutter application architecture guide](https://docs.flutter.dev/app-architecture/guide)
to this repository and is the canonical architecture contract.

The client targets the current schema and internal contracts. It does not keep
migration adapters, compatibility wrappers or parallel legacy architecture.
Development, staging and production remain the supported environments.

## Source layout

```text
apps/flutter/lib/
├── config/                  # startup, dependency registration, environments
├── routing/                 # routes and navigation
├── data/
│   ├── repositories/        # repository contracts and implementations
│   └── services/            # database, transport, SDK and platform adapters
├── domain/
│   ├── models/              # immutable application models
│   └── use_cases/           # shared or multi-repository business operations
├── ui/
│   ├── core/                # design system, localization and application shell
│   └── <feature>/
│       ├── view_models/     # immutable UI state and typed actions
│       └── widgets/         # screens and presentation components
└── utils/                   # Result and small framework-independent helpers
```

The feature directories cover account and authentication, tasks and planning,
focus, productivity, billing, collaboration, Google Calendar, settings,
onboarding, updates, voice and Quick Add. Code belongs to the layer that owns
its responsibility, not to a feature-wide vertical slice that bypasses the
layer boundaries.

## Dependency direction

```text
widgets -> view models -> use cases -> repository contracts
                 |                         |
                 +-------------------------+

config -> repository implementations -> services -> Drift / HTTP / SDK / OS
```

Dependencies point toward stable application contracts:

- Widgets may import UI, routing, domain models and framework code. They must
  not import `data/` or `config/`.
- ViewModels may use repository contracts and use cases. They must not use
  services, database rows, SDK clients or other ViewModels.
- Use cases may use repository contracts and domain models. They must not use
  UI, services or platform APIs.
- Repository implementations may use services and domain types. A repository
  must not depend on another repository area.
- Services must not depend on repositories or UI.
- `config/` is the composition root and may know concrete implementations.
- `utils/` remains framework-independent.

Riverpod providers are allowed in `config/` and the UI layer. `Ref`,
`WidgetRef` and `BuildContext` do not cross into data or domain code. Lower
layers use constructor injection.

## Component responsibilities

### Views and widgets

A screen observes the ViewModel state owned by its feature and forwards user
actions to typed ViewModel methods. Layout, rendering, animation, focus nodes,
text controllers and simple navigation stay in widgets. Reusable presentation
components receive values and callbacks instead of reading repositories.

Widgets do not filter, sort or persist application data. They may derive small
rendering-only values such as spacing, visibility and localized labels.

### ViewModels

ViewModels use Riverpod `Notifier` or `AsyncNotifier`. Each ViewModel:

- acquires and stores private dependencies in `build`;
- publishes immutable state that describes loading, data, validation and
  recoverable errors;
- exposes typed actions for the view;
- prevents duplicate submissions where an action is not safely repeatable;
- owns screen-scoped drafts, selection and pending-action state;
- cancels subscriptions and ignores late results after disposal or an account
  change;
- never calls another ViewModel.

There is no universal ViewModel base class and no separate command framework.
Riverpod already provides lifecycle, observation and state delivery.

### Use cases

A use case exists when an operation coordinates multiple repositories or
contains business logic reused by more than one ViewModel. Current examples
include Quick Add, voice creation, CSV import, account deletion and retention,
focus launching and task scheduling.

A simple read or write against one repository is called directly by the
ViewModel. CRUD methods do not receive one-line use-case wrappers.

### Repositories

Repository contracts sit beside their implementations and expose domain
models rather than Drift rows or SDK objects. They own the application-facing
policy for a data area: caching, local-first behavior, conflict handling and
translation between infrastructure data and domain models.

Observation uses `Stream<T>`. One-shot operations whose failure is part of the
public data contract use `Result<T>`. Narrow infrastructure adapters may throw
inside the data layer; repository implementations and ViewModels translate
those failures before they reach rendered UI state.

Repositories do not call other repositories. Shared persistence or transport
behavior belongs in a service, while multi-repository coordination belongs in
a use case.

### Services

Services isolate Drift, SQL, HTTP, Supabase, `app_account`, `app_voice`,
StoreKit and other platform APIs. Concrete repository implementations may own
narrowly scoped infrastructure mapping, but public repository contracts,
domain models and UI state never expose those external types.

Services contain source-specific mechanics. Business decisions and
application state remain in repositories and use cases.

### Domain models and utilities

Domain models are immutable application values for accounts, tasks, focus,
planning, billing, collaboration, calendar, settings, updates and voice. They
do not depend on Flutter, Riverpod, Drift or SDK packages.

`utils/result.dart` is the shared success/failure value. Utilities may depend
only on Dart and other utilities.

## Composition, navigation and lifetime

`config/` creates services, repositories and other long-lived dependencies for
the selected environment. `routing/` owns route definitions, redirects and
navigation structure. Widgets may perform simple navigation, while decisions
that require business state stay in a ViewModel or use case.

Account, focus and settings data are shared through repositories. Drafts,
selection and action state belong to a retained screen instance. The main
window and Quick Add window therefore share persisted data while keeping
independent drafts.

Long-running work captures stable dependencies before awaiting. Subscriptions
are disposed with their owner. Results are discarded when their screen has
closed or their account generation is stale. Editors retain the existing guard
against losing unsaved changes.

## Storage and synchronization

Drift and transport details remain below public repository contracts. The
local database, outbox and synchronization services own queue draining,
push/pull, retries, cursors and application of remote changes.

Related task, Kanban, focus and outbox changes run in one database transaction.
If any part fails, the complete operation rolls back. Other repositories share
local services rather than depending on an outbox repository. Offline writes
update local state and the outbox atomically; synchronization can retry them
without duplicating the user action.

Storage schemas and serialized formats serve the current application. Legacy
schema readers and migration-only adapters are not architecture requirements.

## External boundaries

- Account and authentication adapters translate `app_account`, Supabase and
  HTTP responses into domain account models.
- Billing adapters translate store APIs into domain products, purchases and
  entitlement state.
- Voice adapters wrap `app_voice`, audio capture and transcription behind
  domain requests and results.
- Google Calendar, notifications, haptics, updates and other platform features
  are exposed through services and domain-facing repositories.

Callbacks from repositories directly into UI controllers are forbidden.
Background processes update repositories or streams that ViewModels observe.

## Automated enforcement

`tool/check_architecture.py` resolves imports, exports, conditional directives
and `part` files. It rejects:

- data or composition access from widgets;
- service access and infrastructure packages from ViewModels;
- UI, routing or composition dependencies from data;
- repository dependencies on another repository area;
- service dependencies on repositories;
- Riverpod in data or domain;
- Flutter, infrastructure or data implementations in domain code, except
  repository contracts used by use cases;
- ViewModel-to-ViewModel dependencies;
- infrastructure in public repository contracts;
- missing local imports and handwritten dependency cycles.

`tool/test_architecture.py` verifies these failure cases. Architecture changes
must pass the checker, static analysis and the applicable automated Flutter and
unit tests through the pinned FVM SDK.

Validation is automated only. Manual UI inspection, application launches,
emulators, physical devices and visual acceptance are not part of the required
or accepted verification for this architecture.

## Change checklist

When adding or changing a feature:

1. Put external API access in a service or a concrete repository
   implementation and map its types at that boundary.
2. Expose domain models through a repository contract.
3. Add a use case only for shared business logic or multi-repository work.
4. Put screen state and actions in a feature ViewModel.
5. Keep widgets declarative and pass data and callbacks to reusable children.
6. Cover meaningful state transitions, failures, retries, duplicate actions,
   disposal and stale responses with automated tests.
7. Run the architecture checker, static analysis and applicable automated
   tests.

Do not add migration shims, a second DI/state package, a generic ViewModel base,
a `Command` abstraction, a use case for every repository method or a demo-only
environment.

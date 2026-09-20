# Flutter application architecture

This document defines the architecture of the Pomodoist Flutter client and is
the canonical architecture contract. It follows the official
[Flutter application architecture guide](https://docs.flutter.dev/app-architecture/guide)
and its [data-layer case study](https://docs.flutter.dev/app-architecture/case-study/data-layer):
the presentation layer uses Riverpod + MVVM, Views talk to ViewModels,
ViewModels read repository contracts directly or call optional use cases,
repositories expose domain data and use low-level services for external I/O.

The official guide is the reference for responsibilities. Project-specific
choices layered on top are listed in
[Project decisions](#project-decisions). Implementation status and verification limits are recorded in the execution
ledger of the alignment plan.

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
│   └── use_cases/           # optional multi-repository or reused operations
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
View -> ViewModel -> Repository contract -> Repository implementation -> Service -> source
                  \-> UseCase ----------/

Source: SQLite / remote API / preferences / platform SDK
Composition: config creates services, repositories, use cases and Riverpod providers.
Observation: source changes -> repository domain stream -> ViewModel state -> View.
```

Simple operations go from a ViewModel to a repository contract. A use case is
optional and exists only for complex or reused orchestration across
repositories. There is no mandatory business-service layer between ViewModels
and repositories.

Dependencies point toward stable application contracts:

- Views may import UI, routing, domain models and framework code. They must not
  access repositories, services, use cases, `data/` or `config/` directly.
- ViewModels may use repository contracts, use cases and domain models, wired
  through providers in `config/`. They must not access source clients, concrete
  repository implementations, database rows, SDK types or other ViewModels.
- Use cases may use repository contracts and domain models. They must not
  access UI, composition, source clients or platform APIs directly.
- Repository implementations may use services, source adapters and domain
  models. They must not call another repository instance or depend on UI,
  ViewModels or composition.
- Services contain source-specific I/O, serialization of transport/storage
  records and platform handles. They must not own screen state, feature
  eligibility decisions or cross-feature workflows, and must not depend on
  repositories, use cases, UI or composition.
- `config/` is the composition root and may know concrete implementations.
- `utils/` remains framework-independent.

Riverpod providers are allowed in `config/` and the UI layer. `Ref`,
`WidgetRef` and `BuildContext` do not cross into data or domain code. Lower
layers use constructor injection. Re-exports and inferred provider types must
not bypass these boundaries.

## Boundary rules

| Component | Owns | Must not own/access |
|---|---|---|
| View | rendering, layout, animation, focus/text controllers, simple navigation | application queries, sorting/filtering business data, persistence, service/repository calls |
| ViewModel | presentation transformation, immutable UI state, drafts, selection, validation feedback, typed actions | raw database/SDK types, source adapters, other ViewModels as data sources |
| Use case | complex/reused operations or cross-repository coordination | UI, Riverpod, concrete storage, mandatory forwarding wrappers |
| Repository | domain data, shared application/session state, caching, refresh, data-related rules, failure translation | UI state/controllers, other repositories, ViewModel dependencies |
| Service | source-specific I/O, serialization of transport/storage records, platform handles and technical resource lifecycle | screen state, feature eligibility decisions, cross-feature business workflows |
| Composition | construction, lifetimes, subscription wiring, environment selection | hidden application workflows or SDK types exposed to UI consumers |

Technical resources such as database connections, recorder handles and request
cancellation belong to their adapters. Services must not become a second owner
of domain or presentation state.

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
- exposes typed actions for the view, with pending and error state where an
  action is not safely repeatable;
- calls a repository contract for a simple operation or a use case when
  orchestration is needed, without implementing data-source mechanics;
- owns screen-scoped drafts, selection and pending-action state;
- cancels subscriptions and ignores late results after disposal or an account
  change;
- never calls another ViewModel.

There is no universal ViewModel base class and no separate command framework.
Riverpod already provides lifecycle, observation and state delivery. Command
behavior is implemented with typed ViewModel actions.

### Use cases

A use case combines repository operations into an application scenario. It
owns their sequencing, passes results between them and handles scenario-level
failures. A use case receives its dependencies through its constructor and does
not acquire providers.

Reuse by multiple ViewModels alone does not require a use case when they can
reuse the same repository operation. Do not add a pass-through use case for
every repository method.

### Repositories

Repository contracts sit beside their implementations and expose domain models
rather than Drift rows or SDK objects. A repository owns application data:
queries, persistence, shared application/session state, caching, refresh,
infrastructure mapping, data-related rules and failure translation. A
repository may encapsulate a remote data source as well as a local database.

Repository contracts use `Stream<T>` for observation and `Result<T>` for
one-shot operations whose failure is part of the public contract. Repositories
translate source failures into results. They do not expose source adapters or
SDK types, and they do not call another repository. Cross-repository workflows
belong in use cases. Repositories may reuse policy helpers within the repository
layer; those helpers are not independent data owners and do not call repository
contracts. Shared source mechanics belong in services below the repositories.
For example, `KanbanTransitionCoordinator` contains shared task/focus/Kanban
rules, while `KanbanTransitionStore` performs the corresponding database I/O.

### Services

Services live in `data/services/`. They isolate Drift, SQL, HTTP, Supabase,
`app_account`, `app_voice`, StoreKit and other platform APIs. A service
contains source-specific mechanics, not business decisions or screen state.
Public repository contracts, domain values and UI state never expose service
or infrastructure types.

Existing classes named `*Service` that wrap an SDK or transport are services in
this architecture. Technical resources such as database connections, recorder
handles and request cancellation belong to their adapters; services are not
required to recreate resources per call.

### Domain models and utilities

Domain models are immutable application values for accounts, tasks, focus,
planning, billing, collaboration, calendar, settings, updates and voice. They
do not depend on Flutter, Riverpod, Drift or SDK packages. Public contracts use
deeply immutable values and typed failures.

`utils/result.dart` is the shared success/failure value. Utilities may depend
only on Dart and other utilities.

## Project decisions

These are project choices on top of the official baseline, not claims that
Flutter mandates the exact APIs:

- Riverpod `Notifier`/`AsyncNotifier` for ViewModels and composition.
- `Stream<T>` for observation and `Result<T>` for recoverable operation
  outcomes.
- Pure domain models without Flutter, Riverpod, Drift or SDK dependencies.
- No ViewModel-to-ViewModel dependencies.

## Composition, navigation and lifetime

`config/` creates services, repositories, use cases and other long-lived
dependencies for the selected environment. `routing/` owns route definitions,
redirects and navigation structure. Widgets may perform simple navigation;
ViewModels translate operation outcomes into screen state and navigation
outcomes.

Account, access, focus and settings data are stored through shared repositories
and exposed to ViewModels through domain contracts. Drafts, selection and
action state belong to a retained screen instance. The main window and Quick
Add window therefore share persisted data while keeping independent drafts.

Long-running work captures stable dependencies before awaiting. Subscriptions
are disposed with their owner. Results are discarded when their screen has
closed or their account generation is stale. Editors retain the existing guard
against losing unsaved changes.

## Storage and synchronization

Drift and transport details remain below public repository contracts. The
local database, outbox and synchronization services own queue draining,
push/pull, retries, cursors and application of remote changes.

Related task, Kanban, focus and outbox changes run in one database transaction.
If any part fails, the complete operation rolls back. A local database
transaction cannot roll back an external API call; partial external failures
need explicit handling in the operation that coordinates them. Offline writes
update local state and the outbox atomically; synchronization can retry them
without duplicating the user action. No network request runs inside a local
SQLite transaction.

Storage schemas and serialized formats serve the current application. Legacy
schema readers and migration-only adapters are not architecture requirements.

### Implemented ownership boundaries

- `QuickAddHintRepository` owns saved hints, refresh thresholds, entitlement-aware
  scheduling and retry state. Services only perform source I/O and serialization;
  providers observe repository snapshots. Composition forwards committed manual
  task-creation events to the hint repository and disposes its subscriptions.
  `QuickAddUseCase` resolves the selected/default focus preset through
  `FocusRepository`; composition does not query or map preset database rows.
- `BillingRepository` / `AppBillingRepository` is the shared owner of catalog,
  checkout, purchase/restore operations, verified entitlements and transaction
  linking. `BillingStore` isolates StoreKit I/O; `BillingViewModel` maps the shared
  state into paywall feedback. Multiple consumers share the same pending purchase.
- `AccountSessionRepository` owns session generations and profile publication.
  Rebinding a late or replaced account client invalidates stale work. Profile
  consumers read its stream; sync captures and rechecks the identity before and
  after source requests, including between batches.
- `SyncOwnershipCoordinator` owns guest/account adoption and reset decisions.
  `SyncOwnerStore` owns local owner records and the per-database operation queue;
  `AccountHistoryPolicyStore` reads retention inputs. Composition injects these
  dependencies without embedding SQL or account-transition rules.
- Task repositories compute focus aggregates. Kanban policy remains in the
  repository layer, including the repair callback injected into sync; services
  perform typed reads/writes inside the existing transaction boundary.
- `timelineDayPresentationProvider` derives day buckets, project rows, indexes
  and menu order from `TimelineViewModel` state. Widgets consume that projection;
  retained animation rows do not replace live values or become selection targets.
- Password recovery observes a plain Dart snapshot/stream contract. Shortcut
  values live in domain models; platform encoding and UI labels are separate.
  Voice draft children and collaboration payloads are deeply immutable snapshots.
- `LocalGlobalQuickAddRepository` owns shortcut preferences and observable state.
  It uses the existing `PreferencesService` and `GlobalQuickAddService` for
  persistence and native registration, restoring the previous registration if a
  preference write fails. The service owns channel validation, platform handles
  and window callbacks; it has no Riverpod or repository dependencies.
- `WatchCompanionUseCase` coordinates task and Focus operations, personal-scope
  restrictions, command acknowledgements and snapshot projections through
  repository contracts. `WatchCompanionService` decodes native requests into
  domain commands, encodes domain results, and owns channel/subscription lifetime.
  Account credentials stay in the source adapter. `config/platform/` only wires
  these objects; disposed adapters do not publish late snapshots or registrations.

## External boundaries

- Account and authentication adapters translate `app_account`, Supabase and
  HTTP responses into domain account models. SDK sessions and tokens never
  enter UI or domain snapshots; source services receive request-scoped
  credentials internally.
- Billing adapters translate store APIs into domain products, purchases and
  entitlement state. Shared subscription access is repository state and works
  without a paywall or ViewModel being mounted.
- Voice adapters wrap `app_voice`, audio capture and transcription behind
  domain requests and results; capture lifetime follows the retained session.
- Google Calendar, notifications, haptics, updates and other platform features
  are implemented by data-layer adapters and exposed through domain-facing
  repository contracts.

Callbacks from repositories directly into UI controllers are forbidden.
Background processes publish changes through the data layer. ViewModels
observe them through repository streams.

## Automated enforcement

`tool/check_architecture.py` and `tool/test_architecture.py` enforce the
dependency direction on handwritten sources: no repository, service,
use-case, data or composition access from views or ViewModels, no
repository-to-repository coupling, no Riverpod in lower layers, no Flutter or
infrastructure in domain code, no ViewModel-to-ViewModel dependencies, no SDK
types in public contracts, no missing local imports and no handwritten
dependency cycles.

`apps/flutter/tool/check_architecture_types.dart` extends the check with
resolved Dart semantics so inferred provider types, re-exports, typedefs and
concrete implementations are classified by what they are, not by the file name
they live in. CI runs both checks after dependency resolution.

Validation for architecture changes uses static analysis, unit/widget tests and
fully automated repository checks. Platform builds, deployment and publication
are separate release gates.

## Change checklist

When adding or changing a feature:

1. Put database and external API access in services or repository
   implementations and expose domain models through repository contracts.
2. Put application data, shared session state and data-related rules in a
   repository. Add a use case only when operations must be composed or reused.
3. Put screen state and actions in a feature ViewModel that reads repository
   contracts or calls those use cases.
4. Keep widgets declarative and pass data and callbacks to reusable children.
5. Cover meaningful state transitions, failures, retries, duplicate actions,
   disposal and stale responses with automated tests.
6. Run the architecture checks, static analysis and applicable automated tests.

Do not add migration shims, a second DI/state package, a generic ViewModel
base, a `Command` abstraction, a use case for every repository method or a
demo-only environment.

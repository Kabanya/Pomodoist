# Flutter architecture alignment status

Last updated: 2026-09-21. Branch `develop`; changes remain in the working tree.

The implementation follows the [alignment plan](docs/superpowers/plans/2026-09-20-flutter-official-architecture-alignment.md)
and the [canonical architecture contract](docs/architecture/flutter-app-architecture.md).
This file records implementation and validation; it is not another architecture guide.

## Implementation

The five architecture gaps identified by the subsequent review are addressed:

| Area | Current ownership |
|---|---|
| Billing | One `BillingRepository` implementation owns catalog, checkout, purchase/restore single-flight, verified entitlement state, linking and expiry. The former access and store repository implementations are removed. The ViewModel maps shared values into paywall feedback. |
| Account and sync | One session/profile owner reconnects after client replacement and rejects stale/disposed responses. Sync captures identity and checks it between requests and batches. Owner/reset policy lives in `SyncOwnershipCoordinator`; SQL lives in `SyncOwnerStore` and `AccountHistoryPolicyStore`. Install registration is source I/O. |
| Kanban and Focus | `KanbanTransitionCoordinator` is a shared repository-layer policy helper; `KanbanTransitionStore` only performs source reads/writes. Task repositories calculate focus aggregates. Sync receives a repository-layer repair callback. |
| Timeline and selection | A ViewModel-layer provider prepares the complete day projection. Widgets render prepared buckets/rows. Selection uses live rows and revalidates metadata after pending dialogs. |
| Public contracts | Recovery no longer exposes Flutter `ChangeNotifier`; shortcut values are framework-free. Voice draft children, collaboration nested payloads and shared billing values cannot be mutated through their contracts. |

Existing plan work remains in place: atomic local writes, optional task/voice use
cases, independent Quick Add/editor drafts, typed collaboration operations,
shared preference/focus/update owners, source adapters and Riverpod + MVVM.
There is no compatibility repository or mandatory pass-through use-case layer.

The boundary checkers distinguish actual repository-to-repository coupling from
reusing a policy helper. Regressions cover same-area repository coupling and
concrete implementations of contracts whose names do not end in `Repository`.

## Platform adapter follow-up

Global Quick Add now uses `LocalGlobalQuickAddRepository` for observable
shortcut state and preference-write policy, the existing `PreferencesService`
for storage, and `GlobalQuickAddService` for native channel/portal I/O.
Failed preference writes restore the previous native registration when possible
and report the original error. Window callbacks are injected by composition.

`WatchCompanionUseCase` owns task/Focus coordination, personal-scope restrictions,
acknowledgements and snapshot projections. `WatchCompanionService` owns native
request decoding, response encoding, account payloads, subscriptions and channel
lifetime. Domain requests/results do not expose MethodChannel or account SDK
types. Both `config/platform/` files now only construct and connect dependencies.

Follow-up validation passed: 27 selected unit tests (platform Quick Add, Watch
Companion and composition contracts), 18 Python checker tests, both architecture
checkers (449 resolved Dart libraries), `flutter analyze --no-pub` and
`git diff --check`. Regression tests first reproduced late registration/snapshot
publication after disposal, then passed after the split. A failed preference
write regression also verifies native registration rollback. Only imports were
updated in the existing keyboard-shortcut widget suite; it was not executed.

## Immutable collections and project move targets

`TaskItem.assigneeIds` and `ProductivitySummary.lastSevenDays` now store
unmodifiable defensive copies. Mutating constructor inputs cannot change the
models, and callers cannot modify the exposed lists.

The ViewModel-layer `projectMoveTargetsProvider` prepares eligible project rows
using the existing hierarchy rules. The move dialog only renders these rows;
eligibility checks still use the complete project collection.

Validation passed: 54 selected unit tests, `flutter analyze --no-pub`, both
architecture checkers (449 resolved Dart libraries), and `git diff --check`.
Regressions cover list aliasing/mutation and reactive move-target filtering,
including invalid hierarchy branches, loading and errors. Widget fixtures were
updated for the non-const constructors but their suites were not executed.

## Remaining collection and widget boundary follow-up

The remaining public domain collection owners now copy and freeze constructor
inputs: task creation/update and deletion results, Quick Add parsing, CSV import
drafts/documents/previews/results/errors, task and update preferences, voice
presentation state, billing products/catalogs/offers/state, and parsed update
versions. Nested billing offers and CSV draft labels are protected by their own
models. Nullable task labels retain the distinction between absent and empty.
Existing immutable models and private parser working state remain unchanged.

`ProjectTreeViewModel.dropTarget` applies the existing hierarchy rules against
current project state; the widget retains pointer geometry and drag feedback.
Both Kanban project controls use `kanbanSelectedProjectsProvider`, preserving
board order and selection semantics without duplicating filtering in widgets.

Validation passed: 1,088 tests from 152 unit-only files and 53 explicitly selected
unit cases from the mixed billing/update suites (1,141 total), full Flutter
analysis, both architecture checkers (449 resolved Dart libraries), and
`git diff --check`. New regressions first reproduced mutable collection aliases
and missing ViewModel projections. Widget cases, app launches and manual checks
were not run.

## Earlier alignment validation

Only static analysis and unit tests are in scope. Test execution never selects
`testWidgets`, golden, integration or browser-only cases. Ordinary unit cases in
mixed files are selected by their explicit names.

Before the platform adapter follow-up, final runs passed: 1,050 Dart tests from 147 unit-only files and 122 explicit
unit cases from 18 mixed files (1,172 total). The main run includes 21 semantic
boundary cases; 18 Python checker tests also passed. `flutter analyze` reports
no issues, both architecture checkers pass (441 resolved Dart libraries), and
`git diff --check` is clean. Detailed evidence is recorded in the completion
entry of the alignment plan.
Additional regressions cover shared checkout/catalog requests, immutable
snapshots, account replacement/disposal, identity changes between sync batches,
preference-write failures, independent preference hydration, Timeline projection
and selection metadata refresh.

Widget/golden/integration checks, app launches, manual checks, platform builds
and deployment were not performed. Unit evidence does not establish those gates.

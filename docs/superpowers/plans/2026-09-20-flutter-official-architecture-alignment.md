# Flutter Official Architecture Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Use superpowers:subagent-driven-development only if that execution method is selected. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align the entire Pomodoist Flutter client with the official Flutter architecture responsibilities while preserving application behavior, persisted data, offline synchronization and platform contracts.

**Architecture:** Keep Riverpod + MVVM. Views use ViewModels; ViewModels use repository contracts directly or optional use cases; repositories own application data and use low-level services for external I/O. Use cases combine repositories or hold complex/reused application logic; there is no mandatory business-service layer between ViewModels and repositories.

**Tech Stack:** Flutter 3.47.0 from `.fvmrc`, Dart SDK constraint `^3.11.5`, Riverpod 3, Drift/SQLite, go_router, existing platform adapters, Python architecture checks, flutter_test and fake_async. Retain locked dependency versions.

**Spec:** The user's decision in this task is to follow the official Flutter architecture. The canonical contract is `docs/architecture/flutter-app-architecture.md`. At plan creation it described the superseded business-service-first design; by this skill review Task 1 had restored the official direction. Preserve that work and verify it against the decisions below rather than repeating the rewrite. This plan defines execution and acceptance, not a competing permanent architecture guide.

## Global constraints

- Write and maintain repository documentation in English.
- Follow `docs/design-system.md` for UI changes. Preserve appearance, accessibility, motion, keyboard input, drag-and-drop, responsive behavior and localization.
- Keep one Flutter package and Riverpod. Do not introduce a generic ViewModel base, a second DI framework, a command framework or one use case per CRUD method.
- Keep `data/services/` for external I/O. Do not create the previously proposed `domain/services/` or rename the whole data layer to `data/infrastructure/`.
- Preserve repository-level domain contracts where possible; change internal callers directly when a contract genuinely needs correction. No migration shims or parallel legacy implementation.
- Preserve database schema, IDs, serialized fields, preference keys, sync commands, account ownership, sharing permissions and entitlement rules. This refactor does not delete existing data migrations or compatibility behavior required by current clients.
- Preserve atomic writes of related task, Kanban, focus and outbox records. No network request inside a local SQLite transaction.
- Preserve development, staging and production; native/web conditional imports and platform entry points remain supported.
- No deployment, release, purchase, live account mutation, schema migration, push or external message is part of execution.
- This plan review changes documentation only. Preserve separately authorized implementation work and its execution ledger; a plan does not itself authorize implementation, commits or broader validation.
- Default execution validation is static analysis and targeted unit tests. Do not run widget/golden/integration/browser tests, builds, devices or manual UI checks under that scope. Task 13 explicitly records the additional automated widget coverage needed to claim alignment with the official testing recommendations.
- Reuse installed dependencies. Task 12 may declare the already locked `analyzer: 10.0.1` as a direct development dependency for semantic checks; no new runtime dependency is planned.

## Review focus

These are high-risk behaviors, with an owning task and explicit test obligations below:

1. Account A signs out or changes to B while a request completes: no A data, token, entitlement or late UI result becomes B state (Tasks 3, 4, 6, 10).
2. An outbox or secondary-row write fails after the first database write: all related local changes roll back and a retry does not duplicate the operation (Tasks 2, 3, 5).
3. Main window, retained Quick Add overlay and another window coexist: shared account/data state stays shared; editing, selection and pending actions remain independent (Tasks 6–9).
4. A billing callback repeats or arrives after account change/disposal: it cannot grant access to the wrong account, finish twice, or override a newer state (Task 4).
5. A selected task is moved/deleted remotely, or presentation is rebuilt during a drag/animation: actions use current IDs, drafts survive, and animated retained rows do not become actionable stale tasks (Tasks 7, 8, 13).

---

## 1. Verified starting point and proof boundaries

Inspected on 2026-09-20, branch `develop`, HEAD `e364cb4`. Before creating this plan, the only tracked working-tree change was `docs/architecture/flutter-app-architecture.md`, made earlier in this task. Re-read status and HEAD at execution time; this is a snapshot, not a promise that the checkout will stay unchanged.

During planning:

- `python3 tool/check_architecture.py` passed.
- `python3 -m unittest discover -s tool -p test_architecture.py` passed all 9 tests.
- `../../.fvm/flutter_sdk/bin/flutter analyze --no-pub`, from `apps/flutter`, passed.
- Earlier in this task, 25 selected tests for collaboration ViewModels, voice disposal, Result and Kanban repositories passed. Those are historical evidence for this plan, not a final refactor test result.

The checker currently misses re-exported ViewModel dependencies, domain-to-UI imports and ViewModel access to repository implementations. Provider inference additionally allows infrastructure objects to reach UI without an explicit SDK import.

**Skill-review checkpoint:** Tasks 1 and 2 are recorded as done by the ongoing implementation. The working tree contains the restored architecture docs, extracted local source modules and `local_write_atomicity_test.dart`. Their recorded execution results below are preserved, not independently recertified by this documentation review. The findings table describes the initial audit; do not treat every row as an unresolved current defect.

Concrete examples found in the source:

| Finding | Existing location | Owner |
|---|---|---|
| Task rules and Drift statements share methods | `data/repositories/tasks/task_repository_impl.dart` | Task 2 |
| Sync service imports a retention use case and owns account/sync orchestration | `data/services/sync/account_sync_engine.dart` and its parts | Task 3 |
| SDK account client and raw `UserRow` reach ViewModels through providers | `config/account_providers.dart`, `config/providers.dart`, `ui/core/view_models/shell_view_model.dart` | Task 3 |
| Billing ViewModel is shared application state used by other ViewModels | `ui/billing/view_models/billing_view_model.dart`, `config/billing_dependencies.dart` | Task 4 |
| Title editing coordinates task/project mutations after awaits | `ui/tasks/view_models/task_detail_view_model.dart` | Task 5 |
| Voice repository owns drafts, saving and presentation flags | `data/repositories/voice/voice_quick_add_repository.dart` | Task 6 |
| Timeline filters/sorts in build; Upcoming prepares groups in widgets | `ui/tasks/widgets/timeline_day.dart`, `upcoming_screen.dart`, `upcoming_day_groups.dart` | Task 7 |
| Selection is owned by a widget-side ChangeNotifier | `ui/tasks/widgets/task_selection_region.dart` | Task 8 |
| Persisted/shared state and preview state overlap in preferences/theme/focus | corresponding repositories, config providers and ViewModels | Task 9 |
| Collaboration exposes command strings and untyped response maps | `data/repositories/collaboration/collaboration_repository.dart` | Task 10 |
| Calendar repository exposes a concrete service-backed class; update controller owns popup state | `data/repositories/calendar/google_calendar_sync_repository.dart`, `data/repositories/updates/update_controller.dart` | Task 11 |
| A design-system source link names a missing file | `docs/design-system.md` points to `ui/core/themes/app_theme_settings.dart`; implementation is in `ui/settings/view_models/theme_settings_view_model.dart` | Tasks 1, 9 |

All paths in tables and task file lists are relative to the repository root; paths beginning `data/`, `domain/`, `ui/`, `config/` or `routing/` are relative to `apps/flutter/lib/`. Test file lists are relative to `apps/flutter/test/` (or `apps/flutter/` when prefixed with `test/`). Root `tool/` and Flutter `apps/flutter/tool/` are distinguished explicitly.

## 2. Reference architecture and project decisions

The official [architecture guide](https://docs.flutter.dev/app-architecture/guide) places source adapters below repositories, permits ViewModels to read repositories, and makes use cases optional. The [data-layer case study](https://docs.flutter.dev/app-architecture/case-study/data-layer) illustrates repositories using services and sharing application data. These responsibilities, rather than copying sample libraries, are the alignment target.

```text
View -> ViewModel -> Repository contract -> Repository implementation -> Service -> source
                  \-> UseCase ----------/

Source: SQLite / remote API / preferences / platform SDK
Composition: config creates services, repositories, use cases and Riverpod providers.
Observation: source changes -> repository domain stream -> ViewModel state -> View.
```

Target folders remain `config/`, `routing/`, `data/repositories/`, `data/services/`, `domain/models/`, `domain/use_cases/`, `ui/` and `utils/`.

### Boundary rules to implement

| Component | Owns | Must not own/access |
|---|---|---|
| View | rendering, layout, animation, focus/text controllers, simple navigation | application queries, sorting/filtering business data, persistence, service/repository calls |
| ViewModel | presentation transformation, immutable UI state, drafts, selection, validation feedback, typed actions | raw database/SDK types, source adapters, other ViewModels as data sources |
| Use case | complex/reused operations or cross-repository coordination | UI, Riverpod, concrete storage, mandatory forwarding wrappers |
| Repository | domain data, shared application/session state, caching, refresh, data-related rules, failure translation | UI state/controllers, other repository areas, ViewModel dependencies |
| Service | source-specific I/O, serialization of transport/storage records, platform handles and technical resource lifecycle | screen state, feature eligibility decisions, cross-feature business workflows |
| Composition | construction, lifetimes, subscription wiring, environment selection | hidden application workflows or SDK types exposed to UI consumers |

Technical resources such as database connections, recorder handles and request cancellation belong to their adapters; the official description of stateless services does not require recreating resources per call. Services must not become a second owner of domain or presentation state.

Project choices retained beyond the official baseline: Riverpod Notifier/AsyncNotifier; `Stream<T>` observation; `Result<T>` for recoverable operation outcomes; pure domain models; no ViewModel-to-ViewModel dependencies. These are project decisions, not claims that Flutter mandates those exact APIs.

### Application of the installed architecture skill

Reviewed against `dart-flutter:flutter-apply-architecture-best-practices` version 1.0.5, installed at `/Users/kabanya/.codex/plugins/cache/dart-flutter/dart-flutter/1.0.5/skills/flutter-apply-architecture-best-practices/SKILL.md`.

| Skill guidance | Application to Pomodoist |
|---|---|
| Lean Views, ViewModels with immutable state | Retain rendering mechanics in widgets; move application state and data projections to their ViewModels. |
| Repositories consume source services and expose domain models | Keep domain mapping, caching and shared data ownership in repositories; isolate I/O below them. |
| Use cases only for complex or reused logic | Allow direct ViewModel-to-repository calls, including simple presentation aggregation. A complex single-repository operation can still justify a use case. |
| Inject dependencies | Use Riverpod for composition and capture stable private dependencies in `build`; lower layers use constructor injection. |
| ChangeNotifier, ListenableBuilder, provider/get_it examples | Preserve the user's Riverpod decision. Do not migrate state management or add a second DI container to reproduce examples. |
| Freezed/built_value immutable models | Reuse current immutable values and installed tooling. Enforce immutable collections without rewriting every model or adding built_value. |
| Services organized by external source | The existing AppDatabase is one source. Local modules may partition its SQL for readability; they do not require one independent service/connection/cache per repository. |
| Unit-test ViewModels and repositories | Use existing fakes and targeted unit tests; retain the separately scoped official widget-testing gate. |

The skill supplies responsibilities, not a reason to copy every sample class. Its one-entry repository cache example must not be copied into multi-account/multi-ID data: real caches must respect their data keys and account lifetime.

### Shared-state contract requirements

Any new `watch...` contract must specify how a new subscriber obtains the current snapshot, how later updates are delivered, and who closes/cancels the source subscription. Use an initial current snapshot plus updates without a subscription gap; a bare broadcast stream that omits existing state is insufficient. Reuse one repository instance per intended application/account lifetime rather than starting I/O for every observing ViewModel.

Account identity/generation travels with account-scoped snapshots. A late operation must revalidate that generation before mutating local data as well as before publishing UI state. Keep per-screen loading/errors separate from the shared operation status needed to coordinate multiple screens. Do not shrink existing rich state to a few booleans if doing so loses error, expiry, tier, restore or verification information.

The official [recommendations](https://docs.flutter.dev/app-architecture/recommendations) distinguish strong, recommended and conditional practices. Keep Riverpod, existing immutable models and go_router. Implement command behavior through typed ViewModel actions with pending/error state; do not add a Command framework merely to match a sample. Test components with fakes; widget-level verification is separately scoped in Task 13.

## 3. Implementation order

| Task | Deliverable | Depends on |
|---|---|---|
| 1 | Canonical contract, baseline, coverage inventory | none |
| 2 | Local storage boundaries and atomic writes | 1 |
| 3 | Account, profile and sync contracts | 2, 12A |
| 4 | Shared billing/access repository and isolated billing UI | 3 |
| 5 | Task edit and creation orchestration | 2, 4 |
| 6 | Voice capture/data separated from draft UI | 3–5 |
| 7 | Prepared task/planning presentation state | 4, 5 |
| 8 | Screen-scoped selection and editors | 5, 7 |
| 9 | Preferences, themes, focus and productivity ownership | 2, 4, 8 |
| 10 | Typed collaboration boundary and lifecycle | 2, 3 |
| 11 | Calendar, updates and remaining platform composition | 3, 9, 10 |
| 12A | Boundary test/tool foundation and initial violation report | 1; perform before Task 3 |
| 12B | Complete enforcement and CI integration | 2–11, 12A |
| 13 | Final verification, documentation and acceptance | 12B |

This order favors complete vertical slices and preserved behavior. Do not make a large file-move-only pass before tests exist. Keep the application analyzable after each task. Stronger rules that would reject unconverted areas become blocking only with the task that resolves their violations; no permanent ignore list or compatibility implementation may remain.

Task 12 is split into an early foundation and a final gate, not postponed wholesale until after the refactor. Run its new checks in report mode against the initial source, record every existing violation with an owning task, and require each completed slice to remove its violations without adding new ones. In 12B the complete source must pass with normal failing exit codes and no exclusions. Do not reset the baseline to accept regressions. Task 12 remains pending until both parts pass.

Each task gets a focused diff review and a recorded command/result. Commit only under the user's chosen execution scope; task boundaries do not require 13 public commits.

## 4. Shared verification protocol

For every logic-changing step: add or strengthen the specified behavioral test, run it to establish the regression or missing contract, implement the change, then run that test and the relevant existing suite. Characterization tests preserving already-correct behavior should pass before and after extraction; do not invent a failing expectation that changes product behavior.

Root checks:

```sh
python3 tool/check_architecture.py
python3 -m unittest discover -s tool -p test_architecture.py
git diff --check
```

Flutter checks run from `apps/flutter`:

```sh
../../.fvm/flutter_sdk/bin/flutter analyze --no-pub
../../.fvm/flutter_sdk/bin/flutter test --no-pub test/utils/result_test.dart
```

Format only changed Dart files with the pinned Dart executable. Target explicit test files; do not run `flutter test` without file selection under a unit-only scope. A file name containing `controller` or `repository` is not proof that it has no widget tests: inspect it for `testWidgets`, `pumpWidget`, golden and platform requirements first. Split mixed files into unit and widget files while preserving both sets of assertions when necessary.

No broad catch-and-ignore, empty success result, removed assertion or longer timeout may be used to make extraction tests pass. Record an unrelated baseline failure separately; do not present the refactor as fully validated while an affected check fails.

## Task 1: Restore the canonical contract and establish complete coverage

**Files:** Modify `docs/architecture/flutter-app-architecture.md`, `docs/architecture/mvvm-implementation.md`, `docs/architecture/repository.md`; repair the stale source link in `docs/design-system.md`. Update this plan's execution ledger as work proceeds.

**Interfaces:** Produces the approved dependency rules and ownership table used by every later task. No runtime API change.

- [ ] Record `git status --short`, `git rev-parse HEAD`, `.fvmrc` and the lockfile state. Preserve the current document edit; replace its superseded design deliberately, not with a blanket checkout restore.
- [ ] Rewrite the canonical document to the diagram in section 2; label target versus implemented behavior accurately.
- [ ] Replace the duplicate architecture exposition in `mvvm-implementation.md` with a link and any unique implementation notes. Point `repository.md` at the canonical contract.
- [ ] Correct the design-system theme-settings link without changing visual rules.
- [ ] Inventory every handwritten source in the coverage appendix. Assign each source to its existing task owner, including conditional files and Dart parts. Generated files are regenerated from owners, never independently redesigned.
- [ ] Run the shared baseline checks; record pass/failure and whether each selected test is unit-only.

**Acceptance:** One canonical architecture definition; no document simultaneously requires `ViewModel -> Service -> Repository`; all source families have an owner.

**Follow-up from skill review:** Check the use-case wording explicitly includes complex or reused logic even when it reads only one repository. Do not describe all use cases as necessarily cross-repository. The completed documentation rewrite is retained; this is a targeted wording check during execution.

## Task 2: Separate local I/O while preserving atomic repository operations

**Modify:** `data/repositories/{tasks,projects,labels,kanban,focus,productivity,achievements}/*_repository_impl.dart`, `data/repositories/calendar/drift_calendar_integration_repository.dart`, `data/services/local/database/app_database.dart`, `data/services/local/{kanban_transition_coordinator,outbox_service,shared_access,task_repository_support}.dart`, `config/providers.dart`.

**Local source modules (now present in the Task 2 working-tree changes):** `data/services/local/task_local_service.dart`, `project_local_service.dart`, `label_local_service.dart`, `kanban_local_service.dart`, `focus_local_service.dart`, `productivity_local_service.dart`, `achievement_local_service.dart`, `calendar_local_service.dart`. Review and reuse these modules around the single existing database; do not recreate them or require a matching service for every repository. Shared SQL stays in one lower-level helper when two modules need it. A module is justified by source I/O isolation, not by a naming convention or line-count target.

**Tests:** Extend `test/core_features_test.dart`, `kanban_repository_test.dart`, `project_hierarchy_test.dart`, `shared_creator_test.dart`, `shared_repository_test.dart`, `shared_focus_history_test.dart`, `sync_queue_repository_test.dart`; create `test/data/local_write_atomicity_test.dart` for fault-injected transaction checks.

**Interfaces:** Preserve the public methods of `TaskRepository`, `ProjectRepository`, `LabelRepository`, `KanbanRepository`, `FocusRepository`, `ProductivityRepository`, `AchievementRepository`, and `CalendarIntegrationRepository`. Local services may use Drift rows internally. No row or companion escapes repository contracts.

- [ ] Characterize create, duplicate, move, recurring occurrence, completion, undo and permission checks using the existing in-memory database setup.
- [ ] Add a failure injection at an outbox write and a secondary-row write. Assert no task/status/focus/outbox partial rows are committed and that retry creates exactly one operation.
- [ ] Extract direct SQL into local services by operation, keeping repository decisions and domain mapping above that boundary. Do not just move the entire existing repository implementation under a Service name.
- [ ] Keep transaction ownership in one shared database connection. Reuse Drift nested transaction semantics deliberately; do not commit each sub-operation independently.
- [ ] Preserve `Result.getOrThrow()` inside transaction callbacks: an inner `Failure` must be rethrown before the callback returns, otherwise Drift can commit the partial work. Convert the thrown failure to the outer `Result` only after rollback. Add a regression for a nested operation returning `Failure` rather than throwing directly.
- [ ] Separate Kanban transition decisions from SQL execution: repository policy computes the requested transition; the shared local write operation applies the affected rows and outbox commands together.
- [ ] Reuse `SharedAccess` checks in the data boundary. Preserve authorization on every mutating path, including sync-originated and shared-project paths; this task does not weaken security checks because a ViewModel also validates input.
- [ ] Re-run the affected repository suites and analyze. Verify native and conditional database imports resolve statically.

Transaction check to retain in the new test file, using the existing Drift test database constructor and seeded fixture from `kanban_repository_test.dart`:

```dart
final beforeTasks = await db.select(db.tasks).get();
final beforeCommands = await db.select(db.syncCommands).get();
// Invoke createTask with an OutboxService fake whose enqueue methods throw.
final result = await repository.createTask(input);
expect(result, isA<Failure<String>>());
expect(await db.select(db.tasks).get(), beforeTasks);
expect(await db.select(db.syncCommands).get(), beforeCommands);
```

The test fixture must implement the existing `OutboxService` interface and throw from both `enqueue` and `enqueueBatch`; do not simulate rollback by preventing the first database write.

**Acceptance:** Repository contracts unchanged; local I/O isolated; transaction rollback proven; no generic transaction framework or schema change.

**Skill-review qualification:** A repository may map Drift records returned by its local service and construct persistence commands inside the data layer. The public contract and UI must not expose those types. Do not add another DTO/mapping layer solely to remove a Drift import from a repository implementation; moving direct source calls behind a service does not imply banning all source types from the implementation that maps them.

## Task 3: Put account, local profile and synchronization behind domain contracts

**Modify:** `config/{account_providers,account_management_dependencies,providers,bootstrap}.dart`, `config/auth/*.dart`, `config/platform/watch_companion.dart`, `data/repositories/account/*.dart`, `data/services/{account,auth,sync}/*.dart`, `ui/settings/view_models/{auth,settings,voice_settings}_view_model.dart`, `ui/core/view_models/{shell,app_startup,app}_view_model.dart`, `ui/collaboration/view_models/share_project_view_model.dart`, `routing/router.dart`.

**Create:** `domain/models/account/account_session.dart`, `data/repositories/account/account_session_repository.dart`, `sdk_account_session_repository.dart`, `data/repositories/sync/sync_repository.dart`, `local_sync_repository.dart`, `domain/use_cases/account/sync_account_use_case.dart`, `test/data/account_session_repository_test.dart`, `test/domain/sync_account_use_case_test.dart`.

**Interfaces:** Reuse `PomodoistAccountProfile`, `PomodoistAccountOverview` and `Result`. The session contract exposes identity and a monotonically increasing generation, never an SDK session/token object:

```dart
typedef AccountSession = ({String? userId, int generation});

abstract interface class AccountSessionRepository {
  AccountSession get currentSession;
  Stream<AccountSession> watchSession();
  Stream<PomodoistAccountProfile?> watchProfile();
  Future<Result<void>> refresh();
}
```

The sync contract receives captured identity and retention inputs rather than another repository:

```dart
abstract interface class SyncRepository {
  Future<Result<Set<String>>> syncNow({
    required AccountSession session,
    required DateTime? retentionCutoff,
  });
}
```

`SyncAccountUseCase` coordinates the account session and synchronization. Its `call({required DateTime? retentionCutoff})` captures `currentSession` before awaiting. Task 3 preserves the existing cutoff producer until Task 4 can wire the corrected billing owner; in Task 4 the coordinator captures account/billing repository snapshots and computes the cutoff itself. This is one implementation changed in place, without an alternate compatibility path. Credentials stay inside source adapters and are bound to the captured account; a mutable global account client must not silently redirect an in-flight request to another user. The sync repository rechecks generation under the existing account-transition serialization before applying changes, not merely before publishing UI state.

- [ ] Test A-to-B account change with an unresolved profile request, sign-out during sync, guest-to-account adoption, and expired/retried auth startup. Complete A's request after B is active and assert no A profile/state is published.
- [ ] Map `AccountAuthState`, `AccountClient`, `UserRow` and SDK profile data to domain snapshots inside account repository implementations.
- [ ] Replace `currentUserProvider` raw-row consumption in shell/sidebar and `accountClientProvider` consumption in ViewModels with domain session/profile providers.
- [ ] Keep SDK initialization in source adapters. Move application retries/status and profile refresh ownership into repositories; keep composition responsible only for their construction/lifetimes.
- [ ] Split sync orchestration from source mechanics. Move account-transition/retention decisions out of `AccountSyncEngine`; retain queue/cursor/transport code as source operations with explicit inputs. Update all `part` files together.
- [ ] Reuse the existing retention calculation from `domain/use_cases/account/pomodoist_retention.dart`; the sync service must no longer import a use case. Call it from the coordinating use case and pass its result down.
- [ ] Route foreground/background/Watch startup through the same account and sync contracts. Preserve serial account-owner transitions, request timeouts, idempotency keys and sync protocol shapes.

**Run:** unit files `account_bootstrap_test.dart`, `account_auth_watchdog_test.dart`, `account_sync_account_boundary_test.dart`, `account_sync_lifecycle_test.dart`, `account_sync_mapping_test.dart`, `account_sync_focus_test.dart`, `shared_sync_test.dart`, plus the two new files.

**Acceptance:** No ViewModel receives an SDK account or Drift user row; old-account work cannot publish into a new session; sync policy does not depend upward from services into use cases.

## Task 4: Make subscription access shared repository state

**Modify:** `ui/billing/view_models/billing_view_model.dart`, `data/repositories/billing/{billing_repository,store_billing_repository,unavailable_billing_repository}.dart`, `data/services/billing/{billing_store,billing_offers}.dart`, `domain/models/billing/{billing_models,billing_store_models}.dart`, `config/{billing_dependencies,billing_store_dependencies,account_providers,providers,bootstrap}.dart`, `ui/{voice,tasks,onboarding,settings}/view_models/*.dart` that consume billing state.

**Create:** `domain/models/billing/billing_access.dart`, `test/data/billing_access_repository_test.dart` (tests access through the existing billing contract, not a second repository). Rename/refactor `store_billing_repository.dart` to `billing_repository_impl.dart`, with `AppBillingRepository implements BillingRepository`, for the application billing owner once its responsibilities include the existing StoreKit and Stripe paths. Move source-specific purchase mapping into the existing billing source modules. Update callers directly and remove the replaced file.

**Interfaces:** Extend the existing `BillingRepository` instead of adding an independent access repository. One injected billing repository owns the catalog, verified entitlement state, refresh/restore and purchase-event processing for the current account. Other features observe a read-only access projection of that same owner. `UnavailableBillingRepository` remains an alternative implementation only for an actually unsupported environment, never a second live owner.

```dart
typedef BillingAccess = ({
  bool hasActiveEntitlement,
  bool hasLocalStoreKitEntitlement,
  bool loading,
});

// Add these members to the existing BillingRepository contract.
BillingAccess get currentAccess;
Stream<BillingAccess> watchAccess();
Future<Result<void>> refreshAccess();
```

`BillingAccess` is a read-only projection for consumers that need only access/loading. It does not replace the existing entitlement/catalog domain values or richer state required by billing UI. `watchAccess()` includes the current snapshot and updates; `refreshAccess()` reports failure through Result without claiming that failed verification succeeded. Account identity and entitlement inputs are injected as domain snapshots/events by composition; business decisions stay in the billing owner. No repository calls another repository.

- [ ] Characterize access for free, monthly, annual, lifetime, expired, restored and unavailable-store states using existing billing fakes.
- [ ] Add account-generation, duplicate purchase callback, cancellation, unverified transaction and late refresh tests. Assert no entitlement gain from an unverified/expired proof and no duplicate finishing.
- [ ] Move shared entitlement state, refresh coordination, expiry and verified purchase bookkeeping from BillingViewModel into the single `BillingRepository` implementation. It owns the one application subscription that processes purchase updates. Keep paywall selection and screen-specific feedback in BillingViewModel; keep purchase/restore single-flight guards in the repository so two screens cannot submit the same unsafe operation concurrently.
- [ ] Preserve StoreKit/Stripe channel selection, transaction ownership/linking, timeouts, existing feature gates and disabled return-offer settings. No purchase or offer activation during this work.
- [ ] Replace Voice/Search/Browse and retention consumers of `billingViewModelProvider` with `BillingRepository.watchAccess()`/`currentAccess` via typed providers. The access-check operation calls `refreshAccess()`, never another ViewModel's `reload()`.
- [ ] Finish Task 3's `SyncAccountUseCase` wiring: inject the existing billing contract alongside account and sync contracts, capture their current session/access inputs before awaiting, compute retention inside the use case and remove the intermediate cutoff argument from its callers. Source adapters continue to receive a captured cutoff/session and never fetch a ViewModel.
- [ ] Replace `config/billing_dependencies.dart` mixed exports. Composition must not re-export a paywall, another ViewModel and raw store types as a single public dependency surface.
- [ ] Move billing callback/provider wiring out of the ViewModel file where it is global composition; eliminate `BuildContext` from application data operations. Sign-in remains a UI outcome/intent handled above data.

**Run:** `billing_access_tier_test.dart`, `billing_offers_test.dart`, `billing_storekit_bridge_test.dart`, `billing_storekit_test.dart` and the new access repository tests, selecting unit cases only.

**Acceptance:** Shared access works without a paywall/ViewModel being mounted; catalog, purchase processing and access have one repository owner; all consumers see the same account-scoped snapshot; all existing billing security and ownership rules remain intact.

## Task 5: Consolidate task edit, Quick Add, import and focus scenarios

**Modify:** `ui/tasks/view_models/{task_detail,task_item,quick_add,quick_add_details,timeline}_view_model.dart`, `domain/use_cases/{quick_add,tasks,focus,account}/*.dart`, `config/{providers,voice_dependencies,task_focus_dependencies}.dart`.

**Create:** `domain/use_cases/tasks/edit_task_title_use_case.dart`, `data/repositories/local/local_transaction.dart`, `test/domain/edit_task_title_use_case_test.dart`. Extend the voice batch rollback tests with the cross-repository case described below.

**Interfaces:** Reuse `TaskItem`, `UpdateTaskPatch`, `QuickAddParser`, `TaskRepository`, `ProjectRepository`, `FocusPresetItem` and `Result`. The new operation is:

```dart
Future<Result<void>> call(
  TaskItem task,
  String input, {
  required DateTime now,
  required FocusPresetItem? focusPreset,
});
```

The use case receives repositories/parser through its constructor and does not acquire providers. ViewModel captures task, time, preset and use case before awaiting. Do not add an edit use case for simple description writes.

Voice batch creation already spans project and task repositories in one database transaction. Preserve that capability with one narrow callable contract alongside the repository contracts, not a repository that calls other repositories:

```dart
// data/repositories/local/local_transaction.dart
typedef RunLocalTransaction = Future<T> Function<T>(Future<T> Function() action);
```

Composition injects the existing `AppDatabase.transaction` method through that signature. The voice batch use case invokes it around repository calls, with all participants using the same database/transaction context. No new transaction manager, global transaction state, domain import of Drift or extra wrapper class is needed. The transaction callback must await every local write and use `getOrThrow()` on inner failures; apply `Result.capture` outside the transaction. Fetch transcription, remote decomposition and other network-dependent inputs before opening it. This local transaction contract is an explicit project extension to the basic guide, justified by the existing atomic batch behavior.

- [ ] Characterize title parsing, quoted project/label metadata, schedule movement, focus estimate calculation and empty-input handling before extraction.
- [ ] Test project creation failure after a successful task patch and task move failure after project resolution. Preserve and explicitly report existing partial-success semantics; do not claim several repository calls are one transaction. Do not create a new project again on a retry if the repository already resolves the existing name.
- [ ] Extract title-edit coordination from `TaskEditorViewModel.saveTitle`; keep pending/error state and draft retention in its ViewModel.
- [ ] Remove post-await `ref.read` from these workflows. Capture dependencies first; suppress late UI updates after disposal/account-generation changes without misreporting an already committed write as uncommitted.
- [ ] Keep Quick Add, CSV import, account deletion and focus launch use cases only where they coordinate or encapsulate meaningful logic. Retain their public behavior and current tests.
- [ ] Rename `quickAddServiceProvider` to `quickAddUseCaseProvider` across all consumers and tests; no compatibility alias. Preserve `createTask` and `createTaskWithContext` signatures.
- [ ] Move voice batch orchestration out of `config/voice_dependencies.dart` into the existing voice use case; inject `RunLocalTransaction` and the captured dependencies. Config wires the function but does not perform the workflow. Test failure on the second task after the first task and a newly resolved project have been written: task rows, project rows, labels and outbox must all return to their pre-call state. Repeat successfully and assert one resulting batch.

**Run:** `quick_add_default_date_test.dart`, `quick_add_analysis_test.dart`, `quick_add_metadata_edit_test.dart`, `csv_task_import_test.dart`, `task_focus_launcher_test.dart`, unit cases from `core_features_test.dart`, and the new use-case tests.

**Acceptance:** No provider reads inside domain operations; meaningful composition is reusable; simple ViewModel-to-repository actions remain simple; batch transaction guarantees unchanged.

## Task 6: Separate voice session data from retained draft presentation

**Modify:** `data/repositories/voice/voice_quick_add_repository.dart`, `data/services/voice/*.dart`, `domain/models/voice/voice_quick_add_state.dart`, `ui/voice/view_models/voice_quick_add_view_model.dart`, `config/{voice_dependencies,account_providers}.dart`, voice consumers in `ui/tasks/widgets/` and `ui/quick_add/widgets/global_quick_add_window.dart`.

**Create:** `data/repositories/voice/voice_capture_repository.dart`, `captured_voice_repository.dart`, `domain/models/voice/voice_capture_state.dart`, `test/ui/voice/voice_quick_add_view_model_test.dart`.

**Interfaces:** Move the existing source capture methods behind a repository contract with domain capture status, transcript, access failure and retry capability. Reuse `VoiceCaptureService` and the existing recording store. Keep `voiceQuickAddViewModelProvider(session)` as the UI entry point; `session` is the retained overlay identity, not the route.

- [ ] Add unit tests with controlled futures/streams for close during capture, close during transcription, retry, permission denial, late decomposition, account change and disposal.
- [ ] Separate device/capture/transcription state from editable drafts, draft revision, saving and panel presentation. Put the latter in immutable ViewModel state.
- [ ] Move locale/smart-mode policy to domain inputs and the existing preferences repository; source adapters must not read Riverpod or UI controllers.
- [ ] Replace `addListener` mirroring of a concrete repository with domain streams and a contract. Capture subscription targets locally before registering disposal callbacks.
- [ ] Keep recording lifetime attached to the retained overlay/session. Route changes must not abort a still-open recording; closing the session must release recorder/subscriptions exactly once.
- [ ] Route access checks through Task 4's existing billing repository and saving through Task 5's voice use case. A failed save keeps editable drafts; a duplicate submit writes once. Do not add another billing/access repository for voice.
- [ ] Remove the old combined repository after every caller and test has moved. Preserve existing recording file formats and recovery behavior.

**Run:** `voice_quick_add_controller_test.dart`, `voice_quick_add_session_test.dart`, `voice_recording_store_test.dart`, `backend_voice_test.dart`, `voice_transcription_mode_test.dart`, `ui/focus/voice_repository_lifecycle_test.dart` and the new ViewModel tests. Browser recording storage verification is a separate gate.

**Acceptance:** Voice source adapters know no screen state; drafts survive permitted rebuilds, remain independent per session and are never published after disposal.

## Task 7: Prepare task and planning data in ViewModels

**Modify:** `ui/tasks/view_models/{timeline,upcoming,task_list,task_search_palette,search,browse,priority_matrix,project,projects}_view_model.dart`, `ui/planning/view_models/today_view_model.dart`; callers in `ui/tasks/widgets/{timeline_screen,timeline_day,timeline_helpers,timeline_project_header,upcoming_screen,task_search_palette,kanban_screen}.dart`.

**Move:** `ui/tasks/widgets/upcoming_day_groups.dart` to `ui/tasks/view_models/upcoming_day_groups.dart` without changing grouping semantics. Update every importer, including tests.

**Create:** `ui/tasks/view_models/timeline_day_data.dart`, `test/ui/tasks/timeline_day_data_test.dart`.

**Interfaces:** Keep existing `UpcomingDayGroup`/`UpcomingTaskRow` APIs and `buildUpcomingDayGroups`. A new immutable `TimelineDayData` contains `allDay`, `visibleTimed`, `beforeHours`, `afterHours` task lists and project grouping. Its pure builder accepts tasks, selected day and existing `TimelineVisibleHours`; screen geometry and pixel placement remain in widgets.

- [ ] Move existing grouping/filtering tests with their implementation; add same-day timezone boundaries, completed tasks, recurring occurrences, missing projects, cycles/orphans and stable ordering cases.
- [ ] Extract task membership and ordering from `_TimelineDay.build`; keep overlap geometry, viewport measurement and drag feedback in widgets where they depend on layout.
- [ ] Have Upcoming's ViewModel produce counts/groups for its selected day; avoid running the same traversal in several widgets.
- [ ] Preserve `TaskMotionScope.retainedTasks` semantics: animation-only rows can be rendered temporarily, but action eligibility comes from live ViewModel data. Do not filter them out so early that exit animations disappear.
- [ ] Move search result eligibility, grouping and filtering from the palette widget into its ViewModel; preserve stable IDs and revalidation before actions.
- [ ] Apply the same ownership rule to Kanban, Today, Browse, Matrix and project lists. Reuse existing `timeline_project_layout.dart`, `task_search.dart`, `today_tasks.dart` and hierarchy helpers rather than creating competing algorithms.
- [ ] Use Riverpod `select` and the existing shared ticker where appropriate. Do not turn all task lists into per-second recomputations.

Example regression using the moved existing function:

```dart
test('selected empty day remains available for task creation', () {
  final day = DateTime(2026, 9, 20);
  final groups = buildUpcomingDayGroups(const [], selectedDate: day);
  expect(groups, hasLength(1));
  expect(groups.single.date, day);
  expect(groups.single.isSynthetic, isTrue);
  expect(groups.single.rows, isEmpty);
});
```

**Run:** `upcoming_day_groups_test.dart`, `today_tasks_test.dart`, `task_search_test.dart`, `browse_summary_test.dart`, `task_time_test.dart`, `task_motion_logic_test.dart` and the new timeline tests.

**Acceptance:** Widgets consume prepared business-data projections; layout and animation remain local; task membership/order and animation behavior are preserved.

## Task 8: Give each screen instance ownership of selection and editing state

**Modify:** `ui/tasks/widgets/task_selection_region.dart`, `task_list_item.dart`, task detail/editor parts, Quick Add widgets; `ui/tasks/view_models/{task_selection,task_detail,quick_add_details,quick_add}_view_model.dart`, `ui/quick_add/view_models/global_quick_add_view_model.dart`, `routing/task_detail_navigation.dart`.

**Create:** `test/ui/tasks/task_selection_view_model_test.dart`, `task_editor_lifecycle_test.dart`, `test/ui/quick_add/quick_add_scope_test.dart`.

**Interfaces:** Extend `TaskSelectionState` with an immutable selected-ID set and active/pending state. Add typed `begin`, `toggle`, `toggleAll`, `retainVisible` and `clear` actions to `TaskSelectionViewModel(identity)`. Existing bulk repository operations remain behind this ViewModel. Widgets keep selection gestures and dialog/navigation callbacks.

- [ ] Create two ProviderContainer/provider-family instances with different screen identities. Select/edit in one and assert the other remains unchanged; persisted task changes must appear in both.
- [ ] Test removal/move of a selected task while a bulk action or dialog is pending. Resolve targets against current valid IDs and preserve partial-failure reporting.
- [ ] Move `_selectedIds`, active selection and pending mutation state from `TaskSelectionController` into its ViewModel. Keep pointer geometry and widget context in the view-side adapter.
- [ ] Move task and Quick Add draft values/validation into their owning ViewModels while keeping TextEditingController, focus and text selection mechanics in widgets.
- [ ] Test failed save followed by close/navigation: draft remains and navigation is blocked; successful retry releases the existing guard. Guard behavior must not depend on a disposed provider.
- [ ] Preserve retained editor/overlay identity across responsive layout changes and separate native Quick Add views. Do not key state solely by a globally shared task ID when two editors need independent drafts.
- [ ] Keep haptic/animation notifications tied to committed action outcomes; synchronization or ordinary rebuilds must not replay them.

**Run:** new unit files plus unit cases in `task_detail_navigation_test.dart`, `quick_add_metadata_edit_test.dart`, `task_motion_logic_test.dart`, `focus_completion_motion_test.dart`.

**Acceptance:** Screen instances own drafts/selection; shared persisted state is still shared; save/navigation and duplicate-action guards retain behavior.

## Task 9: Align preferences, themes, focus, achievements and productivity

**Modify:** `data/repositories/settings/*.dart`, `data/repositories/voice/voice_preferences_repository.dart`, `data/repositories/focus/{focus_preferences,focus_completion_repository}.dart`, `data/repositories/achievements/achievement_announcement_repository.dart`, `config/{task_preferences,voice_preferences,focus,theme_settings,theme_mode,productivity}_dependencies.dart`, `config/{app_language,keyboard_shortcuts}.dart`, `ui/settings/view_models/{theme_settings,task_settings,voice_settings,keyboard_shortcuts}_view_model.dart`, `ui/core/view_models/{app_theme_mode,app_zoom}_view_model.dart`, all focus/productivity ViewModels.

**Create:** `test/data/shared_state_lifecycle_test.dart`. Split contract/implementation files for concrete-only repositories when adding a contract; names use the existing area plus `_repository.dart` / `_repository_impl.dart`.

**Interfaces:** Reuse the existing preference value types and keys. Replace repository-level Flutter `Listenable`/`ChangeNotifier` exposure with immutable domain snapshots and streams where it crosses the data contract. This is the project's framework-independent data choice, not a Flutter requirement to replace every ChangeNotifier in UI.

- [ ] Test hydration racing with a user edit: delayed disk values must not overwrite a more recent selection. Preserve existing load generations and dirty-key tracking.
- [ ] Reuse `PreferencesService` for SharedPreferences I/O. Keep persistent state/cache in repositories and view-local pending/error/draft state in ViewModels.
- [ ] Separate saved theme selection from editor draft/preview. Preserve the documented cross-window live preview deliberately through one explicit preview owner; do not accidentally make all ordinary screen drafts global.
- [ ] Preserve background image preparation/storage, failed-write retry, backup keys, cancel restoration, Web Locks and cleanup-after-success rules. Keep Color/ThemeData/rendering conversion in UI; store plain values below it.
- [ ] Classify focus completion and achievement announcements by lifetime: shared event identity/deduplication belongs to an application-session owner; per-screen animation phase belongs to the ViewModel/view. Do not discard shared exactly-once behavior by moving everything into autoDispose screen state.
- [ ] Preserve a single focus clock and event source. Retain focus time aggregation, paused elapsed time and completion state across routes/windows.
- [ ] Verify productivity/achievement repository projections remain domain values, move any remaining raw SQL through Task 2's services, and keep reports/today aggregation in the appropriate ViewModel or reusable pure helper.
- [ ] Consolidate current settings, zoom, theme and keyboard providers so widgets receive UI values and typed actions instead of storage controllers.

**Run:** `data/task_preferences_repository_test.dart`, `data/language_voice_preferences_repository_test.dart`, `theme_editor_validation_test.dart`, `theme_image_store_test.dart`, `app_zoom_test.dart`, `keyboard_shortcuts_test.dart`, `ui/focus/focus_state_repositories_test.dart`, `productivity_parity_test.dart`, `focus_completion_celebration_controller_test.dart` and the new lifecycle tests. Split mixed widget cases before selecting files.

**Acceptance:** Shared versus local state has a named owner; persisted keys/data are unchanged; theme/focus behavior is not redesigned.

## Task 10: Replace collaboration transport maps with typed domain outcomes

**Modify:** `data/repositories/collaboration/{collaboration_repository,drift_collaboration_repository}.dart`, `data/services/collaboration/collaboration_api.dart`, `domain/models/collaboration/{collaboration_models,public_project,collaboration_conflict}.dart`, `config/collaboration_dependencies.dart`, all `ui/collaboration/view_models/*.dart` and their widgets.

**Create:** `domain/models/collaboration/collaboration_responses.dart`, `test/data/collaboration_mapping_test.dart`. Extend `test/ui/account/collaboration_view_models_test.dart` rather than duplicating its fakes.

**Interfaces:** Replace UI-facing `action(String, Map)` and `Map<String, dynamic>` results with named methods and typed models for members, invitations, comments, public projection and action outcomes. Keep the wire command names/map encoding inside `CollaborationApi`. Reuse `SharedScope`, `CollaborationConflict` and existing public-project projection types.

- [ ] List each currently used action and its exact request/response fields from repository callers; map every caller to a named domain operation before removing the generic public method.
- [ ] Add transport fixture tests for missing/invalid fields, expired/revoked invitation, duplicate member data and unknown role. Reject malformed permission-bearing data rather than treating it as owner/editor access.
- [ ] Move response parsing into the data boundary; keep UI copy/localization and busy/error feedback in ViewModels.
- [ ] Preserve generation checks, scope-ID checks, invitation deduplication and token validation before requests.
- [ ] Test a scope change while members load, account sign-out during invitation acceptance and conflict resolution after a remote update. Old results must not replace the new scope's state.
- [ ] Preserve all shared-subtree permission checks and server payloads. No server/RLS/schema changes are included.

**Run:** `ui/account/collaboration_view_models_test.dart`, `collaboration_policy_test.dart`, `shared_repository_test.dart`, `shared_transfer_test.dart`, `shared_creator_test.dart` and the new mapping tests.

**Acceptance:** UI does not interpret server action strings or untyped response maps; sharing and conflict behavior remains compatible.

## Task 11: Complete calendar, updates, platform and composition boundaries

**Modify:** `data/repositories/calendar/*.dart`, `data/services/google_calendar/*.dart`, `data/repositories/updates/update_controller.dart`, `data/services/updates/*.dart`, `domain/models/updates/update_contracts.dart`, `config/{calendar,update}_dependencies.dart`, `config/{bootstrap,providers,account_providers,keyboard_shortcuts}.dart`, `config/auth/*.dart`, `config/platform/*.dart`, `ui/google_calendar/view_models/google_calendar_view_model.dart`, `ui/updates/view_models/update_view_model.dart`, `ui/core/view_models/*.dart`, `routing/router.dart`.

**Create:** `data/repositories/notifications/notification_repository.dart`, `local_notification_repository.dart`, `data/repositories/updates/update_repository.dart`, `test/data/update_repository_lifecycle_test.dart`, `test/ui/core/composition_contract_test.dart`. Split `GoogleCalendarSyncRepository` into a pure contract and implementation using its existing operation names.

**Interfaces:** Preserve calendar `connect`, `sync`, `disconnect` outcomes, update channel/offer/install semantics and notification commands. Update repository domain state includes availability, offer, phase/progress and recoverable failure; popup visibility belongs to the UI presentation owner. Notification scheduling receives domain requests/copy, not BuildContext.

- [ ] Route settings notification actions through `NotificationRepository`; remove direct `notificationSchedulerProvider` use from ViewModels.
- [ ] Translate calendar authorization errors into domain failures; prevent UI from testing service exception types. Preserve reconnect and noninteractive sync behavior.
- [ ] Move SharedPreferences access from `SharedUpdatePreferences` to the existing preference service. Give update operations a repository contract and separate popup dismissal/visibility from shared download/install progress.
- [ ] Test repeated update checks, dismiss while downloading, disposal during source response and install failure. Never perform a real installation; use existing installer/source fakes.
- [ ] Audit haptics, audio, shortcuts, native links, captcha, Watch and Quick Add window wiring. Source handles stay in services, domain-facing app actions stay behind repository/use-case contracts, and rendering-only platform UI remains in UI. Do not add empty repositories for pure layout helpers.
- [ ] Reduce large config files by moving only remaining application behavior to its owner. Expose typed domain repository/use-case providers; do not barrel-export UI and infrastructure together.
- [ ] Test construction of main and Quick Add provider scopes with fakes, auth redirect state changes and startup teardown without launching the app.
- [ ] Verify all main entry points, conditional imports and tool consumers still resolve. Keep platform-specific permissions and distribution gates unchanged.

**Run:** `google_calendar_server_sync_test.dart`, `google_calendar_sync_lifecycle_test.dart`, `desktop_update_controller_test.dart`, `desktop_update_provider_test.dart`, `desktop_update_network_test.dart`, `native_link_coordinator_test.dart`, `native_account_startup_test.dart`, `notification_scheduler_linux_test.dart`, `notification_scheduler_windows_test.dart`, `platform_quick_add_test.dart`, `watch_companion_test.dart` and the new tests; select unit-only files/cases.

**Acceptance:** No remaining infrastructure object is exposed to a ViewModel through a provider; all app roots use the same architecture; platform actions retain their behavior.

## Task 12: Enforce actual symbol boundaries, not just directory names

**Modify:** `tool/check_architecture.py`, `tool/test_architecture.py`, `apps/flutter/pubspec.yaml`, `apps/flutter/pubspec.lock`, `.github/workflows/validate.yml`, `Makefile`.

**Create:** `apps/flutter/tool/check_architecture_types.dart`, `apps/flutter/test/architecture/type_boundaries_test.dart`. Use the existing locked analyzer package as a direct dev dependency (`analyzer: 10.0.1`), without upgrading it or adding runtime dependencies.

**Interfaces:** Keep the Python check entry point and all existing server/manifest validation. Add a resolved-Dart check with deterministic diagnostics containing file, line, imported/referenced symbol and violated rule; nonzero exit on violations. Analyze all handwritten Dart libraries, including resolved `part` ownership and conditional branches where statically available. Keep the semantic tool scoped to the demonstrated gaps: declaration ownership, concrete/infrastructure types at UI boundaries, re-exports and inferred provider return types. Do not turn this into a general custom lint framework.

**12A — before Task 3:** Add negative/positive fixtures, build the minimal symbol-aware checker, and record initial diagnostics with owning tasks. Report mode still prints every diagnostic and returns failure; early reports are evidence of remaining work, not green acceptance. Do not add permanent suppressions. Integrate the normal full-source blocking gate only after the owning refactor slices are complete.

**12B — after Task 11:** Run the final full-source check, resolve remaining findings, and wire it into CI/local verification. The steps below belong to 12A except final full-source cleanup and CI enforcement, which belong to 12B.

- [ ] Extend Python regression fixtures for `domain -> ui`, `domain -> config/routing`, ViewModel -> concrete repository, SDK packages missing from the current prefix list, re-export chains and services -> use cases. Detect actual calls/dependencies between separate repository instances even within the same area; importing or implementing one's own repository contract and using pure area helpers must remain legal.
- [ ] Add the following exact isolated regression to `tool/test_architecture.py` using its existing temporary-project fixture pattern; it must fail on the current checker before the fix:

```python
def test_domain_cannot_import_current_ui_directory(self):
    with TemporaryDirectory() as directory:
        root = Path(directory)
        files = {
            'server/core-manifest.json': '{"helpers":[],"functions":[]}',
            'apps/flutter/lib/domain/models/task.dart':
                "import '../../ui/tasks/widgets/screen.dart';",
            'apps/flutter/lib/ui/tasks/widgets/screen.dart': '',
        }
        for name, source in files.items():
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(source)
        (root / 'server/supabase/functions').mkdir(parents=True)
        failures = '\n'.join(check(root))
        self.assertIn('domain depends on infrastructure/UI', failures)
```

- [ ] Use Dart resolution for inferred provider result types and referenced elements: accessing `AccountClient`, a Drift row, a source adapter or another ViewModel through `ref.read/watch/select` must be detected. Include typedef, generic wrapper, extension method and re-export fixtures. Do not ban every transitive dependency of composition: a Provider returning a repository interface may legitimately construct a concrete implementation.
- [ ] Define positive fixtures: `Notifier` UI state, a domain-returning StreamProvider, use case -> abstract repository, constructor injection of the pure `RunLocalTransaction` contract, repository -> service, config constructing implementations, and widgets using Flutter framework services for keyboard/focus behavior.
- [ ] Replace filename-suffix assumptions with actual contract declarations in resolved Dart. Current `TaskDecomposer` and concrete classes named `*Repository` must not evade classification.
- [ ] Preserve generated-file handling while examining generated types referenced by handwritten code. Do not inspect build caches as source or allow generated row types in public contracts.
- [ ] In 12B, run the strict checks on the complete client and resolve all findings in their owning tasks. Keep no broad ignores or permanent allowlist for known violations; do not mark 12 complete because 12A's fixtures pass while application diagnostics remain.
- [ ] Wire the semantic check after dependency resolution in CI and the local architecture target. Preserve existing server closure, packaging, release and browser jobs; do not remove unrelated checks.

**Run from root:** Python architecture check/tests. **Run from `apps/flutter`:** pinned `dart run tool/check_architecture_types.dart`, `flutter test --no-pub test/architecture/type_boundaries_test.dart`, `flutter analyze --no-pub`, and pinned `dart analyze tool`.

**Acceptance:** The real bypasses found in this task fail in isolation, legitimate DI stays legal, and the entire refactored source passes without exemptions. Behavioral responsibility still requires review; no import checker proves that a method contains only appropriate business logic.

## Task 13: Final verification, evidence and documentation

**Modify:** canonical architecture docs, this execution ledger and relevant existing tests. Repair source links and provider names affected by moves. Do not generate a second architecture guide.

- [x] Reconcile every source family in the appendix with its task result. Any unowned or newly introduced file is assigned and reviewed before completion.
- [x] Run Python boundary tests, semantic boundary tests, Flutter analysis and all relevant unit suites. Use an explicit unit-file list; record skipped suites rather than letting a glob silently broaden scope.
- [x] Confirm rollback, stale-account, duplicate-action, disposal and multi-window tests from Review Focus all exist and pass.
- [x] Review public domain types for deep immutability, typed failures and absence of SDK/Drift leakage. A `final List` that callers can mutate is not an immutable contract.
- [x] Review error/retry flows: failed drafts stay editable, committed operations are not replayed, permissions remain enforced, and retry state cannot overwrite newer input.
- [x] Review documentation against the final code and checker. Remove the superseded business-service-first target and accurately describe any remaining unresolved work.
- [x] Run `git diff --check`; verify only intended files changed, no generated secrets/config values are included, and no dependency/schema/protocol upgrade slipped in.

### Additional official testing gate

The official recommendations include widget tests for views and routing/DI. They are listed here to make the full target explicit, but are outside the existing unit-only execution scope. Obtain an explicit scope change before running or adding this stage; a unit-only result must be described as architecture refactored with widget validation outstanding, not full testing alignment.

Once that scope is authorized, reuse and extend these existing automated suites:

- Tasks: `task_detail_navigation_test.dart`, `task_search_palette_test.dart`, `kanban_screen_test.dart`, `upcoming_screen_test.dart`, `sidebar_test.dart`.
- Quick Add/voice: `global_quick_add_window_test.dart`, `quick_add_voice_test.dart`, `voice_panel_swipe_test.dart`.
- Settings/account: `settings_navigation_test.dart`, `settings_subscription_test.dart`, `account_sign_out_button_test.dart`, `password_recovery_routing_test.dart`.
- Focus/productivity: `focus_completion_celebration_test.dart`, `reports_screen_test.dart`, `reports_achievements_screen_test.dart`.
- Collaboration/calendar/updates: `collaboration_join_screen_test.dart`, `public_project_screen_test.dart`, `google_calendar_settings_screen_test.dart`, `desktop_update_widgets_test.dart`.

Add widget assertions for retained drafts after save failure, independent window/editor selection, loading/error/retry, account redirects and action dispatch to fakes. Preserve existing keyboard, semantics and Reduce Motion checks. No golden or manual visual acceptance is required to establish these architecture contracts.

Browser storage tests, platform compilation and release validation remain separate gates. CI already contains browser/build jobs; successful unit checks do not claim those jobs passed, and this refactor must not disable them.

### Completion criteria

- [x] Canonical documentation describes the implemented official-style direction.
- [x] No mandatory business-service layer or forwarding use-case hierarchy exists.
- [x] Widgets contain presentation mechanics; ViewModels own their screen state/actions.
- [x] ViewModels and use cases depend on domain-facing repository contracts, not source clients or concrete data implementations.
- [x] Shared account, access, focus and persisted preferences have a single owner independent of screen lifetime.
- [x] Repositories own data state/policy and use source services; repositories do not call other repositories.
- [x] Public contracts contain domain values, immutable collections and explicit operation failures.
- [x] Local transactions, sync protocol, permissions and account ownership are preserved by regression checks.
- [x] New strict boundary checks pass without temporary exclusions.
- [x] All relevant unit checks pass; official widget-test coverage is explicitly outstanding under the additional testing gate.
- [x] No release, deployment or live-service validation is claimed from local checks.

## 5. Execution ledger

At plan creation all implementation tasks are pending. Record evidence here during execution; do not check tasks off merely because files were moved.

Execution baseline recorded on 2026-09-20 before Task 2: `git status --short` showed the modified `docs/architecture/flutter-app-architecture.md`, `.gitignore` and the untracked plan; HEAD `e364cb4`; `.fvmrc` Flutter `3.47.0`; `apps/flutter/pubspec.lock` sha1 `e424cf884dee7dc6`, `analyzer 10.0.1` transitive. `python3 tool/check_architecture.py` passed, `python3 -m unittest discover -s tool -p test_architecture.py` passed 9 tests, `git diff --check` clean, `flutter analyze --no-pub` clean, `flutter test --no-pub test/utils/result_test.dart` passed and is unit-only.

| Task | Status | Evidence required |
|---|---|---|
| 1 | Done | canonical docs rewritten to the official direction, stale links repaired, source families reconciled with the appendix, baseline commands recorded above |
| 2 | Done | direct Drift statements moved to `data/services/local/*_local_service.dart` for tasks, projects, labels, kanban, focus, productivity, achievements and calendar; repository contracts unchanged; `test/data/local_write_atomicity_test.dart` proves outbox-write, secondary-row and nested-Failure rollback plus single-operation retry; affected repository suites and `flutter analyze` pass |
| 3 | Done | `AccountSession`/`AccountSessionRepository`/`SyncRepository` added with `SdkAccountSessionRepository` and `LocalSyncRepository`; `SyncAccountUseCase` captures and rechecks session generation; `AccountSyncEngine` takes an explicit retention cutoff and session guard instead of loading entitlements/use cases; ViewModels and routing consume `accountSessionProvider`, `accountProfileProvider`, `accountSignedInProvider`, `accountAvailabilityProvider`; `currentUserProvider` removed; new session/use-case unit tests pass plus the listed account/sync suites and `flutter analyze` |
| 4 | Done | `BillingAccess`/`BillingAccessRepository` with `DefaultBillingAccessRepository` owning the single purchase-update subscription, refresh/restore single-flight, verified bookkeeping and expiry; `BillingViewModel` keeps presentation/purchase flow; Voice/Search/Browse/Onboarding/Settings access checks use `billingAccessProvider`; `config/billing_dependencies.dart` no longer re-exports the paywall/ViewModel/store surface; `SyncAccountUseCase.call()` computes retention from the access contract and callers no longer pass a cutoff; `billing_access_tier`, offers, StoreKit bridge/store, access-repository and account suites pass |
| 5 | Done | `EditTaskTitleUseCase` extracted with constructor dependencies and 7 tests including partial-success project-create/move failures; title edit captures dependencies before awaiting; `quickAddServiceProvider` renamed to `quickAddUseCaseProvider` everywhere; voice batch transaction moved behind `VoiceQuickAddUseCase` + `localTransactionProvider` with rollback tests; required Quick Add/import/focus suites and `flutter analyze` pass |
| 6 | Done | `VoiceCaptureRepository`/`CapturedVoiceRepository` + `VoiceCaptureState` separate device capture from `VoiceQuickAddViewModel` drafts; old combined `voice_quick_add_repository.dart` removed after callers moved; locale/smart-mode policy routed through domain inputs/preferences; access via billing contract, saving via the Task 5 voice use case; new ViewModel tests cover close during capture/transcription, retry, permission denial, late decomposition, account change, disposal, duplicate submit and failed-save draft retention; listed voice suites and `flutter analyze` pass |
| 7 | Done | `upcoming_day_groups.dart` moved into `view_models/`; `TimelineDayData` + pure builder extracted from `_TimelineDay.build` with geometry left in widgets; Upcoming/search-palette/kanban/matrix/browse ViewModels now produce projections; `timeline_day_data_test` (6) and extended `upcoming_day_groups_test` (16) pass with the required empty-day regression |
| 8 | Done | `TaskSelectionViewModel` owns immutable selected IDs, `active`/`pending`, visibility-based `retainVisible`/`toggleAll`/`clear` and the bulk repository operations with per-item revalidation; `TaskSelectionController` is a view adapter for dialogs/context; `TaskEditorViewModel` owns title/description/subtask drafts and failed-save retention; `TaskDetailSaveGuard` registers per editor identity and `router.onEnter` saves all retained editors; `QuickAddViewModel` owns per-identity drafts. New unit tests `test/ui/tasks/task_selection_view_model_test.dart` (5), `test/ui/tasks/task_editor_lifecycle_test.dart` (3), `test/ui/quick_add/quick_add_scope_test.dart` (2) pass, plus the listed unit cases in `task_detail_navigation_test.dart`, `quick_add_metadata_edit_test.dart`, `task_motion_logic_test.dart`, `focus_completion_motion_test.dart` and `overdue_review_test.dart`; `flutter analyze` clean; root architecture check passes |
| 9 | Done | Task preferences/language/voice/focus-preferences/focus-completion/achievement-announcement repositories expose immutable snapshots plus update streams instead of Flutter `Listenable`; `FocusPreferencesRepository` reads through `PreferencesService`; theme settings persistence split into `ThemeSettingsRepository` (plain JSON, v1 backup, cross-tab merge) while `AppThemeSettingsController` stays the one explicit preview owner; zoom/theme-mode/keyboard-shortcuts raw persistence moved to `AppZoomRepository`/`ThemeModeRepository`/`KeyboardShortcutsRepository`; achievement announced-id persistence uses `PreferencesService`; new `test/data/shared_state_lifecycle_test.dart` (8 tests) covers hydration races, focus exactly-once and announcement dedup; listed unit suites (45 tests) plus affected unit suites pass; `flutter analyze` and root architecture checks pass |
| 10 | Done | `CollaborationRepository` exposes named typed operations (state, publicRead, share, acceptInvitation, members, invite, revokeInvitation, setMemberRole, removeMember, transferOwnership, leaveScope, deleteScope, markNotificationRead, watchComments, watchFocusContributions) returning `PublicProject`, `SharedScope`, `CollaborationState`, `CollaborationMembers`, `CollaborationInviteOutcome` and typed comment/focus values; `collaboration_responses.dart` parses wire maps, `CollaborationApi` owns command names/args, `CollaborationRole`/`CollaborationMember` enforce scope and member permissions, and `CollaborationConflict.serverRevision` replaces raw `lastError` decoding; all collaboration ViewModels/widgets/task history consume typed values; new `test/data/collaboration_mapping_test.dart` (8) covers malformed roles, duplicates, invitation expiry/revocation and repository mapping plus remote-revision conflict retry; extended `collaboration_view_models_test.dart` (6) covers scope-change, sign-out and dedup; six required unit files (34 tests) plus `shared_sync_test`/`collaboration_providers_test` pass, `flutter analyze` and root architecture check clean |
| 11 | Done | `NotificationRepository`/`LocalNotificationRepository` own scheduling policy and localized copy; `SettingsViewModel` no longer reads `notificationSchedulerProvider`; `GoogleCalendarSyncRepository` is a pure contract with `GoogleCalendarFailure` and `GoogleCalendarServerSyncRepository` translating server codes (UI no longer tests service exceptions); `UpdateRepository`/`DesktopUpdateRepository` own channel/offer/install state while `UpdateViewModel` owns popup visibility and automatic checks; `SharedUpdatePreferences` uses `PreferencesService`; `GlobalQuickAddRepository` contract keeps the concrete platform controller out of ViewModels; new `test/data/update_repository_lifecycle_test.dart` (repeated checks, dismiss during download, disposal during source response, install failure with fakes) and `test/ui/core/composition_contract_test.dart` (main/Quick Add scope construction, auth redirect decisions, startup teardown) pass; required unit-only files pass (65 tests plus 13 repository cases; `google_calendar_sync_lifecycle_test.dart` skipped as widget-only, `desktop_update_controller_test.dart` widget case filtered); `flutter analyze` and root architecture check clean. Remaining: `PlatformQuickAddController`/`WatchCompanionController` stay composition adapters because the checker forbids service-to-repository/config direction; billing provider wiring in `config/bootstrap.dart` untouched |
| 12 | Done | `analyzer: 10.0.1` declared direct-dev with only the lock classification changed; `apps/flutter/tool/check_architecture_types.dart` resolves handwritten libraries (including parts) and fails on domain/UI, provider-inferred SDK/Drift-row/source-adapter/concrete-repository/other-ViewModel, typedef/generic/extension/re-export and generated-row-in-contract references; `test/architecture/type_boundaries_test.dart` covers 18 negative/positive fixture cases; Python checker adds `domain -> ui/config/routing`, ViewModel -> concrete repository, extended SDK prefix list, same-area repository coupling, re-export chains and services -> use cases, with the mandated `test_domain_cannot_import_current_ui_directory` regression (verified failing on HEAD's checker); findings fixed by splitting `PreferencesRepository`, `LanguageRepository`, `PasswordRecoveryRepository`, `FocusCompletionRepository`, `FocusPreferencesRepository`, `AchievementAnnouncementRepository` and `VoicePreferencesRepository` into contract/impl, routing email auth through `AccountAuthActionsRepository.submitEmail`, exposing `pendingSyncCommandCountProvider` instead of a Drift row list and moving startup keep-alive wiring into `config/startup_wiring.dart`; root check/tests, semantic check (436 libraries), 18 architecture tests, `flutter analyze`, `dart analyze tool` and `git diff --check` pass; CI and `make architecture` wire the semantic check after dependency resolution |
| 13 | Done | full unit reconciliation: 144 unit-only files (1034 tests) selected by scanning for `testWidgets`/`pumpWidget`/`testGoldens`, all passing; `flutter analyze`, `dart analyze tool`, `dart run tool/check_architecture_types.dart` (436 libraries), 18 type-boundary fixtures, Python check plus 17 architecture tests all pass; Review Focus regressions confirmed (`local_write_atomicity`, account/session/use-case staleness, billing duplicate/unverified, voice/editor disposal, Quick Add scope isolation); new/changed public contracts use unmodifiable collections and domain failures, with SDK/Drift leakage rejected by the semantic checker; canonical docs contain no stale provider/file references; widget/golden/browser/platform/release gates remain explicitly outstanding; `git diff --check` clean with no secrets, schema, protocol or dependency-version changes (only analyzer transitive to direct dev) |

## 6. Source coverage appendix

The inventory below is a planning snapshot. It assigns review ownership to the complete source families, not a requirement to edit every file. A conforming file can remain unchanged with recorded evidence. Tests and all callers must follow any file move or signature change.

| Source family | Task owner | Required review |
|---|---|---|
| `data/repositories/tasks`, `projects`, `labels`, `kanban` | 2, 5 | SQL/source isolation, policy, atomic mutations, domain contracts |
| `data/repositories/focus`, `productivity`, `achievements` | 2, 9 | persisted data versus session events versus screen state |
| `data/repositories/account` | 3 | SDK mapping, identity, auth/recovery, lifetime |
| `data/repositories/billing` | 4 | store I/O versus shared access versus paywall state |
| `data/repositories/planning` | 5, 6 | decomposition contract, remote adapter, fallback behavior |
| `data/repositories/voice` | 6, 9 | capture versus drafts and preferences |
| `data/repositories/settings` | 9 | source adapters, hydration, shared state and theme images |
| `data/repositories/collaboration` | 10 | typed actions, shared permissions and mapping |
| `data/repositories/calendar`, `updates` | 11 | source adapters, domain outcomes and view state |
| `data/services/local` and `local/database` | 2, 9 | database operations, transactions, preferences and conditional storage |
| `data/services/account`, `auth`, `sync` | 3 | source mechanics, no use-case/UI dependency, stable session inputs |
| `data/services/billing` | 4 | technical store state, verification mapping, no UI |
| `data/services/planning`, `voice` | 5, 6 | source requests, recording lifetime, no screen drafts |
| `data/services/collaboration` | 10 | wire contracts and decoding |
| `data/services/google_calendar`, `updates`, `notifications` | 11 | platform/network mechanics, domain-facing boundaries |
| `data/services/audio`, `haptics`, `platform` | 9, 11 | pure UI mechanics versus app actions; platform resource disposal |
| `domain/models` (all areas) | 2–11, final gate | pure values, deep immutability, no source/UI dependencies |
| `domain/use_cases/account`, `focus`, `quick_add`, `tasks` | 3–5 | useful orchestration, repository contracts, no mandatory wrappers |
| `ui/tasks`, `ui/planning` | 5, 7, 8 | queries, projection, drafts, selection, typed actions |
| `ui/voice`, `ui/quick_add` | 6, 8 | retained session/window identity and independent drafts |
| `ui/settings`, `ui/onboarding` | 3, 4, 9 | account/access/settings projections and actions |
| `ui/focus`, `ui/productivity` | 2, 9 | shared data, session events, presentation lifetime |
| `ui/billing` | 4 | screen state isolated from shared subscription state |
| `ui/collaboration` | 10 | typed state, permission-aware actions, stale responses |
| `ui/google_calendar`, `ui/updates` | 11 | domain failures, operation state and presentation |
| `ui/core` | 3, 8, 9, 11 | shell/profile mapping, theme/application state, rendering helpers |
| `config` including `auth`, `platform` | 3–6, 9, 11 | composition-only responsibility, typed public providers |
| `routing`, `main*.dart` | 8, 11 | redirects, retained editor scope, all entry points |
| `utils` | 12 | framework independence, Result contract, no hidden exports |
| generated Dart/localization/platform registration | owner of generator | regenerate only when required; preserve locale and platform contracts |
| `apps/flutter/tool`, root architecture tools, validation workflow | 12, 13 | import-path consumers and validation integration |
| companion clients, server, native runners | compatibility boundary | no redesign; preserve serialized/protocol interfaces and existing checks |


## 7. Review completion — 2026-09-21

This entry supersedes the implementation descriptions in the earlier execution
ledger where they mention the split billing repositories, ViewModel-owned
checkout, service-owned Kanban policy or widget-triggered Timeline grouping.
The earlier ledger remains a historical execution record.

All five follow-up architecture corrections are implemented in the current
working tree. Billing has one shared repository owner. Account/profile consumers
use the session repository, and sync guards identities throughout a run. Local
owner/reset and Kanban/focus decisions are in the repository layer, with SQL in
source stores. Timeline receives a prepared ViewModel projection. Remaining
recovery/shortcut framework leakage and identified nested mutable values are
removed. See [the current status](../../../ARCHITECTURE_ALIGNMENT_STATUS.md) for
the ownership map.

The continuation was performed inline after the user's explicit instruction;
no further delegated work was used. Validation is strictly unit tests and static
analysis. Widget, golden, integration, browser, manual and platform/release
validation are outside this request.


Final verification for this continuation:

- `flutter analyze --no-pub`: no issues.
- 147 explicitly selected unit-only Dart files: 1,050 tests passed, including
  21 resolved-symbol architecture fixture cases.
- 18 mixed files, filtered to 122 explicit ordinary `test` names: all passed;
  no widget cases were selected. Total: 1,172 Dart unit cases.
- `python3 tool/test_architecture.py`: 18 tests passed.
- `python3 tool/check_architecture.py`: boundaries, cycles and manifest closure
  passed; `dart run tool/check_architecture_types.dart`: 441 libraries passed.
- `git diff --check`: clean.

Regression evidence includes a failing-before/passing-after Stripe account
switch catalog test. A parallel Flutter test invocation encountered a shared
native-assets output race; the final mixed-file run was repeated sequentially
and passed. No dependency cleanup, app build or manual workaround was needed.

No commit, push, deployment or external publication was performed.

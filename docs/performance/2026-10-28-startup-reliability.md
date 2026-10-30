# Startup reliability, 2026-10-28

## Findings and changes

The existing Debug Development application contained the entry point from
`integration_test/blocking_test.dart`. Starting that bundle outside its runner
attempted to contact the now-absent test control server and left a black window.
The blocking E2E runner now backs up the normal Development application and
restores it after its child processes stop, including on a failed run. A unit
test covers restoration and an originally absent application. Forced termination
without cleanup (for example, SIGKILL) still requires rebuilding the normal app.

An independent multiview startup race was reproduced: the first native probe and
Flutter view enumeration can both precede window attachment. Initialization now
retries on metrics changes, rechecks an initially absent native window and
registers it once. `runMultiApp` returns a future that propagates setup and
registration failures to bootstrap. Tests reproduce the late window, verify one
show operation across repeated metrics events, and exercise native failures.

Sync engine identity now follows the account client and current user ID. A token
refresh for the same user retains the engine, lifecycle subscriptions and local
startup readiness. The regression test holds the owner's serialized sync queue
open while refreshing the session, then verifies readiness and an actual A-to-B
owner transition. Existing ownership tests cover guest transitions, archived
unsynced changes and delayed writes from the previous account.

Startup no longer awaits recurring-task materialization. Existing background
wiring starts it after local preparation; timer and sync-triggered calls share
one in-flight operation. Permission reads happen only for due recurring shared
tasks. Tests verify one scan, one successor, recovery after a failed scan and no
scope reads for ordinary shared tasks. Owner-bound transaction safeguards remain.

The existing local error/retry screen and task-list refresh behavior are reused.
Retry ignores a preparation that is still pending. Network synchronization keeps
its existing independent status and retry mechanism.

## Diagnostics

`pomodoist.startup` logs and timeline events contain stage names and elapsed
milliseconds only. Each stage is recorded once per isolate:

| Stage | Meaning |
|---|---|
| `begin` | Bootstrap entered |
| `window-attached` | The main desktop window builds its application |
| `first-frame` | Framework frame containing that application completes |
| `shell-ready` | Navigation and application shell complete their first frame |
| `database-ready` | Local database seed/preparation completes |
| `account-local-ready` | Signed-in account ownership preparation completes |
| `interface-ready` | Local startup and background wiring are ready |
| `tasks-emitted` | First local task query emits |
| `task-list-ready` | Framework frame containing an available task list completes |

The account stage is absent when there is no signed-in account. Framework frame
callbacks are not GPU presentation measurements. Logging never includes task
content, account identifiers or session tokens.

## Measurements

Profile Development builds used the pinned Flutter 3.47.0 SDK on the same Mac and
the same small local database. Every row includes ten fresh processes except the
single offline probe. These are process launches, not ten OS cold boots.

| Launch method | Median bootstrap to first query | Median launch to first query |
|---|---:|---:|
| Before, direct executable | 156 ms | 431 ms |
| After, direct executable | 181.5 ms | 446 ms |
| After, LaunchServices (`open -n -a`, Finder/Dock launch mechanism) | 143 ms | 485 ms |
| After, process network denied (one launch) | 238 ms | 596 ms |

All 10 LaunchServices launches emitted local tasks. A rebuilt normal Debug app
also visibly displayed its saved task, and hot reload/restart succeeded without
runtime errors. The stale integration-test app was stopped and replaced.

A second set of 10 LaunchServices launches used the final normal **Debug** bundle
with the corrected content-frame markers. All 10 reached `task-list-ready`:
median main-window attachment **341 ms**, first application frame **622 ms**,
database readiness **892 ms**, and loaded task-list frame **1,324 ms** after
bootstrap. Median LaunchServices-to-loaded-list time was **1,827 ms**. Debug JIT
timings are not comparable to the Profile table. The last application was left
running with its saved task visible.

These samples do **not** establish a normal-launch speedup: the database is small,
and the after/direct series overlapped the full test run. The important bounded
result is that a hung recurrence operation no longer blocks local startup and a
same-user refresh no longer waits behind a hung sync. Both are regression-tested.

The initial profile instrumentation measured an empty multiview warm-up frame;
those values are retained as `framework-warmup-frame` in the
[measurements](2026-10-28-startup-measurements.json), excluded from first-content
frame comparisons. Final instrumentation records the main application frame and
the loaded task-list frame separately. No valid before/after content-frame
speedup is claimed.

## Validation and limits

- 197 targeted Flutter tests passed: startup reliability, recurrence, multiview,
  local ownership, account boundaries/bootstrap, native account startup,
  lifecycle/resume, sync restart, core features, Kanban and collaboration.
- All 5 blocking E2E support unit tests passed.
- Flutter analyzer passed. Import boundaries/cycles/manifest closure passed;
  resolved Dart symbol boundaries passed for 628 libraries.
- Full Flutter suite: 2,784 passed, 17 failed. Failures were in Apple privacy
  manifest expectations, an Xcode settings timeout, Quick Add layout, Timeline,
  Focus rhythm and Blocking widgets. They are outside the targeted startup
  scenarios; their pre-change status was not established by this run.
- Normal Debug and Profile Development builds succeeded with local signing
  disabled. A distribution-signed build was not produced.

The live runs used local data without an authenticated account. Live server token
expiry and real macOS sleep/wake were not exercised. Resume coalescing, blocked
sync, owner changes and old-account writes were covered by automated tests.
No schema migration, new dependency or server API change is required.

## Follow-up: asynchronous task loading inside the shell

The router now keeps `AdaptiveShell` mounted while database/ownership preparation
is pending or failed. Its content area owns loading, slow-operation guidance,
errors and retry. Navigation works during preparation and shell state survives
both readiness changes and retries. Onboarding waits for the data boundary.

Before readiness, the shell does not subscribe to task counts, projects, task or
habit details, Focus playback or achievement overlays. Creation controls and
editing shortcuts stay disabled. A real owner transition hides the previous
content even when an asynchronous provider retains its previous value. Once
preparation completes, the existing task streams fill the main area and sidebar
asynchronously. Same-user background synchronization continues to retain rows.

Widget regressions exercise widths 390 and 1280 with an in-memory SQLite database:
the shell and navigation render before preparation, SQL reads stay at zero until
the boundary completes, a saved task subsequently appears, and preparation of a
new boundary hides the previous task without replacing the shell. Error/retry
also retains the shell state. `shell-ready` is logged separately from
`task-list-ready`; the earlier measurements above predate this follow-up.


### Follow-up validation

- All 102 targeted tests passed, including asynchronous shell loading, auth
  startup, ownership boundaries, shell Focus visibility, onboarding, navigation,
  startup reliability and startup error/retry.
- Analyzer and architecture checks passed, including resolved symbol boundaries
  for 628 Dart libraries.
- Full suite: 2,790 passed and 16 failed. Both new shell/SQLite regressions passed.
  These failures also appeared in the earlier full run above; a clean pre-change
  baseline for the full suite was not established. Concurrent changes elsewhere
  in the working tree were present during both runs.

The full-suite failures were:

- `apple_privacy_manifest_test.dart: each Apple executable declares the UserDefaults reasons it uses`
- `quick_add_voice_test.dart: voice controls remain reachable in landscape with a keyboard`
- `focus_screen_rhythm_test.dart: paused rhythm stays frozen and resumes from the next second`
- `interaction_controls_test.dart: timeline uses short quarter ticks and today indicator`
- `focus_screen_rhythm_test.dart: circle and bar stay still when the Focus stage mounts`
- `focus_screen_rhythm_test.dart: timer launch does not restart on the next second`
- `focus_screen_rhythm_test.dart: primary press keeps geometry stable and activates once`
- `focus_screen_rhythm_test.dart: failed focus action keeps state and shows localized message`
- `focus_screen_rhythm_test.dart: pause handoff crossfades the action and timer color`
- `focus_screen_rhythm_test.dart: work to break hands off phase color and timer shell once`
- `focus_screen_rhythm_test.dart: reduce motion makes timer transitions immediate`
- `focus_screen_rhythm_test.dart: reduce motion switches Full and Minimal immediately`
- `interaction_controls_test.dart: browse completed task link opens completed task screen`
- `distraction_widgets_test.dart: failed profile save keeps the draft and supports retry`
- `distraction_widgets_test.dart: resource corrections remain manual and exceptions target the selected profile`
- `distraction_widgets_test.dart: active Focus locks policy selection while conflict actions remain explicit`


The final normal Debug Development app rebuilt successfully with local signing
disabled and launched via LaunchServices. One cold launch recorded `first-frame`
at 778 ms, `shell-ready` at 1,085 ms, `database-ready` at 1,152 ms,
`interface-ready` at 1,198 ms and `tasks-emitted` at 1,224 ms from bootstrap.
The initial route was Focus; the saved task was visibly verified after navigating
to Today. Its `task-list-ready` marker followed manual navigation and is not a
cold-start task-list measurement. No exceptions were logged during this check.
The final app was left running on Today.

An earlier hot restart during the full test run recorded `shell-ready` at
1,459 ms, `database-ready` at 2,304 ms and `task-list-ready` at 2,733 ms. This is
an ordering check under load, not a comparable cold-launch performance sample.
Live authenticated token expiry and actual system sleep remain untested.

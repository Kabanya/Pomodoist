# Startup stress validation — 2026-10-28

This exercise stresses the asynchronous shell/data boundary and the startup
reliability changes described in [the implementation report](2026-10-28-startup-reliability.md).
No production behavior was changed during this exercise. Regression tests were
strengthened; the large task fixture runs exclusively in an in-memory database.

## Automated scenarios

The targeted suite contains 46 tests across seven files. Its stress cases include:

- 1,000 retry requests while local preparation is unfinished: one preparation.
- 1,000 same-user authentication events while the owner/sync serialization queue
  is blocked: the same sync engine and ready interface, followed by a real A → B
  ownership transition.
- 1,000 inactive/resumed pairs while synchronization is pending: one sync cycle.
- 1,000 window metrics events when the first window attaches late: one native
  window registration/show and a rendered application.
- 10,000 ordinary shared tasks and 100 due recurring series; ten waves of 200
  concurrent materialization requests: ten scans, no ordinary-task access queries,
  exactly 100 new occurrences, and no additional rows in subsequent waves.
- Existing failure/retry, guest/account ownership, old-account deferred writes,
  and asynchronous shell loading at widths 390 and 1280.

All 20 randomized passes (seeds 1–20) passed: 920 test executions, zero failures.
The initial non-randomized pass also passed all 46 tests. Flutter analysis passed.
The accompanying
[measurements](2026-10-28-startup-stress-measurements.json) record each completed
seed and process exit code. The SDK was pinned to Flutter 3.47.0.

Reproduce one randomized pass from `apps/flutter`:

```sh
../../.fvm/flutter_sdk/bin/flutter test --no-pub \
  --test-randomize-ordering-seed 1 --reporter expanded \
  test/startup_reliability_test.dart \
  test/account_sync_lifecycle_test.dart \
  test/multiview_startup_test.dart \
  test/recurring_startup_test.dart \
  test/auth_startup_test.dart \
  test/account_sync_account_boundary_test.dart \
  test/local_sync_owner_startup_test.dart
```

## Live macOS launches under test load

The existing normal Debug Development build was launched 31 times while the
automated suite ran: 20 sequential LaunchServices launches, two groups of three
concurrent LaunchServices launches, and five direct launches with all networking
denied by a process-local macOS sandbox. Existing app processes were preserved;
only processes identified through each test launch's own output file were stopped.
These are process launches with warm OS caches, not machine cold boots.

Every launch reached window attachment, first application frame, shell readiness,
database readiness, interface readiness and task stream emission within the
20-second observation limit. No unhandled Flutter exception, `SQLITE_BUSY` or
`database is locked` message was recorded. The complete task-row digest before
and after all runs matched; the user's task data was unchanged. No task text,
token or raw application log is included in the measurements.

Timings below are milliseconds from Dart bootstrap. Each cell is median / p95 / max.
The task milestone measures stream emission, not a visually loaded task-list frame.

| Launch method | Runs | First application frame | Shell ready | Tasks emitted |
| --- | ---: | ---: | ---: | ---: |
| Sequential LaunchServices | 20 | 755 / 872 / 1160 | 1124 / 1393 / 1783 | 1552 / 2183 / 2221 |
| Concurrent groups of three | 6 | 1076 / 1198 / 1198 | 1514.5 / 1889 / 1889 | 2261 / 2446 / 2446 |
| Direct, network denied | 5 | 898 / 1159 / 1159 | 1226 / 1568 / 1568 | 1713 / 2266 / 2266 |

All offline launches logged an expected `SocketException` because the sandbox
also prevented the Debug VM service from listening on localhost. Application
startup and local task streams nevertheless completed. No system networking
settings were changed.

## Interpretation and limits

The exercised scenarios did not reproduce a stuck startup, repeated sync engine
creation for the same user, parallel recurrence scans or duplicate occurrences.
This is bounded evidence, not a claim that all races or memory leaks are excluded.

The live database contained one local task and no authenticated session. The
large-store and account-transition scenarios used automated fixtures. Actual
system sleep/wake, real server token expiry and a multi-hour memory soak were not
performed. Debug JIT timings under concurrent test/compiler load do not establish
release-mode speed or a before/after speedup. Some randomized widget runs emitted
Drift's multiple-`AppDatabase` debug warning; the added SQLite fixtures use separate
`NativeDatabase.memory()` executors, and no SQLite lock errors were observed.

The full application suite was not repeated for these test-only changes. Its
previous 16 failures remain documented in the implementation report; passing this
targeted stress suite does not turn that earlier full-suite run green.

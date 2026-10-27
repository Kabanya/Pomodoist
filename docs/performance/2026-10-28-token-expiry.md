# Real token expiry and refresh rejection — 2026-10-28

The Flutter client was exercised against real HTTP responses from local GoTrue
`v2.195.0`, using disposable accounts and a temporary SQLite file. Authentication
responses, token expiry, refresh rotation and server-side session revocation were
not mocked. No production application code changed during this validation.

## Scenario

1. Create a confirmed fixture account and sign in through the installed Supabase
   Dart SDK. Open the production account/startup providers and local repositories.
2. Save an unsynchronized task and observe it through the task-list provider.
3. Wait until two seconds after the JWT's actual `exp`. The real Auth server must
   reject that JWT with HTTP 403. Automatic refresh is initially disabled solely
   to force this expired-token condition; restart the SDK's own refresh mechanism.
4. Hold the refresh transport before forwarding the request. In the strengthened
   runs, wait two seconds, then verify readiness and the same sync-engine instance,
   and create a second task while refresh is still pending. Forward the request
   and require HTTP 200 and the SDK's `tokenRefreshed` event.
5. Revoke the session through the server's logout endpoint using a separate
   administrator client, without signing the application client out locally.
   Wait for the replacement JWT to expire and again require HTTP 403.
6. Restart SDK automatic refresh. Require the real HTTP 400 rejection and the
   SDK's `signedOut` event. Local startup must settle within five seconds, and
   both tasks must still exist locally before guest preparation.
7. Run production guest preparation. Require an account recovery snapshot,
   no account tasks in the guest store, and rejection of a write through the old
   account repository. This preserves account isolation after session loss.
8. Dispose the providers and close SQLite. Sign in again as the same fixture
   account, reopen the database, and require both tasks and their pending commands
   to be restored. The strengthened runs compare every field of the restored
   task rows and command rows, including command identifiers and payloads. No
   duplicate account recovery snapshot may remain.

## Results

Three complete runs passed: the initial end-to-end run and two repetitions of
its strengthened version. Each run observed two expired-JWT HTTP 403 responses,
one successful refresh, one rejected refresh after server revocation, and
successful reauthentication. The strengthened runs held refresh for two seconds
and verified complete row equality and rejection of the stale account writer.
See the sanitized [measurements](2026-10-28-token-expiry-measurements.json) for
stage timings and HTTP route/status counts. They contain no credentials, task
content or account identifiers.

The existing 46 startup, account boundary, recurrence, lifecycle and window
regressions passed again. Analysis of the added Dart test passed with pinned
Flutter 3.47.0; the architecture boundary check and Python syntax check passed.
The runner rejects invocation without its explicit `--local` flag.

The original Auth service kept its 3,600-second token lifetime. A separate Auth
container, using the same pinned image and local database, issued 40-second JWTs
only for fixture clients. Its port and the proxy bound to loopback. Fixture users,
the temporary database and the extra container were removed after each completed
run. The user's running application and its database were not used for this test.

## Reproduction

With the existing local self-hosted stack running (`server/README.md`), repository
Flutter dependencies installed, and Docker, Python 3 and a Node version supporting
`node:util.parseEnv` available, run from the repository root:

```sh
python3 server/tests/token-expiry.py --local
```

The runner reads local keys from `server/.env` without printing them, launches a
short-lived Auth container and runs `apps/flutter/test/live_token_expiry_test.dart`.
It cleans up fixture accounts even when the Flutter test fails. The ordinary
Flutter suite skips this live test unless the runner supplies its loopback URL
and credentials. `POMODOIST_AUTH_EXPIRY_TEST_WORKSPACE` may point at an isolated
copy of the Flutter package with its own `.dart_tool` directory; this was used to
avoid native build-hook cache interference from concurrent development sessions.

## Limits

This is a Flutter host test with real networking, real SQLite persistence and
production account/startup/repository code. Native audio and background wiring
are disabled so that synchronization cannot drain the deliberately unsent queue.
It does not exercise the entire signed-in native macOS interface, production
Auth, actual system sleep, or delivery of the restored commands to the remote
sync API. Separate widget and lifecycle regressions cover the shell and resume
behavior. A full application suite was not repeated; its previous failures
remain recorded in the [startup implementation report](2026-10-28-startup-reliability.md).

Early harness attempts were discarded: a read-only provider without an active
subscription could retain an old owner or list emission, and an unobserved
`autoDispose` guest provider was disposed mid-load. The final test holds the same
subscriptions that application consumers hold and waits for task emissions.
Those attempts did not demonstrate an application data-loss bug.

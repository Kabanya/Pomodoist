# Stage 2: desktop distraction protection

Implementation and acceptance ledger for the [Focus roadmap](../README.md#build-from-source).
The full approved specification and wire contracts are in the
[implementation plan](superpowers/plans/2026-10-26-distraction-blocking.md).
Repository documentation is English; Flutter styling follows the shared
[design system](design-system.md).

## Roadmap and release gates

| Part | Implementation | Acceptance gate |
| --- | --- | --- |
| 2.0 mechanisms | Loopback pairing, native shields, browser expiry recovery | Signed App Store and DMG acceptance remain separate |
| 2.1 shared Focus | Account RPC, revisions, idempotent commands, real-time invalidation and 15-second refresh, local fallback/adoption | Concurrent commands and once-only history tested against PostgreSQL |
| 2.2 profiles | Work, Study, custom profiles, categories, exceptions, phase rules, foreground discovery | Dart rule, settings, lifecycle and database tests |
| 2.3 Chrome | DNR redirects, loaded-page guards, media pause, recovery, shared/local Focus | Node and real Chromium lifecycle acceptance |
| 2.4 macOS | Public NSWorkspace discovery and activating AppKit shields, sandbox server entitlement | Real UI lifecycle and AppKit checks passed; signed distribution, Spaces/full-screen and VoiceOver acceptance pending |
| 2.5 Windows/Linux | Win32, GNOME, Plasma 6, X11, Sway and Hyprland adapters | CI compilation plus actual compositor/window acceptance; unsupported Wayland fails explicitly |
| 2.6 Pro categories | Authenticated web search, shared cache, manual precedence and existing AI quota | SQL/Deno tests; real provider/account acceptance separate |

A compiled adapter is not proof of window protection. Do not mark Stage 2 fully
accepted until the signed builds and each advertised desktop environment pass
the manual matrix below. Mobile blocking, schedules, daily limits, usage-time
and content statistics are deferred.

## Runtime ownership

Desktop composition overrides the existing `FocusRepository` with
`LiveFocusRepository`; widgets, Pomo and existing integrations retain one command
boundary. Presets, local Drift storage and history sync remain in use. Other
clients remain compatible with completed history and do not claim live coverage.

The authenticated `pomodoist_focus(p_command)` RPC owns one shared session per
account. A request contains `action`, `requestId`, `deviceId`, `expectedRevision`
and `payload`. Conflicts return the latest state. Server transactions finalize
intervals and project task contributions once. A missed deadline produces a ready
interval; clients only honor automatic starts after a recent, observed expiry.
Sleep/restart never backfills work intervals.

Local sessions keep their preset and exit-policy snapshot. Adoption sends the
current run/interval and all earlier intervals/events before retiring their
superseded local queue entries. Queue retirement is atomic, preserves unrelated
operations in mixed batches, and retries after a crash. A competing shared
session requires an explicit user choice.

`ProtectionCoordinator` lives in app startup, independently of screens and mascot
visibility. Native/bridge replacement waits for the old coordinator to finish
startup, pending application and shutdown. Owner changes invalidate the service;
account tokens are never sent through the loopback bridge.

## Rules and exits

Unknown resources are allowed. Explicit resource rules precede categories;
specific domain exceptions precede parent domains. Manual classification wins
over automatic classification. Classification and exceptions can change during
a strict session.

Work is protected; ordinary pauses preserve rules by default; strict pauses
always preserve them. Short and long breaks are configured separately and are
released by default. Ready, ended and stopped phases release rules.

Strict exit is chosen before Focus: explicit immediate confirmation or a
persisted, cancellable 60-second wait. Stop, skip, restart, replacement start,
preset change, logout, quit and protection disable use the same policy. Device
detach leaves the other devices running. Global stop is a separate action.
Interrupted work does not receive completion effects. Shared completion sounds,
notifications and celebrations reuse existing services and durable deduplication;
task totals remain server-owned.

## Local Chrome channel

The bridge binds `127.0.0.1` only. Each environment has 64 candidates:
production `51987 + 3*n`, staging `51988 + 3*n`, development `51989 + 3*n`,
where `n` is 0–63. Startup tries the last successful port for the account and
environment, then the remaining candidates, binding directly without a separate
availability check. Only address-in-use conflicts advance to another port;
exhaustion and other socket failures remain explicit errors. Repeated starts
share one startup operation, and disposal closes an in-flight listener too.

Pair using the `port-code` value in Tasks and Focus settings; the extension
extracts the port, so no separate port entry is needed. The six-digit suffix
and a manual port remain supported for legacy clients. A code expires after two
minutes and is single-use. Pairing issues a separate random connection token,
pinned to the extension origin and account/flavor. Logout revokes pairing.

An already paired extension checks the saved port and automatically searches
its environment's candidates after a move. Searches share one in-flight
operation and probe at most eight ports concurrently, with a 500 ms timeout per
probe. `POST /discover {clientId,challenge,flavor}` uses the SHA-256 hex digest
of the paired token as `clientId` and a fresh 32-byte base64url challenge without
padding. It returns `{version:1,owner,flavor,port,proof}`. `proof` is the lowercase
hex HMAC-SHA256, keyed by the UTF-8 token, over the UTF-8 JSON array
`["pomodoist-bridge-discovery-v1",challenge,owner,flavor,port]`. Host, Origin,
paired extension origin and flavor are validated before signing. The extension
verifies the proof before sending a bearer token or command and persists the
verified port. Searches never send the token or change account, environment or
Focus authority. Command retries retain their original request ID.

Pair responses advertise `discoveryVersion:1`; existing tokens gain this flag
after a successful proof. Legacy desktops without discovery support remain
usable only at their saved paired port, without sending credentials to search
candidates. Modern pairings never downgrade to legacy discovery. Chrome asks
once for loopback-host access to support reconnecting across ports.

Messages are bounded JSON state/Focus commands; no account credentials,
arbitrary system commands or executable paths are exposed. Host and Origin are
validated, including preflight requests. Test fixtures use ephemeral loopback
ports to avoid colliding with running desktop apps.

Chrome reads cached desktop state with the existing authenticated POST
`/command` (`read`) operation. Chromium omits `Origin` on extension GET requests;
POST retains the bridge's origin validation. Reads never require a cloud round
trip or extend the last confirmed shared lease.

Running leases end at the last confirmed deadline. Paused shared leases expire
five minutes after confirmation. Only a live local coordinator can renew an
offline local lease. Deadline conversion uses request observation time, so
response latency does not extend protection. Reconnect does not silently replace
another shared session. After explicit emergency detachment while offline, a new
local Focus may start without changing the cached shared session. Reconnection
then requires an explicit conflict choice. Known server-owned history shadows
are durably excluded from local lifecycle writes.

Adoption persists its pending run identity before sending the command. A lost
response or restart acknowledges superseded local outbox writes after the
authoritative run is confirmed. Historical intervals retain their original
durations and policies when a preset changed offline; the current preset governs
future intervals and exits.

## Discovery and Pro

App discovery observes foreground use. Chrome discovery starts only after the
user enables protection and grants host access. Domain assignments contain a
hostname, never a URL path/query/fragment, document title or page content.
Executable paths remain local; matching uses platform identifiers.

Free includes unlimited profiles, manual categories/exceptions, strict mode and
desktop synchronization. Pro adds new automatic assignments through
`pomodoist-ai` (`resource.classify`). Public product identity is searched through
a small OpenRouter adapter; sources are required. Ambiguous/error results remain
unclassified. Manual corrections are preserved, including when a search finishes
later. Existing assignments remain after Pro expires.

Account and Pro displays the server's `get_usage_period` result for
`pomodoist/llm_requests`: used, limit, remaining and reset date. Successful new
searches share this quota with task analysis. Cache hits and manual changes do
not consume quota; failed searches release reservations. Never hard-code a plan
limit in clients.

## Automated verification

From the repository root:

```sh
python3 tool/check_architecture.py
python3 tool/macos/test_distraction_shield.py
node --test tool/web-companions.test.mjs
npm --prefix apps/chrome-extension test
deno test --config server/supabase/deno.json --allow-read --allow-env --allow-net server/supabase/functions server/tests/contracts_test.ts
deno check server/supabase/functions/pomodoist-ai/index.ts
```

From `apps/flutter`, using the pinned Flutter SDK:

```sh
flutter analyze --no-pub
TZ=UTC flutter test --no-pub
dart tool/check_architecture_types.dart
```

Plain Flutter tests intentionally have no compile-time flavor. The native icon
unit test explicitly loads its checked-in PNG fixture because flavor-filtered
macOS assets are omitted by that test runner. UTC makes fixed timeline fixtures
independent of the developer's timezone.

### Automated macOS and Chrome UI lifecycle

From the repository root, run:

```sh
node tool/macos/blocking-e2e.mjs
BLOCKING_E2E_FLAVOR=staging node tool/macos/blocking-e2e.mjs
```

Prerequisites: an unlocked macOS console session, Xcode command-line tools, Node
22+, the pinned Flutter SDK (`fvm install`), resolved Flutter dependencies
(`cd apps/flutter && fvm flutter pub get`), and Playwright with its Chromium
installed. The runner imports `playwright`; if it is installed outside normal
Node resolution, set `PLAYWRIGHT_MODULE` to its absolute `index.mjs` path. Set
`CHROME_BIN` to a compatible Chromium executable if needed, and `FLUTTER_BIN` to
the pinned Flutter executable when `.fvm/flutter_sdk` is unavailable. Dependencies
and browsers are never installed by the runner.

`node tool/macos/blocking-e2e.mjs --preflight` checks prerequisites without
starting the UI scenario. The runner accepts development (default) and staging,
and builds the matching macOS scheme, runtime flavor and extension. Production
is rejected. The selected build is copied to a unique temporary
app bundle, assigned the test-only `com.finchforge.pomodoist.dev.e2e` identity and
ad-hoc signed with only sandbox, loopback network and JIT entitlements. Existing
Pomodoist instances are not reused or closed. The compiled helper at
`build/blocking-e2e/BlockingFixture.app` needs Accessibility and event posting
access (depending on macOS, consent belongs to the launching terminal). Grant
these in System Settings if preflight reports them missing; permission dialogs
are not automated. A changed helper may require renewed consent.

The test mounts the actual Pomodoist UI with the real Drift Focus repository,
live Focus wrapper, protection coordinator, native method channel and loopback
bridge. Only storage and external services are isolated: the database is in
memory, preferences are process-local, no account is initialized, and system
notifications and purchases are disabled. Application bootstrap/distribution
behavior is outside this test. The browser uses a temporary profile and a test
copy of the extension with host access granted at installation; permission
prompts are outside this test too.

Through the UI, the test uses the visible discovery and pairing controls,
creates a profile, classifies an
expendable native app and local test domains, adds an allow exception, pairs
Chrome, and starts Focus. An external AppKit helper checks that the real shield
owns keyboard focus and consumes typing/Cmd-W without modifying or closing its
document across ten repeated activations. The integration binding runs live
frames while awaiting native multi-window registration. Playwright checks
protection of an already loaded page, redirects for
new pages, and the allowed exception. Stopping Focus through the UI must restore
native and browser access while preserving drafts.

Browser checks use the `blocking-overlay` and `desktop-pairing-toggle`
`data-testid` attributes, existing form control IDs, and the protection status's
`data-state` (`permission-required`, `idle`, `active`). Preserve these hooks when
redesigning the extension. Colors, layout, CSS stacking values and translated
status/pairing labels are not test contracts. The Chromium lifecycle harness
also changes overlay styling while checking real input suppression and release.

This run temporarily takes foreground focus and sends keys only while its own
fixture or Pomodoist owns focus. Do not use the desktop during the run. It has a
15-minute overall timeout. Logs, available browser screenshots and a Playwright
trace are retained under `build/blocking-e2e/<timestamp>/`; temporary browser
profiles, servers and owned processes are removed on success, failure and
SIGINT/SIGTERM. Native cleanup matches the unique temporary executable path,
including Runner instances started outside Flutter's process group. The compiled
helper is retained for stable macOS consent.

Run both flavors to check environment coverage, and repeat development to check
repeatability. Set `E2E_FAIL_AFTER=before` for an intentional
failure before Focus, to exercise cleanup. Inspect the recorded process IDs and
temporary path in `processes.json` to verify that they no longer exist. Runner
protocol and process cleanup checks run without GUI access:

```sh
node --test tool/macos/blocking-e2e.test.mjs
```

Pause/break policies, strict exit, cloud synchronization, multi-display behavior
and signed App Store/DMG acceptance remain separate checks. This desktop suite is
not added to headless CI.

CI adds SQL tests to the existing database suite and runs real concurrent Focus
commands against its disposable PostgreSQL container. `Desktop updater` compiles
Windows and Linux on develop changes. The browser acceptance harness is
`apps/chrome-extension/test/browser-protection.mjs`; set `PLAYWRIGHT_MODULE` and
`CHROME_BIN` to an installed Playwright package and Chromium executable.

## Manual distribution matrix

For each signed App Store/DMG build and advertised Windows/Linux environment:

1. Grant/refuse permissions; verify actual device acknowledgement and stale,
   missing-extension, incognito and unsupported-adapter states.
2. Start work, pause/resume, both breaks and ready; edit exceptions immediately.
   Hide/disable Pomo and close/reopen the main window without losing protection.
3. Exercise both strict exit policies through every control surface; cancel the
   wait, restart mid-wait, log out/quit one device, and globally stop separately.
4. Use two devices for simultaneous starts/commands; disconnect, start locally,
   reconnect with/without conflict, and verify history and contributions once.
5. Restore browser/app/computer before and after expiry; test loaded pages, SPA,
   history cache, media, worker suspension, and no reload/autoplay on release.
6. Type and use Cmd-W/Alt-F4 in a blocked application. Verify keyboard ownership,
   full-screen, modal windows, multiple monitors/workspaces and document safety.
7. Verify quota errors, malformed search output, manual correction during search,
   exhausted quota, cached results and subscription expiry.

macOS panels take keyboard focus before covering another app and consume
Cmd-W/Escape; a refused activation leaves the shield hidden and retries. Windows
minimizes the blocked window and hides a shield that cannot take foreground.
Background audio and computation can continue. Force quit, extension removal and
system/security/privileged windows are outside protection guarantees.

## Staging rollout

All work is on develop. Server release checks precede the existing private core
sync/staging deployment route. Production and store releases require their
separate release process. Schema tests run before server publication; compatible
clients can be exercised against staging after the migration is installed.

## Verification record (2026-10-27)

- Local UI acceptance: two consecutive complete macOS/Chromium runs passed,
  including UI pairing, native keyboard/Cmd-W protection, loaded-page and new
  navigation protection, the allow exception and release with preserved drafts.
  An injected failure and SIGINT during active Focus both removed their owned
  processes and temporary profiles. Artifacts are retained under
  `build/blocking-e2e/`. The current extension suite passes 103 tests; the
  coordinator/view-model suite passes 10 and runner checks pass four. The shared
  working-tree Flutter suite completed with 2,727 passes and 16 failures; its
  import architecture check also reports a task-editor dependency cycle. These
  results do not replace the historical CI record below.
- Automated: 102 extension tests plus a real Chromium loaded-page/SPA/media,
  worker suspension, expiry and release harness; 453 Deno server tests; 89
  PostgreSQL Focus assertions plus four real concurrent command scenarios.
- Flutter: all 2,729 tests passed in [Validate at fe811015](https://github.com/Kabanya/Pomodoist/actions/runs/40305722653),
  including domain rules, real HTTP pairing/commands, real Drift adoption and
  restart recovery, settings/quota widgets and shared effects. Static analysis
  and both architecture checks passed in that run.
- Windows: the native debug application compiled successfully on the GitHub
  Windows runner. Desktop/window runtime acceptance remains separate.
- macOS: staging debug app built and launched with sandbox and loopback
  entitlements. The real listener rejects unpaired requests. Account and Pro
  displayed server quota and reset date; the latest build was visually checked
  again and hot reload succeeded. The checked-in AppKit executable
  verifies panel activation/key eligibility and Cmd-W/Escape handling.
- Staging: server-v0.1.22-rc.2 (public c1481a80, private a7b0aefc) deployed
  successfully. Disposable-account smoke checks passed 32 assertions for live
  commands, revision conflicts/replay, adoption, strict exit, row ownership and
  once-only history/task aggregates. Synthetic users and entitlement were removed.
- Acceptance still required: signed App Store and DMG builds; real Windows and
  each Linux desktop; multiple devices/displays/workspaces, screen-reader and
  full-screen keyboard behavior; real paid web-search/provider behavior. Source
  and automated tests do not substitute for this distribution matrix.

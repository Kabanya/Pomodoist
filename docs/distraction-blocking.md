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
| 2.4 macOS | Public NSWorkspace discovery and activating AppKit shields, sandbox server entitlement | Local build and AppKit checks; signed distribution, Spaces/full-screen and VoiceOver acceptance pending |
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

The bridge binds `127.0.0.1` only: production 51987, staging 51988, development
51989. Pair using the code in Tasks and Focus settings. A code expires after two
minutes and is single-use. Pairing issues a separate random connection token,
pinned to the extension origin and account/flavor. Logout revokes pairing.

Messages are bounded JSON state/Focus commands; no account credentials,
arbitrary system commands or executable paths are exposed. Host and Origin are
validated, including preflight requests. Test fixtures use ephemeral loopback
ports to avoid colliding with running desktop apps.

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

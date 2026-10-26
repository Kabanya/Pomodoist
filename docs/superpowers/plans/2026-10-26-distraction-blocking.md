# Distraction blocking implementation plan

Status: implementation in progress. The approved conversation is the product specification.
Work is on `develop`, based on origin/develop 8b5fba38e6f1f2de5d2adb38cfa64d5573283593.

## Product contract

Free includes unlimited named profiles, manually assigned thematic categories, ordinary/strict Focus, and desktop synchronization. Pro optionally assigns categories using real web search. Cache misses share the existing AI quota with task analysis; cache hits are free. Account & Pro must display server-reported AI usage, limit, reset and this explanation.

Categories: social, messaging, video, music, games, news, shopping, education, development, productivity, other, unclassified. Resources have one category. Manual assignments override automatic ones. Explicit profile allow/block overrides category; more specific domain overrides beat parent-domain overrides. Unknown resources are allowed. Domain rules include subdomains, never lookalikes. Automatic and manual corrections apply during active strict sessions.

Profiles contain id, name, blockedCategories, overrides, blockOnPause (default true), blockOnShortBreak (false), blockOnLongBreak (false). Default Work and Study start without silently classifying resources. Application discovery uses foreground activity; domain discovery requires explicit Chrome permission. Inventory is local; selected assignments/profiles sync. No executable paths, browsing paths/query/fragments, document/window titles or page content are uploaded by discovery.

One online desktop Focus per account, common controls/task/timer. Reuse Focus presets/calculation/history. Commands are idempotent and compare a revision; history finalizes once server-side. Real-time invalidations plus active 15-second fallback; no per-second network writes. Online state authority is server; offline starts use existing local Focus. A disconnected shared session does not generate later intervals. Running protection expires at the confirmed deadline; paused remote protection expires five minutes after last authoritative read. Local offline authority can renew its browser lease while alive.

Work blocks; pause preserves by default and always in strict mode. Break policies are independent. Ready/end releases. Strict exit is chosen before start: confirmed immediate or 60 seconds, default 60. Countdown persists and can be cancelled. Stop/skip/restart/preset changes obey one policy across all controls. Resource corrections remain allowed. Ordinary exit is immediate. Quit/logout/disable obey exit policy and detach this device only; stopping Focus everywhere is separate. Force quit/uninstall are outside guarantees.

Offline reconnect adopts a continuing local run if no common run exists, preserving IDs and remaining time; conflicts require join common or stay local. Replacing common requires its exit policy. Never silently merge history. Offline emergency release is local only.

Protection lives for application lifetime independently of mascot visibility. Native blockers shield/hide/minimize windows, never kill or suspend processes. Background audio/work may continue. Display existing focused Pomo pose, task/generic text, remaining time and return-to-task. Preserve documents; release never auto-plays media.

## Shared interfaces (wire version 1)

- ResourceAssignment: `{id,kind:'domain'|'app',name,platform?,category,source:'manual'|'automatic',sources?:[{title,url}],updatedAt,isDeleted?}`. Domain ID is normalized hostname. App ID is a platform-prefixed public identity; executable bindings stay local.
- DistractionProfile: `{id,name,blockedCategories:string[],overrides:[{kind,id,action:'allow'|'block'}],blockOnPause,blockOnShortBreak,blockOnLongBreak,updatedAt,isDeleted?}`.
- ProtectionSnapshot: `{version:1,owner,sessionId,revision,phase,status,strict,expiresAt,remainingSeconds,taskId?,taskTitle?,profile,assignments}`. All dates ISO UTC; null profile means no blocking. `phase`: work/shortBreak/longBreak; `status`: running/paused/ready/ended.
- FocusLiveSession: `{id,revision,run,interval,preset,profileId,strictExitSeconds,exitRequestedAt?,serverNow,protectionExpiresAt}`. run/interval/preset use existing Flutter Focus JSON names. `run.id == session.id`; per-interval stable IDs. Server derives userId.
- Focus API: authenticated RPC `pomodoist_focus(p_command jsonb)` returns `{session:null|FocusLiveSession,serverNow,profiles:DistractionProfile[],assignments:ResourceAssignment[],devices:DeviceProtectionStatus[],settingsRevision}`. Commands `{action,requestId,expectedRevision?,deviceId,payload?}`. Actions read/start/startReady/pause/resume/restart/complete/skip/requestStop/cancelStop/detach/registerDevice/profileUpsert/assignmentUpsert. Read accepts no expectedRevision; mutations of live sessions must compare it. Version conflict is explicit with latest state, never local fallback. Start payload carries preset snapshot (validated), optional task/project and profileId; IDs/time are validated/server assigned except adopting valid local IDs.
- Native MethodChannel `pomodoist/distractions`: `capabilities`, `setProtection({active,blockedApps,taskTitle,remainingSeconds,expiresAt})`, `clearProtection`; native event `foregroundApp` with `{id,name,platform}`; native event `blockedAttempt` with resource identity. Event handling may reuse channel method callbacks. No raw executable path in events. Native adapter owns windows and restores only changes it made.
- Loopback bridge: authenticated bounded JSON on 127.0.0.1, one-use pairing code, independent random connection token, strict Origin/Host, flavor/account isolation, no account credentials or arbitrary commands. Provide state and Focus actions. Default ports distinct by flavor and visible in setup. Pairing revoked on logout. Surface actual capability rather than claiming protection when a required permission/adapter is missing.

## Tasks / ownership

1. Backend: atomic shared Focus RPC and once-only history, profile/resource sync, device coverage, authenticated Pro classification through existing AI endpoint/quota. Own server files.
2. Chrome: rules engine/DNR/content guard/block page, background lifecycle, profiles/assignments editing and discovery, shared Focus and local bridge client, permission UX, privacy/packaging/localization/tests. Own apps/chrome-extension.
3. Native: macOS public/sandbox-safe shield + discovery, Windows foreground/shield, Linux supported compositor adapters, Dart native gateway. Own native sources and Dart platform gateway only.
4. Flutter integration: Dart models/rules/persistence/shared Focus repository coordinator, app lifetime, local bridge server, settings/profile editor, Account & Pro AI quota, localization and tests. Own remaining Flutter sources.
5. Review: automated suites first, platform checks where available, security/expiry/owner/strict/reconnect regression checks, actual acceptance matrix and remaining limitations.

## Verification / rollout

Use meaningful behavior tests before new nontrivial code. Backend SQL tests must exercise concurrent/replayed/stale commands and row ownership. Browser tests cover already-loaded/cache/SPA/media, worker restart and expiry cleanup. Dart tests cover rule precedence, all Focus phases/exit policies, offline conflicts and app-lifetime wiring. Native compile/runtime checks separately per environment; unsupported environments must be reported. Signed sandbox macOS + loopback feasibility gates claims, not code availability. Staging changes and deployment are authorized. Production deployment and store release are outside this task.

Use existing Focus imagery, themes, localization and accessibility/Reduce Motion. Follow docs/design-system.md. New repository docs are English. Mobile blocking, daily quotas/schedules, content/duration statistics and anti-tamper are deferred. Optional local deduplicated blocked-attempt events only.

## Progress ledger

- Preflight: backend produces FocusLiveSession consumed by Flutter/Chrome; JSON contract above is authoritative.
- Preflight: native produces method channel consumed by Flutter protection coordinator; native agent does not edit Flutter UI/providers.
- Preflight: browser/server/native owners do not overlap; Flutter integration owns settings and localization.
- Ruling: use an isolated managed worktree on develop, leaving existing main checkout edits untouched. User explicitly requires latest develop; fetched and verified before editing.

## Native keyboard acceptance

- macOS shields use an activating, key-capable panel and take Pomodoist activation before showing and hide unless the panel becomes key. Deactivation hides the panel; Cmd-W and Escape do not dismiss it or reach a covered application. An AppKit executable check verifies key eligibility, activating style, and dismissal shortcuts; Swift compilation and project-file lint pass. Live typing, multiple displays, Spaces/full-screen transitions, VoiceOver, and signed sandbox distribution remain manual acceptance checks. If activation is refused, the shield stays hidden and protection retries on subsequent foreground observations.
- Windows checks foreground ownership after attempting shield activation and hides the shield when Windows refuses it. The blocked window remains minimized. The native debug application compiled successfully in CI; foreground-lock denial, typing, and restore behavior still require Windows runtime acceptance.

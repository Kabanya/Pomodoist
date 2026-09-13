# Two-minor-release architecture design

The accepted design is an application monorepo: one Flutter package under
`apps/flutter`, Telegram Mini App and Chrome beside it, OpenClaw under
`tool/openclaw`, and a shared modular server under `server`. Root Make,
`.fvmrc`, environment files, deployment helpers and CI remain repository concerns.

See [repository structure and dependency direction](../../architecture/repository.md)
and [compatibility, identity and release sequence](../../architecture/compatibility.md).
The [implementation plan](../plans/2026-09-13-repository-refactor-options.md) is the
execution checklist.

## Required properties

1. Watch is a client adapter. AI provider orchestration and task/Focus operations
   are owned by common server modules with explicit dependencies.
2. Telegram and MCP/OpenClaw call common behavior directly. Guarded mutations keep
   durable idempotency, authorization and revision/hash checks.
3. Draft batch creation persists all intended operations atomically. Legacy
   accepted-command retries do not create duplicates or dangling relationships.
4. Flutter retains a single database, existing offline queue and provider
   lifetimes. Voice orchestration, billing access/state/UI, and sync mapping have
   clear owners. Pure rules do not depend on app composition, UI or storage.
5. Source relocation preserves app identities, database/settings formats, native
   embedding, build configurations and existing root commands.
6. Architecture boundaries and handwritten cycles are checked automatically.
   Existing date behavior is captured, not changed.

## Exclusions

No new packages, microservices, dependency upgrades, UI redesign, entitlement
policy, AI quota changes, date-rule changes or historical lost-data recovery.
Manual testing is excluded from this implementation by the user's latest
instruction; use unit tests and simple automatic checks only.

## Rollout

R1 ships the structure, additive migration and common server implementation while
keeping both old and new AI entries available. Default client builds keep the
Watch AI route. R2 selects the new AI entry explicitly, requires server R1, retains
input on missing endpoint and never automatically replays an ambiguous call.
The old external API remains until a separate support decision removes it.

Implementation occurs directly in `develop` from `71a9814`, without a worktree.
Version selection, commit/push, deployment, platform release acceptance and
publication are separate actions. Server migration must precede new functions;
R2 backend rollback must not go below R1.

# OpenClaw integration implementation plan

**Goal:** Resolve #49 with native OpenClaw OAuth/MCP access to Pomodoist tasks and Focus, without a second task store or account password handling.

**Architecture:** Retain the existing MCP resource and OAuth grant. Expose additive guarded tools that plan using the existing task/Focus runtimes, then atomically check the account revision, push sync operations and persist an idempotency receipt. Native OpenClaw tool filters default to reads; explicit write setup permits only guarded tools.

**Base:** `b8db2ed37fd725ad7f967c096db582abc0234e8b` (`main` when the branch was created).

## Deliverables and verification

- [x] `openclaw/configure.mjs`, `config.test.mjs`: reject credential-bearing/non-TLS remote endpoints, produce narrowly scoped native MCP configuration, invoke OAuth only under explicit `--apply`. Verify read/write allowlists and argv-based execution.
- [x] `openclaw_actions.ts`, `openclaw/actions.test.mjs`: canonical argument fingerprints, prepare-before-plan, buffered legacy writes, replay without replanning, no automatic retries on ambiguous failures. Run the Node tests before and after implementation.
- [x] `openclaw_tools.ts`, `openclaw_tools_test.ts`: reuse task schemas/handlers; expose explicit Focus identity checks and task deadline/duration editing. Test the real registration/runtime in the Deno CI suite.
- [x] Additive `*_pomodoist_core_openclaw.sql`: preserve shared sync semantics, serialize account writes with the existing calendar lock, service-only OAuth-bound action/state RPCs, private RLS-protected durable receipts. Never edit the frozen baseline or a live deployment.
- [x] `pomodoist_openclaw.test.sql`: exercise ACLs, user isolation, replay, changed fingerprints, concurrent-device revision conflicts, transaction rollback and revoked access using synthetic rollback fixtures.
- [x] Document setup, explicit permissions, revocation, duplicate recovery, supported operations and rollout. Keep existing workflows unchanged; the current jobs discover the new Deno and database tests. Run the Node setup/planner suite separately.
- [ ] Review final diff and run CI. Record any environmental verification limits in the PR, rather than claiming unexecuted checks passed.

## Constraints

No hardcoded hosted endpoint, additional secret, new service-role exposure or production deployment. A read-only tool filter is local policy, not a new server-side OAuth read scope. Keep original MCP names unchanged. A new deliberate action gets a new UUID; retrying an uncertain action keeps the same UUID and arguments. Receipts contain mutation metadata, not account tokens, and are retained until account/client deletion.

# Branch-Based Backend Deployment — Corrected Implementation Plan

**Status:** Corrected after verification against both live repositories and hosted state
on 2026-09-23. This revision supersedes the prior corrected draft: three of its findings
(C2, C3, C4) were themselves partly wrong, and the error changed which task is the real
blocker. Read "Verified corrections" before implementing anything.

**Goal (unchanged):** A relevant push to `develop` automatically reaches staging; a
relevant push to `main` automatically reaches production. Public Pomodoist server
changes reach the matching private backend branch with no manual tag, lock update, or
deployment command.

**Architecture (unchanged):** Keep immutable `server-vX.Y.Z` tags and the
digest/revision-checked `pomodoist-core.lock.json`. Public server CI publishes a
branch-appropriate tag and sends `repository_dispatch` to the private repo with a
short-lived GitHub App token. The private workflow verifies public refs, reconciles the
branch lock, and explicitly dispatches that branch's deployment workflow. An hourly
scheduled run repairs a lost event. Staging and production are independent lanes.

---

## Verified corrections

Each finding below was produced by reading both working trees, their Git history, and
live hosted state. Where a prior draft was wrong, that is stated explicitly.

### C1. The private repo already implements most of the staging and production work

Confirmed: `origin` is `https://github.com/Kabanya/account-sync-platform.git`.
`origin/develop` is **2 commits ahead of `main`** (both trees otherwise clean):

- `4810250 ci(staging): trigger staging from develop and drop the production dry run`
- `c5e226a ci(production): require a default-branch dispatch for the promotion gate`

`git diff --stat origin/main..origin/develop` touches exactly six files:
`supabase-staging.yml` (−37), `supabase-production.yml` (+17), `supabase-production-dry-run.yml`
(+4), `docs/supabase-release.md`, `scripts/validate-supabase-workflows.ts` (+82),
`scripts/validate-supabase-workflows_test.ts` (+62).

What `4810250` already did: `branches: [main]` → `[develop]`; deleted the entire
`production-dry-run` job from the staging workflow; staging `needs: validation` only.
What `c5e226a` already did: a `Require a dispatch from the default branch` step
comparing `github.ref` to `refs/heads/<default>`; and rewrote the staging-run lookup to
match `.path == ".github/workflows/supabase-staging.yml" && .event == "push"` instead of
`branch == default`.

Treat Tasks 4 and 5 as **reconciliation and completion**, never greenfield. Rewriting
either workflow silently reverts a green commit. Note that `c5e226a` did *not* drop the
staging-run requirement itself — it only rewrote how the run is matched. The production
lane gate in Task 5 still has to be replaced.

### C2. The staging workflow on `develop` has no `workflow_dispatch` trigger

Read `origin/develop:.github/workflows/supabase-staging.yml`: the trigger block is
`push: branches: [develop]` with path filters and **nothing else**. There is no
`workflow_dispatch`, so there is no `inputs.release_sha`.

This matters because of the `GITHUB_TOKEN` rule at the heart of the design: the sync job
commits the lock with B's built-in token, and that commit will not start an ordinary
`push` run. `workflow_dispatch` is the supported exception, and it works only if the
workflow declares that trigger — and the declaration must exist on B's **default branch
(`main`)**, not just on `develop`, or GitHub will not offer the workflow for dispatch.
Adding the trigger to `develop` alone is insufficient.

`supabase-production.yml` already has `workflow_dispatch` with `inputs.release_sha`
(required, string) plus `inputs.enable_turnstile`. It is declared on `main`, so dispatch
works there today.

### C3. Collaboration is *already reachable* from production's pinned release

A prior draft claimed production "has never adopted the collaboration core at all" and
that adoption was a large separate release. **That is wrong**, and it inverted the risk.

`server-v0.1.9` — the tag B `main` pins — contains:

- `server/supabase/migrations/20260914081546_pomodoist_core_collaboration.sql`
- `server/supabase/migrations/20260914104510_pomodoist_collaboration_consumers.sql`

`20260914104510_pomodoist_collaboration_consumers.sql` is in the assembler's closed
`LEGACY_FORWARD_MIGRATIONS` frozenset (line 28 of `scripts/prepare-pomodoist-core.py`),
so it survives assembly. It is committed as a **109-byte symlink** into
`../functions/_shared/.pomodoist-core/supabase/migrations/…`; the symlink resolved on
disk to the same target, and `git ls-files` tracks it. The blob is the symlink itself,
not the SQL.

Critically, `server-v0.1.9`'s manifest lists **`pomodoist-collaboration`** in
`manifest["functions"]` (13 functions total, verified in the tag's
`server/core-manifest.json`),
and `server/supabase/functions/` on that tag carries `pomodoist_collaboration*.ts`
helpers. So the pinned core v0.1.9 already contains both the collaboration migration
and the Edge Function.

Consequence: **the initial collaboration chain is not gated behind adopting a new tag.**
It is already in the deployable set for B `main` today. The pending-migration question
is what the ledger boundary `20260913222604` → present actually applies from the
assembled B migration directory. P's new initial baseline is explicitly excluded, so
its contents do not upgrade an existing database by themselves. Review the exact
pending SQL, not only tag membership.

Scope limit on this finding: v0.1.9 has the collaboration *schema and function*, but its
dispatcher has no `unshare` branch (see C4). So C3 removes a scoping blocker; it does not
remove the need for the forward migration.

### C4. The `unshare` baseline-vs-legacy byte-identity check is correct but was misread

The prior draft's byte-identity finding (35959 bytes each, `CREATE` header normalized)
between the baseline `private.pomodoist_collaboration` and the legacy file stands. What
was misread is its meaning. The baseline `20260922162731_pomodoist_initial.sql` exists
**only on `develop`**; `main`'s manifest baseline is instead
`20260906123349_pomodoist_initial.sql`. So the byte-identity says the *unshare body
itself* is already correct in the new baseline — it does **not** say a forward migration
is a no-op in all cases, because hosted production has never applied any collaboration
migration at all.

The prior draft's instruction "do not create a forward migration" was too broad.
Verified: `server-v0.1.9:server/supabase/migrations/20260914081546_pomodoist_core_collaboration.sql`
(82857 bytes) contains **no occurrence of `unshare` at all**. The legacy
`20260917000000_pomodoist_core_collaboration_unshare.sql` handles it at line 225
(`action='unshare' and actor<>s.owner_id` → SQLSTATE `42501`) and line 283
(`elsif action='unshare'` → restore owner content, emit `access.unshare` at line 306).
P `develop`'s active migration directory holds only the fresh-install baseline plus
`api_v1`; those three `20260916*`/`20260917*` dispatcher revisions live in
`server/supabase/legacy/`, which is the immutable pre-baseline chain.
A hosted forward upgrade carrying the reviewed `unshare` dispatcher **is required**.
For this one-time transition, reuse the three existing immutable legacy revisions as
regular B migrations in their original order; the last one installs `unshare`.

**Completing the picture — why the hosted chain must be complete.**
`server/scripts/migrate.sh` is explicit that `legacy/` is used *only* to upgrade
existing independent servers, and its own comment says the runner "is never used to
upgrade the hosted production database". For a hosted upgrade the assembler plus
`supabase db push` is the operative path. Hosted production is at ledger
`20260913222604` and has none of the three revisions. Copy all three into B's hosted
migration directory; then the ordered pending set can apply them after the v0.1.9
collaboration schema. Merely leaving them in P `legacy/` has no hosted effect.

### C5. Live hosted state: production 404s, staging 400s — different causes

Production project (`ewauihswbwduvklrozke` as currently configured):

```
POST /functions/v1/pomodoist-collaboration -> HTTP 404 NOT_FOUND
```

The hosted `private` schema holds 28 functions and none is a collaboration function.
Combined with C3, the v0.1.9 Edge Function was never deployed there.

Staging returns `400 {"error":"Unknown collaboration action","code":"invalid_request"}`.
That is emitted by the Edge handler's `validateCollaborationRequest` before auth or SQL.
B `develop` and `main` both still pin `server-v0.1.9`; the `unshare` action set differs
between that tag and P `develop`. Do not attribute the staging 400 to the PL/pgSQL
dispatcher.

The immediate staging 400 is an **Edge function-version** gap. The complete fix also
requires a SQL forward upgrade: the pinned tag's dispatcher lacks `unshare`, and the
new baseline containing it is excluded for existing databases (C4).

### C6. Production ledger sits at `20260913222604`

`supabase_migrations.schema_migrations` on `ewauihswbwduvklrozke` has 43 rows ending at
`20260913222604`. There is no `20260914*` … `20260922*` row. B `main`'s local
`supabase/migrations/` also has exactly 43 entries ending at the same
`20260914104510_pomodoist_collaboration_consumers.sql` — which is a symlink, so its
content only materializes after the assembler extracts the core cache.

The user states Nottica is no longer connected to Pomodoist and must stay separate.
Historic Nottica references (e.g. `20260821153913_recover_nottica_account_relations.sql`,
`20260907230247_pomodoist_only_production_cleanup.sql`) are history, not proof of live
sharing. Verify the target project is Pomodoist-only; never redirect a Pomodoist deploy
at a Nottica project.

### C7. Public tags stop at `server-v0.1.9`; no RC tags exist

`server-v0.1.2` … `server-v0.1.9`, all on `main`. No `-rc.*` tag exists anywhere.
`develop` carries 111 files of server changes absent from `main`. The next RC would be
the **first ever**. Task 2's tests must seed synthetic RCs.

`server/supabase/migrations/` on `develop` holds only `20260922162731_pomodoist_initial.sql`
and `20260922162925_pomodoist_core_api_v1.sql`; neither exists on `main`. Any instruction
to "sort after `20260922162925…`" is checking a `develop`-only file.

### C8. B's assembler contract is intact and must not be weakened

`prepare-pomodoist-core.py` reads `core-manifest.json` (`format: 1`), enforces the closed
`LEGACY_FORWARD_MIGRATIONS` frozenset and the `_pomodoist_core_` infix rule, rejects
symlinked locks, and refuses a shared migration that conflicts with existing immutable
history. B's `20260906124741_pomodoist_core_account_runtime.sql` is byte-identical to P's
legacy copy (md5 `0a1480e382da2f8662a87e06acdd90d9`). Preserve all of it.

### C9. Live GitHub settings

`gh api repos/Kabanya/account-sync-platform/environments` returns `production`,
`production-validation`, `staging`, all with `protection_rules=[]`. There is **no**
reviewer gate today, so unattended deployment is already possible; there is nothing to
remove. P environments are `android-production` and `windows-production` only — there is
**no** `server-release` environment for App credentials to hang from, so either create
one or scope repo-level secrets with a job `if`.

### C10. Updating the lock to the restructured public core currently breaks migration history

I ran B's assembler in a temporary target containing its tracked legacy collaboration
consumer symlink, using P `develop/server` as the source and `--update-lock`. The command
returned success, but the old `20260914104510_pomodoist_collaboration_consumers.sql`
symlink became dangling, `20260914081546_pomodoist_core_collaboration.sql` was absent,
and only the new `api_v1` forward migration appeared. The assembler replaces its one
ignored core cache with the new tag's files; P `develop` no longer contains the old
forward migration files because they were consolidated into the fresh-install baseline.

Therefore tag/lock automation must not be enabled until B's **published forward
migration history is self-contained**. Materialize every still-needed v0.1.9 forward
migration under its original immutable filename/content as a regular tracked SQL file
in B, replacing cache symlinks and adding generated-but-untracked historical files.
Then carry the three later legacy revisions into B as immutable hosted migrations and
test both a clean baseline and the B hosted-style upgrade. A green assembler exit alone
is insufficient; assert that
every migration path resolves and that the pending set contains the old collaboration
schema before the `unshare` replacement.

**The independent-server runner fails hard.** `server/scripts/migrate.sh`
(line 27) resolves an applied version with:
`source="$root/migrations/$version.sql"; [ -f "$source" ] || source="$root/legacy/$version.sql"`.
If neither exists it exits with `Unknown applied migration: $version` — a hard failure,
not a skip. An independent server whose `pomodoist_meta.schema_migrations` ledger names
a missing migration cannot complete startup; this check runs before any new migration.
However, all 14 v0.1.9 migration files, including its baseline, are present under P
`develop/server/supabase/legacy/` with **identical bytes**, so this specific P upgrade
still resolves them through the runner's fallback. Do not describe self-host startup as
already broken by the observed cache replacement.
Hosted production instead uses `supabase_migrations.schema_migrations` and
`supabase db push`, so this runner does **not** prove the hosted failure mode. The
scratch assembler result independently proves its output can contain dangling links
and omit historical files without failing: B's assembler does not import P `legacy/`.
The hosted path needs its own continuity check before `db push`.

Two consequences the earlier drafts missed:

- This extends beyond the collaboration files. The assembler swaps the whole core cache,
  so **every** v0.1.9 forward migration is at risk, not only
  `20260914104510_pomodoist_collaboration_consumers.sql`. v0.1.9 carries 14 files under
  `supabase/migrations/`; the baseline is excluded, leaving 13 whose original names
  and bytes must be preserved through the cache replacement.
- Three further files are at risk and are easy to miss: they exist **only** under
  `server/supabase/legacy/` and in *neither* `server-v0.1.9` nor
  `develop/server/supabase/migrations/` (verified in both):
  `20260916000000_pomodoist_core_collaboration_share_revision.sql`,
  `20260916120000_pomodoist_core_collaboration_shared_envelope.sql`,
  `20260917000000_pomodoist_core_collaboration_unshare.sql`.
  `checked_files` reads only `source/supabase/migrations`, and `assemble` creates links
  only for the `future` set, so `legacy/` is never imported. A lock bump therefore
  produces a migration set that silently lacks the dispatcher revisions. Note that
  `server/supabase/legacy/` holds 17 `.sql` files (the 14 tag files plus these three),
  not 14.
- These three are not redundant with each other. Verified: `20260916000000` replaces
  `private.pomodoist_collaboration` and handles `invite`/`role`/`transfer`/`leave` but
  still has **0** occurrences of `unshare`; `20260916120000` replaces only
  `private.pomodoist_shared_apply`; `20260917000000` replaces
  `private.pomodoist_collaboration` again and introduces the `unshare` branch. So the
  final hosted dispatcher is produced only by the last file, and skipping either earlier
  revision loses `share`-revision or envelope behavior. Carry all three.
- `baseline_check.py:100-103` proves the independent-server contract: it iterates
  `supabase/legacy/*.sql`, applies each, and records a **sha256 of the file bytes** in
  `pomodoist_meta.schema_migrations`. Line 133 then asserts that mutating an applied
  checksum makes `migrate()` fail. This does not describe the hosted Supabase ledger.
  Byte fidelity is still the release requirement: `prepare-pomodoist-core.py` rejects
  differing bytes at an existing migration path (line 136), and the cutover must compare
  all 13 historical files with the pinned tag, including dangling paths that the
  assembler currently misses.

---

## Revised task list

### Task 0: Write the corrected defect statement

- [ ] Replace the earlier single-cause framing with C3/C4/C5/C10 evidence. State
      plainly that staging's immediate `400` is an Edge function-version gap, while
      completing `unshare` on an existing database also needs a forward SQL upgrade.
- [ ] Confirm the production project ref belongs only to Pomodoist. Audit stale Nottica
      references in B's Pomodoist Auth, config, and release docs; remove obsolete
      coupling through a separate reviewed change.
- [ ] Do not assume that a function body already present in the fresh-install baseline
      upgrades hosted databases. The baseline is excluded there.

### Task 1: Produce the pending-migration dry-run artifact (the real gate)

- [ ] Before changing the lock, enumerate every v0.1.9 forward migration and every
      symlink/generated migration in B. Copy the immutable SQL from the pinned tag
      into B as regular tracked files under the **same names and bytes**; replace
      symlinks that would dangle when the cache changes. Keep the fresh-install
      baseline excluded. Verify file hashes against `server-v0.1.9`.
- [ ] Cover all 13 non-baseline v0.1.9 forward migrations, not only the two
      collaboration files (C10). Verify original names and bytes against the tag.
      `migrate.sh` makes an independent server refuse to start if an applied file is
      missing or changed, but P `develop/legacy` currently preserves all 14 old files.
      Hosted production needs a separate pre-`db push` assertion because B does not
      assemble that `legacy/` directory.
- [ ] Also materialize the three dispatcher revisions that exist **only** in
      `server/supabase/legacy/` and in neither the tag nor `develop/migrations`:
      `20260916000000_…share_revision.sql`, `20260916120000_…shared_envelope.sql`,
      `20260917000000_…unshare.sql`. Copy them into B as regular tracked SQL files under
      their original names; all three already use the `_pomodoist_core_` prefix. Without this
      the lock bump yields a set missing the dispatcher chain.
- [ ] Use the existing `20260917000000` legacy file (sha256
      `2a0139a3af762217e9da5ffd4083450a33fe9d665d7bb57bf5ae4f56c7774e08`)
      as the `unshare` forward revision. Do not add a second migration with the same
      final dispatcher. The earlier `20260916000000` dispatcher is an intentional
      intermediate revision in this historical chain.
- [ ] Verified dependency chain for that ordering (do not reorder):
      `20260914081546` creates the collaboration tables and base functions
      (`private.pomodoist_members`, `pomodoist_scopes`, `pomodoist_shared_apply`, …) and
      the original `private.pomodoist_collaboration`. `20260914104510` adds consumers.
      `20260916000000` then `create or replace`s `private.pomodoist_collaboration`
      (still **no** `unshare` branch — verified 0 occurrences; it adds
      `share`/`role`/`transfer` handling). `20260916120000` replaces only
      `private.pomodoist_shared_apply`. `20260917000000` replaces
      `private.pomodoist_collaboration` again, adding the `unshare` branch at lines 225
      and 283. Applying the three copies out of order would fail on a missing dependency
      rather than silently mangle the dispatcher, so assert the resulting body contains
      the `unshare` branch after the full chain.
- [ ] Sort order confirmed: the assembled pending set is
      `20260914081546` → `20260914104510` → `20260916000000` → `20260916120000` →
      `20260917000000` → `20260922162925` (`api_v1` last, as required).
- [ ] Do not rely on `server/supabase/legacy/` for the hosted upgrade. `migrate.sh`
      states that path is only for existing independent servers and is "never used to
      upgrade the hosted production database"; `baseline_check.py` is likewise a
      disposable local container (line 14 asserts a `pomodoist-selfhost-*` source).
      The hosted path is assembler + `supabase db push`; only the copies tracked in B's
      migration directory join that pending set. Verify the three files apply in order
      after the v0.1.9 collaboration schema and before `api_v1`.
- [ ] In a temporary B checkout, update the lock to a P `develop` source snapshot;
      assert that every assembled `supabase/migrations/*.sql` resolves, the old
      collaboration schema migration remains present, and the copied `unshare` revision
      sorts after it. The assembler must fail rather than silently leave a
      dangling historical migration link.
- [ ] Run the assembler into a scratch checkout and compare the generated migration set
      against the applied ledger (`20260913222604` … present). Capture the ordered list
      from `supabase db push --dry-run` **and review the SQL contents of every pending
      file**. The CLI dry-run prints which migrations would apply; it does not execute
      them or provide a line-level safety diff. Keep both the list and SQL review as
      the release artifact.
- [ ] Confirm the chain is additive on the verified Pomodoist schema: no table/data
      removal, Auth/users reset, seed, CAPTCHA toggle, Stripe flag change, or unrelated
      Auth redirect rewrite.
- [ ] Deploy `pomodoist-collaboration` only alongside the RPC it calls (see C3: the
      migration is in the pinned tag, so sequencing within one release is sufficient).
- [ ] Keep SQL evidence: owner may unshare; participant gets SQLSTATE `42501`; owner
      personal content restored and shared membership removed. These assertions exist in
      `server/tests/database/pomodoist_collaboration.test.sql` (lines 336-384); extend
      only where a hosted-schema target genuinely differs.
- [ ] Run `make -C server test-db test-smoke`, then B
      `make local-supabase-ensure` and `supabase test db supabase/tests/database --local`.

### Task 2 (unchanged in intent): Publish tested public server tags per branch

**Files:** P `.github/workflows/selfhost.yml`; new `server/scripts/next_release_tag.py`,
`server/tests/test_next_release_tag.py`.

- [ ] Add `develop` to `selfhost.yml` push branches; only the tag job gets
      `contents: write`.
- [ ] Release job depends on the `server` test job; same-repo `push` on `develop`/`main`
      only. Compare remote branch head with `github.sha`; exit without tagging if stale.
- [ ] Compute the `server/` Git tree ID; if the newest branch-appropriate tag already
      points at that tree, exit with no tag.
- [ ] Deterministic next-tag function over `server-vX.Y.Z` / `server-vX.Y.Z-rc.N`.
      `main` → stable, `develop` → rc. Seed with `server-v0.1.9`, **synthetic** RCs (C7),
      a stable promotion, unrelated/malformed tags, and a same-SHA rerun.
- [ ] Serialize publishing (`concurrency`, `cancel-in-progress: false`). Tag the tested
      SHA, verify it does not exist elsewhere, push one tag, write tag/SHA/tree to the
      summary. On a lost race refetch and recompute; never force-push.
- [ ] Mint a short-lived GitHub App installation token scoped to B and send
      `repository_dispatch` type `pomodoist-core-published` with branch, tag, public SHA.
      Never on PRs. Fail visibly if dispatch fails after tagging.
- [ ] Comment that `GITHUB_TOKEN` tags do not start ordinary tag-triggered workflows, so
      the dependency on the already-green suite is essential.

### Task 3: Reconcile the public release into each private branch

**Files:** B new `scripts/select-pomodoist-core-release.py` + `_test.py`, new
`.github/workflows/supabase-core-sync.yml`.

- [ ] Selector uses stdlib + read-only Git: input lane, public branch ref, public tags,
      current lock version; output tag + SHA, or `not ready` / `no change`.
- [ ] `main` → stable only. `develop` → matching RCs plus the stable tag whose `server/`
      tree equals the branch's. Candidate commit must be reachable from the public
      branch and its `server/` tree must equal the **current** branch tree, else
      `not ready`. Numeric SemVer; reject older than the existing lock.
- [ ] Tests with temporary Git repos: normal update, unchanged tree, two queued releases
      out of order, branch ahead of its tag, tag on wrong branch, malformed version,
      branch moved after selection.
- [ ] Workflow triggers: `repository_dispatch`, hourly off-hour `schedule`,
      `workflow_dispatch` for recovery. Keep scripts from trusted `main`; treat the
      target branch as data. Accept only `develop`/`main`. `contents: write` +
      `actions: write` only; **no Supabase or Coolify secrets**.
- [ ] Run `prepare-pomodoist-core.py --target <checkout> --version <tag> --update-lock`
      from trusted B `main`. Verify only `pomodoist-core.lock.json` changes and
      every historical migration path still resolves after cache replacement (C10).
- [ ] Before commit, re-read the public tag/branch tree and B remote target head; abort
      if either moved. Identical lock → no commit. Push without force.
- [ ] After a successful bot lock push, explicitly `workflow_dispatch` the branch's
      deployment workflow with the full B SHA as `release_sha`. This requires the target
      workflow to declare `workflow_dispatch` **on B `main`** — see C2.
- [ ] Later no-change pass: if no successful or running deployment exists for that B SHA,
      dispatch once. If the run failed, surface it and wait for a code change.

### Task 4 (revised — see C1, C2): Complete the `develop` staging lane

**Files:** B `.github/workflows/supabase-staging.yml`, `scripts/validate-supabase-workflows.ts`
+ `_test.ts`; inspect `supabase/coolify/release.sh`, `docker-compose.xubuntu.yaml`.

- [ ] **First** diff `origin/main..origin/develop` and keep what `4810250`/`c5e226a` did:
      trigger already `develop`; `production-dry-run` job already removed; staging
      already `needs: validation`.
- [ ] Add `workflow_dispatch.inputs.release_sha`, and land it on **`main`** as well as
      `develop` (C2). For a human push use `github.sha`; for dispatch require the full
      input SHA to equal the checked-out branch head. Reject any non-`develop` event.
- [ ] Before invoking Coolify, recheck the B commit is still `origin/develop` head and
      the pinned tag's `server/` tree equals P `develop`'s current `server/` tree. A
      stale run exits without deploying.
- [ ] Retain the Coolify deployment UUID/commit proof, health, OAuth, and Google Calendar
      checks. Add the collaboration smoke: POST
      `{"action":"unshare","scopeId":"00000000-0000-0000-0000-000000000000"}` with no
      bearer token; expect `401` and `code: "unauthenticated"`. Never a real scope. Do
      not gate staging on this until the function is actually deployed.
- [ ] Set `concurrency` so two database releases cannot overlap. Note the current
      `cancel-in-progress: true` on `develop` cancels an in-flight staging deploy; prefer
      serial execution plus a branch-head check over cancelling a running migration.
- [ ] Update the policy validator and mutation tests. Run
      `deno test --config supabase/deno.json --allow-run --allow-read --allow-write --allow-env scripts/validate-supabase-workflows_test.ts`
      and `deno run --quiet --allow-read scripts/validate-supabase-workflows.ts`.
- [ ] In the existing B Coolify staging resource, set the Git source branch to `develop`
      if it still tracks `main`; disable any parallel un-gated auto-deploy that would
      race the CI webhook. Do not create a second staging resource.

### Task 5 (revised — see C1, C3, C6): Complete the `main` production lane

**Files:** B `.github/workflows/supabase-production.yml`,
`scripts/validate-supabase-workflows.ts` + `_test.ts`, `docs/supabase-release.md`.

- [ ] Add the relevant-path `push` trigger for `main`, keeping
      `workflow_dispatch.inputs.release_sha`. On push use `github.sha`; on dispatch
      validate 40-char SHA, `main` ref, exact checked-out commit, and current
      `origin/main` head. Never accept a `develop` or PR SHA.
- [ ] Replace the staging-run requirement (`c5e226a` only rewrote how it matches; the
      gate itself remains) with the production lane gate: reusable B validation passes
      for this exact main SHA, and trusted production `supabase db push --dry-run` passes
      before **any** production mutation.
- [ ] Require the B lock to name a **stable** tag, verify via
      `prepare-pomodoist-core.py`, and prove its `server/` tree equals P `main`'s current
      `server/` tree.
- [ ] Reorder: prepare and validate core → link and complete dry-run → MCP
      secret/bootstrap and endpoint preflight → signing-key check → forward migrations →
      remaining functions → smoke checks. A failed dry-run leaves production untouched.
- [ ] Fail before `db push` if any assembled historical migration is missing or dangling;
      an assembler exit code of zero does not prove migration continuity (C10).
- [ ] **Review the Task 1 dry-run artifact before enabling unattended runs.** Per C3/C6
      the pending set includes collaboration migrations already present in pinned
      `server-v0.1.9`, applied against a live project with historic cross-product
      references. Verify the Pomodoist-only target and decide explicitly whether
      unattended `main` pushes may apply it.
- [ ] `pomodoist-collaboration` is absent from the production function list and 404s
      today. Add it once its RPC dependency is present in the same release. Record
      intentional exclusions for `pomodoist-ai`, `pomodoist-subscription-offer`,
      `pomodoist-transcribe` rather than deploying everything blindly.
- [ ] Add the same unauthenticated `unshare` → `401` smoke after deployment. Verify the
      ledger contains the new versions. Do not run a real owner's `unshare` in CI.
- [ ] Update the strict validator so a production `develop` trigger, missing main
      validation/dry-run, prerelease core lock, unsafe Auth toggle, or missing
      collaboration function fails policy validation.

### Task 6: Keep PR and local gates aligned

- [ ] B validation and private-key scan run on PRs and both branches. Ordinary PR
      validation stays secretless. `pull_request_target` dry-run keeps the trusted
      assembler and candidate-as-data model. Note `4810250` restricted that dry-run to
      `branches: [main]`.
- [ ] Keep B full local DB/Edge/Flutter tests and Compose validation in the reusable
      gate. Extend fixtures only for the release selector, branch mapping, SHA/lock
      freshness, migration, and policy rules.
- [ ] P public boundary, Deno/server DB suite, and tag-selection test run before tag
      creation on both branches; logs show tested SHA and released tag.
- [ ] Run P `sh tool/test_public_boundary.sh`,
      `python3 -m unittest server/tests/test_next_release_tag.py`,
      `make -C server test-db test-smoke`. Run B
      `python3 scripts/prepare-pomodoist-core_test.py`,
      `python3 scripts/select-pomodoist-core-release_test.py`, `make test-deno`, the
      policy Deno tests, and local Supabase DB tests. Report exact skipped commands if
      Docker/FVM is unavailable.

### Task 7: Operator docs and one-time settings

- [ ] Replace B docs describing manual tagging and manual promotion.
- [ ] Configure one GitHub App installed **only** on B with `Contents: write`. P has no
      `server-release` environment (C9): create one to scope the App ID/key, or keep them
      as repo secrets gated by job `if`. Never put a long-lived PAT in P; never print the
      key or token. Confirm B's default-branch workflow listens for `repository_dispatch`.
- [ ] Confirm B Actions may grant the sync job `contents: write` + `actions: write`.
- [ ] Environments: all three B environments have no protection rules (C9) — nothing to
      remove. Recheck live before assuming otherwise.
- [ ] Confirm the B staging Coolify resource tracks `develop` with commit recording on.
      Inspect P web staging/production; do not reconfigure them.
- [ ] Operational notes: dispatch is the normal trigger; the hourly schedule repairs a
      missed event; failures stay visible in Actions; `workflow_dispatch` is recovery
      only; schema migrations are never rolled back by pinning an older tag.

### Task 8: Cutover

**Precondition:** Tasks 0-7 reviewed and locally checked.

- [ ] Merge the P release workflow into P `develop`. Observe the green `selfhost.yml`
      run, the new RC tag and target SHA. A web-only P push must produce no server tag.
      Per C7 this is the **first** RC tag ever created.
- [ ] Merge B sync/staging workflow into B `develop` **and** default `main` (C2: the
      `workflow_dispatch` declaration must exist on `main`). Point the staging Coolify
      branch at `develop` before the first new webhook. Confirm the public release event
      updates only the B `develop` lock and dispatches staging for the new B SHA.
- [ ] Read the staging run and Coolify UUID. Require exact B SHA, migration before
      function publication, health, OAuth/calendar checks. The collaboration smoke is
      meaningful only after the function exists.
- [ ] Merge P `develop` → P `main`; observe green CI and an immutable stable tag. Release
      the public server first, then the private adapter/lock — the repos cannot deploy
      atomically.
- [ ] Merge B branch changes to `main`. Expect exactly one effective production
      deployment for the latest B SHA, green validation, green dry-run.
- [ ] **Do not let the first unattended `main` run apply the pending chain unreviewed.**
      Use the Task 1 artifact, confirm historical migration continuity, and accept the
      pending SQL explicitly in the run record.
- [ ] Verify the production ledger and collaboration endpoint read-only. Do not infer
      owner success from a `401` alone — the SQL tests prove the owner path.
- [ ] Record the four source SHAs, selected tags, B lock SHAs, CI run IDs, Coolify UUID,
      and migration/function outcomes. Distinguish "implemented", "CI green",
      "staging deployed", "production deployed".

---

## Stop conditions and recovery

- **Public CI fails / no tag matches branch server tree:** do not update B's lock.
- **B branch head changed during sync:** never force-push; retry next scheduled run.
- **Staging CI/migration/health fails:** do not label staging deployed.
- **Production dry-run, signing key, MCP, migration, or function step fails:** stop.
  Never reset production DB or replay the public baseline.
- **Sync commit exists but dispatch was lost:** next reconciler dispatches once.
- **An identical deployment run already failed:** no blind periodic retry.
- **Pending-migration dry-run shows destructive SQL:** stop and treat as a separate,
  explicitly approved release.

## GitHub Actions facts behind this design

- `GITHUB_TOKEN`-created commits/tags do not trigger ordinary `push` runs;
  `workflow_dispatch` is the exception.
- Repository-dispatch accepts a GitHub App installation token with `Contents: write`;
  dispatch workflows must exist on the destination default branch.
- Scheduled workflows can be delayed or dropped; hourly reconciliation recovers.
- The workflow dispatch API needs `Actions: write`.

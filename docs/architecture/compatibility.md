# Compatibility and two-release rollout

Baseline: `develop` at `71a9814`. The implementation is prepared directly in that
checkout. Committing, pushing, deployment and publication are separate release
actions. No version numbers are selected by this refactor.

## Persisted identity

| Contract | Preserved value or behavior |
| --- | --- |
| Main Apple bundle / Android application ID | `com.finchforge.pomodoist` |
| Watch bundle ID | `com.finchforge.pomodoist.watchkitapp` |
| Focus widget bundle ID | `com.finchforge.pomodoist.focuswidget` |
| Apple app group | `group.com.pomodoist` |
| Deep-link scheme | `pomodoist` |
| Drift database name / native filename | `pomodoist` / `pomodoist.sqlite` |
| Drift schema version | `7` |
| Native data directory | Existing application documents directory |
| Linux data directory | Existing documents database when present; otherwise `$XDG_DATA_HOME/com.finchforge.pomodoist` or `$HOME/.local/share/com.finchforge.pomodoist` |
| Web storage identity | Existing Drift database name and origin |
| Web SQLite/worker URLs | `/assets/web/sqlite3.wasm`, `/assets/web/drift_worker.js` |
| Sync app / local owner | `pomodoist` / `local-user` |
| Client configuration | Root `.env.*`, existing public runtime configuration and native sources |
| Flutter dependencies | Existing pinned lockfile and root `.fvmrc` |

Moving source files does not migrate user data. Native Apple references to
`../apple` and `../../StoreKit` retain their relative geometry because all native
projects and shared files move together. Regenerate generated Flutter/Xcode
configuration with the pinned SDK; do not edit generated absolute paths manually.

## API behavior

Both `pomodoist-watch` and `pomodoist-ai` accept the existing
`task.decomposeTranscript` command. They share authentication, StoreKit proof
verification, response decoding, error codes, prompts, model selection, fallback
order and time budgets. Analysis returns editable drafts and does not create
stored tasks. Existing paid/free access and quotas are unchanged.

The draft-commit command uses `command.id` as its retry key. Every draft operation
is distinct; entity IDs remain stable on a retry. The additive receipt procedure
makes the batch atomic and recognizes the original legacy receipt. Retrying an
already accepted old command acknowledges it without recreating lost historical
drafts. A request without an ID cannot guarantee cross-request idempotency.

Flutter still owns its local queue/database and commits local changes with their
queued operations atomically. Chrome keeps its sync API. Date serialization,
settings and entitlement semantics remain unchanged.

## Release sequence

| | R1 | R2 |
| --- | --- | --- |
| Repository | Full new layout and common implementation | Same architecture |
| Server | Additive migration, then compatible functions | R1 or newer required |
| Maintained Flutter client | Default `POMODOIST_AI_ENDPOINT=watch` | Build with `POMODOIST_AI_ENDPOINT=ai` |
| Installed old clients | Old Watch endpoint supported | Old Watch endpoint still supported |
| Missing new endpoint | Not selected by default | Show server-upgrade guidance; preserve input/drafts |
| Automatic fallback replay | None | None |
| Server rollback floor | Previous verified compatible release, with matching functions/schema | R1 |

Set the existing client build defines explicitly for R2; do not infer capability
from a failed paid call or mutation. A timeout/404 does not trigger a second call
to another endpoint. Removing the legacy external API requires a separate
support decision, even after R2 ships.

Apply `20260913110613_pomodoist_core_companion_state_and_draft_receipts.sql` **before**
deploying R1 functions: they depend on the new receipt and scoped-read RPCs. The
initial installation migration is immutable. Hosted delivery consumes the public
manifest and additive migrations; self-hosted delivery uses `server/compose.yaml`.
Do not publish private platform migrations or production credentials in this repo.

## Acceptance and limits

Automated evidence belongs in the implementation report: Flutter analysis/unit
tests, Deno/Node units, real isolated SQL receipt assertions, helper tests and a
clean-copy dependency/path check. The requested scope excludes manual testing.

Before a release, separately confirm supported platform builds and staging old
requests, Focus, purchases, offline synchronization and rollback ordering. Local
unit tests do not establish remote CI, staging or production health. Compare
existing error/timeout logs without logging user transcripts or secrets.

Known date differences (local/UTC projection, parser interpretation and
productivity day boundaries), new entitlement rules and AI quota policy remain
separate tasks. Existing contract cases preserve the current behavior.

## Inherited hosted assembler gate

The configured hosted assembler rejects the baseline file
`20260913000418_pomodoist_voice_quota_2500.sql`: its existing rule requires
`_pomodoist_core_` in every additive migration name. The failure reproduces on
`71a9814`; this refactor preserves that already tracked migration and its policy.
The new refactor migration uses the required prefix. Manifest-only packaging and
AI/Watch/MCP dependency checks pass, but the inherited full-assembly failure must
be resolved in the release tooling before deployment. Do not rename applied
migration history merely to satisfy the assembler.

## Implementation verification — 2026-09-13

The candidate Git tree was exported through a temporary index into a fresh
checkout directory containing spaces. It contained all relocated tracked files,
no private environment overrides and no generated application files. Dependency
resolution used the existing pinned SDK and `--enforce-lockfile`. No commit was
created to prepare this check.

| Automated check | Result |
| --- | --- |
| Clean-copy `make check` | Architecture checks, Flutter analysis and 1468 tests passed |
| Complete server, contract and Mini App Deno suite | 280 tests and 69 steps passed |
| Isolated PostgreSQL contracts | 290 assertions across 13 files passed |
| Actual draft planner through SQL receipts | 1 test passed; also registered in self-hosted CI |
| Complete focused AI client file in R1 and R2 | 7 tests passed under each endpoint selection |
| Chrome, OpenClaw and companion Node tests | 63 passed from the clean copy |
| Helper unit checks | Android 30, release notes 5, architecture 3, Linux updater 6 passed |
| Mocked packaging and paths | Linux installer, AppImage payload and Make checks passed; no real app built or launched |
| Server package boundaries | Self-host configuration and manifest-only AI/Watch/MCP dependency checks passed |
| Reviews | Server, Flutter, relocation and final cross-module reviews approved after corrections |

Manual testing, platform builds, staging, publication and production verification
were not performed. The inherited full hosted-assembly gate above remains open
and must be resolved before a hosted release.

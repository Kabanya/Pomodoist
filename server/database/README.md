# Database contract and adoption

`supabase/migrations/20260906123349_pomodoist_initial.sql` initializes a **new** database. It was extracted with `pg_dump --schema-only` from a disposable local database built from repository SQL definitions. No hosted database was contacted. The file contains the final Pomodoist objects and static application catalog, with no user data, unrelated application schema or migration history.

The baseline requires already migrated Supabase Auth and Realtime. It resets the
API roles' inherited object privileges before applying its explicit access rules,
so upstream image defaults cannot expose service RPCs or account projections. Its guard refuses an existing Pomodoist schema. The Docker bootstrap applies it after those services initialize, applies later migrations, then runs `database/enable-selfhost.sql`. The administrator must have initialized Vault, `pg_cron` and `pg_net`; the packaged PostgreSQL configuration supplies their preload settings. Persist and back up the Vault encryption key together with the database.

## Maintained source

The initial baseline is a frozen installation snapshot. Change running behavior in a new `*_pomodoist_core_*.sql` migration. The shared account runtime is defined in `20260906124741_pomodoist_core_account_runtime.sql`; both independent and existing hosted deployments consume that same file. Do not edit the baseline after its first release.

Existing hosted deployments retain their historical migrations and **exclude the initial baseline** when assembling this core. They apply only the later shared migrations, following a staging compatibility check. No migration-history repair or production baseline replay is required.

A multi-application host installs these two private SQL adapters before the shared account migration:

- `private.initialize_additional_account(uuid) returns void`: initializes storage for its other applications.
- `private.additional_account_overview(uuid, text) returns jsonb`: returns only additional application fields such as usage and purchase binding; `{}` leaves the common response unchanged.

The public migration supplies empty adapters only when they are absent. The common account wrappers, profile handling, entitlement grant and sync/integration functions stay in the public source. A host with a separate MCP gateway sets `mcp_issuer` and `mcp_audience` on its protected instance-settings row; otherwise the audience derives from that server's issuer. The public defaults contain no official-service origin. MCP OAuth permits HTTP only for the exact loopback hosts `localhost`, `127.0.0.1` and `[::1]`; remote issuers require HTTPS.

## Local feature access

The settings row defaults to `selfhost_features_enabled = false`. Only the independent-server bootstrap enables it. A protected helper gives local accounts an active, non-expiring lifetime entitlement with source `selfhosted`. The existing entitlement calculation and Pro projection then expose all local features without an official purchase. Existing official payment claims are unaffected, and service credentials remain necessary for Calendar, Telegram, MCP and payment service RPCs.

`handle_new_user()` and `ensure_profile()` both initialize local access, so new registrations and existing local accounts receive the same behavior. Client roles cannot change instance settings, write the Pro projection or execute the grant helper. External integrations still require the operator's provider credentials.

## Exposed contract

The application schema has 16 public tables and 10 private tables; all have RLS. The account SDK uses `ensure_profile()`, `get_account_overview()`, `get_apple_app_account_token()`, the current `get_usage_period` / `consume_quota` signatures and a direct RLS-protected upsert into `user_app_installs`.

`push_changes()` / `pull_changes()` retain operation receipts, deletion-wins behavior, pagination and per-account isolation. Private broadcast policies authorize only `sync:<current-user-id>:<known-app-id>` channels. Calendar includes encrypted account credentials, jobs, links and the generation guard; Telegram includes link attempts and focus arbitration; MCP includes session resolution, OAuth pseudonyms, rate limits, readers, mutations and sync hints. Empty StoreKit/Stripe tables and service RPCs support the common optional payment handlers; they are not required for independent access.

The retired quota overload that accepted a client-supplied limit is absent. Profile, token, quota and trigger entrypoints have explicit anonymous-execution restrictions. The current account SDK uses the retained signatures.

## Verification

### Advisor warnings and RPC permissions

Migration `20260913222604_pomodoist_advisor_rpc_security.sql`, applied to the hosted
project, keeps the seven account/sync RPC signatures in
`public` as `SECURITY INVOKER` wrappers. Their `SECURITY DEFINER` implementations
live in `private`, derive the account from `auth.uid()`, and retain the UTC quota
reader settings. `authenticated` and `service_role` can execute these entrypoints;
`PUBLIC` and `anon` cannot. Schema `USAGE` for `authenticated` permits resolving
those functions but grants no access to private tables or arbitrary-user helpers.
Keep `private` out of the exposed Data API schemas.

The migration also fixes the timestamp trigger's search path and evaluates the
current user once per statement in the 11 account/sync RLS policies. The automated
`pomodoist_advisor_security.test.sql` checks roles, tenant boundaries, private
entrypoints, trigger behavior, and policy/function definitions.

The expected hosted advisor result is one WARN: leaked password protection is
disabled on the retained Free plan. Supabase requires Pro or above for that feature.
INFO notices about indexes and intentionally closed RLS tables are outside this
change. Do not grant access merely to silence those notices.

Deployment verification confirmed one security WARN and no performance WARNs.
All 456 SQL assertions across 18 test files passed on isolated PostgreSQL 17 with
Supabase Auth migrations and a minimal Realtime fixture; no manual UI checks or
Realtime service integration checks were performed for this database-only change.

### Sync validation and client rollout

`20260913211408_pomodoist_core_quota_integrity_sync_validation.sql` adds a positive
usage-period interval and a composite reference to the quota definition. It
validates existing rows atomically and does not rewrite usage. A definition with
usage history cannot be deleted. Lowering a limit below already recorded usage
remains valid.

The shared sync writer checks the complete operation array, string identifiers,
`upsert`/`delete` commands and object payloads before writing. SQL NULL/empty
batches, snake_case aliases and the existing missing-command/payload defaults
remain supported. Validation errors use SQLSTATE `22023` and do not echo task
contents. Receipt replay, conflict handling and integration transactions remain
unchanged.

Client batch limits are deliberately **not enabled by the normal migration set**.
The prepared script is
`database/pending-migrations/20260913210628_pomodoist_core_client_sync_batch_limits.sql`.
It replaces `private.push_changes`, behind the public invoker wrapper, to limit
the client RPC to 1,000 operations and 8,388,608 bytes
of `p_operations::text` (PostgreSQL's JSONB text representation, including UTF-8
bytes). Larger batches return HTTP 413 / SQLSTATE `PT413`. Trusted integration
writers retain their existing atomic batch behavior.

Flutter and the extension keep their ordinary 100-operation batches and halve a
rejected batch on HTTP 413. They preserve operation IDs and order. Other errors,
or an oversized single operation, stop the attempt with pending data retained.
Flutter replays already accepted halves safely through receipts; the extension
persists each acknowledged part before sending the next one.

Release checklist:

- [x] Apply and automatically verify quota integrity and shared sync validation
  on the hosted project (`20260913211408`); include the same migration in self-hosted releases.
- [ ] Publish Flutter and extension releases containing automatic 413 splitting.
- [ ] After publication, create a fresh migration with
  `supabase migration new pomodoist_core_client_sync_batch_limits --workdir server`
  and copy the prepared SQL into it. Apply that migration and verify the limits.
- [ ] Once the migration is active in the normal migration set, remove the
  pending-script include from `pomodoist_sync_batch_limits.test.sql` and delete
  the pending script; the same assertions must then test the installed RPC.

These steps do not require every user to update. Older clients can continue
ordinary sync, but oversized requests require a client update. Local tests
exercise the pending script inside a rolled-back transaction; passing those
tests does not mean the production limit has been enabled.

### Client versions

Clients report their version and platform using the existing RLS-protected
`user_app_installs` upsert keyed by account, app and device. Flutter sends
`version+build` (or just the version when no build exists) and `android`, `ios`,
`macos`, `windows`, `linux` or `web`. The extension sends its manifest version and
`chrome_extension`. Registration is advisory: failure never blocks account reads
or synchronization. The extension refreshes this metadata with its minute-cached
overview; Flutter refreshes it when its account overview is reloaded.

Old clients may have a missing version or the legacy `flutter` platform. Do not
infer their versions, capabilities or access rights. Newly reported metadata
only appears after updated clients connect. No version history, feature flags or
automatic minimum-version enforcement is introduced.

To inspect recently reported installations (not all integration identities):

```sql
select coalesce(nullif(platform, ''), 'unknown') as platform,
       coalesce(nullif(app_version, ''), 'unknown') as app_version,
       count(*) as installations, max(last_seen_at) as last_seen_at
from public.user_app_installs
where app_id = 'pomodoist' and last_seen_at >= now() - interval '7 days'
group by 1, 2
order by 1, 2;
```

### Automated database tests

Against the explicitly selected **local** Docker database:

```sh
make test-db
```

Run this command from `server/`; it reads only the local instance password.
The runner refuses targets outside the `pomodoist-selfhost-*` Docker namespace. It uses the existing pgTAP suites and rolls back synthetic accounts after each file. It does not accept a database URL.

Validated locally: fresh baseline plus shared migration, 238 assertions in 10 public suites; historical multi-application schema plus private adapters and the same shared migration, 215 assertions in 10 hosted suites. The hosted account overview was also compared before and after adoption for synthetic free and paid accounts with another application's purchase and usage records: the JSON was identical after removing `generatedAt`. All 49 common stored routine definitions matched between the two installations; only the two private application adapters differed. Hosted local grants stayed disabled and the configured MCP audience was preserved. These are local checks, not a production adoption or deployment.

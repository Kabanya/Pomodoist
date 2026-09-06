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

Against the explicitly selected **local** Docker database:

```sh
make test-db
```

Run this command from `server/`; it reads only the local instance password.
The runner refuses targets outside the `pomodoist-selfhost-*` Docker namespace. It uses the existing pgTAP suites and rolls back synthetic accounts after each file. It does not accept a database URL.

Validated locally: fresh baseline plus shared migration, 238 assertions in 10 public suites; historical multi-application schema plus private adapters and the same shared migration, 215 assertions in 10 hosted suites. The hosted account overview was also compared before and after adoption for synthetic free and paid accounts with another application's purchase and usage records: the JSON was identical after removing `generatedAt`. All 49 common stored routine definitions matched between the two installations; only the two private application adapters differed. Hosted local grants stayed disabled and the configured MCP audience was preserved. These are local checks, not a production adoption or deployment.

# Self-hosting Pomodoist

This directory runs a private Pomodoist server and web client with Docker Compose. It includes PostgreSQL, Auth, REST, Realtime, Edge Functions, a Kong API gateway, and the Flutter web app. Data stays in named Docker volumes. Optional AI, calendar, Telegram, Stripe, CAPTCHA, and Sentry integrations remain disabled until you add their credentials.

## Requirements

- Docker Engine or Docker Desktop with Compose v2
- `make`, `bash`, `openssl`, `curl`, and `jq`
- Node.js 16 or newer; when it is absent, setup uses a temporary `node:22-alpine` Docker container
- 4 GB RAM and 40 GB free disk as a practical minimum

## Local setup

From this directory:

```sh
make setup
make up
```

`make setup` creates `.env` with fresh database, API, encryption, and ES256 Auth signing keys. It keeps legacy HS256 API keys for client compatibility while Auth signs account sessions asymmetrically, so the MCP server can verify sessions through Auth's public JWKS endpoint. Setup never prints the secrets and refuses to replace an existing `.env`. Keep that file private and backed up separately.

The default endpoints are:

- Web app: `http://localhost:58080`
- API: `http://localhost:55421`

Create accounts in the web app. Local email accounts are auto-confirmed by default, so an SMTP server is not required for initial setup. Set `ENABLE_EMAIL_AUTOCONFIRM=false` and configure the `SMTP_*` values before requiring email verification.

The startup migration enables local Pomodoist access for this independent instance. The setting lives in a private schema, and account ownership and row-level isolation remain enforced.

Useful commands:

```sh
make status
make logs                 # or: make logs SERVICE=auth
make migrate
make test-db              # database contract against the running local DB
make test-smoke           # registration, login, sync, and tenant-isolation checks
make backup
make down                 # preserves all data
```

`make core-up` starts the API and function services without building the Flutter web image.

## Configuration

Edit `.env` before the first `make up` when changing ports or public URLs. Core startup does not require provider keys.

For Google sign-in, set `GOOGLE_AUTH_ENABLED=true`, its client ID and secret, and register `${API_EXTERNAL_URL}/callback` with Google. Google Calendar, Telegram, AI providers, CAPTCHA, monitoring, and Stripe each use the matching optional variables in `.env`. Stripe checkout stays disabled unless `STRIPE_CHECKOUT_ENABLED=true` and its required Stripe values are configured.

The browser receives only `ANON_KEY`; `SERVICE_ROLE_KEY`, the database password, and provider secrets stay in server containers. The database schema enforces account ownership and row-level isolation.

## HTTPS and a custom hostname

Plain HTTP is intended only for loopback. For a server, point DNS at the host and terminate TLS in a reverse proxy. Keep `BIND_ADDRESS=127.0.0.1`, then proxy two hostnames to the local ports. A minimal Caddy configuration is:

```caddyfile
api.example.com {
  reverse_proxy 127.0.0.1:55421
}

tasks.example.com {
  reverse_proxy 127.0.0.1:58080
}
```

Set these values in `.env` before recreating the services:

```dotenv
SUPABASE_PUBLIC_URL=https://api.example.com
API_EXTERNAL_URL=https://api.example.com/auth/v1
SITE_URL=https://tasks.example.com
ADDITIONAL_REDIRECT_URLS=https://tasks.example.com/login-callback,https://tasks.example.com/auth/challenge,pomodoist-dev://login-callback,pomodoist-dev://captcha-callback,pomodoist-stg://login-callback,pomodoist-stg://captcha-callback,pomodoist://login-callback,pomodoist://captcha-callback
GOOGLE_CALENDAR_APP_REDIRECT_URI=pomodoist://google-calendar-connected
POMODOIST_MCP_ALLOWED_ORIGINS=https://tasks.example.com
```

Set `GOOGLE_CALENDAR_APP_REDIRECT_URI` to the scheme of the client served by
that deployment (`pomodoist-dev`, `pomodoist-stg`, or `pomodoist`).

Then run `make up`. The proxy must forward `X-Forwarded-*` headers and WebSocket upgrades. Caddy does both automatically. Open ports 80 and 443 to the proxy; do not expose PostgreSQL or container-internal service ports.

## Optional file storage

Personal and shared project/task files use the private `pomodoist-shared` logical
bucket. The base stack leaves uploads unavailable; enable the Storage overlay
only after provisioning a dedicated private S3-compatible bucket. Configure the
`STORAGE_S3_*` values in `.env` for your provider (AWS S3, R2, MinIO, or another
S3 API). Keep credentials server-side and block public bucket access.

```sh
export COMPOSE_OVERLAYS=compose.storage.yaml
make up
```

Keep that environment variable set for subsequent `make` and maintenance commands.
The overlay starts Storage, initializes existing database credentials, creates or
updates the private logical bucket with a 20,000,000-byte per-file limit, and
provisions the cleanup worker's encrypted Vault URL/credential. Application SQL
owns authorization, Pro eligibility and the reserved account's monthly/yearly quotas.
The gateway exposes `/storage/v1`; upload URLs never permit overwrite and download
URLs expire in 60 seconds. Preview URLs permit only the supported raster formats.

For hosted Supabase, deploy `pomodoist-files` and `pomodoist-files-cleanup`, set the
Edge secret `POMODOIST_FILES_STORAGE_ENABLED=true`, and provision Vault secrets
`pomodoist-files-cleanup-url` (full function URL) and `pomodoist-files-cleanup-secret`
(a random worker secret matching the Edge secret `POMODOIST_FILES_CLEANUP_SECRET`).
The worker checks `X-Pomodoist-Cleanup-Secret`; it does not compare the bearer JWT
with the runtime's service-role key. Self-hosted installations may set the same
worker secret in their environment; the service-role key remains the default.
The migration schedules dispatch every five minutes and a separate response check
every minute, since `pg_net` sends requests after the dispatch transaction commits.
`pomodoist-files-cleanup-response` fails in Cron on an unsuccessful HTTP response
or a missing response after two minutes. Requests without the exact configured
worker secret are rejected; failed object removals remain queued for retry. Never delete
`storage.objects` rows to remove files: the worker calls the Storage API so bytes
and metadata are removed together.

Storage is pinned to `supabase/storage-api:v1.74.0`, matching the
[upstream Compose configuration](https://github.com/supabase/supabase/blob/master/docker/docker-compose.yml)
and its [S3 overlay](https://github.com/supabase/supabase/blob/master/docker/docker-compose.s3.yml).
No image transformation service is required.

### File API and quota ownership

`pomodoist-files` accepts `capabilities`, `reserveUpload`, `finishUpload`,
`download`, and `deleteAttachment`. Reservation and capabilities identify exactly
one `projectId` or `taskId`, with `scopeId` for shared content. Clients supply a
UUID upload ID, name, MIME type and byte length; they cannot choose object paths,
access owners or quota accounts. Completion returns server-authored attachment
metadata and its revision; the existing personal/shared sync streams deliver
subsequent changes. Ordinary sync writes cannot create attachment metadata.
Legacy collaboration and MCP file actions use the same SQL authority.

Personal uploads require the owner's Pro. Shared uploads require an editor role:
the uploader's Pro is used first, otherwise the shared owner's Pro sponsors the
upload. A full uploader quota never falls back to the owner. Each file is limited
to 20,000,000 bytes; successful uploads consume 1,000,000,000 bytes per UTC calendar
month and 5,000,000,000 stored bytes per completion year. Every unfinished upload
holds the bucket maximum of 20,000,000 bytes, regardless of its declared size.
Expired or deleted uploads keep that hold until Storage deletion is confirmed
after outstanding upload URLs expire. A deleted finished file also holds a full
slot during that window. The bucket must enforce a maximum no greater than
20,000,000 bytes; unbounded or larger bucket limits disable new uploads.
At least 20,000,000 bytes of quota headroom is required to start an upload;
successful completion replaces the reservation with the exact stored bytes.
Completion checks current access, the fixed payer's Pro, actual stored size/MIME,
and the completion period's limits. Repeated completion never charges again.
Deleting a file releases that year's storage, but not monthly upload volume.

Pro expiry leaves existing downloads available. Sharing, leaving, changing the
owner and unsharing never change a file's quota payer or physical path. Unsharing
restores all current projects/tasks (including those created while shared) and
files to the owner's personal account. Public project links omit attachments.
Deleting a project removes its direct attachments; task files follow their task
when moved and are removed when retained task history is purged. Cleanup retains
expired/deleted identities long enough to remove late writes from issued upload
capabilities. Metadata is cached offline; uploads and download links require a
connection.

The implementation is checked with source analysis and isolated unit tests.
These checks do not execute migrations, validate RLS on a deployed database, or
prove a configured S3 provider works.

## Habits through MCP

The existing `pomodoist-mcp` endpoint exposes `list_habits`, `get_habit`,
`create_habit`, `update_habit`, `add_habit_check_in`, `complete_habit`,
`undo_habit_check_in`, `finish_habit`, `reopen_habit` and `delete_habit`.
Reads and date-sensitive changes require an IANA `time_zone`; an omitted date
means today in that zone. Progress uses the selected date's schedule version.
Future dates are read-only. Night belongs to the same selected calendar date.

`period_targets` assigns independent morning, afternoon, evening and night goals;
the daily target is their sum. Single marks require `period` when multiple groups
are scheduled. `complete_habit` fills remaining marks for the date or one period.
`finish_habit` ends the schedule on its inclusive `end_date` (today by default),
retaining history; `reopen_habit` removes the end date from today. Undo deletes the
latest mark, optionally in one period. Habit deletion uses existing tombstones.
Metadata and schedule updates, daily marks and reminders use ordinary account
sync; one reminder time still means one notification. No check-in time selects
its period automatically.

OpenClaw receives matching guarded `openclaw_*` actions with durable request
receipts, existing session checks and account revision protection. Update its
explicit tool filter to enable the new actions. These tools expose only the
connected account's personal habits and eligible personal projects.

Apply `supabase/migrations/20261003140901_pomodoist_habit_day_period.sql` before
releasing the updated Flutter client and `pomodoist-mcp` Edge function. This is
the single pending migration for period settings, quotas, mark attribution and
MCP support; the existing Habits baseline migration is unchanged.

## Backup and restore

`make backup` writes a compressed archive under `server/backups`. It captures application, Auth, Vault, and Storage metadata in one database snapshot, along with the instance's Vault encryption key. Treat it as sensitive. Keep a separate protected copy of `.env` as well. To choose another directory:

```sh
make backup BACKUP_DIR=/srv/pomodoist-backups
```

With `COMPOSE_OVERLAYS=compose.storage.yaml`, backup also includes the S3 object
bytes in `storage.tar.gz`. Install AWS CLI v2 and Python 3.12+ on the maintenance
host. The helper reads the same provider/credentials as Storage through Compose;
there is no separate bucket setting that can silently back up another provider.
Backup temporarily stops the running client-facing services and Storage so signed
uploads and cleanup cannot race the database snapshot, then restarts those services.
Allow downtime and sufficient local disk space for the complete bucket. A backup
without the Storage overlay refuses to proceed if object metadata exists.

Restore with the same overlay restores bytes before the transactional database
restore; it does not delete unrelated S3 keys. On any failure, services remain
stopped for inspection. Use a dedicated bucket and immutable file paths; do not
modify object bytes outside Storage. The archive and provider credentials are
sensitive. The release fingerprint includes active overlays and pins the required
Storage version as well as application migrations.

Test and copy backups off the server. Restore replaces the current database contents, so it requires both an exact file and an explicit confirmation token:

```sh
make restore \
  BACKUP=/srv/pomodoist-backups/pomodoist-20260906T120000Z.tar.gz \
  CONFIRM=--replace-current-database
```

Restore stops client-facing services, loads the dump in one transaction, and starts the stack again. It refuses a backup made from a different migration set, because data-only restores require the same server release. If database loading fails, it rolls the database transaction back and restores the previous Vault key before reporting failure.

## Password changes and session revocation

The session-revocation migration checks each authenticated Data API request
against `auth.sessions`, including RPCs in both `public` and `api_v1`. A revoked,
missing, mismatched or expired session returns HTTP 401 (`PT401`), even while its
JWT has not expired. Restrictive RLS policies also require an active session for
direct account-table access and Realtime channel authorization. Existing
ownership policies and server credentials retain their authority.

Supabase Auth revokes other sessions when a password changes; the session making
the change remains valid. The Flutter client signs out a rejected session on
its next account-overview or synchronization request. A late rejection cannot
sign out a newer session.

Apply `20260930222811_pomodoist_session_revocation.sql` before releasing the client
change. It registers `public.pomodoist_check_session` as the PostgREST pre-request
function and reloads configuration. Deployments with an existing custom
pre-request hook must incorporate this check into that hook instead of replacing
their checks. A client release alone does not close the server-side vulnerability.

Run the regression against a disposable local stack:

```sh
make test-db test-sessions
```

The API test creates and deletes a synthetic account, changes its password in
one session, and checks the other session's unexpired JWT against profile reads,
writes, account overview, and synchronization. It also checks the current/new
sessions and local sign-out. It refuses non-loopback URLs.

## Updates

The active migration directory contains the fresh-install baseline and subsequent
changes. The immutable pre-baseline chain lives in `supabase/legacy` and is used
only to upgrade existing independent servers. The migration runner checks every
installed checksum and the resulting application catalog before replacing the
legacy ledger with the new baseline record; it does not recreate user tables.
Unknown versions or schema drift stop adoption rather than being silently repaired.
Active migration files must not contain transaction boundaries: the runner commits
each file and its checksum record in one transaction, so a failed ledger write
rolls back the migration too. Archived files retain their original contents.

Old backups still require the exact old release that created them. Restore using
that release, upgrade through the normal migration runner, then create a new
backup. Do not bypass the backup release-fingerprint check.


Container versions are pinned in `compose.yaml` and the Dockerfiles. Read the upstream self-hosting changelog before changing them. PostgreSQL major versions require a documented database upgrade; changing the image tag alone cannot upgrade an existing data volume. Make a verified backup before any version update.

This package intentionally omits Studio, Storage, image transformation, connection pooling, and log analytics because Pomodoist core does not need them. Add a service only when a deployed feature requires it.

## Companion and AI endpoints

`pomodoist-ai` accepts the existing `command.type: task.decomposeTranscript`
request and returns the same task/error envelope as `pomodoist-watch`. Both call
one shared provider and purchase-verification adapter. The AI endpoint permits
StoreKit-only requests through the gateway, then verifies the signed purchase on
the server; gateway JWT verification must remain disabled for this endpoint.
Provider keys, model selection, fallback deadlines, and access policy are unchanged.

Watch draft batches use an atomic command receipt. Retry with the same command ID
after a lost response. Already accepted commands from older server versions are
acknowledged without creating new tasks; this does not recover drafts lost before
the upgrade. Apply all additive migrations before deploying the new functions.

Companion snapshot reads page through every relevant task/project/label and active
Focus state, excluding historical events. Page size never truncates task trees.
The shared state, task, Focus, decomposition and projection helpers are listed in
`core-manifest.json` so public/self-hosted packaging includes their full closure.

The draft persistence integration test executes the TypeScript planner against a
real disposable local database after migrations. The self-hosted CI workflow runs
it after the database contracts:

```sh
POMODOIST_TEST_DB=pomodoist-selfhost-refactor-db deno test \
  --config supabase/deno.json --allow-env --allow-run \
  tests/database/task_drafts_database_test.ts
```

## Google and Outlook calendar synchronization

Google and Outlook can be connected simultaneously. Each provider uses a separate
account connection, dedicated Pomodoist calendar, event links and work lease.
Scheduled personal tasks are mirrored into every connected provider. Supported
external edits update the task before being published to its other calendars.
Deleting a linked event preserves the task, clears its schedule and duration, and
removes its counterpart. Explicit rescheduling creates a new scheduled incarnation.
Disconnect preserves tasks and existing events while stopping further sync.

Apply `20261011222749_calendar_provider_connections.sql` before releasing the
updated calendar functions and Flutter client. The migration preserves existing
Google credentials, calendar IDs, linked event IDs and watch state. The endpoints
retain the authenticated `start`, `sync` and `disconnect` actions. Client-visible
connection/link entities contain safe projections; OAuth tokens remain in Vault.
The minute cron dispatches due jobs, expired leases and subscription maintenance;
a complete recovery read runs at least daily. Outlook uses Microsoft Graph basic
change notifications and lifecycle notifications rather than periodic five-minute
calendar polling. Foreign mailbox events are filtered and own writes are recognized
by their accepted baseline/version. Recurring or moved linked events pause that
link and expose a warning; losing access to a calendar does not clear all schedules.

Configure Microsoft identity platform as a confidential web application supporting
the intended organizational and personal Microsoft accounts. Register the exact
HTTPS callback `${SUPABASE_PUBLIC_URL}/functions/v1/pomodoist-outlook-calendar`,
then set `OUTLOOK_CALENDAR_CLIENT_ID`, `OUTLOOK_CALENDAR_CLIENT_SECRET` and a random
`OUTLOOK_CALENDAR_WORKER_SECRET` of at least 16 characters. The function requests
delegated `Calendars.ReadWrite`, `User.Read` and offline access through PKCE.
`OUTLOOK_CALENDAR_APP_REDIRECT_URI` defaults to
`pomodoist://outlook-calendar-connected`; use the matching flavor scheme for other
app flavors. The notification and lifecycle paths beneath the function URL must
be reachable over HTTPS. Worker configuration is persisted when starting OAuth
or requesting sync. Flutter currently exposes these controls on native platforms,
matching the existing Google settings availability.

Keep the existing Google calendar environment variables configured. New Google
connections also request `calendar.calendarlist.readonly` for recovering a
calendar creation whose response was lost; the normal event scope remains
`calendar.app.created`. Existing migrated connections with a calendar ID continue
using their original credentials.

A provider account replacement invalidates old workers and callback identities.
An old subscription whose credentials are no longer usable may remain at the
provider until its expiration; its callbacks cannot mutate the replacement
connection. Disconnect explicitly queues subscription/channel removal, then
removes its credential. Provider outages and throttling remain asynchronous and
retry according to backoff and `Retry-After`.

Calendar verification is unit-only: the Deno tests use injected HTTP/RPC adapters;
Flutter tests use provider containers and in-memory repositories. No live OAuth,
provider API, widget, browser or database integration checks were performed for
this change. Run the focused server units with:

```sh
deno test --config supabase/deno.json \
  supabase/functions/_shared/calendar/ \
  supabase/functions/pomodoist-outlook-calendar/ \
  supabase/functions/pomodoist-google-calendar/
```

Implementation choices: work is based on develop `84b43a9` in the existing
checkout; shared reconciliation contracts live in `reconcile.ts`. Local legacy
Google rows remain a compatibility fallback until canonical server projections
arrive, avoiding fabricated connection IDs. Foreground resume refreshes account
projections without forcing another provider calendar read; missed notifications
can therefore wait for daily recovery unless Sync now is requested. Outlook asks
for a 48-hour subscription and renews 24 hours before its returned expiration.
Same-account reconnect keeps a valid registration while invalidating worker
leases; reconnect queues maintenance. Provider-neutral linked labels and a visible
unsupported-event warning were included so Outlook users can identify their state.
The completed feature branch is retained for later integration; the deferred
cleanup behavior on account replacement is described above.

### Manual Pomodoro estimate compatibility

Deploy the `pomodoist_manual_focus_estimate` migration before releasing clients
that send `isFocusEstimateManual`. The optional boolean travels with
`estimatedFocusIntervals` through personal and shared sync. Missing values mean
legacy automatic precedence; no existing estimates are reclassified. New manual
estimates override the timed block's calculated target without changing its
schedule. Older clients still apply their previous precedence when starting Focus.

### Synchronization repair and local archives

The pending `20261020092144_pomodoist_manual_focus_estimate` migration also restores
server-only attachment metadata writes and file/calendar lock ordering. Personal
user-label memberships may be re-added with a newer clock; equal-time deletion
wins. Shared memberships require a revision that includes the tombstone and still
validate the referenced task, label and editor permissions. Deploy this server
change before the recovery client.

This migration was amended before its production application. An installation
that already applied an earlier copy will not receive the changes by editing the
file. Check its migration ledger before upgrading; do not alter checksums or
remove ledger entries to force a replay.

In Flutter Settings, **Restart synchronization** also detects a `legacy-unowned`
local archive. It asks the user to confirm ownership for the displayed account
before queuing personal records with their original IDs and clocks. The source
archive is retained until explicit deletion of its confirmed account, and the claim and queued operations commit together. Later
runs resume the existing queue; switching accounts cannot confirm or import the
archive for the wrong session. Integration credentials, shared caches and sync
cursors are excluded. Archived active Focus sessions are restored paused on this
device and are not published as active sessions. An unresolved archive, rejected
operation or unfinished recovery scan prevents a completed status.

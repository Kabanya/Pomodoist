# Pomodoist API v1

API v1 names the existing application contract explicitly. It uses the same users,
data, authorization rules and durable operation receipts as legacy v0.

## Transport

The Supabase origin remains configurable through the existing public configuration.
No custom domain is activated by this change. Reviewed hosted origins live in
`apps/flutter/lib/config/backend_endpoints.dart`; runtime configuration cannot
extend its own allowlist. A future domain still requires ownership, Auth callback,
client session-storage and deployment verification before it is approved there.

For PostgREST RPCs select `api_v1`: POST requests use
`Content-Profile: api_v1`; reads use `Accept-Profile: api_v1`. The URLs retain
`/rest/v1/rpc/<name>`. The `v1` in Supabase's URL is independent of this contract.
Use the existing publishable key and signed-in user's Bearer token. Anonymous
roles have neither schema access nor function execution privileges.

## RPC contract

All wrappers use SECURITY INVOKER and delegate to the existing public function.
Arguments, defaults, validation errors and JSON responses are preserved.

| Operation | Arguments | Result |
| --- | --- | --- |
| `ensure_profile` | none | Current user's profile UUID |
| `get_account_overview` | none | Existing account overview JSON |
| `get_apple_app_account_token` | none | Existing account-bound Apple UUID |
| `get_usage_period` | `p_app_id text`, `p_quota_key text`, optional `p_period_start timestamptz = null`, `p_period_end timestamptz = null` | Existing usage/quota JSON |
| `consume_quota` | same period arguments plus `p_units integer` | Existing quota consumption JSON; endpoint-managed voice/LLM quotas remain forbidden |
| `pull_changes` | `p_app_id text`, `p_device_id text`, optional `p_since_revision bigint = 0`, `p_limit integer = 500` | Existing changes/cursor JSON; advance only according to the returned cursor |
| `push_changes` | `p_app_id text`, `p_device_id text`, `p_operations jsonb` | Existing applied/receipt JSON |

The active implementation remains authoritative for entitlement rules, supported
entity payloads and pagination caps. Clients must tolerate additional JSON fields.
The public self-hosted baseline retains its existing collaboration features;
introducing v1 does not deploy those features to the official hosted database.

Keep operation IDs, device IDs, queued payloads and cursors across client updates.
Do not automatically retry an ambiguous failed v1 mutation through v0. A deliberate
version transition retaining the same operation IDs is deduplicated by the shared
receipt store; callers do not need to discard or drain their durable outboxes.
PostgREST SQLSTATE errors retain their existing mapping, including `22023` for
invalid sync input and `42501` for denied operations. Direct profile/install table
requests, Auth, Storage and Realtime retain their existing schemas and protocols.

## Application-owned Edge Function envelopes

The following application JSON request paths accept absent `apiVersion` (legacy),
`apiVersion: 0` or `apiVersion: 1`:

- account deletion, AI, Watch commands, transcription and purchase verification;
- Stripe billing client requests and subscription-offer requests;
- collaboration and file-attachment requests (`pomodoist-collaboration` and
  `pomodoist-files`);
- Telegram Mini App requests (not Telegram bot webhooks);
- Google Calendar and Outlook Calendar authenticated client POSTs
  (`pomodoist-google-calendar` and `pomodoist-outlook-calendar`; not OAuth
  callbacks, provider notifications or server worker-secret requests).

Other explicit values, including strings, null and fractional numbers, return HTTP
400 with `code: unsupported_api_version` before application mutations or provider
work. Existing method/origin/authentication, configuration and body-size checks
retain their precedence. Versioning does not activate a disabled feature.

MCP/JSON-RPC, Stripe and Apple webhooks, and provider-defined callbacks keep their
protocols. The application version is not added to signed/provider envelopes.
The `pomodoist-files-cleanup` worker uses `X-Pomodoist-Cleanup-Secret`, not the
application JSON version envelope.

## Calendar client requests

Both calendar functions use the shared
[`calendar/actions.ts`](../../server/supabase/functions/_shared/calendar/actions.ts)
handler. Send authenticated JSON POSTs to
`/functions/v1/pomodoist-google-calendar` or
`/functions/v1/pomodoist-outlook-calendar`, with an `action` and optional
`apiVersion` as described above. The request body limit is 16,384 bytes.

| Action | Successful JSON response | Meaning |
| --- | --- | --- |
| `start` | `{ "authorizationUrl": "..." }` | Open the provider authorization URL; OAuth uses PKCE and single-use state. Unconfigured integrations return HTTP 503. |
| `sync` | `{ "queued": true }` | Queue synchronization; this response does not mean provider synchronization has completed. |
| `disconnect` | `{ "disconnected": true }` | Record disconnection; provider cleanup can run asynchronously. |

Successful actions return HTTP 200. Missing or invalid user authentication returns
401; an unsupported action returns 400. OAuth callbacks use GET and redirect to
the configured application URI after connecting the account.

The shared [`calendar/runtime.ts`](../../server/supabase/functions/_shared/calendar/runtime.ts)
routes provider traffic separately: Google notifications use `X-Goog-Channel-ID`,
Outlook notifications use `/notifications` and `/lifecycle`, and worker POSTs use
`X-Pomodoist-Worker-Secret`. These are not user-authenticated client actions.

## Deployment order

1. Prepare and verify the additive `20260922162925_pomodoist_core_api_v1.sql`
   migration against the actual target. Existing public RPCs remain available.
2. Explicitly expose `api_v1` in the hosted project's Data API settings. Editing
   local `config.toml` or self-hosted Compose does not update Supabase Cloud.
3. Publish a tested `app_account` release with `apiVersion` support, then update the
   consumer's pinned SDK tag and pass `apiVersion: 1` at account initialization.
   Existing SDK defaults remain v0. No unpublished tag or local override is shipped.
4. Update other clients deliberately; keep the old endpoint and shared receipts
   available. Baseline history adoption is a separate, verified operation.

Preparation and local tests are not evidence of production deployment. No client
is switched to v1 by this repository change alone.

## Automated verification

- Account SDK HTTP unit tests cover all RPC routes, one Auth session, unchanged
  direct-table routing and preservation of operation IDs/cursors.
- `server/tests/database/pomodoist_api_v1.test.sql` covers role access, parity,
  ownership, input validation and both directions of receipt deduplication.
- `python3 server/tests/database/baseline_check.py pomodoist-selfhost-db` creates a
  disposable container, tests legacy adoption, drift/checksum refusal, atomic
  migration recording, fresh initialization (including optional Storage), and
  data-only backup restoration, then runs the SQL contract suite. The source
  container is read only.
- `server/supabase/functions/_shared/api_version_test.ts` covers version parsing
  and rejection before mutations for its listed handlers, including the legacy
  Google Calendar handler. The current Google and Outlook entry points use the
  shared calendar runtime instead; its routing tests and Outlook OAuth and
  notification tests cover worker authentication, provider routing, PKCE and
  OAuth state handling. File-request validation has separate tests in
  `_shared/pomodoist_files_test.ts`. These suites do not establish exhaustive
  version-rejection coverage for the current calendar runtime or file handler.
  No manual, device, emulator or UI tests are required for this documentation.

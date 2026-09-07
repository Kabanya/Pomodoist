# Telegram bot and Mini App

The existing `pomodoist-telegram` function now serves two authenticated adapters:

- `POST /functions/v1/pomodoist-telegram` remains the signed Mini App API.
- `POST /functions/v1/pomodoist-telegram/webhook` handles native private-chat messages and inline buttons. It requires `X-Telegram-Bot-Api-Secret-Token` and does not accept Mini App credentials instead.

No database migration is required. Both adapters reuse the same Telegram account mapping, guest-account linking, schema-v1 entities, operation receipts, and `push_pomodoist_telegram_changes` transaction. Existing task creation and 25-minute Focus behavior come from the shared Watch/Telegram backend rather than a second task database.

## Everyday use

Send any ordinary text message to create an Inbox task. The bot replies with a
short confirmation and a single **Open Pomodoist** Mini App button. `/start`, old
commands, legacy inline buttons and replies to old signed edit prompts now lead
to the Mini App without modifying tasks. Repeated message deliveries retain the
same operation ID. The registered command list contains only `/start`.

The Mini App at `/telegram/` contains Inbox, Today (including overdue), Upcoming,
Completed, Focus and Account. Lists include the linked account's tasks and use
the device's IANA time zone. Open a task to edit its title or comment, set an
all-day date, choose P1–P4, complete/restore it, start Focus, or confirm deletion.
The existing six-task pagination remains in use. Project, deadline, recurrence
and timed schedules are shown as metadata; changing the date explicitly replaces
a timed schedule with an all-day date while preserving recurrence.

The existing signed API accepts `view`, `page`, `timeZone` and optional `taskId`
on snapshot and command requests. Command responses retain list context and
include the affected task. Request bodies are bounded at 48 KiB so supported
2000-character titles and 8000-character Unicode comments fit. Field validation,
account mapping and operation receipts are shared with the existing backend.

Focus uses the existing 25-minute work interval and stored timestamps. Pause,
resume and stop are available inside the Mini App, including on clients without
Telegram bottom-button support. Elapsed completion is checked by the server.
Native Flutter active timers remain device-local under the existing sync design;
terminal Focus history and task counters synchronize. No background notification
service is added.

The Mini App follows Telegram's light/dark mode using the Pomodoist palette,
BackButton, safe areas, mobile keyboard layout and optional haptics. Its seven
existing locales remain supported. Chat responses support English and Russian.
Account linking reuses the existing secure web sign-in flow.

Task creation drafts, task-edit drafts and the ordered command outbox survive
reloads. A stale task revision leaves the draft editable; Refresh keeps edited
fields and loads current values for untouched fields before another save. Failed
requests remain queued for activation, reconnection or manual Refresh. Queue
status is visible. Expired Telegram authorization asks the user to reopen the
Mini App. Old navigation responses cannot replace the current view.

## Security, retries and synchronization

Only private chats whose chat ID matches the sender are accepted. Group, channel and mismatched callback contexts cannot read account data. Account ownership comes from the verified Telegram identity, never from a request-supplied Pomodoist user ID. All database reads are scoped to that mapped account and `app_id = pomodoist`; the write RPC rechecks the mapping under its existing row lock.

Webhook delivery IDs and Mini App commands produce stable operation IDs. Retry the same event after a timeout: the existing persisted receipts prevent a second mutation. Callback presses are acknowledged before database reads. API requests have timeouts; transient failures return HTTP 503 so Telegram can retry. Validation failures produce a safe user message. Bot tokens, message bodies and account-link tokens are not logged. Telegram delivery itself is not an exactly-once channel: an ambiguous send failure can still cause a repeated confirmation message, but it does not require a repeated task write.

Writes use field patches and preserve unrelated task properties. Mini App edits carry a revision preflight check to reject already stale cards; the existing server merge protocol remains authoritative for concurrent writes. Subtree completion/deletion stays atomic under the existing RPC's 50-operation limit. Larger hierarchies and deletion of recurring occurrences are rejected without partial changes and explicitly routed to the full app. No recurrence expansion algorithm or new authorization policy is introduced.

After a commit (or replay), a private `sync:<account>:pomodoist` broadcast hint prompts connected clients to pull. Hint/cleanup failures cannot turn a successful durable write into a failed mutation. Mini App refreshes read server state; chat confirmations are not synchronized task cards. State reads use keyset pagination, omit event history and retain a bounded safety limit.

## Deployment

The root `.env.example` includes server-only `TELEGRAM_STAGING__` and
`TELEGRAM_PRODUCTION__` profiles. Fill them in the ignored `.env.setup`, then run
`make setup-telegram` to generate `.env.telegram.staging` and
`.env.telegram.production` with private file permissions. These profiles must
never be compiled into Flutter or public web configuration.

For a local Docker backend, load its normal generated server secrets first and
the selected Telegram profile second (run from the repository root):

```sh
docker compose --project-directory server --env-file server/.env \
  --env-file .env.telegram.staging -f server/compose.yaml \
  -f server/compose.telegram.yaml up -d --build --wait functions
```

This runs against the local Docker database; the profile's public webhook URL
must point to that deployment before Telegram can reach it. For a remote
deployment, install the profile's server values in that deployment's secret store.
The overlay honors `POMODOIST_WEB_URL`, falling back to `SITE_URL` when empty.

After deploying the matching function, web host and secrets, register the bot with
`make telegram-configure` (staging), or
`make telegram-configure TELEGRAM_ENV=production`. Registration verifies the token
belongs to `POMODOIST_TELEGRAM_BOT_USERNAME` before changing any Telegram settings.
Setup alone neither deploys nor registers a webhook.

For the normal hosted release path, `make deploy-telegram-staging` deploys staging
and then configures `@pomodoist_test_bot`; `make deploy-telegram-production` does
the same for production and `@pomodoist_bot`. `make deploy-all` deploys both
environments and then configures both Telegram bots.

Deploy the updated **existing** function and configure these server-only values:

```dotenv
POMODOIST_TELEGRAM_BOT_TOKEN=...
POMODOIST_TELEGRAM_WEBHOOK_SECRET=...
POMODOIST_TELEGRAM_TIME_ZONE=UTC
POMODOIST_WEB_URL=https://your-app.example
```

Generate the webhook secret with `openssl rand -hex 32`. Never put it or the bot token in web runtime config. `POMODOIST_TELEGRAM_TIME_ZONE` accepts an IANA identifier such as `Europe/Helsinki`; UTC is the explicit default. This is a deployment-wide zone, not a guessed per-user zone. The bot shows it in every dated list.

For the self-hosted stack, add the values from `server/telegram.env.example` to the existing ignored `server/.env`, then from `server/` use:

```sh
docker compose -f compose.yaml -f compose.telegram.yaml up -d functions
```

The optional overlay adds only the new function environment settings. Keep the normal database and API secrets generated by `make setup`. The webhook requires a public HTTPS API endpoint; the Mini App requires the HTTPS web host with `/telegram/` deployed. Existing gateway JWT verification stays disabled for this function because its two entry points perform their own authentication.

Once the function and server secrets are deployed, register commands, the Mini App menu and webhook using Node.js 22 or newer from the repository root:

```sh
node --env-file=server/.env tool/configure-telegram-bot.mjs --apply
```

The setup script uses `SUPABASE_PUBLIC_URL` (or `SUPABASE_URL`) and `POMODOIST_WEB_URL` (or `SITE_URL`). An explicit `POMODOIST_TELEGRAM_WEBHOOK_URL` may override the webhook URL; it must end in `/pomodoist-telegram/webhook`. It rejects insecure URLs, retains pending updates, subscribes only to `message` and `callback_query`, and verifies the resulting webhook URL. Without `--apply` it makes no changes. Registration replaces that bot's existing webhook; use a staging bot for acceptance testing first. The implementation/CI does not automatically contact or reconfigure a production bot.

Acceptance checks: create a task by private message, repeat its webhook delivery,
open the Mini App, then edit/schedule/complete/restore/delete tasks and verify the
linked main-app account. Confirm that old commands, buttons and edit replies only
open the Mini App. Exercise Focus, reconnect/reload with pending changes, both
themes and Telegram's Back button. Inspect webhook errors before production use.

## Verification

The CI workflow checks the deployed entry point with Deno and runs the new bot/adapter tests together with the existing Mini App and shared Watch tests. It never uses production secrets or registers a webhook.

```sh
cd server/supabase
deno check functions/pomodoist-telegram/index.ts
deno test --allow-read --allow-env functions/pomodoist-telegram \
  functions/pomodoist-watch/pomodoist_watch_test.ts ../../telegram-mini-app/core_test.ts
```

The new dependency-free tests also run offline via a Node.js adapter from the repository root (this is not a substitute for the Deno entry-point check):

```sh
node --experimental-transform-types tool/run-telegram-tests.mjs \
  ./server/supabase/functions/pomodoist-telegram/commands_test.ts \
  ./server/supabase/functions/pomodoist-telegram/bot_test.ts \
  ./server/supabase/functions/pomodoist-telegram/api_compat_test.ts \
  ./server/supabase/functions/pomodoist-telegram/store_test.ts
node --test tool/configure-telegram-bot.test.mjs
```

The browser regression uses Playwright and Chrome, without contacting Telegram or
production. It exercises the real Mini App against controlled API responses and
the shared task operations. With Playwright available to Node (or `NODE_PATH`
pointing to an existing runtime):

```sh
node tool/test-telegram-mini-app.mjs
```

Use Node 22 with `--experimental-transform-types` if needed; current Node versions
strip TypeScript natively. Optional `TELEGRAM_SCREENSHOT_DIR` saves light/dark
mobile previews. Live Telegram device acceptance and deployment are separate.

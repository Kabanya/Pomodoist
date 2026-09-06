# Telegram bot and Mini App

The existing `pomodoist-telegram` function now serves two authenticated adapters:

- `POST /functions/v1/pomodoist-telegram` remains the signed Mini App API.
- `POST /functions/v1/pomodoist-telegram/webhook` handles native private-chat messages and inline buttons. It requires `X-Telegram-Bot-Api-Secret-Token` and does not accept Mini App credentials instead.

No database migration is required. Both adapters reuse the same Telegram account mapping, guest-account linking, schema-v1 entities, operation receipts, and `push_pomodoist_telegram_changes` transaction. Existing task creation and 25-minute Focus behavior come from the shared Watch/Telegram backend rather than a second task database.

## Everyday use

Send `/start` or `/help`. A plain text message or `/add Buy milk` creates an Inbox task. Inbox, Today (including overdue), Upcoming, Completed, Focus and Account are available as buttons. Lists have six tasks per page and show their configured time zone.

Open a task to change its title or notes, set an all-day date, complete/restore it, start Focus, or delete it. Edit buttons send a signed ForceReply prompt: reply directly to that message. The prompt belongs to the Telegram user, task and observed task revision; it expires after 15 minutes and accepts one successful mutation. `/cancel` returns to navigation without changing data. An already sent prompt remains usable until expiry if explicitly replied to later.

`/task <UUID>`, `/edit <UUID> <title>`, `/note <UUID> <text>`, `/schedule <UUID> YYYY-MM-DD`, `/done <UUID>` and `/undo <UUID>` provide command equivalents. `clear` removes notes or a nonrecurring schedule. Scheduling explicitly replaces a timed schedule with an all-day date; existing recurrence metadata is preserved. `/delete <UUID>` only opens a confirmation. Nothing is deleted until **Yes, delete** is pressed.

Focus uses the existing 25-minute work interval: `/focus`, `/pause`, `/resume`, `/stop` and `/finish`. The server checks elapsed time before finishing. The timer is calculated from stored timestamps and does not depend on an open chat. There are no newly scheduled background notifications; use Refresh for the remaining time, or keep the existing Mini App open for its running countdown. Active timers in the native Flutter app remain device-local under the existing sync design; terminal Focus history and task counters synchronize.

The chat interface supports English and Russian, defaulting to English for other languages. The Mini App and its existing translations remain unchanged. Account linking reuses the existing secure web sign-in flow; ordinary task and Focus actions stay in Telegram.

## Security, retries and synchronization

Only private chats whose chat ID matches the sender are accepted. Group, channel and mismatched callback contexts cannot read account data. Account ownership comes from the verified Telegram identity, never from a request-supplied Pomodoist user ID. All database reads are scoped to that mapped account and `app_id = pomodoist`; the write RPC rechecks the mapping under its existing row lock.

Webhook delivery IDs, action buttons and signed replies produce stable operation IDs. Retry the same event after a timeout: the existing persisted receipts prevent a second mutation. Callback presses are acknowledged before database reads. API requests have timeouts; transient failures return HTTP 503 so Telegram can retry. Validation failures produce a safe user message. Bot tokens, message bodies and account-link tokens are not logged. Telegram delivery itself is not an exactly-once channel: an ambiguous send failure can still cause a repeated confirmation message, but it does not require a repeated task write.

Writes use field patches and preserve unrelated task properties. Inline edits carry a revision preflight check to reject already stale cards; the existing server merge protocol remains authoritative for concurrent writes. Subtree completion/deletion stays atomic under the existing RPC's 50-operation limit. Larger hierarchies and deletion of recurring occurrences are rejected without partial changes and explicitly routed to the full app. No recurrence expansion algorithm or new authorization policy is introduced.

After a commit (or replay), a private `sync:<account>:pomodoist` broadcast hint prompts connected clients to pull. Hint/cleanup failures cannot turn a successful durable write into a failed mutation. Bot navigation always reads server state; previously sent chat messages are not proactively edited when another device changes a task. State reads use keyset pagination, omit event history and retain a bounded safety limit.

## Deployment

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

Acceptance checks: create/edit/schedule/complete/restore/delete a task in private chat, repeat the same webhook update, restart the function between delivery and retry, verify changes in a linked main-app account, edit in the main app and refresh the bot, verify wrong-secret/group requests cannot expose tasks, then exercise start/pause/resume/stop and elapsed Focus completion. Check Telegram webhook delivery errors before switching the production bot.

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

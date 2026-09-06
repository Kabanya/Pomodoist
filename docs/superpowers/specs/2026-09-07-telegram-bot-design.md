# Telegram bot: issue #9

The implementation extends the existing Telegram adapter, not the Flutter client or billing schema. Native private-chat commands and inline navigation cover task creation, title/notes editing, completion/restoration, confirmed subtree deletion, all-day scheduling, Inbox/Today/Upcoming/Completed views, account linking and the existing 25-minute Focus lifecycle.

A secret-authenticated `/webhook` route stays separate from the Mini App's signed-initData route. Both use the existing account mapping and transactional sync RPC. Stable per-bot/per-user operation IDs provide retry safety; signed edit prompts bind the intended user, task and observed revision. No arbitrary account identifiers are accepted from Telegram clients. Callback acknowledgement precedes database work. Server errors retain retries, while permanent input errors are shown safely.

The adapter reuses existing creation/Focus functions. New task mutations are field patches, respect the 50-operation atomic limit and do not expand the RPC's entity allowlist. Unsupported recurring deletion is rejected without modifying any row. Writes emit best-effort private sync hints; reads are scoped, keyset-paginated and bounded. The configured IANA time zone is visible and preserved in responses; UTC is the default.

Production webhook registration is an explicit deployment step, not part of CI. The optional self-hosted Compose overlay wires new secrets without changing the default stack. The Mini App UI and translations remain unchanged. Existing native-device active timers remain device-local; terminal Focus results use the established synchronization behavior.

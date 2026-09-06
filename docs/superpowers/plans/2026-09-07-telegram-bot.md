# Telegram Bot Implementation Plan

**Goal:** Implement issue #9 in `9-issue/make-better-telegram`, based on `a5730db` from the Chrome extension branch.

**Architecture:** Add private-chat UI and webhook routing to the existing Telegram Edge Function. Inject shared creation/Focus helpers into the storage adapter; reuse account mapping, receipts and the existing write RPC.

**Tech stack:** TypeScript, Deno Edge Functions, Telegram Bot API, existing Supabase SDK, Node.js built-in tests.

**Spec:** `docs/superpowers/specs/2026-09-07-telegram-bot-design.md`

## Constraints

No production credentials, schema migration, new dependency or automatic deployment. No changes to the Chrome extension inherited from the parent. Keep the existing Mini App API compatible, gate deletion on confirmation, reject unsafe/oversized operations atomically, and do not claim live Telegram or database verification from mocks.

## Implementation and evidence

- [x] Add command validation, scoped task patches, subtree operations and timezone-aware pagination in `commands.ts`; verify failing then passing domain tests.
- [x] Add private-chat routing, compact keyboards, signed prompts and stable receipts in `bot.ts`/`bot_ui.ts`; verify callback acknowledgement order, invalid contexts, safe replies and duplicate-delivery IDs.
- [x] Wire `index.ts` and `store.ts` to the existing backend; verify adapter tests for ownership, persisted receipt replay, failed pushes, stale revisions, optional Realtime failures and response time zones.
- [x] Keep `pomodoist_telegram.ts` compatible with signed Mini App and authenticated account-link requests; test that transient failures stay retryable.
- [x] Add opt-in configuration script, Compose overlay, secret template, deployment instructions and CI with existing Watch/Mini App regressions.
- [ ] Check the complete Deno entry point and existing regression suite in CI, since the local offline environment only provides Node/TypeScript.
- [ ] Production acceptance and webhook registration are operator release steps, not automatically executed by this change.

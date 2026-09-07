# Pomodoist for Chrome

Manifest V3 companion for Pomodoist. It uses the same Supabase Auth account, account overview and schema-v1 synchronization contract as the Flutter clients.

## Included

- Email/password and Google/Apple PKCE sign-in with token refresh.
- Today (including overdue), Upcoming, Inbox and completed views.
- Create, edit, schedule, complete and restore tasks.
- One-click task creation from the current tab's title and URL.
- Durable local outbox, cursor-based pull, idempotent retries and remote tombstones.
- Private Realtime hints while the popup is open, with a bounded refresh fallback.
- Server-owned account and subscription/entitlement status.
- Compact light/dark UI and keyboard-accessible task tabs.

Recurring schedule metadata is preserved; recurrence rule management remains in the full app. Project moves, deletion, Focus, voice and billing also remain in the full app.

## Build

Node 22 or later is sufficient; the extension has no runtime npm dependencies.

```sh
cd chrome-extension
export SUPABASE_URL='https://your-api.example.com'
export SUPABASE_ANON_KEY='your-public-anon-or-sb_publishable-key'
export WEB_APP_URL='https://your-web-app.example.com'
export TURNSTILE_SITE_KEY=''
npm test
npm run build
```

Use a public `anon` JWT or `sb_publishable_...` key only. The builder rejects service-role/secret keys and insecure non-loopback origins. `dist/` can be loaded from `chrome://extensions` in Developer mode or zipped for Chrome Web Store validation.

The build reuses `web/icons/Icon-192.png` and the repository `LICENSE`.

## Authentication deployment

For Google/Apple, add the real extension ID callback to the shared Supabase Auth allowlist:

```text
https://<extension-id>.chromiumapp.org/auth-callback*
```

When CAPTCHA is enabled, deploy `web/auth/extension-challenge.html` and `extension-challenge.js` with the web app. The page returns only a nonce-bound short-lived Turnstile token to Chrome's generated `/captcha-callback`; credentials and account tokens do not cross that page.

## Security and performance

Permissions are limited to `storage`, `identity`, `activeTab` and the configured backend origin. There are no content scripts, history permission, analytics, remote extension code, `eval`, or all-URL host permissions. Extension storage is limited to trusted contexts. The Realtime socket and 30-second fallback refresh run only while the popup is open; closing it stops those timers. Unsynced edits are durable and retry on the next open.

See [PRIVACY.md](PRIVACY.md).

## Chrome Web Store release checklist

Source and packaging are prepared by this change, but publication is an operator action. Before closing the release portion of issue #22:

1. Build against the production backend and deploy the CAPTCHA page if used.
2. Add the published extension ID to the OAuth redirect allowlist and verify email/password, Google and Apple sign-in.
3. Smoke-test two-way synchronization with an existing Pomodoist client and verify the same entitlement/subscription is reported.
4. Publish the privacy disclosure and complete the Chrome Web Store single-purpose, permission and data-use declarations.
5. Upload the production ZIP with the authorized publisher account and record the listing URL.

No store upload, backend deployment or subscription purchase is performed by this source change.

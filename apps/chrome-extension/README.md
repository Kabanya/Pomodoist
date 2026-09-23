# Pomodoist for Chrome

Manifest V3 companion for Pomodoist. It uses the same Supabase Auth account, account overview and schema-v1 synchronization contract as the Flutter clients.

## Included

- Email/password and Google/Apple PKCE sign-in with token refresh.
- Today (including overdue), Upcoming, Inbox and completed views.
- Create, edit, schedule, complete, restore and delete tasks.
- One-click task creation from the current tab's title and URL.
- A standalone interval timer tab with 15/5/25/50-minute presets, automatic
  focus-to-break transition and start/pause/reset controls.
- Durable local outbox, cursor-based pull, idempotent retries and remote tombstones.
- Private Realtime hints while the popup is open, with a bounded refresh fallback.
- Server-owned account and subscription/entitlement status.
- Compact light/dark UI and keyboard-accessible task tabs.

Recurring schedule metadata is preserved; recurrence rule management remains in the full app. Deleting a task removes only that task — its subtasks are left behind, and the confirmation reports how many there are before you commit. Project moves, Focus, voice and billing also remain in the full app.

The timer tab is local to the popup. It is deliberately not connected to tasks
or to the synced Pomodoist Focus entities, so its intervals are never uploaded
and never appear in the full app. It keeps counting against the wall clock, so
reopening the popup shows the correct remaining time, but it stops when the
popup is closed and there is no toolbar badge. The chosen duration and current
phase are cached per browser session, not per account.

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

Use a public `anon` JWT or `sb_publishable_...` key only. The builder rejects service-role/secret keys and insecure non-loopback origins. `build/chrome` can be loaded from `chrome://extensions` in Developer mode or zipped for Chrome Web Store validation.

The build reuses `apps/flutter/web/icons/Icon-192.png` and the repository `LICENSE`.

### Make commands

From the repository root:

```sh
make chrome-debug    # .env.staging → build/chrome/debug; opens Chrome
make chrome-run      # Load the built extension and check the popup renders
make chrome-release  # .env.testflight → build/chrome/release + ZIP
```

`make chrome-run` depends on `chrome-debug`, then loads `build/chrome/debug` into
a dedicated profile via `--load-extension`. It works because it drives a
Playwright Chromium build: stable Chrome ignores `--load-extension` from version
137 on. The profile is reused across runs, so the extension ID stays the same
and a manual sign-in survives restarts. The tool opens the popup, reports what
rendered, and fails when something is missing.

```sh
node tool/chrome-extension-run.mjs --preview --view timer --screenshot /tmp/popup.png
```

`--preview` injects a stub extension message layer, so the popup renders a fixed
task list without a signed-in account; `--view` switches to a tab before
inspecting and `--screenshot` saves the popup at its real 392px width.
`--await <seconds>` holds the browser open (what `make chrome-run` does).
Signing in is the one step that stays manual: open the printed
`chrome-extension://<id>/popup.html` URL.

The first time — or if you prefer stable Chrome — enable Developer mode in
`chrome://extensions`, choose **Load unpacked**, and select `build/chrome/debug`.
Keep using that directory so its local extension ID stays stable on this
computer. After rebuilding, click **Reload**, then reopen the popup. Popup-only
changes also appear when reopening it. Debug uses real staging accounts;
production accounts are separate.

The release archive is `build/chrome/pomodoist-chrome-release.zip`. Release builds
do not overwrite debug files or publish to the store. `npm run build` writes to
`build/chrome`.

Use `COMPANION_OPEN=0` to skip opening Chrome. Override profile paths with
`COMPANION_DEBUG_CONFIG` and `COMPANION_RELEASE_CONFIG`. Match the profile's public
URL, anon key and `TURNSTILE_SITE_KEY` to the server's published `/config.js`;
an empty site key against a server requiring CAPTCHA breaks password sign-in.
Keep these values in the ignored `.env.setup` and generated profiles, not in the
tracked template. After loading the unpacked extension, register its actual
`https://<extension-id>.chromiumapp.org/auth-callback*` URL in the **staging** Auth
redirect allowlist before testing Google/Apple sign-in. This is separate from
the published extension's callback.

## Authentication deployment

For Google/Apple, add the real extension ID callback to the shared Supabase Auth allowlist:

```text
https://<extension-id>.chromiumapp.org/auth-callback*
```

When CAPTCHA is enabled, deploy `apps/flutter/web/auth/extension-challenge.html` and `extension-challenge.js` with the web app. The page returns only a nonce-bound short-lived Turnstile token to Chrome's generated `/captcha-callback`; credentials and account tokens do not cross that page.

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

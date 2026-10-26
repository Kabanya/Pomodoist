# Pomodoist for Chrome

Manifest V3 companion for Pomodoist. It uses the same Supabase Auth account, account overview and schema-v1 synchronization contract as the Flutter clients.

## Included

- Email/password and Google/Apple PKCE sign-in with token refresh.
- Today (including overdue), Upcoming, Inbox and completed views.
- Create, edit, schedule, complete, restore and delete tasks.
- One-click task creation from the current tab's title and URL.
- Shared Focus controls with 15/5/25/50-minute start presets, common task/timer, strict exit policy and server-owned history.
- Optional website protection, manual profiles/categories/overrides, local hostname discovery and opt-in Pro automatic classification.
- Paired desktop Focus and protection leases for same-device offline use.
- Durable local outbox, cursor-based pull, idempotent retries and remote tombstones.
- Private Realtime hints while the popup is open, with a bounded refresh fallback.
- Server-owned account and subscription/entitlement status.
- Compact light/dark UI and keyboard-accessible task tabs.

Recurring schedule metadata is preserved; recurrence rule management remains in the full app. Deleting a task removes only that task — its subtasks are left behind, and the confirmation reports how many there are before you commit. Project moves, voice and billing remain in the full app.

## Focus and protection

The timer tab controls the account's common Focus through `pomodoist_focus`.
The server owns revisions, interval transitions and once-only history. A version
conflict refreshes the common session and asks you to retry; it never creates a
second offline timer. Presets are selected before starting. Strict sessions use
one confirmed immediate exit or a persistent 60-second countdown, chosen before
start. **Stop everywhere** ends the shared session. Disabling protection or
signing out detaches this browser through the same exit policy. The separately
confirmed emergency release affects this browser only and is available only when an authoritative read fails because the server/desktop is unreachable.

Enable **website protection and domain discovery** to request HTTP/HTTPS host
access. Unknown domains are allowed. Work and Study start with empty categories.
Profiles can block categories or explicitly allow/block a domain and its
subdomains; more specific explicit rules win. Manual category corrections apply
during an active session. Opt-in automatic categorization requires server-verified
Pro, searches public domain identities only, and shares the task-analysis AI
quota. Cached categories and manual edits are free. The popup shows server quota
usage/reset and actual website permission/incognito coverage. Enable incognito
access separately in Chrome's extension settings if wanted.

Protection runs in the MV3 worker, independently of the popup. New main-frame
requests redirect to the packaged Focus page. Already-loaded, cached and SPA pages
receive a removable shield; forms stay in the original document and accessible
media is paused, including permitted child frames. Private task titles appear
only inside an isolated extension frame or the extension's top-level block page.
A restrictive page can retain a generic shield if its policy rejects the frame.
Release never reloads a page, navigates back, resumes media or invents another
interval. Deliberate page tampering, force quit and uninstall are outside the
guarantee. Privileged Chrome pages and sites without granted host access cannot
be protected. Chrome limits this implementation to 1,000 domain rules per active profile; exceeding it shows an error rather than silently dropping rules.

The worker uses private realtime invalidations and a 15-second active fallback.
Thirty-second alarms, tab/navigation events and guard checks recover after worker
suspension. Leases expire locally without network access: running protection ends
at the last confirmed deadline, and disconnected paused protection ends within
five minutes of the last authoritative read. Browser alarms can be late; guards
and the block page also check expiry. A late stale redirect stays on the released
block page instead of redirecting in a loop.

### Pair a desktop

In the desktop app, create a one-use pairing code for this extension's exact
`chrome-extension://<id>` origin. Enter its visible port/code in the popup.
Defaults are production **51987**, staging **51988**, development **51989**.
Build with the matching `APP_ENV`. The client accepts only
`http://127.0.0.1:<numeric-port>`, pins the account/environment returned by pairing,
and stores a separate random bridge token in trusted extension storage. Cloud
account credentials are never sent to loopback. Choose **Account cloud** or
**Paired desktop** explicitly; authorization and revision failures do not switch
authority automatically. The desktop must keep renewing an offline lease while
alive; closing it cannot leave permanent browser blocking.

Bridge wire version 1: `POST /pair {code,deviceId,flavor}` returns
`{token,owner,flavor}`; bearer-authenticated `GET /state` and
`POST /command <FocusCommand>` return the Focus RPC envelope plus optional
`protection`. Desktop logout revokes pairing; extension logout clears its token.

## Build

Chrome 120 or later and Node 22 or later are required; the extension has no runtime npm dependencies.

```sh
cd chrome-extension
export SUPABASE_URL='https://your-api.example.com'
export SUPABASE_ANON_KEY='your-public-anon-or-sb_publishable-key'
export WEB_APP_URL='https://your-web-app.example.com'
export TURNSTILE_SITE_KEY=''
export APP_ENV='production' # staging or development for the matching desktop
npm test
npm run build
```

Use a public `anon` JWT or `sb_publishable_...` key only. The builder rejects service-role/secret keys and insecure non-loopback origins. `build/chrome` can be loaded from `chrome://extensions` in Developer mode or zipped for Chrome Web Store validation.

The build reuses `apps/flutter/web/icons/Icon-192.png`, the existing `apps/flutter/assets/pomo/focus-still.webp` pose and the repository `LICENSE`.

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

The configured backend is the only required host. Website hosts are optional.
`storage`, `identity`, `activeTab`, `tabs`, `scripting`, `webNavigation`, `alarms`
and `declarativeNetRequest` support the existing task flow and independent
protection. Registered scripts start only after opt-in. Extension storage is
restricted to trusted contexts. Content scripts can request a bounded guard
lease/return-to-task action, never account tokens, task caches or arbitrary
commands. There is no history permission, analytics, remote extension code or
`eval`. Unsynced task edits are durable.

`npm test` runs the dependency-free Node suite, including rules, expiry/restart,
strict detach, revision/idempotency, account isolation and packaging checks.
The optional real-browser acceptance check uses an existing Playwright install:

```sh
PLAYWRIGHT_MODULE=/absolute/path/to/playwright/index.mjs \
CHROME_BIN=/absolute/path/to/chrome-for-testing \
node test/browser-protection.mjs
```

It builds a temporary extension copy with website hosts granted at install and a
test-only worker handle. It exercises the shipped guard/DNR code on existing,
cached and SPA pages, media/form preservation, private iframe text, worker stop
and offline expiry. The shipped build retains optional permissions. Live account
sign-in, paid-provider classification and desktop pairing require their running
services and separate acceptance testing.

See [PRIVACY.md](PRIVACY.md).

## Chrome Web Store release checklist

Source and packaging are prepared by this change, but publication is an operator action. Before closing the release portion of issue #22:

1. Build against the production backend and deploy the CAPTCHA page if used.
2. Add the published extension ID to the OAuth redirect allowlist and verify email/password, Google and Apple sign-in.
3. Smoke-test two-way synchronization with an existing Pomodoist client and verify the same entitlement/subscription is reported.
4. Publish the privacy disclosure and complete the Chrome Web Store single-purpose, permission and data-use declarations.
5. Upload the production ZIP with the authorized publisher account and record the listing URL.

No store upload, backend deployment or subscription purchase is performed by this source change.

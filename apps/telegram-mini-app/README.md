# Mini App development

The Mini App is plain HTML, CSS and JavaScript. It does not require a Flutter
build or npm packages. Use Node 22 or later and the existing generated profiles.

```sh
brew install cloudflared  # one-time macOS setup
make telegram-debug
```

This starts a server on `127.0.0.1:7359` and a Cloudflare Quick Tunnel, then opens
the chat with `@pomodoist_test_bot`. Press **Pomodoist Debug** in the **chat menu**
to load your local code on desktop or mobile Telegram. The profile's main Mini
App button and older message buttons still open the deployed app.

Edit the local source files and refresh the Mini App to see changes. The server
reads files on every request and disables caching. The tunnel URL changes after
a restart, so reopen the app using the current chat menu. Finish syncing changes
before stopping: browser-local drafts/outbox entries belong to the old origin.

Debug uses real Telegram authentication and real **staging** accounts/data from
`.env.staging` and `.env.telegram.staging`. Link a staging Pomodoist account in the
Mini App if needed; production accounts/data are separate. The local proxy forwards
only `/functions/v1/pomodoist-telegram` to that backend, which still validates
Telegram signatures. Linking and opening the full app use the deployed staging
web app. No backend build, deployment or webhook change is involved.

Only the four Mini App assets and public runtime configuration are served. Bot
credentials stay in the local process. The command temporarily changes the
test bot's **default menu for all users**. Stop with **Ctrl+C** to restore its
previous menu and close the tunnel. Recovery state stays in
`build/telegram/debug/menu.json` until restoration succeeds. After a crash or
network failure, run `make telegram-debug` again to recover it; do not delete the
state file. A menu changed independently by another operator is preserved.

Use `COMPANION_OPEN=0` to suppress opening Telegram. Profile paths can be changed
with `COMPANION_DEBUG_CONFIG` and `TELEGRAM_DEBUG_CONFIG`, but both must describe
the same staging environment and the token must belong to `@pomodoist_test_bot`.
Only one debug process can use port 7359 at a time. If the tunnel cannot become
reachable, the command fails without pointing the menu at an unavailable app.
Inspect `build/telegram/debug/tunnel.log` for DNS or connection errors. Quick
Tunnels need working DNS and outbound access to Cloudflare; an HTTP proxy alone
does not provide the tunnel's DNS/transport connectivity.

## Release artifact

```sh
make telegram-release
```

Uses the public production values from `.env.testflight` (override with
`COMPANION_RELEASE_CONFIG`) and produces `build/telegram/release/` plus
`build/telegram/pomodoist-telegram-release.zip`. Serve the directory as a web
root: `/config.js` is at the root and Mini App assets are under `/telegram/`.
Use the existing web server's Telegram-compatible security headers and framing
policy. The build does not publish files or modify the production bot.

## Checks

```sh
node --test tool/web-companions.test.mjs tool/configure-telegram-bot.test.mjs
npm --prefix chrome-extension test
node tool/test-telegram-mini-app.mjs
```

The browser check needs Playwright available (for example through `NODE_PATH`)
and Google Chrome installed. It uses fixture data; it does not prove live login
or synchronization. On Node 22, add `--experimental-transform-types` when running
the browser script (Node 26 no longer accepts that flag). For live verification,
open the debug menu, link a staging account, create and complete a test task,
and start/stop Focus. Verify the same
task in the staging web app or debug extension, then stop the preview and check
that the previous menu returns.

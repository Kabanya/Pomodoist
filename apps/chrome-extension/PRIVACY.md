# Pomodoist Chrome extension: data handling

This document describes the extension implementation. Before a store release,
the operator must publish it with the applicable service privacy policy and
support contact. The configured Pomodoist service governs server-side retention.

## Information used

The extension uses the account email, access/refresh tokens, account subscription
status, tasks, project names, labels, completion history and workflow assignments
to display and synchronize the same account used in other Pomodoist clients.
A random device identifier and operation identifiers support synchronization.

Choosing **Add current tab** immediately creates a task from the active page's
title and URL, including any query or fragment it contains, and synchronizes it
to the user's configured account. It does not read page content or query browsing
history.

Passwords are sent to the configured authentication endpoint for sign-in and
are not persisted. OAuth is handled by the selected identity provider. When
the server requires CAPTCHA, verification runs on the hosted Pomodoist web app
using its configured Cloudflare Turnstile integration, not inside the extension.

## Storage and network access

Account tokens, a task cache and unsynced operations are kept in local Chrome
extension storage, restricted to trusted extension contexts. They are not put in
Chrome's cross-device `storage.sync`. The extension does not add its own encryption
on top of browser/operating-system protection. Network synchronization uses the
configured backend over HTTPS; HTTP is accepted only for loopback development.
After explicit website protection/discovery opt-in, the extension observes only
HTTP/HTTPS top-level hostnames, storing up to 500 locally. It does not inventory
paths, queries, fragments, page content, window titles or executable paths.
Child-frame guards pause media using the parent tab's protection decision and do
not add child hostnames to discovery. Explicitly saved domain assignments,
profiles and shared Focus state sync to the configured account. The existing
**Add current tab** action remains a separate, explicit full-URL task action.

An additional Pro opt-in sends newly discovered public domain identities to the
configured Pomodoist AI endpoint for web-search classification. Private, internal,
loopback and IP identities are excluded. The server uses its configured search/AI
provider and quota, returning category/source links. Known manual categories are
preserved; unclassified resources remain eligible. Failed or uncertain automatic
classifications are throttled locally. Cached results do not use the shared AI
quota; new classifications and task analysis do. Quota usage/reset comes from the
server. There are no extension analytics or advertising.

Protection snapshots/rules and an optional independent loopback pairing token
are kept in trusted local extension storage. Pairing reaches only numeric ports
on 127.0.0.1 and pins the desktop account/environment. It never transmits account
credentials to loopback. Website scripts receive only protection leases; private
task text is rendered in a separate extension document, never in the host page's
DOM. No browsing paths or media content are sent for blocking.

## User control

Strict Focus applies its chosen exit policy before detaching this browser. A
separately confirmed emergency release is local only. Protection leases expire
without contacting the service. Release preserves the page and never resumes
media automatically. Incognito protection/discovery requires Chrome’s separate
incognito permission; its status is shown in the popup.

Sign-out clears local credentials, pairing tokens, discovered domains, protection
snapshots/rules, cached account data and, after explicit
confirmation, unsynced changes. It requests revocation of this session only.
It does not delete already-synchronized tasks from the shared service. Rebuilding
for another backend resets the local account data, so synchronize first.
Server-side deletion and account management remain available in the full app.
Removing the extension removes its local extension storage.

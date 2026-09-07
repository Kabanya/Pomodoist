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
The extension contains no analytics, advertising or background browsing-history
collection code and does not send task data to an additional extension service.

## User control

Sign-out clears local credentials, cached account data and, after explicit
confirmation, unsynced changes. It requests revocation of this session only.
It does not delete already-synchronized tasks from the shared service. Rebuilding
for another backend resets the local account data, so synchronize first.
Server-side deletion and account management remain available in the full app.
Removing the extension removes its local extension storage.

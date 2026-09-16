# Pomodoist collaboration

The authenticated POST API is implemented by `index.ts` and the private SQL dispatcher in the additive `pomodoist_core_collaboration` migration. Shared storage is canonical per scope; direct client table/Storage policies are intentionally absent. The public RPC is an invoker wrapper around the private dispatcher, which checks live Auth user/session records before every private action. `publicRead` is the sole anonymous action and returns a whitelist projection.

## Runtime configuration

Provide `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `POMODOIST_WEB_URL`, `SMTP_HOST`, `SMTP_PORT`, `SMTP_ADMIN_EMAIL`, `SMTP_USER`, and `SMTP_PASS` to the Edge runtime. SMTP uses TLS on port 465 or mandatory STARTTLS on other ports. SMTP credentials never reach SQL or the response. Invitation delivery returns `emailDelivery: sent | failed | not_requested`; a failed delivery preserves the invitation so its link can still be copied. Only invitations generate email. Notification email for other events and background push are follow-ups.

Configure this function with `verify_jwt = false` in the deployment configuration to allow anonymous public reads. All other actions are authenticated in the handler and independently checked against current membership and an unrevoked Auth session in SQL. This repository change does not deploy the function or configure any live service.

## API

POST `{action, ...arguments}`. Failures return `{error, code}`. IDs are strings. Scope responses contain `id`, `rootProjectId`, `ownerId`, `role`, `revision`, `historyUnlimited`, and `graceEndsAt`. Members contain `userId`, `role`, and `displayName`; email addresses are never included in a member directory.

- `state`: `{userId, scopes, invitations, notifications, preferences, personalHistory, personalRevision}`. `personalRevision` is the maximum revision of the caller's personal stream, which is what `share` compares against.
- `share(rootProjectId, expectedRevision)`: `{scope}`. `expectedRevision` must be the `personalRevision` reported by `state` after successful personal sync. Send `state` first; a client-side sync cursor is not this value. A mismatch is rejected with code `22023` (HTTP 400), a client error rather than a retryable one, so re-read `state` instead of replaying the request. The operation preserves project/task/section IDs, copies referenced labels to `scopeId:oldLabelId`, rewrites label links, saves the owner's private placement/preferences, and tombstones transferred personal content atomically. Personal completed focus records remain personal and produce shared contribution records.
- `pull(scopeId, sinceRevision)` and `export(scopeId, sinceRevision)`: `{changes, nextCursor, hasMore, members, scope, preferences}`. Pages contain at most 500 records; export consumers continue until `hasMore` is false and use `download` for attachment bytes.
- `push(scopeId, operations)`: `{applied, conflicts, rejected}`. Each operation is `{opId,entityType,entityId,operation,payload,baseRevision,clientUpdatedAt}`. Types are project, section, task, label, task_label, task_kanban_status, task_completion, comment and focus_interval. Activity/attachments are server-authored. Operations are upsert, delete, or task-only assign `{add,remove}`. Applied entries include the pull change shape plus opId. Conflicts contain `fields`, `current`, `data`, and `serverRevision`. Resolve a conflict with a new operation ID and refreshed base revision. Receipts reject operation ID reuse with changed content.
- `preferences(scopeId,entityType,entityId,data)`: `{preferences}` for the caller only, including observers. Allowed data keys are isFavorite, isCollapsed, dayOrder, reminders, viewStyle, viewPreferences and rootParentId. Writes merge fields; rootParentId belongs to the scope preference (`entityType=scope`, `entityId=scopeId`) and must name the caller's personal project or null. Pull/state include only the caller's preferences.
- `invite(scopeId,email?,role?)`: email invitation or reusable join link with member/observer role, `{id,token,email,role,expiresAt,url,emailDelivery}`. `invite(scopeId,invitationId,revoke:true)` revokes an invitation/link. Tokens expire in seven days. `accept(token)` requires explicit acceptance; email invitations additionally require a verified matching account. `members(scopeId)` includes an invitations list only for administrators.
- `role(scopeId,userId,role)`, `remove(scopeId,userId)`, `leave(scopeId)`, `transfer(scopeId,userId)`, and `delete(scopeId)` implement the protected-owner lifecycle. The owner cannot leave or delete their Auth account before transfer/deletion.
- `publicLink(scopeId,enabled)`: `{token,url}`. Enabling rotates the token, disabling revokes it. URLs use `/shared/public/<token>`. `publicRead(token)` returns `{scope,projects,tasks,comments}` without member directory, emails, author IDs, files or focus statistics. Responses carry `X-Robots-Tag: noindex, nofollow` and `Cache-Control: no-store`.
- `notifications`: `{notifications}`. `readNotification(notificationId)` marks the caller's notification as read. Lists are limited to the latest 200 entries.
- `reserveUpload(scopeId,taskId,name,contentType,bytes,uploadId)`: `{uploadId,path,signedUrl,token,expiresAt,finished}`. PUT the file to signedUrl using contentType; upload IDs are UUIDs and retries must preserve their metadata. A finalized replay does not issue another upload capability.
- `finishUpload(scopeId,uploadId)`: `{attachment}`. SQL checks actual Storage metadata, uploader identity, current Pro/editor access, and completion-month/year budgets. Successful completion is idempotent.
- `download(scopeId,attachmentId)`: `{url,name,attachmentId}`. The URL expires in 60 seconds. Current members, including observers and members whose Pro expired, can download.
- `deleteAttachment(scopeId,attachmentId)`: logical deletion, original-year quota release and a durable Storage deletion request. Monthly uploaded bytes are never refunded.

Comments use `{taskId,body,mentions:[userId]}`. Completed focus contributions accept a FocusIntervalRow or `{taskId,durationSeconds,startedAt,completedAt}`; the actor is always authenticated, dates support ISO and milliseconds, and only completed work intervals count. Personal focus totals must continue to count only the caller's work. Recurrence successors carry `recurrenceSourceId` and `occurrenceKey`; the server serializes the scope and permits one successor ID per source. Clients retain their existing recurrence calculation and deterministic IDs.

## Retention and files

The existing daily history maintenance call now applies 365 days for free completed/deleted tasks and unlimited history for active paid subscription/lifetime. Shared history considers every accepted member, including observers. Losing the last paid member starts a non-extending 30-day grace period. Entitlement changes and membership deletion refresh that state; natural entitlement expiry is detected by state/pull/maintenance. Open tasks do not age out. Shared purging retains empty tombstones, removes associated content/receipts, and queues file deletion.

Upload quotas use decimal units: 20,000,000 bytes/file, 1,000,000,000 successful uploaded bytes per UTC month, and 5,000,000,000 stored bytes per uploading user per completion UTC year. Pending reservations participate in quota admission. Finalization rechecks the actual completion period. Deleting a file releases only its original completion year's stored bytes. Files uploaded in other years do not consume the current year's stored quota.

The SQL deletion queue is drained best-effort after authenticated state/finalization/deletion calls. Deployments that require physical cleanup while there are no client requests should schedule an authenticated service worker to drain this existing queue. Do not delete `storage.objects` rows directly. Already issued download URLs can remain usable for their remaining 60-second lifetime after access removal; new signing requests require current membership.

## Unit verification

Run from the repository root:

```sh
deno test --no-check server/supabase/functions/_shared/pomodoist_collaboration_test.ts
```

Tests use only in-process doubles for Auth, RPC, Storage and SMTP. They verify request contracts, authentication/signing order, body bounds, public redaction, invitation delivery failures, TLS-before-auth and private preference dispatch. They do not execute SQL, RLS, actual storage/email requests, deployment, builds or static analysis. SQL transaction/concurrency/privilege behavior remains unvalidated on a database by the explicit validation boundary.

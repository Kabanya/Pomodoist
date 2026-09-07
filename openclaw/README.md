# Pomodoist for OpenClaw

Connect OpenClaw to the existing Pomodoist account using native Streamable HTTP
MCP and browser OAuth. There is no separate task database, account-password
prompt, service key, hosted endpoint default, or dependency on an unofficial
OpenClaw plugin. Requires an OpenClaw build with `openclaw mcp set/login/doctor`
and a Pomodoist server with the OpenClaw migration and updated MCP function.

## Connect

Use the exact MCP resource URL supplied by your Pomodoist server operator
(`POMODOIST_MCP_RESOURCE_URL`), normally ending in
`/functions/v1/pomodoist-mcp`. The script requires Node.js 22 or newer. HTTPS is
required except for exact local loopback development hosts.

```sh
# Preview only: prints an OpenClaw config fragment and changes nothing.
node openclaw/configure.mjs "$POMODOIST_MCP_RESOURCE_URL"

# Save the named pomodoist server, sign in in the browser, and verify it.
node openclaw/configure.mjs "$POMODOIST_MCP_RESOURCE_URL" --apply

# Explicitly enable guarded task/project/label writes and Focus controls.
node openclaw/configure.mjs "$POMODOIST_MCP_RESOURCE_URL" --write --apply
```

`--apply` replaces only `mcp.servers.pomodoist`; review an existing entry before
using it, especially when changing accounts or servers. Sign out first when
switching servers. Other configured servers are not changed. OAuth access and
refresh tokens remain in OpenClaw's native credential store, not in this script,
repository, skill, or generated config. Sign in and approve access only on the
trusted Pomodoist consent page. Never paste a password, service-role key, access
token, or refresh token into a conversation.

Install the skill on the machine running OpenClaw:

```sh
mkdir -p "$HOME/.openclaw/skills"
cp -R openclaw/skills/pomodoist "$HOME/.openclaw/skills/"
openclaw mcp doctor pomodoist --probe
```

Restart the running OpenClaw gateway/agent through its usual restart mechanism.
`openclaw mcp reload` alone only resets the invoking CLI process, not another
running gateway. A minimal tool profile or a policy denying `bundle-mcp` can hide
MCP tools; use an appropriate tool profile without disabling other safety rules.

## Permissions and disconnect

The default setup filters out all mutation tools. `--write` includes explicit
`openclaw_*` mutations, not legacy mutation names or wildcard tool patterns.
**This is local OpenClaw tool policy, not a server-enforced read-only OAuth scope.**
Pomodoist currently grants account-level MCP access. Anyone holding that OAuth
credential could invoke other permitted MCP tools outside this local filter.
Use a trusted OpenClaw deployment and keep its channel/agent access restricted.

To revoke server access, open Pomodoist Settings and revoke the corresponding
OAuth connection. The server checks the live OAuth session on every guarded
read/action, including receipt replays. Then clear local credentials/config:

```sh
openclaw mcp logout pomodoist
openclaw mcp unset pomodoist
```

Logout alone clears local credentials; it does **not** revoke Pomodoist consent.
Removing the local server definition or skill alone is also not revocation.

## Supported actions

| Area | Tools / behavior |
| --- | --- |
| Lists | `list_tasks`: Inbox, Today, Upcoming, date, project, search, all, completed; explicit IANA time zone for date-sensitive views and cursor pagination. |
| Tasks | Guarded create, update, complete, restore, delete; project, priority, labels, description, parent, focus estimate and schedule/recurrence use the existing MCP schemas. |
| Scheduling | `openclaw_update_task` with `arguments.schedule`; date-only and timed schedules remain distinct. Timed schedules require start, end and IANA time zone. |
| Deadlines | `openclaw_set_task_details` edits the separate `deadline_date` and `duration_seconds`; `null` clears either. `openclaw_get_task` reads both. A deadline does not reschedule a task. |
| Projects and labels | Guarded project create/update/delete and label create/delete, preserving existing MCP restrictions on system anchors. |
| Focus | `openclaw_get_focus`, then `openclaw_focus`: start a single 25-minute work session (optionally linked to a task), pause, resume, complete after its timer elapses, or stop with confirmation. Uses the shared Watch/Telegram Focus runtime, events and task totals. Custom session lengths/preset editing are not exposed in this version. |
| Reports | Existing Focus history, productivity and achievements read tools. |

Each guarded mutation has a UUID `request_id` and a nested `arguments` object:

```json
{
  "request_id": "c48f390d-e61e-4d7b-ac7f-07dcb9db0320",
  "arguments": {"content": "Review the proposal", "priority": 2}
}
```

This example is for `openclaw_create_task`; generate a fresh UUID for each new
intent, not the example UUID. Deletion tools additionally require top-level
`confirmed: true` after the user confirms the specific deletion. Focus controls
require the current `run_id` and `interval_id`; stopping additionally requires
`arguments.confirmed: true`. A delayed command must not control a newer run.

## Failures, retries, and synchronization

An action first obtains an account revision, plans using the shared runtime, and
then atomically checks the revision, pushes sync operations and saves its result.
The shared sync push path takes the same per-account advisory lock as the
calendar pipeline. If another device pushes while an action is being planned,
the action returns `conflict` without writing. Unrelated account changes can
conservatively cause a conflict too: reread instead of automatically overwriting.

After a timeout or lost response, retry with **the same request_id and identical
arguments**. A committed result is returned without replanning or creating a
second task/session. A different action or argument fingerprint under the same
ID is rejected. Do not create a new request ID merely to bypass an error. After a
confirmed conflict, reread current state and ask/decide whether a genuinely new
action is still appropriate. `forbidden` means reconnect or restore permission;
a failed/expired login must not be bypassed using direct database credentials.

Receipts are private, RLS-protected and service-RPC-only. They store mutation
metadata and a SHA-256 argument fingerprint, not OAuth credentials or task text.
They survive Edge restarts and are retained until account/client deletion, so
late retries cannot recreate a previously completed action. Sync hints are
best-effort after commit; normal client pulls recover a missed hint.

## Server rollout and tests

Apply `server/supabase/migrations/20260907021651_pomodoist_core_openclaw.sql`
through the existing hosted/self-hosted core migration procedure, **then** deploy
the updated `pomodoist-mcp` function (including its imported Watch/shared files).
No new endpoint, secret, or Supabase project is needed. The frozen initial
migration remains unchanged. Existing non-OpenClaw MCP tools remain available.
OAuth issuer, resource audience, dynamic client registration, allowed origins and
the existing Pomodoist consent UI must already be configured for the instance.

```sh
node --experimental-strip-types --test openclaw/*.test.mjs
# From the repository root, with the existing server dependencies available:
deno test --config server/supabase/deno.json --allow-env --allow-net --allow-read server/supabase/functions
make -C server test-db
```

The existing self-hosted CI discovers the Deno registration/runtime tests and
pgTAP fixtures for auth, isolation, replay, rollback and revision conflicts.
Run the setup/planner Node tests separately using the command above.
Live browser OAuth and cross-device smoke still need a deployed test instance:
connect, read Today/Upcoming, create/edit/schedule/complete a task, start/pause/
resume/stop Focus, repeat a request, revoke access and verify reads/writes fail.

Official integration contracts:
- [OpenClaw MCP tools](https://docs.openclaw.ai/tools/mcp)
- [OpenClaw MCP CLI and OAuth](https://docs.openclaw.ai/cli/mcp)

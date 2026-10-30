# Pomodoist for OpenClaw

Connect OpenClaw to the existing Pomodoist account using native Streamable HTTP
MCP and browser OAuth. There is no separate task database, account-password
prompt, service key, hosted endpoint default, or dependency on an unofficial
OpenClaw plugin. Requires OpenClaw 2026.9.3 or newer with native
`openclaw mcp set/login/doctor`, Node.js 24.16+ on the 24.x line or 26.1+,
and a Pomodoist server with the OpenClaw schema and updated MCP function.

The distributable skill is `tool/openclaw/skills/pomodoist/`. The parent folders
organize this repository; installation still uses the `pomodoist` skill directory
with `SKILL.md`, `LICENSE`, and `scripts/configure.mjs`. It runs independently
of this repository, without installing JavaScript dependencies. The skill is
MIT-0 licensed; the application and server remain AGPL-3.0-only. See
[release preparation](RELEASE.md) for the licensing boundary, publication status,
and the remaining release gates.

## Connect

Pomodoist Cloud uses `https://mcp.pomodoist.com/functions/v1/pomodoist-mcp`.
For self-hosting, use the exact resource URL supplied by your server operator,
normally ending in `/functions/v1/pomodoist-mcp`. HTTPS is required except for
exact local loopback development hosts. Use your account on the selected server;
hosted service access follows the account's Pomodoist plan.

Use HTTPS for deployed instances. Native loopback OAuth and probing passed with
OpenClaw 2026.9.4 in the isolated review stack. Other versions or operator network
policies may reject a target; do not disable network guards to complete setup.

From the repository root, set the endpoint and preview before applying:

```sh
POMODOIST_MCP_RESOURCE_URL=https://mcp.pomodoist.com/functions/v1/pomodoist-mcp

# Preview only: prints an OpenClaw config fragment and changes nothing.
node tool/openclaw/configure.mjs "$POMODOIST_MCP_RESOURCE_URL"

# Save the named pomodoist server, sign in in the browser, and verify it.
node tool/openclaw/configure.mjs "$POMODOIST_MCP_RESOURCE_URL" --apply

# Explicitly enable guarded task/habit/project/label writes and Focus controls.
node tool/openclaw/configure.mjs "$POMODOIST_MCP_RESOURCE_URL" --write --apply
```

The setup checks CLI compatibility and saved configuration before making changes.
It refuses to overwrite a different server named `pomodoist`. An existing entry
for the same endpoint can be updated to enable writes. Other servers are not
changed. OAuth access and
refresh tokens remain in OpenClaw's native credential store, not in this script,
repository, skill, or generated config. Sign in and approve access only on the
trusted Pomodoist consent page. Never paste a password, service-role key, access
token, or refresh token into a conversation.

Install the skill on the machine running OpenClaw. Until version 1.0.0 is
published on ClawHub, copy the directory instead:

```sh
mkdir -p "$HOME/.openclaw/skills"
cp -R tool/openclaw/skills/pomodoist "$HOME/.openclaw/skills/"
openclaw mcp doctor pomodoist --probe
```

Once published, install it from the registry:

```sh
clawhub install pomodoist --version 1.0.0 --workdir .
```

For a skill installed from ClawHub or copied without a repository checkout, run
the bundled script from the installed `pomodoist` directory:

```sh
node scripts/configure.mjs https://mcp.pomodoist.com/functions/v1/pomodoist-mcp
node scripts/configure.mjs https://mcp.pomodoist.com/functions/v1/pomodoist-mcp --apply
```

Add `--write` only when enabling changes and Focus controls deliberately.

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
openclaw mcp configure pomodoist --disable
```

Optionally remove the disabled definition with `openclaw mcp unset pomodoist`.
Some OpenClaw versions reject removal with a `size-drop` configuration guard;
leave the connection disabled rather than bypassing that guard. Removal must
succeed before this setup can switch to a different endpoint.

Logout alone clears local credentials; it does **not** revoke Pomodoist consent.
Removing the local server definition or skill alone is also not revocation.

## Supported actions

| Area | Tools / behavior |
| --- | --- |
| Lists | `list_tasks`: Inbox, Today, Upcoming, date, project, search, all, completed; explicit IANA time zone for date-sensitive views and cursor pagination. |
| Tasks | Guarded create, update, complete, restore, delete; project, priority, labels, description, parent, focus estimate and schedule/recurrence use the existing MCP schemas. |
| Scheduling | `openclaw_update_task` with `arguments.schedule`; date-only and timed schedules remain distinct. Timed schedules require start, end and IANA time zone. |
| Deadlines | `openclaw_set_task_details` edits the separate `deadline_date` and `duration_seconds`; `null` clears either. `openclaw_get_task` reads both. A deadline does not reschedule a task. |
| Habits | `list_habits` / `get_habit`; guarded create, update, add/undo check-in, complete a daily goal, finish/reopen a schedule and delete. Explicit `time_zone`, historical dates, per-period goals including night. |
| Projects and labels | Guarded project create/update/delete and label create/delete, preserving existing MCP restrictions on system anchors. |
| Focus | `openclaw_get_focus`, then `openclaw_focus`: start a single 25-minute work session (optionally linked to a task), pause, resume, complete after its timer elapses, or stop with confirmation. Uses the shared Watch/Telegram Focus runtime, events and task totals. Custom session lengths/preset editing are not exposed in this version. |
| Reports | Existing Focus history, productivity and achievements read tools. |
| Device settings | `openclaw_list_app_devices`, fresh `openclaw_get_app_settings`, `openclaw_set_app_shortcut`, `openclaw_set_app_appearance`, and `openclaw_get_app_settings_request`. Changes require `--write`, a selected online device, UUID, and the affected group’s `expected_version`. |

Habits use `period_targets` for independent morning, afternoon, evening and night
goals; their sum is the daily target. For example, `{"morning":2,"night":5}`
means seven repetitions. A single check-in on a multi-period habit requires the
chosen `period`. `complete_habit` fills missing check-ins; `finish_habit` ends the
schedule on an inclusive `end_date`, defaulting to today. Past dates remain
correctable and future dates are read-only. Night always belongs to the selected
calendar date. One reminder time does not create one notification per repetition.

Each task, habit, project or Focus guarded mutation has a UUID `request_id` and a nested `arguments` object:

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

Device settings use their own short-lived receipt gateway. Their arguments are
at the top level: `request_id`, `device_id`, `expected_version`, `value`, and
`setting` for appearance. Device listing includes registered devices with explicit `online` availability.
A fresh read returns group versions and capabilities;
shortcuts share one version. Internal bindings use `physicalKeyId`, global Quick
Add uses native `keyCode`, and `binding: null` resets. A pending response returns
a UUID for status polling. Only `status: applied` confirms a change. An expired
request was not claimed; claimed execution has a fixed 120-second deadline; an uncertain request may have applied and needs a fresh
read before any new intent. Never blindly replay uncertain work. Settings receipts
are limited to 24 hours and 100 per device, including short-lived image source
URLs cleared when requests finish or expire. Image bytes and paths never cross
the gateway. Settings stay local to the selected runtime and are never queued for
an offline device or replayed after restart.

## Server rollout and tests

The current self-hosted baseline includes the OpenClaw schema; existing instances
receive it through the supported upgrade procedure. For hosted releases, verify
that the historical OpenClaw migration is already applied before deploying the
updated `pomodoist-mcp` function (including its imported Watch/shared files).
Do not replay files from `server/supabase/legacy` on an initialized database.
Habit tools additionally require
`server/supabase/migrations/20261003140901_pomodoist_habit_day_period.sql` before
rolling out the updated function/client. All new habit server changes are in
that single migration. Existing saved OpenClaw filters must be deliberately
reapplied with `--write` to expose the new guarded habit actions.
No new endpoint, secret, or Supabase project is needed. Existing non-OpenClaw MCP
tools remain available.
OAuth issuer, resource audience, dynamic client registration, allowed origins and
the existing Pomodoist consent UI must already be configured for the instance.

```sh
node --experimental-strip-types --test tool/openclaw/*.test.mjs
# From the repository root, with the existing server dependencies available:
deno test --config server/supabase/deno.json --allow-env --allow-net --allow-read server/supabase/functions
make -C server test-db
```

The self-hosted CI runs the Node setup/planner tests, including installation
from a standalone copy, plus Deno registration/runtime tests, pgTAP fixtures for
auth, isolation, replay, rollback and revision conflicts, and the HTTP acceptance
test against a fresh local instance:

```sh
make -C server test-openclaw
```

That test requires the local stack and its generated private `server/.env`. It
refuses remote URLs and uses only synthetic accounts for OAuth/PKCE, tasks, Focus
actions, two-client synchronization, refresh and revocation. It does not prove
that a real production account has signed in.

`make -C server test-openclaw-native` exercises the bundled setup through the real
OpenClaw CLI with isolated configuration and credentials. It passed with OpenClaw
2026.9.4 after correcting the setup-script path. See
[release preparation](RELEASE.md#native-cli-acceptance) for the exact local scope;
production OAuth and clean ClawHub installation still need release verification.

## Publish on ClawHub

Choose **Skill**, not Plugin. The publication unit is only
`tool/openclaw/skills/pomodoist/`, not this entire repository or `tool/openclaw/`.
ClawHub distributes skills under MIT-0 and does not sell skills; the paid part of
Pomodoist is the hosted service, which must be disclosed next to the install
instructions. That split is recorded in [RELEASE.md](RELEASE.md) and `LICENSING.md`.

- **Import from GitHub:** after these files are pushed to the public repository,
  select `Kabanya/Pomodoist` and `tool/openclaw/skills/pomodoist/SKILL.md`.
- **Upload files:** upload the package's three files, preserving the `scripts/`
  directory. Review the publisher, version, requirements, and file preview.

A GitHub import of `tool/openclaw/skills/pomodoist/SKILL.md` only picks up the
files in that directory; keep the bundled script committed and pushed first.

Alternatively, from the repository root, preview publication with the ClawHub CLI:

```sh
clawhub login
clawhub skill publish "$PWD/tool/openclaw/skills/pomodoist" --slug pomodoist --name Pomodoist --version 1.0.0 --dry-run --json
```

Remove `--dry-run --json` only when intentionally publishing. A successful dry
run is not publication or registry approval. After processing, inspect the public
listing and verify a clean installation using the exact identifier shown there.
Do not advertise an installation command until it succeeds.

Before announcing availability, verify the deployed OAuth/task/Focus/revocation
flow and ensure the consent screen and public documentation accurately describe
Focus access. The authorization screen must state that connecting an agent grants
account-level MCP access, including starting, pausing and stopping the active
Focus session when writes are enabled. Local setup tests do not prove production
sign-in or device sync. See [release preparation](RELEASE.md) for the remaining
gates.

Official integration contracts:
- [OpenClaw MCP tools](https://docs.openclaw.ai/tools/mcp)
- [OpenClaw MCP CLI and OAuth](https://docs.openclaw.ai/cli/mcp)

Device settings require
`server/supabase/migrations/20261029081042_pomodoist_core_app_settings.sql`
before deploying the updated function and client. Apply existing saved tool
filters deliberately to expose the settings tools.

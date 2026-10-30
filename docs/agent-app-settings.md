# Agent control of local app settings

Connected MCP agents can read and change shortcuts and appearance on an explicitly
selected, signed-in, online Pomodoist device. Commands use the existing OAuth
connection and do not prompt for every change. Revoking the connection stops new
commands and commands that have not yet been claimed. A change already executing
on a device may finish; revocation cannot undo a local side effect.

## Tools and workflow

1. Call `list_app_devices` and select an online device ID. The list includes
   retained offline devices with `online: false`; capabilities describe each
   platform's supported settings and key formats.
2. Call `get_app_settings(device_id)`. The response contains current values and a
   version for each group. If the response is pending, poll its request ID.
3. Call `set_app_shortcut` or `set_app_appearance` with `device_id`, a new UUID
   `request_id`, and that group's `expected_version`.
4. Poll `get_app_settings_request(request_id)` until the device reports a result.
   A queued or claimed request is not a successful settings change.

Retry a timed-out call with the same request ID and identical arguments. A new
intent needs a new UUID. `expired` means the device did not claim the request.
`uncertain` means the device may have changed: read fresh settings before deciding
what to do. Do not blindly replay a write with a new UUID.

The OpenClaw configuration includes settings reads in its read-only allowlist and
settings writes only in its explicit write configuration. Existing saved
allowlists must be regenerated to expose newly added tools.

## Settings

`set_app_shortcut` accepts `value: {command, binding, enabled?}` and uses the
`shortcuts` version. `command` is an advertised app command or `globalQuickAdd`.
A null binding restores that command's default. App bindings use
`physicalKeyId`, `keyLabel`, and `meta/control/alt/shift` flags. Global Quick Add
uses its existing platform-native `keyCode` instead; it is not a USB HID code.
Read the current native binding before changing it. Global bindings are available
only on supported native desktop platforms. Conflicts and reserved zoom bindings
return an error without silently displacing another action.

`set_app_appearance` accepts one `setting` and its typed `value`:

| Setting | Value |
| --- | --- |
| `themeMode` | `system`, `light`, `dark` |
| `theme` | `classic`, `ocean`, `forest`, `sepia`, `graphite`, `custom` |
| `customTheme` | Partial `light`/`dark` HEX role maps and/or background settings |
| `icon` | An advertised existing app icon ID |
| `statusItemStyle` | `classic`, `modern` (native macOS) |
| `bottomNavigation` | `{style, destinations}` using advertised enum values |
| `taskDetailLayout`, `taskListStyle`, `taskBranchStyle`, `taskRowSpacing`, `taskTimeDisplayMode` | Existing advertised enum value |
| `zoom` | Native interface scale percentage, 50–200 |
| `focusTimerStyle`, `focusViewMode` | Existing timer shape or detail level |

Custom theme writes preserve unspecified colors/backgrounds and the immutable
built-in themes. Existing theme editor drafts return `busy`. Successful writes
return the actual value and its new version. A stale version returns `version_conflict`,
including when the user changed that setting manually after the agent read it.
Unsupported settings fail; no tool exposes arbitrary preference keys or code.

## Local images

A `customTheme` value can include `image_url`, `image_palette` (`light` or `dark`)
and `image_zone` (`main`, `sidebar`, `quickAdd`). The selected app downloads the
image itself. It imports through the normal image preparation path: maximum
source size 50 MiB, first-frame PNG normalization with maximum dimension 2560 px.
Only the prepared file and its opaque identifier are stored locally (native app
support files or browser IndexedDB). Source URLs are not saved as backgrounds.

The downloader sends no account credentials, limits the response stream and total
download time, and accepts only public HTTPS destinations on the default port.
Native downloads validate DNS answers and connect to the validated address; every
redirect is checked again. Browsers require CORS and reject redirects because
redirect targets cannot be checked safely. Browser DNS/address-space enforcement
is controlled by the browser; a public address-space fetch is requested.
Download or decoding errors preserve the previous background.

Image bytes, base64 data, filesystem paths and persistent remote image URLs are
never uploaded through settings RPCs or stored in database/Storage. Database
records contain bounded command metadata and results only; source URLs are cleared
when a request finishes or expires.

## Delivery, failures and compatibility

Notifications use the existing private
[Realtime Broadcast](https://supabase.com/docs/guides/realtime/broadcast) channel
with app/device/request identifiers only. The authenticated RPC supplies commands
and results; periodic polling repairs missed notifications.

One main app instance holds a renewable device lease. Another browser tab cannot
steal a live lease; the separate Quick Add window never claims commands. A device
that has stopped unexpectedly can remain listed until its lease expires. Commands
must be claimed within 15 seconds and target that exact app instance. Closed,
restarted and disconnected instances do not replay old commands on startup.

The runtime records execution locally before side effects and retries only the
acknowledgment after a lost response. After a crash it reconciles interrupted
execution with current settings while preserving the uncertain outcome. A saved
receipt is retained server-side for at most 24 hours, with at most 100 requests per
device. Terminal records are pruned on authenticated access.

Apply the additive backend migration/functions before shipping clients that
advertise these capabilities. Old clients do not register and retain their current
settings behavior. Existing photos and local preference formats are preserved.
No photo synchronization, custom UI code, new fonts or arbitrary layout editing
is introduced.

## Validation

Run MCP Deno tests, the app-settings SQL lifecycle/authorization tests, and the
Flutter adapter/runtime/image tests together with existing affected controller
suites. Run Flutter analysis and hot reload/restart. Platform fake tests do not
replace checking a real native shortcut/icon or a browser CORS import. Before
release, verify an agent changes a shortcut, palette and photo on one device,
leaves another device unchanged and retains settings after restart.

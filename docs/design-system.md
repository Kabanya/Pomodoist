# Pomodoist design system

Rules for changes to the Flutter interface. This is an ongoing guide, not a
record of visual verification. When shared rules change, update this document
alongside the theme and components.

## Direction

Neutral surfaces, expressive typography, subtle borders, and calm motion.
References: the Pomodoist landing page, Notion, and Todoist. Quality comes from
consistent details, rather than larger elements or more effects.

- Prioritize desktop and web; narrow screens and touch remain fully supported.
- Develop light and dark themes together.
- Preserve density, approximate text and control sizes,
  keyboard shortcuts, selection, resizing, and drag-and-drop.
- Style empty, loading, and error states consistently with populated screens.
- Expressive recognition of an achievement is welcome: Focus completion should
  feel rewarding while retaining the app's palette and character.

## Sources in code

| Purpose | Source |
|---|---|
| Palette, typography, Material and Shadcn themes | [app_theme.dart](../lib/app/theme/app_theme.dart) |
| Built-in themes, local copies, selection and live preview | [app_theme_settings.dart](../lib/app/theme/app_theme_settings.dart) |
| Shared durations, curve, and Reduce Motion | [app_motion.dart](../lib/app/theme/app_motion.dart) |
| Main application integration | [app.dart](../lib/app/app.dart) |
| Separate Quick Add window integration | [global_quick_add_window.dart](../lib/app/global_quick_add_window.dart) |
| Task row events and effects | [task_motion.dart](../lib/features/tasks/presentation/widgets/task_motion.dart) |
| Voice panel motion | [voice_panel_motion.dart](../lib/features/tasks/presentation/widgets/voice_panel_motion.dart) |
| Focus completion | [focus_completion_celebration.dart](../lib/features/focus/presentation/focus_completion_celebration.dart) |

`AppThemePalette` is the single source of colors. In widgets, use
`context.appColors`, `Theme.of(context).textTheme`, and `AppTheme.monoTextStyle`.
Make shared changes in the theme instead of copying new values across screens.
`AppTheme.shadFromMaterial` keeps Shadcn aligned with the current Material theme,
including during theme transitions.

## Color, typography, and geometry

| Role | Light theme | Dark theme |
|---|---|---|
| Background `canvas` | `#FAFAFA` | `#0A0A0A` |
| Surface `surface` | `#FFFFFF` | `#141414` |
| Secondary surface `surfaceTint` | `#F5F5F5` | `#1C1C1C` |
| Hover `surfaceHover` | `#EEEEEE` | `#242424` |
| Primary text `primaryText` | `#171717` | `#FAFAFA` |
| Secondary text `secondaryText` | `#737373` | `#A3A3A3` |
| Decorative border `border` | `#E5E5E5` | `#292929` |
| Accent `accent` | `#D83B2E` | `#FF6B5E` |
| Primary button fill `accentFill` | `#D83B2E` | `#D83B2E` |
| Soft accent fill `accentTint` | `#FDECEA` | `#301B19` |

- The selected accent highlights the primary action and active states. Semantic colors for
  projects, priorities, and task timing retain their meaning; resolve task time
  status colors through `AppThemePalette.taskTimeColor`. Errors and overdue task
  colors have dedicated roles and do not follow an accent change. P1 priority
  indicators share the urgent `overdue` color, retaining their red meaning in
  the built-in blue and green themes.
- Use Geist for the interface and GeistMono with tabular figures for timers and
  numeric metrics. Both fonts are bundled locally in `shadcn_ui`.
- Use the existing `textTheme` roles instead of a separate size scale for each
  screen. Build hierarchy through weight, color, and spacing.
- Use Lucide icons exported by `shadcn_ui` for the shared interface. Preserve
  action meanings, icon sizes, and accessible labels.
- Corner radii: controls **8 px**, cards **10 px**, dialogs **12 px**. Circular
  timers, indicators, and decorative marks may retain their own shapes.
- Align spacing to a **4 px** grid while preserving the current density.
- Keep main screens flat. Use shadows to separate floating surfaces.
  Decorative gradients, glow, and spring transitions are not the backdrop
  for everyday actions.

### Theme selection and editing

The table above describes **Classic**, the default palette. The selector always
contains **Classic, Ocean, Forest, Sepia, Graphite, Custom**, in that order, in one
compact horizontal row that scrolls on narrow layouts. Ocean uses cool blue
accents and surfaces; Forest uses green;
Sepia combines paper surfaces with brown and sand accents; Graphite uses neutral
surfaces with dark accents in light mode and light accents in dark mode. Graphite
uses dark text on its light button fill. Semantic status colors keep their meaning.
Each theme is a pair of light and dark palettes. Selecting a pair never changes
the separate System / Light / Dark preference or its shared web cookie.

The five built-in themes are immutable. Custom is the only editable slot, starts
from Classic, and keeps its fixed name and identifier. Editing resumes its saved
colors; there is no base selector, duplication, renaming or deletion. Reset to
Classic changes both draft palettes; Save commits the reset and Cancel discards
it. `AppThemeSettingsController` persists the selected identifier and single
custom pair together in SharedPreferences. The shared desktop provider scope
keeps Quick Add and the main window aligned.

Local settings use format version 2. The active custom pair from version 1 becomes
Custom; otherwise Custom starts from Classic and the selected built-in theme is
preserved. Before the first version 2 write, the controller stores the original
version 1 JSON, including inactive copies, under `app.themeSettings.v1Backup`.
A failed backup blocks the new write and keeps the draft available for retry.

All 18 palette roles are editable as opaque RGB / HEX colors, including `error`,
`overdue`, `onAccent` and `onError`. Use the foreground roles on filled controls
instead of fixed white. Derived Material and Shadcn colors remain centralized in
`AppTheme`; project colors remain project data.

Editor changes preview immediately in both app roots but remain in memory until
Save. Cancel, Escape and Back discard the preview and restore the prior selection.
The light/dark switch selects the palette to edit without changing application
brightness. Colors and Backgrounds tabs share one draft. Invalid HEX input in
either palette blocks saving. Saving errors keep the draft
open for retry. The editor itself uses Classic so even an unreadable custom
palette can be repaired; its two previews show the actual custom colors.

Custom has one global background type: color, photo or `macosGlass`. Switching
types retains imported photos. Glass has independent light and dark tint amounts
from 0–100%, defaulting to 40% and 50% respectively. It uses the same theme
provider, live preview, Save and Cancel flow, and optional version 2 persistence.
Older settings infer photo when any photo is present and color otherwise. Reset
to Classic clears every background type's settings in the draft; unreferenced
photos are removed only after a successful save.

On macOS, place a native `NSVisualEffectView` behind Flutter with behind-window
blending and `underWindowBackground` material. The main area and sidebar share
one native glass layer; the separate Quick Add window has its own. Inline Quick Add
is unchanged; the in-app Quick Add overlay reveals and blurs the app beneath it.
Keep controls and the Classic editor solid. Background samples use a checkerboard,
while the real window remains live glass behind the editor.
Both app roots must also make `ShadAppBuilder.backgroundColor` transparent only
for active, acknowledged glass; its default opaque fill would cover the native
effect even when the page and window backgrounds are transparent.
In native macOS full screen, glass temporarily becomes the opaque Custom palette
(Classic by default); colors remain editable. Restore glass when that window
leaves full screen, without changing the saved theme, photos or dimming values.

Fall back to the palette's solid background on non-macOS platforms, before the
native view is ready, after native errors, and when Reduce Transparency is
enabled. Accessibility changes update live. Preserve the existing 180 ms theme
transition, Reduce Motion behavior and interface zoom.

### Photo backgrounds

Custom supports optional photos in three modes: main area only, one continuous
background across the entire app, or separate backgrounds for the main area,
sidebar and Quick Add. Each zone has independent light and dark settings, up to
six photos; an empty zone uses its solid palette color. Entire app reuses the
main photo for Quick Add. The sidebar includes the mobile drawer; Quick Add
includes its overlay and separate window, while the inline composer is unchanged.

Center photos with cover scaling and keep them pinned while content scrolls.
Dimming mixes in the zone's palette `canvas` or `surface` color from 0–100%,
defaulting to 40% in light mode and 50% in dark mode. Blur ranges from 0–20,
defaults to 0, and affects only the image. Cards, inputs, menus, dialogs and the
Classic theme editor remain solid, preserving readable controls and focus states.

Photo edits share the existing live preview, Save and Cancel behavior; Reset to
Classic clears photos and restores both palettes in the draft. Import and save
errors preserve the draft. Accept source files up to 50 MiB, normalize the first
frame to PNG with a maximum dimension of 2560 px, and store images locally in
native application support files or browser IndexedDB. Store only references and
photo settings in optional version 2 theme fields. Browser writes and cleanup hold
one Web Lock; preset selection reloads the latest saved Custom before writing.
Browsers without Web Locks retain old image files instead of risking another tab's
photos. Missing image references cannot overwrite a valid saved draft. Photos do
not synchronize or require new dependencies.

## Interface zoom

Native windows share a locally saved interface zoom of 70–150%, initially 100%.
Command + / − changes it by 10 percentage points and Command 0 resets it;
Windows and Linux use Control. Accept both Command = and Command Shift = for
zooming in, plus the numeric keypad equivalents. Reserve these shortcuts from
navigation bindings; Reports defaults to Command/Control Shift 0. Migrate older
conflicting bindings while keeping unrelated custom shortcuts and avoiding
duplicates. Shortcut recording consumes its keys without changing zoom.

Scale the entire content viewport, including Material and Shadcn overlays and
the separate Quick Add window. Keep the widget tree mounted so zoom retains
drafts, focus, routes and timer state. Adapt logical viewport size, density and
insets together; retain system text scaling and Reduce Motion. Context menus
convert pointer coordinates into their overlay's coordinate space. Zoom applies
immediately without an animation. On the web, browser zoom owns these keys and
its persistence; do not add a second app-level scale.

## Contextual navigation

Desktop task details retain the underlying list, selection and scroll position.
The selected task uses the background route's `task` query parameter; changing it
replaces the selection instead of stacking detail routes. Existing `/task/:id`
links remain valid. With at least 960 px of content width, details occupy a
440 px side panel; narrower layouts keep the background mounted behind details.
Below the 820 px shell breakpoint, details fill the viewport and temporarily
replace the shell top bar, bottom navigation and mini Focus player. Restore that
chrome on close, while keeping the detail controls inside the system safe area.
Navigation waits for pending title and description edits and retains failed
drafts. Close and Escape restore focus; nested menus handle Escape first.
Keep the close/back and overflow actions pinned at the top of task details,
inside the safe area, with task content scrolling below them.

### Sidebar

Group daily destinations separately from planning views, followed by the existing
project tree. Search and Add task stay near the profile. Browse, Reports and
Settings sit below projects; on short windows the footer scrolls with the list.
Preserve command identities and user shortcut bindings independently of visual
order. Shortcut hints display the actual configured binding.
Use `textTheme.titleMedium` for destination labels, Add task, and project names
and their header, matching task titles. Group captions, counts, and shortcut
hints keep their smaller text styles.

Project rows share their context menu between the sidebar and Projects screen.
Secondary click and touch long press expose renaming, icon and color selection,
favorites, and confirmed deletion. Project icons are synchronized project data;
existing projects retain the hash icon until changed.

### Today

Keep daily context to one text summary and one active Focus strip. The strip and
global mini player share the existing session, interval and clock providers.
Only replace the global player once the run and interval agree and remaining
time is available. Completed-today rows form a collapsed group with independent
selection, using the local completion day.

### Browse

Center Browse content within 1120 px. Keep the header, account settings link and
pending-change indicator compact. The productivity summary spans the content
width; projects sit beside labels and the completed-task link at 960 px or more
of available content width. Below that, stack sections. Separate sections with
spacing and subtle dividers instead of large cards or permanent creation fields.

Today is the initial period; the seven-day selection lasts only while the page
is open. Sum the existing `lastSevenDays` for completed tasks, completed focus
intervals and focus time. Open now always shows the current open-task count.
Use four metric columns, or two below 640 px, and keep labels readable. Retain
available data during refreshes and errors, showing loading and retry explicitly.

Show active projects in their existing tree order, excluding Inbox. Reuse their
colors, icons, creation dialog and context menu. Counts include only each
project's own open tasks, including subtasks, without rolling up child projects.
Keep the menu button visible for keyboard and touch access. Labels use compact
chips and the existing confirmed creation form. Completed tasks retain their
existing route and history policy.

The queue indicator describes local changes awaiting upload, not overall sync
health. Its details distinguish loading, failure and a known count; an empty
queue never confirms successful synchronization. Use the shared popup motion and
Reduce Motion. Only period changes transition the summary; data updates do not
replay its entrance.

### Overdue review

Below the Browse summary, show a compact overdue count and Review action only
when tasks are overdue. Loading and failure remain explicit and retain available
data. `/browse/overdue` shares the task list, styles, spacing, order and hierarchy;
include only overdue rows, without pulling in other subtasks. Start with no
selection, offer Select all, and omit Quick Add. Return to Browse with Back.

Use the same task data and app clock for the count and page. Open, non-deleted
all-day tasks become overdue at local midnight after their date; timed tasks at
`end <= now`, even during active Focus. Unscheduled tasks are excluded. Moving a
date preserves the existing time, duration and recurrence. Cancellation never
writes; bulk failures retain the failed selection and show an error. A still-past
schedule stays overdue, and finishing the review shows a quiet empty state.

### Quick Add

Parsed date/time, project and priority chips edit recognized spans in the source
phrase. Both `#` and `№` introduce project names, including quoted names, in
parsing, highlighting, and autocomplete. The phrase is the only metadata state:
clearing a token reveals the existing context defaults. Preview and creation use the same parser, configured
duration and clock. Preserve IME composition, selection and unrelated tokens.
Quoted metadata names remain literal during date normalization. Ready voice
subtasks preview the project inherited from their parent's current phrase.
Details stay below the editable input; the separate window scrolls when needed.
Voice draft titles start at one line and grow with their text up to three lines;
do not reserve blank lines for short tasks. Keep metadata and comments editable.

Voice gestures belong only to explicit `VoicePanelSwipeArea` surfaces. Swipe up
on the compact panel to expand and down on the editor header to collapse, using
touch or trackpad input. The task list, transcript, fields, and surrounding body
remain outside those areas: scrolling there must never collapse the panel,
including at either edge, during overscroll, or when the content fits without
scrolling. Do not hand off a content-scroll gesture to panel motion.
Keep capsule dragging on the microphone handle; buttons, text editing and
keyboard actions retain their normal behavior. Require 48 logical pixels of
vertical movement, ignore horizontal gestures and pinching, and allow one transition per
gesture (one wheel burst ends after 200 ms without events). Reuse the retained
voice editor and its 240 ms transition, including Reduce Motion; collapsing never
stops recording, transcription or analysis and never discards drafts.

### Date and time selection

Use `AppDateTimePicker` for date/time selection in Quick Add, task details and
Timeline. Keep its anchor mounted on the invoking chip or button. Its
`ShadPopover` belongs above that surface, including manually inserted Quick Add
and voice overlays; do not push a Navigator picker route underneath them.

Use the shared palette and typography for a compact calendar and editable clock
fields. Preserve locale-specific date input, first weekday, and 12/24-hour time
with the system override. ShadCalendar uses DateTime weekday numbering (1–7),
whereas Material uses 0 for Sunday. Use the exported ShadTimePicker fields so an
empty field invalidates the draft instead of retaining the previous time.

The Timed block action in task details opens only the start and end time pickers,
without a calendar step. Retain the task's scheduled date, or use the current
local day when it has no schedule. Date selection remains a separate action.

Keep selection local until confirmation. Cancel, Escape and Back dismiss the
picker without changing the source phrase or saved schedule; restore focus to
the invoking control. Preserve each caller's date limits and interval rules.
Use shared popup motion and Reduce Motion. Place pickers in the roomier visible
area above or below the invoking control, using overlay coordinates so zoom
stays correct. Exclude safe insets and the on-screen keyboard, cap the complete
panel size including decoration, and scroll content within that area. Recompute
placement after scrolling or resizing; when neither side can hold a control,
use the visible viewport with overlap rather than placing controls off-screen.

### Task row styles

Modern is the default shared task row layout; Classic preserves the previous
layout. The local `tasks.listStyle` preference changes only shared rows, including
search, planning lists and subtasks. Both styles share task actions, selection,
drag-and-drop and motion. Modern keeps desktop metadata and action slots aligned,
wraps metadata on narrow screens, and reveals actions on hover or keyboard focus.
In both styles, timing stays below the task title and its description when shown,
including in date-grouped lists. Keep its existing date/time format and status
color. In the shared column layout, project (120 px) and focus progress (56 px)
remain to the right of the title block, before row actions. Keep their order when
metadata wraps; the subtask indicator retains its position before these fields.
Touch actions stay available. Project and timing colors retain their semantics.
Custom Kanban and Timeline blocks keep their specialized layouts.
Kanban card action menus open on activation; pointer hover only highlights the
ellipsis button and must not open its menu (`ShadMenubar.selectOnHover: false`).

Task row spacing is independent of Modern / Classic. The local
`tasks.rowSpacing` preference selects Compact (4 px), Comfortable (10 px), or
Spacious (16 px) vertical padding on each side of a row. Comfortable is the
default for missing or unknown values. Changes apply immediately without a new
animation; a late preference load must not replace a local selection. A failed
save keeps the current session's selection and reports the error in Settings.
Font sizes, icons, metadata placement, and horizontal spacing stay unchanged.

All shared task lists use `TaskListDivider` between rows, including completed
groups, subtasks, and the priority matrix. The line is 1 px in `appColors.border`,
starts 38 px from the row's leading edge, and adds 18 px per level of the less
indented adjacent task. Do not add leading or trailing separators. Its total
height is 1 px on desktop/web and 12 px on native iOS/Android, with the line
centered to retain the existing touch drop area. Root-task drop targets keep
their existing expansion and Reduce Motion behavior. Kanban and Timeline do not
use this spacing preference.

### Touch task dragging

On native iOS/Android, long-press the shared row's text or metadata to drag using
`LongPressDraggable`. Do not show a separate grip or start dragging from the
checkbox or action buttons. Long-press no longer opens a competing context menu;
keep the ellipsis available in both row styles alongside existing buttons.
In selection mode, long-press toggles selection and dragging is disabled. Preserve
drag payloads, previews, nesting and drop targets. Mouse dragging and specialized
Kanban and Timeline cards retain their existing behavior.

### Mobile swipe actions

On native iOS/Android, an unfinished shared task row follows a horizontal finger
gesture. A physical right swipe reveals Focus; a physical left swipe reveals
Schedule, independently of text direction. Reveal after 48 logical pixels, with
an action area capped at 144 px and half the row width. Even a full swipe only
reveals a button: never execute or dismiss a task on gesture completion.

Use Flutter's gesture arena to separate horizontal swipes, vertical scrolling and
long-press dragging. Disable swiping during selection, task dragging and action
execution. Close on an outside tap, reverse swipe or Back. Snap open and closed
with the existing 180 ms state transition; Reduce Motion applies the final state
immediately, without delaying actions or waiting for animation callbacks.

Single-task Schedule uses the same confirmed date panel and patch application as
bulk scheduling, without changing selection or requiring a selection scope. Read
the task again before applying a single update, retain recurrence and interval
rules, and surface failures. The action also works in subtasks and the matrix.

Shared row Focus actions use the selected preset and task estimate. Open an
existing active or paused session for the same task without restarting it. Ask
before replacing a different session, revalidate after confirmation, and preserve
it on cancellation. Share the in-flight guard across rows, report failures, and
open Focus after a successful action. Completion remains on the checkbox.

### Focus completion actions

When the current task is open and a next scheduled task is available, completing
it and starting the next task is the primary action. Completing only the current
task and keeping it open remain explicit alternatives. Finishing a timer never
automatically completes a task. Show the next task alongside the actions; retain the
existing scheduling order and roll back task completion if starting Focus fails.
Guard repeated clicks and scope asynchronous dismissal to the completed run.
Actions remain independent of the decorative animation and Reduce Motion.

### Empty states and full search

Inbox, Today and project empty states explain the current context and offer a
relevant Quick Add action. Today distinguishes no planned tasks from a clear list
with completed work. Loading and errors retain available rows and offer retry.
Search supports project and Open / Completed / All status filters. It starts with
all projects and open tasks; Clear filters selects all projects and all statuses
without changing the query. Completed results follow the existing history policy.
Creating from search opens an editable Quick Add draft without saving it.

### Desktop command search

The existing Search command and sidebar entry open a contextual palette on wide
layouts; narrow layouts keep the full search screen. Preserve user-configured
shortcut bindings. Show at most six matching open tasks and three active projects,
followed by creation, dictation, Focus and full-search actions. Reuse local task
data and filtering. Task results open contextual details; creation opens an
editable draft. Dictation closes search and opens the existing voice panel,
preserving its transcription preference, access checks and any active session.
Arrow keys, Enter and Escape work without disrupting IME composition; restore
focus on closing. Keep result selection tied to stable identifiers and revalidate
a result before acting after data changes.

### Settings

Keep settings centered within 1200 px so all six theme previews fit at full width.
At 960 px of available content width,
use a 216 px section menu and a content pane. Narrower layouts show the section
index or the selected section with Back. Resize the existing tree: retain the
selected section, each visited section's scroll position, and unfinished input.
The `section` query parameter on `/settings` identifies General, Appearance,
Tasks and Focus (`tasks-focus`), Integrations and data, Account and Pro, or About.
Without a valid parameter, the initial wide view opens General and the narrow
view opens the index. Profile and Browse account links open `section=account`.
Keep the existing shortcuts and Google Calendar routes and their return paths.

Use flat setting rows with 12 px vertical padding, thin `border` separators,
and 24 px between groups. Labels and explanations sit beside controls; below
600 px of content width, complex controls stack beneath them. Keep the same
widget subtree when changing direction so editing state survives resizing.
Keep tap targets at least 48 px on phones, and use shared hover/focus states.
Only substantive previews and status notices need cards. Section transitions
use the existing 180 ms fade and end immediately with Reduce Motion.

The theme editor uses Colors and Backgrounds tabs with one shared light/dark
draft. Keep its heading, palette switch, tabs, validation feedback and Save/Cancel
actions pinned around a scrolling body. Use an at-most 820 px dialog on wide
windows and a full-screen surface below 600 px. Preserve independent tab scroll
positions and invalid input while switching tabs. Keep Classic editor chrome,
live previews, validation, reset, save failures and cancel restoration.

Show a compact, localized account profile and subscription status. Offer the
existing LaunchOfferPaywall through a button, retaining purchase, restoration
and management actions and the account-section return location. Loading and
failed subscription lookups are unknown rather than confirmed Free; keep
confirmed entitlement data visible during refreshes. Put sign-out and account
deletion in a separate bottom group. Keep platform and authentication gates,
import previews, integration warnings, revoke confirmations and shortcut conflict
handling. Persistence errors show existing feedback without resetting session
values. Standalone login, registration and onboarding layouts are unchanged.

### Authentication

Use one compact dialog, up to **440 px** wide, for sign-in, registration and
password recovery. Keep the Pomodoist brand and close action at the top, put
labels above the email and password fields, provide an accessible show/hide
control for password fields, and make the primary action full width. The
secondary magic-link action and registration or sign-in footer remain visible
without competing with the primary action.

Switch the same form between sign-in, registration and recovery while preserving
the entered email. Use the shared **180 ms** transition and finish immediately
with Reduce Motion. Support light and dark themes, scroll the content in short or
narrow windows, retain visible keyboard focus, and expose labels, errors and
icon-only controls to accessibility services.

After registration without an active session, replace the dialog form with a
persistent Check your email step showing the submitted address and a return to
sign-in action. Clear the password and keep the email when returning. Do not
reduce this instruction to a transient snackbar; registration with an immediate
session keeps the existing signed-in transition. A sessionless signup response
with an explicit empty identity list uses the existing account-may-exist feedback
and sign-in action, not the check-email step. Do not treat omitted identity data
as an empty list. Describe email delivery conditionally and provide sign-in and
password-recovery paths without promising that an email was sent. Do not add a
separate account-existence lookup.

Email entry points share the application-layer `EmailAuthController`. Preserve
CAPTCHA, SDK PKCE handling and return paths, block concurrent submissions, and
keep field values after failures. Magic-link sign-in uses `shouldCreateUser:
false`; only explicit registration creates a new account.

| Scenario | Feedback and next action |
|---|---|
| Empty or malformed input | Field validation before any request |
| Unknown address or wrong password at sign-in | The same email-or-password error; offer recovery and registration |
| Explicit duplicate-account error or sessionless signup with empty identities | Keep the form and offer sign-in or password recovery |
| Signup without a session and without an explicit empty identity list | Persistent, conditional check-email step |
| Signup with a session | Continue through the existing signed-in return path |
| Unconfirmed password sign-in | Offer signup-confirmation resend using CAPTCHA |
| Unknown address for a magic link or recovery | Conditional check-email response; do not create an account |
| Email delivery failure or server conflict | Retryable service error, distinct from rate limits and duplicate accounts |
| Expired recovery or PKCE link | Offer a new recovery link |
| Network, rate limit, CAPTCHA, weak password or restricted account | Localized existing feedback and appropriate retry/edit action |

Classify documented error codes rather than parsing or displaying server messages.
Changing the server's confirmation policy is separate from the client flow.

Enter the new-password flow only for a password-recovery session validated by the
authentication SDK. Require a new password and confirmation; keep user input when
validation or network errors occur. If a password update takes more than 30 seconds,
show the shared slow-request message and allow leaving the screen. Keep further
updates blocked until the original request settles; leaving is not cancellation
of a request already sent to the server. The password PUT is bound to the verified
recovery session and must not apply a late user response to a different SDK session.
Never log recovery tokens or passwords. Route
cold-start and warm-app callbacks through the same handler so each valid callback
is processed once and invalid or expired links return to a recoverable state.

## Components and independence

- Current direct dependencies: **`shadcn_ui 0.56.3`** and
  **`flutter_animate 4.5.2`**. Versions are pinned in `pubspec.yaml` during
  adoption. `google_fonts`, `FlexColorScheme`, and `wolt_modal_sheet` are outside
  this phase.
- Use `shadcn_ui` for standard buttons, inputs, switches, selects, menus,
  tooltips, dialogs, and simple panels when the component preserves the required
  behavior and density. Do not create a universal wrapper for every component.
- Existing Material components may use the shared theme. Mixed dialog content
  must retain the Material ancestors its widgets require.
- Task rows, smart Quick Add, the calendar, Timeline, Kanban, timers, and
  resizable windows retain their specialized implementations. Do not rewrite
  them merely to make widget names consistent.
- Start with an existing component or Flutter mechanism; use the already
  installed `flutter_animate` for compound effects. New dependencies need a
  concrete missing behavior to justify them, rather than a styling preference.
- UI libraries stay in the presentation layer. Models, Riverpod controllers
  for business logic, storage, and synchronization remain independent of Shadcn.
- Preserve `ShadApp.custom` and `ShadAppBuilder` around the existing
  `MaterialApp.router`, as well as routing, localization, theme selection, and
  `DesktopUpdateHost`. The separate Quick Add window uses the same theme.
- For `ShadButton(expands: true)`, the library adds `Expanded` itself: pass a
  regular child widget without a nested `Flexible`/`Expanded`.

## States and accessibility

- Interactive elements must have distinguishable hover, pressed, selected,
  disabled, loading, error, and keyboard focus states where applicable.
- Menubar popovers use the shared automatic anchor so actions remain inside
  the viewport near window edges.
- Open field and action menus through explicit activation (click, tap, or
  keyboard), never pointer hover. Keep `ShadMenubarTheme.selectOnHover` disabled.
- Keep keyboard focus visible. Task row actions must be available through
  keyboard focus and touch, not only hover.
- Communicate state through text, icons, or semantics as well as color.
  Icon-only actions need accessible labels and tooltips where appropriate.
- On narrow screens, use wrapping, existing adaptive layouts, and scrolling.
  Do not shrink text or touch targets simply to eliminate overflow.

### Software keyboard

Both app roots use `KeyboardDismissRegion` above navigation and overlays. A
completed touch tap on unused space removes focus and hides the software
keyboard on native mobile and mobile web. Do not unfocus on touch down, scrolling
or dragging; let fields, selection, suggestions and buttons handle their own
gestures. Keep mouse behavior unchanged and exclude the surrounding tap handler
from accessibility semantics. Dismissal only removes focus: it does not submit a
form, close a panel or clear a draft. Existing save-on-blur behavior still applies.

## Motion

The shared curve is `AppMotion.curve` (`easeOutCubic`). For standard transitions,
use `AppMotion` and `AppMotion.duration(context, duration)`.

| Event | Rule |
|---|---|
| Hover and press | Color and background, **120 ms** |
| Menu, tooltip, dialog | Opacity and movement up to **4 px**, **180 ms** |
| Sidebar and voice panel | Size and position, **240 ms** |
| Task creation | Appear and rise up to **6 px**, **240 ms**; highlight fades within **500 ms from the start** |
| Task completion | Ring/checkmark, **180 ms**; the row disappears according to existing list rules |
| Task deletion | Fade and collapse, **240 ms** |
| Theme and Focus state changes | **180 ms** |

### Focus completion: an expressive exception

Keep the animated ring and drawn checkmark, a brief soft halo, and a burst of
small particles in the current theme's accent and gray palette. The composition
lasts **900 ms**; text and actions appear within **180 ms**, moving up to **4 px**,
independently of the decorative effect finishing. Do not reduce completion to a
static icon when normal motion is enabled. The screen remains until the user
acts.

### Events and Reduce Motion

- Preserve `TaskMotionController`, `VoicePanelMotion`, and the Focus completion
  controller. Tie effects to events and stable identifiers, not ordinary
  rebuilds or incoming synchronized data.
- Do not replay completion for a Focus run that has already been presented.
  Preserve `TaskMotionController.maxAnimatedBulkTasks` for bulk task changes.
- During a drag, the element follows the pointer without delay. Saving data and
  advancing the timer do not wait for an animation to finish.
- With system Reduce Motion enabled, show the final state immediately. Disable
  particles and decorative movement while keeping confirmation, actions, and
  Undo functional. Enabling Reduce Motion midway through an effect must also
  complete it immediately.
- Cleanup of temporary visual state must not block the workflow when an effect
  has zero duration.

## Validation

For styling work, the agent formats changed Dart files, runs static analysis,
and runs targeted unit tests using the pinned FVM SDK:

```sh
.fvm/flutter_sdk/bin/dart format <changed-files>
.fvm/flutter_sdk/bin/flutter analyze --no-pub
.fvm/flutter_sdk/bin/flutter test --no-pub <relevant-unit-test-files>
```

For macOS glass background changes, run only selected unit tests with that SDK;
broader analysis, builds, app launches and visual checks remain separately scoped.

Test changed logic: theme conversion, animation events, bulk limits, state
preservation, duplicate suppression, and Reduce Motion. Reuse existing tests.
Do not add tests that only repeat constants or a separate architecture solely
for testability.

The user performs visual and manual checks. Widget, golden, integration, and
end-to-end tests, builds, app launches, browser checks, emulators, and profiling
are outside the agent's default styling scope unless the user requests them
separately. Passing analysis or unit tests does not establish visual quality.

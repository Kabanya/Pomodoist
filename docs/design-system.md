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
| Palette, typography, Material and Shadcn themes | [app_theme.dart](../apps/flutter/lib/ui/core/themes/app_theme.dart) |
| Built-in themes, local copies, selection and live preview | [theme_settings_view_model.dart](../apps/flutter/lib/ui/settings/view_models/theme_settings_view_model.dart) |
| Shared durations, curve, and Reduce Motion | [app_motion.dart](../apps/flutter/lib/ui/core/themes/app_motion.dart) |
| Main application integration | [app.dart](../apps/flutter/lib/ui/core/widgets/pomodoist_app.dart) |
| Separate Quick Add window integration | [global_quick_add_window.dart](../apps/flutter/lib/ui/quick_add/widgets/global_quick_add_window.dart) |
| Task row events and effects | [task_motion.dart](../apps/flutter/lib/ui/tasks/widgets/task_motion.dart) |
| Voice panel motion | [voice_panel_motion.dart](../apps/flutter/lib/ui/tasks/widgets/voice_panel_motion.dart) |
| Focus completion | [focus_completion_celebration.dart](../apps/flutter/lib/ui/focus/widgets/focus_completion_celebration.dart) |

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
- Input focus outlines stay inside the field bounds, with the same corner
  radius as the field. Shadcn inputs use a 2 px accent outline with zero outward
  offset so scrollable containers cannot clip its sides; focusing does not change
  field spacing or size.
- Align spacing to a **4 px** grid while preserving the current density.
- Settings rows vertically center labels and controls in horizontal layouts;
  narrow layouts stack them. Account avatar, nickname and subscription actions
  fill the same trailing column and use a 48 px height. The avatar preview sits
  inside its action button.
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
it. `LocalThemeSettingsRepository` persists the selected identifier and single
custom pair together in SharedPreferences as plain JSON; the color conversion
stays with `AppThemeSettingsController`. That controller is the one explicit
preview owner: its draft is shared through the desktop provider scope so Quick
Add and the main window stay aligned, while ordinary screen drafts stay local.

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

## Application icon

Appearance settings offer Pomo (the default) and Classic, with localized labels,
previews and selected semantics. Keep `icon-light-pomo` as the internal identifier
and asset name only; use the localized Pomo name in all user-facing copy. The
selection is device-local, independent of account synchronization and of the
companion's visibility. Disable choices during loading and saving; expose failures
and a load retry. Apply the platform change
before saving `app.icon`; a failed save restores the previous platform icon.
Read the actual platform selection after a failure instead of claiming a rollback
succeeded. Restore the saved choice when the application starts.

`assets/branding/app_icons/icon-light-pomo.png` is the Pomo master. The existing
`pomodoist_icon_<flavor>.png` masters remain unchanged as Classic. Run
`tool/generate_app_icons.dart` to generate both choices, previews, native resources
and the install-time defaults. Development and staging Pomo icons carry DEV/STG
badges: a rounded cobalt rectangle for DEV and an amber capsule for STG, each
with a thin contrasting rim and visually centered text. `--check` validates the
generated output without writing it.

The Chrome extension uses the generated Pomo icon for its build flavor in both
the toolbar and extension list.

On iOS/iPadOS use alternate app icons; on Android use launcher aliases while
keeping MainActivity and its deep links enabled. Enable the new alias before
disabling the previous one. Watch uses the default Pomo icon without a selector.
On macOS selection changes the running Dock icon; Finder and the closed app use
Pomo. Windows updates window icons and the current installation's Start menu
shortcut, preserving its target, arguments and AppUserModelID. Linux updates GTK
window icons and managed user desktop entries, preserving launcher fields and
storing the selected image outside an AppImage mount. Unmarked personal desktop
entries are left alone. Existing pinned or manually copied shortcuts are not
migrated. Web selection changes the favicon only; installed PWA icons remain
browser-managed. Explain these limits beside the choices, using localized copy.
Validate favicon selection and manifest races with
`node tool/test_app_icon_web.mjs` from `apps/flutter`.

## Interface zoom

Native windows share a locally saved interface zoom of 50–200%, initially 100%.
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
440 px side panel spanning the main area's full height, including the shell
top bar; narrower layouts keep the background mounted behind details.
Below the 820 px shell breakpoint, details fill the viewport and temporarily
replace the shell top bar, bottom navigation and mini Focus player. Restore that
chrome on close, while keeping the detail controls inside the system safe area.
Navigation waits for pending title and description edits and retains failed
drafts. Close and Escape restore focus; nested menus handle Escape first.
Keep the close/back and overflow actions pinned at the top of task details,
inside the safe area, with task content scrolling below them.
When compact details replace the shell header, preserve the inherited top
MediaQuery padding so their SafeArea still clears the system status bar.
Command-Option-B and Command-Shift-B (Control-Alt-B and Control-Shift-B on
Windows and Linux) both toggle the last opened task details. Both bindings are
configurable. Before any task is opened, or after that task is deleted, they
do nothing. Reuse the existing full-screen details layout below the shell
breakpoint.

### Detailed task editor

The leading Quick Add icon opens the detailed creation editor. Reuse the same
syntax-aware title controller and description draft; Cancel returns to Quick
Add with that text intact. Do not repeat project, date, priority, tag or Pomodoro
pickers inside this editor. Its header shows the resolved project, followed by
assignee chips for shared projects, description, and pending attachments. There
is one Create task action. Discussion, history and subtasks appear only after a
task exists. Keep the header and actions pinned while the form scrolls.

Use a resizable 1080 × 760 dialog, constrained to the viewport and keyboard.
The separate native Quick Add window temporarily expands within its display's
work area and restores its previous base size afterward. Temporary editor sizes
must not overwrite the saved Quick Add dimensions. Light, dark and custom themes
use the same palette roles, 12 px dialog corners and 44 px action targets.
Description formatting inserts portable Markdown emphasis, list and link syntax
in a plain-text field; it does not introduce a separate rich-text data format.

Only editable members of the resolved collaboration scope can be assigned.
Create the task, its assignees and their ordered sync commands in one local
transaction. Pending files remain local until Create. Commit the task identity
before uploading, retain remaining files after failure, and retry the existing
upload reservation rather than creating another task. Once a task exists, lock
its creation fields; offer upload retry or removal of pending files followed by
Done. Busy creation/upload blocks dismissal. Cancellation before creation never
publishes a task or an attachment.

Existing task panels expose Expand editor in their header. Expansion keeps the
same mounted task screen and editor identities, centered at up to 1280 px with
24 px viewport margins on desktop; narrow viewports use the available area.
Shared tasks use a 65/35 content/discussion split at 900 px of editor width.
Below that width, discussion follows the content in one scrollable column.
Retain the same discussion section when moving between columns so its unsent
draft survives resizing. Assignees sit below the title without a second copy in
Properties. Save persists title/description and returns to the side panel;
existing permissions and immediate task actions retain their current behavior.

### Task card and files

Task cards follow the internal-tabs concept: a quiet project header, completion
control beside the title, and a neutral Focus action/progress row that remains
above the tabs. Tabs use a thin accent underline and muted counts, without a
filled segmented background. Keep 24 px content insets in the desktop panel and
20 px in compact fullscreen details; interactive targets remain at least 44 px.
Use existing text roles with a medium-weight headline and smaller section titles.

Details place label/value property rows before the description and subtasks.
Date actions live in the date row; avoid a second schedule toolbar and repeated
metadata badges. Calendar linkage appears only when linked. Assignees and
recurrence use the same quiet property rhythm. Subtasks reuse task-row actions,
hierarchy and drag behavior with a compact title/completion presentation; their
creation field expands on demand. Focus history expands from a quiet text row.
Description first keeps description, attachments and subtasks in the reading
flow, with properties initially collapsed. Both layouts share these components.

The Project value opens a checked menu of active, editable projects within the
task's collaboration scope. Description starts at one line and grows with its
content without reserving a second empty line.

Task attachments use small image previews (two columns when space and text scale
allow), compact document rows and overflow actions. These task-only treatments do
not change the project's file toolbar, list or gallery. Comments use initials,
author/date/time, body text and a permission-aware overflow menu; their composer
contains the send action within one input outline. Preserve a new draft typed
while a previous comment is sending. Hide Discussion for personal tasks.

Use the same mounted editor and section instances across tab and layout changes.
Hide inactive sections with retained state rather than replacing their widget
trees; preserve title, description, comment and subtask drafts. The layout setting
does not change task routing, the 440 px desktop panel or compact fullscreen
behavior. Tabs scroll horizontally at narrow widths and controls retain accessible
labels and keyboard focus.

Project and task attachments share one Files panel and common empty, loading,
error and upload states. Offer list and gallery views, search and file-type
filters; project files may be shown together or grouped by task. View (List /
Gallery) and Grouping (All together / By task) are independent controls with local
per-project preferences. On wide screens keep search on the left and the labeled
grouping/view controls on the right; on narrow screens give search its own row
and wrap the controls without shrinking tap targets. Keep Add file the primary
action and avoid a third level of tabs. Keep attachment
uploads separate from browsing rights: viewers can read and download, while
uploads follow edit permission and Pro entitlement. Confirm permanent file
removal, and warn that deleting a project permanently removes files attached
directly to it. Use palette surfaces and existing controls in both themes.

Files uses the same format icons in list and gallery views, without extension
badges: distinct Lucide signs for spreadsheets, documents, plain text, PDF,
presentations, archives, audio, video and code. Match extensions without case
sensitivity, fall back to MIME, and retain a generic icon for unknown types.
Image previews share session-bound state by attachment and scope. Recover once
from a failed URL or image load with a fresh signed URL after one second; further
failure stays visible until Files is refreshed. Release cached images when their
preview provider is disposed, not when an individual consumer disappears.

### Calendar planning view

Calendar is a separate planning destination before Timeline in Views. Its Day,
Week, Month and Routine modes share the same task schedules, project filter and
selected date. Use a vertical time grid, subtle project-color fills, compact
cards and the existing task-detail panel. Month cells retain every scheduled
task; changing only the date retains timed duration and recurrence. All-day and
unscheduled drop areas are explicit conversions. Desktop cards drag immediately;
touch cards drag after a long press. Read-only tasks remain visible without edit
or drag affordances. Overlapping timed tasks receive separate lanes; intervals
spanning midnight appear on each intersecting day.

Empty Month cells and all-day slots use the full empty area as the create target,
without a permanent plus icon. Reveal the localized Schedule label in a subtle
surface-tint badge on hover or keyboard focus, with the standard 120 ms fade.
Keep the label visible on mobile platforms and the action labeled for assistive
technology even when the badge is hidden. Honor Reduce Motion and use at least
44 px of height for the all-day creation row.

Day overview opens from one labeled button in every mode. With at least 1060 px
of content width it uses a 300 px side column; narrower layouts use a dismissible
modal with keyboard focus containment and safe-area clearance. The panel contains
a locale-aware mini calendar and the existing live Focus session and linked task.
It must never start a separate timer or silently replace an active session.

When task details occupy the shared 440 px side panel, calculate Calendar's
820 px mobile and 1060 px overview breakpoints from the host width before the
details panel reserves space. Keep an open Day overview between the calendar
grid and task details; shrink the grid and reuse its horizontal scrolling.
Opening or closing details must preserve the selected date, desktop mode,
scroll position and overview visibility. Do not reopen an overview the user
closed. Command-Option-B and Command-Shift-B retain their task-details actions.
Below the 960 px side-panel breakpoint, keep the existing full-width details
and responsive calendar behavior.

Calendar task cards share one context menu for the overflow button, secondary
click and keyboard menu shortcut. Keep touch long-press available for dragging.
Offer Start Focus for an idle task; the task linked to the active run offers
Pause or Resume and Stop (or Start interval while ready). Respect preset pause
restrictions and confirm switching away from another task's run. Read current
Focus state before acting; keep the calendar open and let its overview update.

Use the existing TaskSelectionRegion for every calendar mode and the unscheduled
tray. Enter selection from the header, the task context menu, or Ctrl/Cmd-click;
subsequent card taps toggle membership. Count multi-day tasks once by ID and
exclude read-only tasks. Show selected cards with an accent border, checkmark
and selection semantics. Disable card dragging and duration resizing while
selection is active. Date/project changes reset selection; mode changes retain
only tasks still visible. Reuse the shared bulk actions, recurring deletion
confirmation and deletion Undo. Clear due removes scheduling while preserving
the task; Delete removes the task itself. Context-menu bulk actions always
operate on the selected set, including when opened from an unselected card.

Routine is the initial calendar layout on desktop and mobile when no mode is
saved; subsequent visits restore each saved mode. It groups tasks by start time,
with localized default Morning, Afternoon and Evening periods. Users may name, add,
remove and adjust periods; invalid or overlapping ranges cannot be saved. Tasks
outside the configured periods remain visible. The routine and selected mode are
local preferences; failed saves retain the editor draft. Reuse shared colors,
fonts, localized time/date formatting and existing Focus/task actions.

Below 820 px of available calendar width, use three equal text segments: Day,
Month and Rhythm. Keep the active segment visibly selected and exposed to
accessibility; retain the selected date, project filter and visible selection
when switching modes. Save the mobile mode separately from the desktop mode,
defaulting missing mobile preferences to Rhythm without changing the saved
desktop view.

Mobile Day uses a single chronological column with time labels, full-width
cards and tappable free windows. Concurrent tasks stack rather than shrinking
into narrow lanes. Month shows date cells with task indicators and a full-width
agenda for the selected day; its month grid collapses to a week strip. Rhythm
shows only the selected day's configurable, collapsible periods, plus all-day
and outside-period tasks. Scroll the mode switch, date controls and content
in one scroll view; the mode switch is not pinned. Keep the contextual footer
reachable independently of the scroll position.

On these compact layouts, card taps open an action sheet and long presses enter
selection. Date and time edits share a sheet with explicit Save/Cancel; duration
edits change the end date/time and preserve recurrence. Keep the existing shared
bulk toolbar and Focus mini-player. Hide the shell's floating plus on Calendar;
use a labeled Schedule action bound to the selected date, hidden during
selection. Overflow exposes overview, unscheduled tasks and project filters;
overview opens as a bottom sheet with the existing live Focus information.
The unscheduled sheet owns its own selection region and bulk toolbar, so Select
all targets the visible list rather than hidden tasks from the current day.
All controls retain touch targets and text scaling in both themes.

### Mobile bottom panels

Below the 820 px shell breakpoint, contextual calendar actions, bulk task
selection, the floating Focus mini-player and bottom navigation share
`BottomPanelSurface`. Use 12 px side margins, a 12 px corner radius, `surface`
fill, a full `border` outline and the navigation's soft shadow (10% black,
18 px blur, 0/8 px offset). Leave 8 px below each contextual panel; navigation
keeps 12 px bottom spacing and uses the adaptive geometry described below.
Clip interaction ink to the rounded surface and retain existing touch targets.

Keep panels in normal layout, ordered as screen actions, active Focus, then
navigation. Bulk selection replaces the calendar action row. Hosts own safe
areas outside the surface; the shell removes bottom padding from screen content
and owns one bottom SafeArea around the mini-player and navigation together,
including when navigation is hidden.
Do not add a second safe-area inset or a full-width background behind panels.
Honor both themes, shared state transitions and Reduce Motion.

Keep task content mounted when selection panels appear or disappear. Give the
content a stable local key directly in the selection region's layout, covering
both expanded and shrink-wrapped content, so selection and task actions retain
scroll position and local state.

Desktop retains its existing flat surfaces. Modal selection panels opt out with
`TaskSelectionRegion.floatingToolbar: false`, including Calendar's Unscheduled
sheet; their existing toolbar, safe area and elevation remain unchanged.

### Bottom navigation preferences

Appearance settings offer two styles and an ordered selection of zero to five
main destinations. Start with Today, Upcoming, Focus, Inbox and Projects in
that order. All main destinations may be pinned, including Settings; individual
projects and labels are not pin targets. Match selection by destination identity
and route boundaries, including project detail routes. Removing the current
destination never navigates away or selects another button.

Soft accent is the default: only the active destination shows its label, beside
its icon, on `accentTint` with `accent` foreground. Center the icon and label as
one row with a 6 px gap; reveal the label within that row during transitions.
Center the compact surface
for one to three destinations; four or five fill the available width. With
labels always fills the width between the standard side margins, with equal
button widths. One or two destinations place labels beside icons; three to five
place labels below icons. Horizontal buttons start at 48 px high; vertical
buttons start at 64 px. Increase height for text scaling. Retain at least 44 px
touch targets, use ellipsis rather than shrinking text, and expose full labels
through semantics and tooltips. Preserve logical order in RTL.

Zero destinations removes the entire navigation surface and its spacing. The
shell still owns the system inset; the upper menu, task creation, Focus player
and contextual panels remain independently available. Reuse the actual panel
clearance tracker. Settings previews must not register as shell clearances.

The editor previews a local draft using the real component. Save publishes only
after a successful local preference write; failures keep the draft for retry.
Cancel discards edits, Remove all retains the style, and Use defaults restores
both style and destinations. Store one local record, without account sync.
Preserve an explicitly empty list, ignore unknown or duplicate stored IDs and
cap restored selections at five. Preview uses the current theme; changing the
navigation style does not change the application theme. Switching destinations
uses a coordinated 360 ms smooth reveal with `AppMotion.navigationCurve`
(`cubic-bezier(0.22, 1, 0.36, 1)`). Animate every button width, the surface width
and the outgoing/incoming label reveals together; the surface always equals
the current sum of button widths plus its insets. Soft accent uses one decorative
`accentTint` background that slides and resizes on the same animation frame,
instead of fading independent button backgrounds. Position it from the logical
start edge for RTL, below the buttons, without intercepting gestures or adding
semantics. Fade it out when the current route is not pinned. With labels retains
its individual selected-button background. Keep outgoing labels mounted
until they have faded and collapsed. Rapid selections retarget the visible
frame, without restarting from the previous destination's final geometry.
Retain the shared 180 ms color transition. Configuration changes and enabling
Reduce Motion show the final layout immediately.

Holding a destination in compact bottom navigation opens in-place editing,
with that destination selected and without changing routes. Secondary click,
Context Menu / Shift+F10 and an accessibility action provide alternative entry
points. Editing uses equal icon targets, a visible selection border, horizontal
drag-and-drop and earlier/later buttons. Tapping an icon selects it for replacement;
choosing an already pinned destination swaps the two slots. Keep the existing
zero-to-five count: adding/removing sections and restoring an empty panel remain
in Appearance settings.

Place the editor card above the actual dock in the compact Scaffold body,
without moving or remounting route content. Use `BottomPanelSurface`, one shell
SafeArea, scrollable editor content and fixed Save/Cancel controls. Block actions
behind the card without dimming the screen. Hide the floating Add control and
mini Focus player while editing without changing the Focus run. Retain both
styles, all main destinations, localized copy, RTL and accessible touch targets.
All changes remain a local draft until the existing preference write succeeds.
Save failures retain the draft and show a retryable error; block edits and
dismissal during saving. Close, outside tap, Back and Escape discard the draft.
Route/detail changes, fullscreen map entry and switching to the wide shell also
close the editor. Do not migrate or synchronize existing navigation preferences.

### Compact task creation

In the inline Quick Add bar, center the microphone and Add buttons vertically
within the row, including when task metadata increases its height.

Below the 820 px shell breakpoint, show a 52 px circular Add task button with a
24 px plus icon, `accentFill` background, `onAccent` foreground and subtle shadow.
Start at the bottom right, 16 px from safe edges. Allow dragging and snap to the
nearest of four safe corners on release, as with the collapsed voice panel. Keep
the chosen corner while navigating within the shell; no saved setting is needed.
Follow the pointer immediately during a drag. On release or a bottom-panel
change, slide into place over 240 ms with `AppMotion.curve`, keeping size and
rotation unchanged. A new drag or interrupted transition starts from the visible
position. Reduce Motion makes all repositioning immediate.
Clamp movement below the header and above bottom navigation, the mini Focus
player, contextual action panels and the software keyboard. Floating bottom
surfaces register their actual top edge with the existing bottom-clearance
tracker, shared by voice controls and the Add button; do not sum panel heights
or system insets twice. Modal selection panels do not register.
Keep it available on shell routes, including Focus, Settings and task details;
Calendar uses its labeled Schedule action instead.
It opens the existing Quick Add dialog; modal surfaces retain their normal input
barriers. Give the button the localized Add task label and a visible focus state.

Hide it for the entire voice Quick Add session in the same root overlay, including
recording, transcription, draft review and the collapsed panel. Restore it when
the session finishes or closes. Track session lifetime centrally for every voice
entry point; do not derive visibility from recording status or panel expansion.
Wide layouts keep their existing task creation controls.

The Quick Add overlay below 820 px is a full-width bottom sheet with 12 px top
corners, positioned above software keyboard insets and inside system safe areas.
Use a compact heading with an explicit Close action, a large multiline field,
and wrapping date, project and priority controls with 48 px touch targets. Show
the short `P1`–`P4` priority label while retaining its localized accessible name.
Only the text field requests autofocus on opening, so typing can start with the
software keyboard immediately; surrounding focus wrappers must not claim it.
Keep the microphone and expanded Add button in a pinned 48 px action row; scroll
the heading, field and metadata when height is limited. Honor the selected theme's
Quick Add background and accent, keeping the input solid with a visible focus
indicator. Preserve the draft and input focus when resizing between the sheet
and desktop dialog, and keep the existing voice-session lifecycle.

Desktop Quick Add uses a compact command panel in both the wide-layout dialog
and the separate native window. Place a large multiline input between the
list-plus icon and microphone, above a thin divider. Keep date, project and
short priority menus together with Add in the bottom row. Show full labels while
the complete row fits; switch all six controls to icons only when any labeled
control would wrap. Measure the current labels, values, text scale and shared
button geometry rather than using a fixed width breakpoint. Keep localized
accessible names and
tooltips with current values, semantic colors and comment-presence indicators.
Wrap metadata within its available width and scroll it vertically when height
is limited; keep Add outside that scroll area and always available. Use 40 px
desktop controls and the current theme, without a duplicate heading or an Escape
hint. Enter submits and Escape
closes as before; retain a localized accessible name for the panel. Keep the
input scrollable and size its region to its content, with 12 px vertical padding;
extra window height must not create a gap between the text and the footer. Keep
the footer outside the input scroll area, resizing available, and voice-window
expansion intact. Start the dialog at 680 × 180 px and the native window at
680 × 200 px, widening the native window on its first opening to fit the full
labeled toolbar within native and display limits. The native title bar supplies
window controls. A saved manual size takes priority over this initial width.
The separate window
remembers the user's width and height locally across openings and app restarts.
Constrain restored and expanded sizes to native limits and the display's working
area. Temporary comment or voice expansion does not replace the saved size;
manual resizing in any mode becomes the new base size. Keep the last manual size
usable in memory if local storage fails.

### Sidebar

Group daily destinations separately from planning views, followed by the existing
project tree. Search and Add task stay near the profile. Browse, Reports and
Settings sit below projects and scroll with the list at every window height.
On supported native desktops (macOS, Windows and Linux), place a 44 px Pomo button
with a monochrome outlined tomato to the right of Settings, including in the
narrow-window drawer. Match the other 20 px line icons and inherit the button
foreground color. Stretch Settings and the Pomo button to the same row height,
with a minimum 44 px target and room for larger text. Its
localized tooltip offers Enable Pomo / Disable Pomo based on the saved enabled
preference, independently of current visibility or an active Focus run. Use a
neutral disabled-companion appearance and an accent enabled-companion appearance,
with toggle semantics and visible keyboard focus. Keep the row scrolling with
the list. Block repeated activation while saving, and expose failures through
the standard action feedback using the existing localized Pomo error message.
Preserve command identities and user shortcut bindings independently of visual
order. Shortcut hints display the actual configured binding.
Use `textTheme.titleMedium` for destination labels, Add task, and project names
and their header, matching task titles. Group captions, counts, and shortcut
hints keep their smaller text styles.

The sidebar's desktop scrollbar is 4 px wide in every state. Use `secondaryText`
at 25% opacity normally, 40% on hover and 55% while dragging; preserve Flutter's
standard scrolling, hit targets and fade behavior. Scope this treatment to the
sidebar rather than other scrollable views.

Project rows share their context menu between the sidebar and Projects screen.
Secondary click, touch long press, and the Context Menu / Shift+F10 keys expose
renaming, icon and color selection, favorites, archiving/restoration for editors,
and confirmed deletion. The open project header exposes the same menu through
an accessible ellipsis button. Archive preserves tasks, files and hierarchy;
it applies to the selected project, leaving subprojects unchanged. Archived
projects can be opened and restored from the existing archive filter. Inbox
cannot be archived. Sidebar
rows show no menu button; the Projects screen keeps its ellipsis button for
keyboard and touch access. Project icons are synchronized project data;
existing projects retain the hash icon until changed. The shared-project badge
follows the project name in both rows, before the task count. It always uses the
users icon. Keep sync conflicts internal: do not show conflict badges, tooltips,
messages or resolution controls in the interface. Preserve sync conflict storage
and processing independently of presentation.

Labels follow the project palette while keeping their own icons and `@` names.
Show the same label color in navigation, task surfaces, and selection controls;
never use color alone to identify a label. Show each label's own open-task count,
including subtasks, in the Labels list and Browse chips. Keep labels out of the
sidebar; they remain accessible from Projects / Labels and Browse.

The shared project context menu also offers **About project** for every project
except Inbox, including archived projects. Its read-only dialog shows the current
owner, the viewer's role and members with role, owner and viewer labels. Resolve
shared subprojects by their scope ID. Personal projects show the viewer as their
only member and owner; loading, missing or failed shared data must never fall
back to personal ownership. Reuse the standard dialog's responsive width,
scrolling body and pinned close action.

Projects support arbitrary nesting with globally unique names. The shared menu
offers Create subproject, Move project, and Move up/down among siblings. Keep
the Projects screen menu button visible for keyboard and touch access. A project
and its task count include only its own tasks. Deleting a parent promotes its
immediate children into its position; only the deleted project's tasks move to
Inbox.

The sidebar and Projects screen share tree controls. Branches start expanded,
retain collapse state while the screen is mounted, and reveal the destination
ancestors after creation or movement. Limit indentation to four visual steps
without limiting hierarchy depth. Use 12 px per nesting step, without reserving
an empty leading slot for expansion. Place branch toggles at the trailing edge.
Keep Projects and Browse rows at a compact 44 px baseline, with 8 px horizontal
padding and icon-to-title gaps; the sidebar uses 6 px vertical padding. Preserve
text scaling, keyboard focus, and accessible action labels.
Mouse dragging the middle half of a row
nests a branch; the top and bottom quarters insert before and after the row.
Show a parent highlight or insertion line, scroll at viewport edges, and show
a Top level target during dragging. Disable dragging during search and archive
viewing. Touch retains long-press menus; keyboard users can move through the
same menus. Keep feedback immediate, without introducing motion or dependencies.
Missing parents and cycles from synchronization must never hide projects.

### Today

Center the list within 1200 px of content width. Keep the date below the title
and use the shared connected task rows with the existing inline Quick Add.

Keep daily context to one text summary and one active Focus strip. The strip and
global mini player share the existing session, interval and clock providers.
Only replace the global player once the run and interval agree and remaining
time is available. Completed-today rows form a collapsed group with independent
selection, using the local completion day.

### Upcoming

Render the agenda as one lazy sliver list across all days, with variable row
heights and stable task keys. Day headings retain the narrow stacked and wide
date-column layouts. Selection uses the complete logical projection, including
rows outside the viewport; collapsed descendants remain excluded. Keep Quick
Add state mounted through ordinary updates. A selected date scrolls after
layout using the measured header, without repeating on task refreshes. Observe
row structure in list parents and current task, progress and ancestor snapshots
in individual cards; content-only updates must not rebuild unrelated cards.

Use a flat agenda without enclosing day cards. At 760 px of available agenda
width, put the date in a 112 px leading column with a 24 px gap; below that
threshold, place it above the day's tasks. Keep the calendar rail, local-day
grouping, Quick Add, route selection and scrolling anchors. A task remains in its
own scheduled day even when its parent belongs to another day.

For calendar rails below 760 px, a period spanning two months uses localized
abbreviations with one shared year, such as `Sep–Oct 2026`. A year boundary
keeps both years, such as `Dec 2026–Jan 2027`; preserve the locale's year
placement and month markers. Omit the calendar icon in all narrow headers,
including single-month periods; compact ranges use 4 px horizontal button
padding. Keep normal text sizing and a minimum 48 px target; let longer labels
wrap and the header grow. Accessibility
announces the full month names. Single-month headers keep their existing
labels, and wide headers retain their labels and calendar icon.

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

Every empty Quick Add input uses the same permanent, localized syntax example:
`Task name tomorrow p2 #Project @label 2p`. Keep it independent of task history,
subscription status and saved suggestions; it never triggers AI generation or
changes to a generic prompt after task creation. The separate window's native
hint bridge uses the same localized copy.

Parsed date/time, project and priority chips edit recognized spans in the source
phrase. Both `#` and `№` introduce project names, including quoted names, in
parsing, highlighting, and autocomplete. The phrase is the only metadata state:
clearing a token reveals the existing context defaults. Preview and creation use the same parser, configured
duration and clock. Preserve IME composition, selection and unrelated tokens.
Quoted metadata names remain literal during date normalization. Ready voice
subtasks preview the project inherited from their parent's current phrase.
The composer renders entered text at a regular weight in opaque primary text.
Recognized tokens use semantic foregrounds and soft fills shared with the metadata
controls: green for dates, times and durations; blue for projects and sections;
the existing P1–P4 colors for priority; the selected accent for Pomodoro estimates;
and muted violet for labels and Comment. Resolve these through
`AppThemePaletteQuickAdd` in `app_theme.dart`, including the shared light/dark
violet role; no additional theme setting is stored. Foregrounds adjust toward
primary text when needed to retain 4.5:1 contrast on normal and interaction fills.
Use native `TextSpan.backgroundColor` without changing text metrics, selection
or composing underlines. Tokens reflect the phrase's effective priority.
On mobile and desktop, the composer hint uses light weight (300) and secondary
text at 65% opacity to stay unobtrusive.
`QuickAddComposer` owns this styling, so the dialog and the separate window
stay consistent. Details stay below the editable input; the separate window
scrolls when needed.

Date, project, priority, Pomodoro estimate and Comment controls retain soft fills
and thin tinted borders even without a value. Open menus and the expanded Comment
control use a stronger semantic border. Hover and press retain the semantic color
with a slightly stronger fill; disabled states retain the shared button behavior.
Keep 8 px control corners, existing sizes and wrapping, and keyboard focus outlines.
Apply this treatment to inline Quick Add, dialogs, the separate window and editable
voice drafts including subtasks, using the existing shared components.

A Pomodoro estimate chip precedes Comment whenever the phrase is nonempty.
Without an estimate it remains a softly accent-tinted, discoverable action. Manual estimates
and recognized `3p` / `3п` tokens use the palette accent, independently of priority.
The anchored, keyboard-accessible editor offers a 1–999 interval field, decrement,
increment and Clear estimate. Opening it proposes one interval without changing
the phrase. Edits replace only estimate spans; clearing reveals the automatic
schedule estimate or an empty estimate. Manual estimates override schedule-based
counts without changing the schedule. The focus-time preview uses only the selected
preset's work duration, excludes breaks, and stays hidden until a preset is available.
Use the existing viewport/keyboard-safe popover geometry, scroll constrained content,
and retain 48 px touch controls and regular token text weight in both themes.

All Quick Add surfaces (inline lists, dialogs, the separate window and voice
previews including subtasks) offer a Comment chip alongside date, project and
priority. Show the chip only when the task input contains non-whitespace text,
alongside the other metadata; hide it again when that input is cleared. Expanding it
reveals a softly tinted multiline field below the metadata; collapsing it keeps
the text, and a checkmark on the chip indicates a nonempty comment. Use the
existing localized task-comment labels, 40 px desktop and 48 px touch controls,
and the shared palette in both themes. Enter adds a newline in the comment.
The comment is literal task description text, never parsed as Quick Add metadata;
create and synchronize it atomically with the task. Keep both drafts after a
failure and clear them only after successful text creation.

Opening the comment raises the desktop dialog minimum height to 320 px and
temporarily raises the separate window height to at least 340 px without changing
its chosen width. Expanded voice temporarily requests at least 720 × 720 px.
Neither mode shrinks an already larger window; constrain both to the working area
and restore the user's base size when closed. Preserve comment text and selection
across mobile/desktop layout changes. In constrained windows, scroll the input and
comment while keeping creation controls outside their scroll regions. Allow the
metadata to scroll independently when wrapping exceeds the available height,
keeping Add outside its scroll region. Mobile keeps the existing keyboard-aware
sheet and pinned action row. Returning from
voice mode restores the separate window's expanded comment size when applicable.

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

Use `AppDateTimePicker` for date/time selection in Quick Add, task details,
Timeline and the habit editor. Keep its anchor mounted on the invoking chip or
button. Its `ShadPopover` belongs above that surface, including manually inserted
Quick Add and voice overlays; do not push a Navigator picker route underneath them.

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
color. In the shared column layout, project (120 px), focus progress (56 px), and
descendant progress (72 px) share one vertically centered metadata row to the
right of the title block, before row actions. Reserve all three slots even when
a value is absent, with 12 px gaps; scale slot widths with text size. Narrow
desktop layouts place these slots below the heading, aligned to the trailing
edge, and wrap only when they do not fit. A task's nesting depth must not change the
list's column-layout breakpoint. Subtask disclosure stays before the completion
circle on desktop and in the trailing action slot on mobile. Progress controls
remain outside task drag targets.
Native mobile rows use a separate, flat composition in both Modern and Classic.
The completion circle and disclosure have 44 px targets aligned with the first
title line, independently of the row's total height. Titles and schedule labels
wrap without a line limit, ellipsis, or font shrinking. Description previews
retain their existing limit. Description, schedule, and metadata follow the
heading with only the small internal gap of the selected density.
Keep only the first-line inset needed to align the title with the 44 px controls.
Mobile rows replace the parent-context text line with one muted 12 px
`cornerDownRight` marker after the title, separated by 4 px. Keep the marker
beside the first title line, mirror it in RTL, and preserve the full ancestor
path in tooltip and screen-reader semantics. Its tooltip must not claim the
row's long-press menu gesture. Show it under the same hidden-parent/deep-nesting
conditions as the parent context. Parent navigation lives in the native row's
context menu, with a localized 44 px action only for an accessible parent outside
bulk selection. Revalidate the parent before navigation; unavailable parents
retain the neutral marker without an action.

Schedule occupies the full text width below the title and description,
independently of parent context and metadata. Use separate localized date/time
blocks rather than parsing a combined string. Keep a same-day time range whole
when wrapping below its date; only an individually oversized block may wrap
internally for accessibility. Recurrence gets its own line. Ranges crossing
local midnight use separate dated start/end lines; Start only still omits the
end, and Upcoming omits the start date already shown in its group heading.
Preserve Smart / Start only / Range and the system's 12/24-hour format.

The next metadata row groups project, Focus count and descendant count together
at the leading edge, in that order, with 8 px horizontal gaps and intrinsic
widths. Reserve no absent slots and do not push counts to the trailing edge.
Wrap whole elements with the selected density's internal gap between runs. Project names keep their
160 px maximum (also bounded by available width) and may ellipsize. Align count
labels to the first text line. The native descendant count is an informational
label with localized screen-reader semantics; opening details uses the containing
task row's target of at least 44 px. Do not reserve a separate button height below
the count. Omit empty schedule/metadata blocks.
Project and timing colors retain their semantics.
Custom Kanban and Timeline blocks keep their specialized layouts.
Kanban card action menus open on activation; pointer hover only highlights the
ellipsis button and must not open its menu (`ShadMenubar.selectOnHover: false`).

Task row spacing is independent of Modern / Classic. On desktop/web, the local
`tasks.rowSpacing` preference selects Compact (0 px), Comfortable (8 px), or
Spacious (20 px) vertical padding on each side of a row. Comfortable is the
default for missing or unknown values. Changes apply immediately without a new
animation; a late preference load must not replace a local selection. A failed
save keeps the current session's selection and reports the error in Settings.
Compact also caps existing vertical gaps between text blocks and wrapped metadata
rows at 2 px; Comfortable and Spacious retain their existing internal gaps.
`TaskRowGeometry` defines these density rules for desktop/web rows, including
grouped branches. Native mobile rows use the same 0 / 8 / 20 px outer vertical
padding per side. Their internal gaps are 0 / 2 / 4 px for Compact / Comfortable /
Spacious, only between present title, description, schedule and metadata blocks
and between wrapped metadata runs. Do not reserve space for absent content.
Keep mobile branch anchors offset by the outer padding so their arms still meet
the completion controls. Specialized compact rows retain their existing geometry.
Font sizes, separator heights, and touch targets of at least 44 px stay
unchanged.

All shared task lists use `TaskListDivider` between rows, including completed
groups, subtasks, and the priority matrix. The line is 1 px in `appColors.border`,
starts 38 px from the task body's leading edge, after any disclosure margin,
and adds 28 px per level of the less
indented adjacent task. Do not add leading or trailing separators. Its total
height is 1 px on desktop/web and 12 px on native iOS/Android, with the line
centered after title-only rows. When a native row shows content below its
title, move only the stroke down by half the title inset (at most 5 px) so the
visible gaps on both sides match. Keep the 12 px separator and touch drop area
unchanged. Root-task drop targets keep their existing expansion and Reduce
Motion behavior. Kanban and Timeline do not use this spacing preference.

### Connected task branches

On desktop, use an icon-only disclosure button before the completion circle,
outside the task body's hover, selection, and drop highlight. Hierarchical lists
share a compact 24 px leading margin; lists that cannot expand branches reserve
no disclosure margin. On native iOS/Android, reserve no leading margin: place
the disclosure in the 48 px trailing action slot, with a minimum 44 px tap target,
and omit the ellipsis button in both row styles. Long-press opens the task menu.
Keep the margin empty for leaf rows and apply tree indentation outside the
highlighted body as well. The margin remains inside the row's layout bounds so
the disclosure has a working hit target without relying on painted overflow.
Disclosure must not toggle completion, start dragging or activate task details.
Keep completed/total descendant progress beside the task heading as a separate
button opening full task details. Count all descendant levels, including tasks
outside the current filter, and explain this in the localized tooltip. Task
details section headers may combine the chevron and progress in one button.

Filter first, then project the visible tree. Roots start expanded and nested
branches start collapsed. Persist explicit choices locally in task preferences,
independently by destination and task ID, without synchronizing them. Today and
Upcoming use stable destination keys without dates; projects, labels and task
details include their IDs. Preserve local interaction over delayed preference
loading; keep the current choice and show save feedback if persistence fails.

Draw 1 px theme-border connectors through rows and their separators, with 28 px
per level and a maximum visual indentation of two levels. Horizontal arms stop
at the completion ring's outer edge, including its stroke (16.75 px arms for the
24 px completion control), never inside the circle.
On mobile, connector endpoints follow the completion circle's first-line anchor,
not the row's vertical center. End rails at the last visible sibling. At the
two-level indentation cap, keep the direct rail continuous while the next
displayed row remains at that cap, including deeper descendants and returns to
their ancestors' siblings. Recompute this continuation from the final displayed
sequence, including retained motion rows and task-details subsets; end it before
a shallower row or the end of the list. Keep actual
ancestry at deeper levels and show its path beside the title block (below the
title on mobile). With an absent visible parent, promote the row visually to the root
and show a parent link instead of phantom indentation. An unavailable parent has
neutral, noninteractive text. Paths and connectors respect text direction.

Shared lists, task details and Today's completed section use these branches.
Search and Priority Matrix preserve their existing ordering and partitions;
they show parent context and progress linking to details. Kanban, Calendar,
Timeline and Focus use a single-line compact summary within their existing
geometry and activation target, without expanding a second tree in the card.

Disclosure has no additional animation. Preserve focus on its button when a
branch closes; remove hidden rows from bulk selection. Expand ancestors after
explicit task creation or nesting in the current destination. Completion, Undo,
row density and drag semantics remain independent of disclosure. Interactive
disclosure and desktop parent links have at least 44 px touch targets; native
mobile parent navigation uses the 44 px menu action. Compact summaries rely on
the containing task's accessible activation target.

The local `tasks.branchStyle` preference independently selects Connected lines
(default) or Grouped branch on all platforms. Keep Modern/Classic, row spacing,
and expansion choices independent. Persist immediately with ordered writes;
late loading must not replace a local choice. Unknown values use Connected lines.
A failed write keeps session state and uses the existing settings error feedback.

Grouped branch paints one surface around a visible root with eligible children
and its displayed descendants, with a 1 px border, 14 px outer corners, and no
shadow or nested cards. Collapsed roots retain their single-row block. Standalone
tasks remain flat. Within a block replace connector rails with 12 px indentation
per level, capped at two levels relative to the displayed group root. Compute
first/last segments from the displayed forest, including retained motion rows;
paint through internal separators without replacing lazy rows or their keys.
Details recompute group boundaries after omitting their owning task. Upcoming
never joins groups across dates. Apply this to hierarchical lists and details;
do not regroup Search, Priority Matrix, Kanban, Calendar, Timeline, Focus, or Map.

### Project map

An open project exposes List and Map directly in its heading. The last
choice is a single local preference for every project, initially List; it is not
an Appearance setting or synchronized project data. Keep the shared Quick Add
composer mounted, preserve detail routing and drafts, and retain each visited
view's scroll position while the project remains open.

Both project and catalog maps offer a 48 px expand/collapse control at the
viewport's top trailing corner. Expanded Map fills the app viewport, hiding the
sidebar, shell bars, project heading and composers while keeping the same map
and header state mounted. Collapse, Escape or Back restores the ordinary layout;
nested menus, task selection and task details handle their own dismissal first.
Keep safe-area insets, task-detail navigation, filters, expansion and scroll state.
Expansion is temporary route state, independent of the saved List/Map preference.

Map lays out the current project horizontally through existing subprojects,
tasks and subtasks. It uses a shared hierarchy projection and a local
expansion scope per open project. Root and first-level nodes begin expanded;
deeper nodes begin collapsed. Empty subprojects remain visible. Exclude
archived/deleted descendant projects; hide completed tasks initially, with an
inline Show completed control. Progress includes all accessible descendants,
independently of filtering and disclosure. Order projects before tasks, retaining
each entity type's existing sibling order.

Use measured, text-scaled cards, theme surfaces and 1 px border connectors;
mirror geometry in RTL. Anchor the vertical scrollbar to the right edge of the
map viewport, outside the horizontally scrolling canvas; avoid duplicate
automatic scrollbars. Keep controls at least 44 px and title tooltips available.
Cards use existing details, menus, completion/Undo and Focus actions. New tasks
and subprojects use the existing composers; adding a subtask uses the existing
subtask editor logic. Explicit creation and successful drops reveal the parent.

On Map, task title activation opens a rename dialog for editable tasks; read-only
titles open details. Keep Open in the task menu for detail navigation and preserve
bulk selection on title activation. Clicking the rest of a task card opens its
detail panel (or toggles selection in bulk mode); nested buttons retain their
own actions. Limit the rename hit area to the title, not its surrounding empty
space. Task and project title regions have no hover
fill; retain rounded keyboard focus feedback. Rename uses the existing title
editor, keeps failed drafts available for retry, and disables dismissal while
saving. Project title navigation and the card's drag behavior remain unchanged.

Mouse drops distinguish before, inside and after. A task dropped on a project
becomes a root task; a task dropped on another task becomes its subtask. Move
the entire task subtree atomically with order and sync-queue changes. Projects
can move only relative to other projects; the diagram root is not draggable.
Reject cycles, unavailable destinations and forbidden scope changes. Invalid
drop zones do not highlight. Dragging near the viewport edge scrolls the canvas.
On touch, Map scrolls normally and structure changes use menus instead
of long-press dragging. The ordinary list and project catalog retain their
existing hierarchy and interaction rules.

The Projects catalog also offers List and Map directly in its heading.
Its view preference and map expansion scope are local and
independent of the view inside individual projects. A display-only Projects root
connects the project forest; it is never a stored project or a task destination.
Exclude Inbox. Keep empty projects and promote projects whose parent is excluded
by the active/archive filter. All catalog project and task branches start
expanded so nested subtasks are visible on entry. Explicit saved collapse
choices still take precedence; completed-task filtering is unchanged.

Catalog diagrams search project names and task titles case-insensitively. Project
matches retain their contents; task matches retain their ancestor paths. Reveal
matching paths temporarily without overwriting saved expansion. Completion
visibility still applies to search; progress ignores search and expansion.
Disable structural moves during search and in archive mode, including menu and
bulk moves. Otherwise, dropping a project on the catalog root returns it to the
top level using the existing scope and permission checks. Preserve per-view
scroll positions, the search field, and task detail routing across view switches.
Keep the catalog header scrollable and bounded on short windows and while the
software keyboard is visible. Retained inactive views must not capture keyboard
focus, Escape or Back through their selection controllers. The Labels tab and
ordinary list keep their existing search behavior. Use the
tabs component's own scrolling mode; do not put expanding tabs into an unbounded
horizontal viewport.

### Touch task menus

On native iOS/Android, long-press the shared row's text or metadata to open its
context menu, including Focus and Move. Do not also register a long-press drag
recognizer on that row. In selection mode, long-press toggles selection. Mouse
dragging, drop targets, and specialized Kanban and Timeline cards retain their
existing behavior.

### Mobile swipe actions

On native iOS/Android, an unfinished shared task row follows a horizontal finger
gesture. A physical right swipe reveals Focus; a physical left swipe reveals
Schedule, independently of text direction. Reveal after 48 logical pixels, with
an action area capped at 144 px and half the row width. Even a full swipe only
reveals a button: never execute or dismiss a task on gesture completion.

Use Flutter's gesture arena to separate horizontal swipes, vertical scrolling and
long-press menus. Disable swiping during selection, task dragging and action
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
The task-details Focus action follows its linked interval: Start focus, Pause,
Resume, or Start interval. Keep the details open and honor preset pause rules.
Clicking the mini Focus player's non-control surface opens the Focus screen;
its pause and stop controls keep their own actions.

### Minimal Focus timer

The Focus keyboard shortcuts are Cmd/Ctrl+5 and Cmd/Ctrl+F by default; both
remain configurable. From another destination, open Focus in its stored view
mode. When Focus is already open, toggle Minimal / Full and persist the choice
without changing the session or countdown. Ignore key repeats and overlapping
mode writes, and surface preference-save failures through the existing Focus
error feedback. Preserve user bindings when adding the second shortcut; if F is
occupied, choose the first available Shift+F through Shift+Z combination with
the platform's Command or Control modifier.

Use one centered column in Minimal view: a quiet preset selector while idle,
large light-weight GeistMono digits with the selected progress style, and a
56 px circular Play / Pause action. The active phase stays visible above the
digits; the primary action retains its localized accessible label, tooltip,
keyboard activation and preset pause restrictions. Use theme tokens for both
light and dark palettes. Fit long timer values within the available width.

Place the direct Full view action in the Focus header, outside the centered
column. Hide it when the host fixes the view mode. Honor the stored Circle / Bar
preference in both Minimal and Full views: visual style and detail level are
independent. Minimal uses a circular progress ring for Circle and an 80 px by
2 px progress track for Bar, both while idle and during an active interval.
Both views scale the circle with the available width and window height, from
280 px up to 520 px on large windows. Digits scale proportionally; the dial and
long countdown values shrink to fit narrower layouts.

### Full Focus layout

Use the control-dock composition: header actions and the session rhythm at the
top, linked task above the horizontally centered timer, and a separated control
dock at the bottom of the available viewport. Keep the task and timer grouped
with the header: use a 64 px gap below the rhythm on desktop and 16 px on compact
layouts. Compact Full view has no extra top page padding, keeps 16 px below the
stage and timer, and uses 12 px between the header and rhythm. Linked tasks have
no extra top padding and 12 px below them. Subtract the actual page padding from
the available stage height, preserving system safe areas and control sizes.
Extra viewport height belongs below the timer, before the dock. Let the entire stage scroll when its content
exceeds that height; embedded stages size to their contents. Center the primary
action independently of the session summary and Complete interval action. Below
680 px of dock width, place the overflow menu at the trailing edge of the session
summary row, with matching leading space to keep the summary centered. Stack the
primary action and Complete interval on the timer's center axis with a 12 px gap.
Reuse the summary's surrounding spacing for the 48 px menu target instead of
adding another control row. Let summary text wrap when space or text scaling
requires it, keeping every action reachable.

The overflow menu offers **Compact** and **Icons** session displays. Compact
uses duration-weighted segments; Icons preserves the numbered work sessions,
break icons, interval history and active-step recentering. Persist the choice
locally, independently of Minimal / Full and Circle / Bar, defaulting to Compact.
Changing this presentation never starts, stops or resets a running interval.
Keep preset selection in the header and retain existing strict-mode constraints,
localized feedback, accessible timer summaries and Reduce Motion behavior.

### Focus sounds

Tasks and Focus settings offer Soft kalimba, Neon pulse, and Orbit bloom, in that
order, through the shared setting row and select control. Soft kalimba is the
default for new and upgraded installations. The device-local choice applies to
start, pause, resume, and completion cues at the existing 55% playback volume.
Loading a stored choice precedes the first cue; changing it never resets a run.

The localized Listen button auditions only the selected completion cue using a
separate player, without vibration or timer actions. Repeated presses restart
the sample; changing the family or leaving the settings section stops it. Keep
save failures on the previous choice, and present playback failures inline.
Use the shared light/dark styling and responsive setting-row geometry. Validation
for this change is static analysis and targeted unit tests only.

### Focus completion actions

Focus controls never show bottom success snackbars, including start, pause,
resume, stop, and interval completion, on any surface. Preserve action errors,
timer sounds, system notifications, and the Focus completion screen.

When the current task is open and a next scheduled task is available, completing
it and starting the next task is the primary action. Completing only the current
task and keeping it open remain explicit alternatives. Finishing a timer never
automatically completes a task. Show the next task alongside the actions; retain the
existing scheduling order and roll back task completion if starting Focus fails.
Guard repeated clicks and scope asynchronous dismissal to the completed run.
Actions remain independent of the decorative animation and Reduce Motion.

### Empty states and full search

The application shell and navigation render before local data is ready. Show
preparation, errors and retry inside the main content area; retain the shell's
state while preparation finishes or fails. Task creation, project creation,
details, task counts, project lists, Focus playback and account-data overlays
activate only after local database preparation and account ownership checks.
Never read previous-owner data to populate the preparing shell. Task lists
subscribe asynchronously after that boundary; loading a list does not block
navigation. Defer onboarding overlays until local preparation completes.
Token refresh, background synchronization and app resume retain the working
interface and available rows; network failures use the existing sync status.
Recurring task generation runs after local startup through the background wiring.
Local preparation failures retain the existing error/retry screen, and retry
cannot start a second preparation while the first is pending. A real account
change still gates access until its ownership transition completes.

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
data and filtering. On supported native desktops (macOS, Windows and Linux), append an
Enable Pomo / Disable Pomo command after full search and before the keyboard hint.
Its label follows the saved enabled preference, including while Pomo is temporarily
hidden. Reuse the shared companion controller; block repeated activation while
saving, close on success, and keep the palette open with localized Pomo error
feedback on failure. The command participates in the same keyboard selection.
Task results open contextual details; creation opens an
editable draft. Dictation closes search and opens the existing voice panel,
preserving its transcription preference, access checks and any active session.
Arrow keys, Enter and Escape work without disrupting IME composition; restore
focus on closing. Keep result selection tied to stable identifiers and revalidate
a result before acting after data changes.

### Labels

Open a user label from Projects / Labels into the shared task list, filtered by
label ID across projects. Text and voice Quick Add on that screen inherit the
label while preserving explicitly selected projects and other labels. Missing
or deleted labels show a return to Labels instead of a task composer.

Label icons use a separate Lucide set: tag (default), bookmark, flag, bolt,
lightbulb, clock, bell, pin, phone, mail, link, and wrench. Keep this set distinct
from project icons. Offer selection during label creation, from the label row's
context menu and visible edit button, and from its screen heading. Use localized
icon names, keyboard focus, and selected-state semantics. Persist and synchronize
icon identifiers; missing or unknown identifiers render as tag. Kanban status
labels are excluded from these screens and edits.

### Settings

Keep settings centered within 1200 px so all six theme previews fit at full width.
At 960 px of available content width,
use a 216 px section menu and a content pane. Narrower layouts show the section
index or the selected section with Back. Resize the existing tree: retain the
selected section, each visited section's scroll position, and unfinished input.
The `section` query parameter on `/settings` identifies General, Appearance,
Tasks and Focus (`tasks-focus`), Pomo (`pomo`), Integrations and data, Account and
Pro, or About. Pomo follows Tasks and Focus and contains the companion settings,
including Linux monitor controls and availability feedback. Show the section on
native macOS, Windows and Linux, even while Linux capabilities are being checked
or the companion is unavailable. Hide it on mobile and web. The menu, content
panes and selected content index use the same platform-filtered section list.
The Pomo menu entry uses a monochrome tomato outline with a leafy crown, an
18 px size and rounded strokes matching the Lucide icons. It inherits the menu's
icon color, including the selected accent; do not use an emoji or a face.
Without a valid or available section parameter, the initial wide view opens
General and the narrow view opens the index. Profile and Browse account links
open `section=account`.
Keep the existing shortcuts and Google Calendar routes and their return paths.

Use flat setting rows with 12 px vertical padding, thin `border` separators,
and 24 px between groups. Labels and explanations sit beside controls; below
600 px of content width, complex controls stack beneath them. Keep the same
widget subtree when changing direction so editing state survives resizing.
Keep tap targets at least 48 px on phones, and use shared hover/focus states.
Only substantive previews and status notices need cards. Section transitions
use the existing 180 ms fade and end immediately with Reduce Motion.

Appearance has one full-width task-list preview below the list controls. It
reflects the current list style, branch style, row density and light/dark/system
theme using the live row content widgets and branch geometry, never a separate
mobile layout. Palette choices and the theme editor retain their existing
color/background samples; the navigation editor retains its existing draft
preview. The task-list sample shows a localized parent and two subtasks, short and
long titles, a description, schedule, project and counts, plus a completed row
with absent metadata. Previews observe the existing settings state immediately.
The sample creates no records, loads no user tasks and exposes no task actions;
keep informational text available to screen readers and exclude preview controls
from keyboard focus. Do not shrink text or clip content to a fixed preview height.
Show the real action controls in the desktop sample, including Modern's hover
reveal in the column layout and Classic's persistent Focus action. Reuse the live
action widgets and opacity rules. Absorb task gestures inside each sample row,
after its hover region, so hovering works without opening menus or starting Focus.
Native mobile samples preserve the actual shared layout; Modern's heavier title
weight is the style difference, not an invented desktop layout on a phone.

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
values. Standalone login and registration retain their own layouts.

### Emoji avatars

Account settings offer an emoji avatar beside nickname editing. The editor uses
`emoji_picker_flutter 4.5.4` only in presentation, with localized category tabs,
skin tone choices and unrestricted keyboard input validated as one complete
Unicode emoji sequence. Preserve flags, modifiers, variation selectors and ZWJ
sequences; never truncate input to one code unit. The local generated sequence
set records its Unicode version and license independently of the picker catalog.

Preview is a local draft. Save persists `profiles.avatar_emoji`; Reset clears the
draft and persists null only on Save. Cancel discards edits. Retain failed drafts,
block duplicate submissions and bind saving to the account that opened the
editor. Show the saved emoji in the sidebar, mobile drawer and account panel;
null retains each surface's existing default avatar. OAuth avatar URLs and other
members' collaboration avatars remain separate.

Use a dialog up to 560 px wide, fullscreen below 600 px, with pinned heading and
wrapping Save/Cancel/Reset actions around scrolling content. Emoji cells and
controls have at least 48 px targets, keyboard focus and accessible labels.
Category navigation respects Reduce Motion. Both themes use shared palette roles.
Verification is static analysis, selected unit tests and SQL permission/RPC tests;
visual checks and app builds retain their existing separate scope.

### First-run onboarding

Use the compact slide-card direction from variant 02 in
`variants/onboarding/index.html`: a minimal header with the step counter and
Close, a decorative illustration above the current setting, and a pinned footer
with Back, six progress indicators,
and Continue / Later / Finish. The flow is Language, Timer, Tasks, Theme, Pro,
Account. Derive the step counter from the step enum; wrap the 48 px navigation
targets and stack progress above actions when the full row cannot fit.
Center a dialog up to 540 px wide on larger windows. When the viewport's
shortest side is below 600 px, use a fullscreen surface in both orientations.
Paint the opaque surface behind the safe-area insets too; dimming, shadows and
dialog borders belong only to the larger-window presentation. The mobile slide
body fills the remaining height and scrolls independently, keeping the footer
at the bottom even on short slides. Use 20 px horizontal content padding and
120 px artwork on mobile, reducing artwork to 88 px below 500 px of safe-area
height. Keep labels and touch targets at their normal accessible sizes. Stack
progress above the actions on narrow layouts or with enlarged text.

Tasks and Theme use variant 02 from the onboarding HTML sketches. These two
slides replace the decorative illustration with live, noninteractive task samples.
Tasks presents Modern/Classic as preview cards, then spacing choices, the shared
sample, and Connecting lines/Grouped branch choices. Stack cards on narrow
screens or with enlarged text. Samples use the shared row padding rules and
respond to all three choices without creating tasks or exposing task actions.
Theme presents System/Light/Dark above a vertical catalog of Classic, Ocean,
Forest, Sepia, and Graphite, with swatches, descriptions, selection indicators,
and the same task sample below. Custom palette/background editing stays in
Settings. Existing Custom selections are retained until a preset is chosen.
Both slides use the existing task, palette, and theme-mode controllers and their
local persistence. Disable changes and navigation while saving; retain existing
save feedback and allow retry when palette loading fails. Navigation never resets
selections, and users who already completed onboarding are not shown it again.

Show all supported languages as selectable tiles, with System using a full row.
The Timer slide uses variant 01 of `onboarding-sketches/timer-sessions.html`:
one shared timer/session preview below the heading, followed by two labeled
choice rows. Order timer choices Circle then Bar, and session choices Compact
then Icons (leading to trailing, mirrored in RTL). New or invalid preferences
use Circle and Compact; saved choices always win. Persist both independently
through the existing focus preferences repository. The static session sample
uses `FocusRhythmRail` without creating a focus run; both choices update the
preview. Keep its height at 192 px and scale only the decorative content on
narrow screens. Choice labels retain text scaling and 48 px minimum targets,
stacking when needed. Keep the footer pinned and allow the slide body to scroll
on short screens. Preserve swipe navigation over the combined preview.
The language illustration follows the selected language. Reflow choices into one
column when space or text scale requires it. Use existing localized strings,
palette roles and bundled fonts.
Decorative previews are excluded from semantics and text scaling; setting labels
retain text scaling, selection semantics and keyboard focus. Keep touch targets
at least 48 px and prevent focus from reaching the underlying app.

Back, progress indicators and swipes over the illustration navigate between
slides without clearing saved settings. Mirror swipe direction in RTL; a swipe
on the account slide never finishes the wizard. Use the shared 180 ms fade,
finishing immediately with Reduce Motion. Keep real billing and account actions,
including purchase restoration and signed-in/error states. Account buttons use
the shared panel's compact vertical presentation. Closing or finishing still
persists completion; prevent overlapping preference writes and show localized,
retryable feedback when a write fails.

### Optional app tour

After first-run onboarding closes or finishes, offer one optional tour of Add
task, Focus, and Projects. Keep the tour on the real app surfaces: highlight
the current control without intercepting its tap, and place a compact callout
beside it. If the control is hidden by a collapsed sidebar, customized bottom
navigation, or an active Focus run, show a callout with an explicit action to
open the destination. Let users skip each step or close the tour at any time;
keep a replay action in General settings. Opening Quick Add pauses the callout
until the composer closes. Never create a sample task or start Focus on the
user's behalf. Keep the launch-offer card out of the way during the tour.

Automatically show the launch-offer mini card once per device, after onboarding
and the tour have finished and confirmed billing access has no active Pro.
Wait for preferences, access and any signed-in Stripe offer catalog to load.
Record `launchOffer.shown.v1` through the existing local preferences repository
after the card is first rendered; keep that presentation visible until dismissal
or offer expiry. Closing the app without dismissing also consumes the display.
Do not show it again on restart or in later weekly campaigns. A failed save must
not crash the app or repeat the card in the current session. Existing installations
without the flag get one eligible display; another device or cleared local data
can get a new display. Offer terms and manually opening the paywall are unchanged.

Use the active palette, 44 px or larger controls, safe-area-aware placement,
keyboard focus and screen-reader announcements. Follow the shared 180 ms popup
motion and show the final position immediately with Reduce Motion. Localize
every visible string through the existing ARB catalog.

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

Native OAuth and email links keep the exact registered
`pomodoist://login-callback` redirect, with the local `returnTo` route in its URL
fragment. Supabase includes query parameters when matching its redirect allowlist,
so putting navigation metadata in the query can send native users to the website
fallback. Web sign-in retains its `/login-callback` URL and query return path.
Read legacy query return paths as well, reject ambiguous or external destinations,
and leave authorization codes and session verification to the SDK.

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

### Shared project links

The collaboration backend builds two web addresses from the application URL: an
invitation link (`/shared/join/<token>`, sent by email) and a public read-only
link (`/shared/public/<token>`). Both are standalone routes outside the
application shell. Neither may fall through to the router's not-found page, and
both validate the token shape before any request.

The share dialog no longer shows or copies the public link: creating one is
temporarily withdrawn from the UI, while the backend action and the read-only
route stay in place so already issued links keep working and the switch can be
restored in one change.

An invitation link requires an account. A signed-out web visitor signs in and
returns to the exact link; the screen then names the pending role and joins only
on an explicit Accept action, opening the joined project afterwards. Use one
compact **440 px** card with its loading, failure and accepted states. The server
decides whether the invitation is acceptable, so report its refusal as an
unavailable invitation rather than as a signed-out or generic error.

Because these routes mount outside the application shell, they must read what
they show straight from the server instead of through a local synchronization: a
database that is not open yet must not change what a standalone screen claims.
Never present a value the screen failed to read as a known one — state the role
only when the server named it, since a guessed role tells a member they can only
watch.

A public link never requires an account and never offers editing affordances. It
renders only what the server's read-only projection returns: project and task
content, completed state, due information, author and assignee display names,
and comments. Center it within the Browse content width.

## Components and independence

- Current direct dependencies: **`shadcn_ui 0.56.3`** and
  **`flutter_animate 4.5.2`**, plus **`emoji_picker_flutter 4.5.4`** for the
  account avatar catalog. Versions are pinned in `pubspec.yaml` during
  adoption. `google_fonts`, `FlexColorScheme`, and `wolt_modal_sheet` are outside
  this phase.
- Use `shadcn_ui` for standard buttons, inputs, switches, selects, menus,
  tooltips, dialogs, and simple panels when the component preserves the required
  behavior and density. Do not create a universal wrapper for every component.
- Existing Material components may use the shared theme. Mixed dialog content
  must retain the Material ancestors its widgets require.
- Shadcn overlay surfaces (`ShadDialog`, `ShadSheet`, `ShadPopover`, and
  similar) do not insert a `Material` ancestor. Any Material widget placed
  inside one that calls `Material.of` — `ListTile`, `CheckboxListTile`,
  `SwitchListTile`, `InkWell`, `Ink` — must be wrapped in
  `Material(type: MaterialType.transparency)`, as
  `collaboration_inbox_dialog.dart` and `share_project_dialog.dart` in
  `apps/flutter/lib/features/collaboration/presentation/` do.
- Missing that wrapper fails during build: a debug build reports "No Material
  widget found."; a release build strips the debug assert and instead throws a
  null check inside `Material.of`. The framework replaces the widget with an
  `ErrorWidget`, which a release build paints as a large featureless grey box
  with no text, so the dialog looks like a blank panel rather than an error.
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
- Overflow actions use `AppActionMenu` with `ShadContextMenuItem`; pointer menus
  reuse `AppContextMenuRegion`. Do not introduce Material `PopupMenuButton` or
  `showMenu` for app actions. Keep checked, disabled and destructive states,
  localized labels and at least 44 px menu rows. Long menus scroll within the
  available viewport, including with the keyboard open. Overflow buttons choose
  the side with more free space when opened, in overlay coordinates so interface
  zoom is respected. Bound scrolling to that side, leaving room for the menu
  border, padding, anchor gap and safe-area/keyboard insets.
- Pointer context menus use the same side selection at the click position and
  exclude bottom panels from the available space. Near the bottom, expand upward
  instead of shrinking to the space below the pointer. Button and keyboard
  activation of the same menu also recompute placement when opened.
- Menubar popovers use the shared automatic anchor so actions remain inside
  the viewport near window edges. `ShadAnchorAuto` uses different follower
  alignment semantics from `CompositedTransformFollower`: bottom followers place
  the menu below, top followers place it above; use the opposite horizontal
  follower alignment to align matching trigger and menu edges.
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

### Pomo desktop companion

The Satellites layout is a desktop-only transparent, size-adaptive surface.
Keep the pet, progress ring, time capsule and 48 px satellite targets separate from
visibility/reaction policy so future layouts can reuse the same behavior. Use the
active Material palette, Geist/GeistMono typography and localized accessible
labels. Automatic appearance must not activate the app. Hiding Pomo or dismissing
its settings must not reopen or focus the main window. On macOS, generic app
activation does not restore hidden windows; explicit Dock reopen still does.
Transparent exterior
space passes input to the desktop; only visible controls accept interaction.

The pet's right-click menu offers Open application above Hide Pomo. Explicitly
opening the application restores a minimized or hidden main window and transfers
keyboard focus to it without changing the current route. Close the context menu
after activation and include both rows in the native pointer-input region. Reuse
the shared command busy/error handling; only explicit user actions raise the main
window.

On Linux, probe the actual GDK backend and compositor capabilities before opening
Pomo. X11/XWayland uses a passive RGBA utility window; native Wayland uses a
`gtk-layer-shell` top-layer surface with no exclusive zone and on-demand keyboard
focus. Apply the role and transparent GTK/Flutter backing before realization.
For native layer-shell placement, measure the available extent with transparent,
non-interactive stretched surfaces. Keep placement, drag, panel anchoring and
saved relative positions in the same usable-relative coordinate space; keep
full logical output rectangles separate for cursor/output selection. Read
committed xdg-output geometry when GDK monitor data is stale after rearrangement.
The compact panel is a GTK child popup of the companion layer surface. Open it
from the initiating input event, read its compositor-constrained bounds, and
release keyboard/pointer grabs on dismissal, parent hide and destruction.
Ordinary application/Quick Add windows activate explicitly with a current X11
server timestamp when no current GTK input event exists. Passive companion show
and restoration must never request activation. On X11, a remapped companion
accepts keyboard focus only after direct interaction; keep the settings panel
keyboard-accessible. Observe initiating input in GTK's capture phase so Flutter's
internal event widget cannot consume the popup activation serial first.
The Linux shared Flutter engine must remain resumed while any real GTK app
window has keyboard focus, including secondary Quick Add windows. Reconcile
native focus without activating windows, discard stale asynchronous replies,
and return to inactive when focus leaves the app. Retained Quick Add and Pomo
settings views restore their own input focus on native reactivation.
Linux native 3D textures are vertically inverted at the texture presentation
boundary. Keep raster fallback images and other platforms upright as authored.
On GNOME Wayland, choose the XWayland backend for the whole Linux application
before GTK initialization. The user's desktop session remains Wayland. Require
the compatible Pomo GNOME extension for companion placement and tracking; the
main application stays usable when it is missing or disabled. The extension
controls only registered Pomo utility windows, never the main app or Quick Add.
Use GNOME stage coordinates and actual Mutter window bounds as the authority;
do not mix them with GDK/X11 global pointer coordinates. Move on Shell frames,
resize only for layout/DPI changes, and read back constrained bounds. Convert
local input regions using the measured viewport/frame relationship only.
Keep the GNOME companion and compact panel in a fitted stage canvas when the
Flutter viewport differs from the Shell frame. Drawing, transformed pointer hits
and context-menu input bounds must share that mapping. Keep the canvas identity
stable so viewport changes do not recreate the live model or restart a reaction.

The main app and Quick Add keep their normal roles. Keep Pomo settings visible
while probing or unavailable; an unavailable state includes a localized
explanation, `support@pomodoist.com`, an editable mail draft and copyable
technical environment details. Never send a support message automatically.

GNOME availability includes explicit Install, Enable and Update actions with
shared busy/error handling. First local installation or replacing loaded code
may require signing out and back in; installed files alone never mean active
support. Install only after a user action, without root or network access, and
preserve other enabled extensions. Never restart the user's Shell, enable unsafe
mode or invoke Shell Eval. Explain unsupported Shell versions and keep support
contact/details accessible. Hide the companion during Overview, session lock or
bridge loss without persisting a manual dismissal. Stop dragging and tracking,
then restore only the existing enabled/visible intent after reconnection.

Linux monitor controls select either the user's screen or a pinned monitor.
Follow the pointer in X11, GNOME with its extension, KDE Plasma 6 and Hyprland; explain that Sway follows
the active workspace. Dwell for 500 ms before changing outputs, and suspend
following while the pointer interacts with Pomo, dragging, or menus/settings are
open. Native Wayland dragging uses accelerated relative-pointer motion, sampled
independently of surface-local pointer coordinates. Never add a new requested
window origin to a pointer event based on an older compositor origin: that feeds
surface movement back into the drag and causes jumps. X11 uses an anchored global
pointer position. Serialize/coalesce drag moves, settle cancelled follow work
before capturing the drag origin, and release tracking on end, hide or destroy.
The manual cross-monitor switch applies only in automatic mode; disabling
it by pinning retains its saved value. Keep monitor controls in main Settings;
the compact size panel retains its fixed dimensions. Remember monitor-relative
positions, preserve placement and the live scene on output changes, and fall
back to the primary output while a pinned monitor is disconnected without
forgetting the pin. If only automatic tracking is unavailable, keep manual
monitor selection usable. These monitor controls are Linux-only.

Pet activation opens/closes controls with a finite reaction; capsule activation
only toggles controls. Dragging never triggers a tap, and Escape collapses controls.
Greeting, Happy, Sad and Surprised are explicit events, never rebuild effects.
Sad precedes manual hiding for 900 ms (1.2-second maximum); Reduce Motion and Quiet
mode remove that delay. Motion preferences must stop the current animation as
soon as they change. Render the Blender-derived skinned 3D model in a transparent
native surface. Transitions into and out of Focus blend from the currently visible
skeleton over 700 ms with easing at both ends; other emotion changes use 250 ms.
Use spherical interpolation for bone rotations and synchronize facial/arm-volume
morphs with that movement. Switch the distinct Thinking hand/material variant
during a brief blink at the movement's midpoint; render only one opaque variant
at a time to avoid double contours and depth artifacts. Interrupted
transitions continue from the visible pose. Quiet and Reduce Motion
set the matching 3D pose immediately and stop continuous rendering. Loading or
rendering failure may use the corresponding raster still. Bundle the live model
as a gzip-compressed GLB and decode it off the UI isolate; do not replace geometry
or motion with image sequences. Pomo model/textures/stills/manifests together have
a 10,000,000-byte budget, excluding native renderer libraries. Runtime texture
maps have a maximum side of 1024 pixels; preserve aspect ratios and never upscale
smaller maps. Keep high-resolution Blender source textures for authoring.
Release glTF source data after loading scene metadata. Hidden windows dispose
the scene, GPU surface and the companion-owned native renderer engine before a
subsequent model initializes. Resizing and emotion changes preserve the window,
model and animation state. Use the shared
Focus state and commands; the companion must never own a second timer.
Active work uses the focused pose regardless of accumulated work time; idle,
ready and paused states use Calm, and breaks use Rest. Event reactions may
temporarily override these poses.
When idle, both the Start focus capsule and the play satellite start a Focus
session with the saved selected preset, falling back to the default preset.
Wait for Focus state to load before deciding to create a session. Keep the main
window in place; active-session controls pause, resume or start the ready interval.

Pomo size is a device-local preference (25–250%, default 100%, 5% control steps).
Use the same size control and controller in the main Pomo settings (including
when disabled) and the compact utility panel opened by the upper-left gear.
The upper-right Hide control mirrors the gear. The panel has its own fixed size,
is excluded from main-window anchoring, and is reused without duplicates. Prefer
placement left of Pomo, then right; clamp to the display work area. Escape,
close and blur dismiss only the panel; hiding/disabling Pomo dismisses both.
Keep the open panel at its screen position while resizing Pomo so the size
control stays under the pointer. Only clamp it if the display work area changes;
choose a new adjacent position on the next opening.

The main settings and compact gear panel share a device-local Show timer switch,
enabled by default. Turning it off hides the entire capsule, including Start
focus when idle, while retaining the progress ring and Focus controls. Hidden
capsules have no semantics or native input region. Keep the mascot position and
window size stable; only an active error indicator restores that input region.
Save through the existing preference queue and retain the saved value on failure.

Satellite buttons retain circular surfaces. Override their local Material style:
transparent hover/pressed overlays, no ink splash, an accent-colored icon on
hover/press and a circular keyboard focus outline. Never change the global icon
button theme to implement this exception. Keep targets at least 48 logical pixels
and timer text at least 12 pixels at every scale. The adaptive layout keeps
controls separate rather than shrinking their hit targets below that minimum.

Preview scale changes immediately in both settings surfaces; save slider changes
on release and the last draft on panel close. Buttons/reset save immediately;
failed writes restore the last saved scale and use the existing Pomo error text.
One computed layout supplies Flutter geometry and native macOS/Windows hit regions.
Serialize native resizing/movement/region updates and coalesce stale requests.
Skip unchanged sizes, positions and input-region configurations; compare native
frames with physical-pixel rounding tolerance. Menu/focus changes must not reset
an already configured transparent backing surface or reposition the settings panel.
Preserve the mascot center before work-area clamping. When the chosen size does
not fit, apply the largest fitting scale without overwriting the preference;
show chosen and applied percentages when they differ.

## Reports

Reports keeps a flat reading order: today's focus time and completed tasks,
seven-day focus bars and totals, project distribution, then the closest locked
achievement. Open tasks are secondary context. The interval ring compares
completed intervals with estimates on open tasks due today or earlier; these
estimates are not a separately configured daily goal. Identify today as an
unfinished day rather than comparing it with completed days.

Project distribution has a local Today / Last 7 days selector, initially Last
7 days. Changing it resets expanded project groups without changing the daily
overview or weekly chart. Live updates retain expansion by project ID. Use the
existing project colors, duration formatting, task-details navigation and
keyboard-accessible buttons. Preserve text scaling: totals stack when needed,
project rows wrap, and narrow weekly charts scroll instead of shrinking labels.
Provide a spoken chart summary including today's marker.

Count the same non-deleted completed work intervals and actual duration without
pauses as the existing daily summary. Attribute time to the project recorded on
the interval, even after a task moves. Keep unlinked, missing and deleted records
in explicit groups; unavailable tasks do not open. Zero-time distributions have
no percentage or proportion bar. Both themes use the shared palette and type.

## Apple widget family

The Quiet Typography family uses native SwiftUI system type, prominent monospaced
digits, a restrained red accent, thin rules and adaptive system backgrounds.
Focus retains the user's timer color. Tasks, Habits, Day and Progress share this
hierarchy across iPhone/iPad and Mac widget sizes, Lock Screen accessories and
Apple Watch Smart Stack widgets/complications. Keep accessory content short and
legible when WidgetKit removes backgrounds or applies system tinting.

Focus Live Activities use ActivityKit's countdown and support Dynamic Island
and system StandBy presentation. Interactive completion and pause/resume open
the app and use its existing command bridge; pause/resume validates the interval
ID. Regular widgets display cached snapshots and deep-link to existing screens.
Do not infer background execution or exact refresh timing from timeline entries.

Snapshots contain personal tasks, scheduled habits with period-aware progress,
today's schedule and a Monday-first calendar week of focus totals. Dates follow
the local calendar day. A previous day's overview shows an update prompt until
the app publishes fresh data. Empty states use real data; samples are limited
to WidgetKit previews. Treat task titles and overview content as privacy-sensitive.
Shared widget storage must never contain account credentials. Watch habits and
reports currently refresh through iPhone; direct Watch API replies retain that
same-day projection until a new iPhone snapshot arrives.

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

## Habits

The personal `/habits` destination reuses the shell, palette, Geist typography,
Lucide icons and shared controls. It is optional in bottom navigation; adding
the destination never changes an existing selection. The week strip starts on
Monday and keeps the selected day visible when moving between weeks. Today
is marked separately from the selected day. Summaries count fully completed
habits; rows retain partial progress and clamp displayed counts to the daily
goal. Future days are read-only. Ended habits remain available in Finished
so earlier dates can still be corrected.

The default List view uses a compact header, with the Monday-first week strip
and completed-habit summary beside each other when at least 700 px of content
width is available, stacked otherwise. Calendar controls retain 44 px targets;
the strip scrolls horizontally when text scaling needs more room. Preserve the
selected date, editor draft and action state when switching List / Day rhythm.
The selected view is a device-local preference; failed writes retain the previous
view and expose retry feedback. Finished remains an ordinary historical list.

List / Day rhythm use separate choice chips matching Active / Finished in size,
fill, typography, 8 px corner radius and selected checkmark. Each has a 1 px
outline: accent for the selected view and the palette border color otherwise.
Keep 8 px gaps and allow wrapping on narrow screens. Disable the view chips while
their preference is loading or saving, and hide them in Finished.

Habit signs use one optional synced `icon` value: a stable Lucide catalog name
or one complete Unicode emoji. Null uses the existing repeat icon. Keep a neutral
32 px square with 8 px corners, an 18 px icon or 20 px emoji, and a 44 px button
target. Render unknown signs with the default icon without discarding stored data.
List, Day rhythm and Finished use the same sign and keyboard-accessible picker.

The habit editor places the sign button beside the name input; selections remain
in the draft until Save. Selecting a sign from a row saves only the sign and its
update timestamp immediately. The picker offers the complete installed emoji
catalog with localized categories, search and skin tones, plus 16 habit icons.
Reset selects the default sign; Cancel discards an uncommitted choice. Keep failed
choices available for retry and block dismissal and duplicate actions during a
write. Use a dialog up to 560 px, fullscreen below 600 px, with pinned heading and
actions around scrollable content. Picker cells have 48 px targets. Reuse palette,
localization and Reduce Motion conventions from the account emoji editor.

Drift schema 11 adds one nullable habit icon column. The server validator must
accept the optional icon before releasing updated clients. Older payloads that
omit the icon retain the server value; explicit null clears it. Habit icon writes
must not revise schedules or check-ins.

Active List rows are divided into Remaining and Done, with counts. Partial goals
stay in Remaining; completing or undoing a check-in moves the row between groups.
Rows use flat dividers, a neutral repeat icon and trailing check-in/overflow
controls. Show project, schedule and optional reminder below the title. Remaining
rows show five historical days with localized weekday labels, tooltips and date /
count semantics: solid accent is complete, accent outline is partial, neutral fill
has no check-ins, and neutral outline is unscheduled or future. Multi-check-in
goals also have a compact progress bar. Done rows use muted titles, less vertical
padding and omit the history and progress bar. The summary counts each habit once.

Day rhythm groups habits into Throughout the day, Morning, Afternoon, Evening
and Night, in that order, hiding empty groups. Each heading counts completed
period goals / planned period goals, with incomplete rows before complete rows.
Automatic and Throughout the day retain a single shared goal. The By parts of
day mode selects one or more of Morning, Afternoon, Evening and Night, with an
integer goal for each. The daily goal is their sum, from 1 to 99. Each selected
period shows the habit with its own count, progress and five-day history. List
and Finished retain one row per habit; the summary counts each habit once and
completion requires every period goal. In List, adding to a multi-period habit
opens a period menu with counts; in Day rhythm, the row determines the period.
Undo removes the most recent mark in that row's period, or the most recent mark
overall in List. Check-in wall-clock time never determines its period. Night
belongs to the selected calendar date. Reminders remain one optional time and
do not multiply with periods or targets.

Automatic puts goals above one, or habits without a reminder, in Throughout the
day. Single-goal reminders resolve in local wall-clock minutes: Night [00:00,
05:00), Morning [05:00, 12:00), Afternoon [12:00, 18:00), Evening [18:00, 24:00).
Show the resolved automatic group and its reason as the draft changes.

Schedule JSON retains optional `dayPeriod` for older single-period rules and
adds optional `periodTargets` for explicit quotas. Missing fields mean Automatic;
Automatic serialization omits `dayPeriod`. Quota changes follow the selected
date's schedule revision and take effect today without rewriting past rules.
Each check-in stores its optional `dayPeriod` in one nullable local column,
introduced by the single Drift 9-to-10 migration. Both quota and check-in fields
synchronize through the existing account protocol. All new server validation
changes are consolidated into one migration, which must precede client release.
Older payloads remain valid. Older clients may drop new metadata when rewriting
schedules or marks; check-in identities, dates and counts remain intact.

Legacy marks without a period, and marks whose period is no longer selected,
fill available quotas in the fixed period order after explicit marks are counted.
Sort legacy marks by creation timestamp and ID only to make this fallback stable;
never infer a day period from those timestamps. This projection preserves stored
marks and supports period-scoped undo. Excess marks within a period are capped
for display and never complete another period's goal.

Create and edit use the shared contextual details panel, spanning the full main
area height, including the space occupied by the shell header and mini Focus
player. At 960 px of content width it is a 440 px right panel; narrower layouts
keep the Habits screen mounted behind the editor. Below the 820 px shell
breakpoint, the editor fills the
viewport and replaces the shell header, bottom navigation and floating Add task
button. Preserve system safe areas, keep Close and Save pinned, and scroll the
form between them. The `habit` query parameter controls selection and closing;
Escape and Back close the panel except while saving. Resizing preserves drafts
and the background's selected date and scroll position.
Forms retain failed drafts and expose saving, loading, empty and error states.
Use calendar date pickers, weekday
choices, a 1–99 daily goal, inclusive duration presets and an optional active
personal project. Unsupported reminders and denied permissions are explained
in the editor. Schedule frequency uses the shared scrollable segmented tabs;
weekday choices use theme-aware buttons with selected semantics. Date and time
fields use neutral outlined controls and the shared anchored picker. The reminder
label sits beside a trailing switch, following Settings. Destructive deletion
requires confirmation. No bespoke motion is introduced; shared dialog and
control behavior respects Reduce Motion.

Dates are local calendar values, event timestamps are UTC, and schedule edits
take effect today without rewriting previous rules. Local reminders share one
serialized replacement queue, cover the next 30 calendar days and occupy at
most 30 slots, preserving iOS capacity for other notifications and Focus.
Validation for this feature is unit tests, SQL tests, localization/Drift
generation and static/architecture analysis only.

## Blocking preset desk

The desktop-only `/blocking` destination follows Focus in the sidebar. Settings
links to it rather than duplicating its controls. At a content width of 820 px or
more, show the preset rail beside the selected preset's settings. Below that
width, put a horizontal preset list above the settings. Selecting a preset edits
its association without changing Focus selection or the active session.

Initially show the first three presets in their existing order. When there are
more than three, place a 44 px ghost Show all / Collapse button below the list
in both layouts. Keep expansion state in memory
for the app lifetime, including navigation away and back; a fresh app starts
collapsed. Collapsing never changes selection or brings a later preset into
the first three. Profile saves and preset refreshes preserve expansion state.

Preset tiles use a neutral surface with 10 px corners and an accent outline and
filled checkmark for selection. Emphasize work minutes on the leading side,
with labeled short and long breaks beside them and the profile status below.
Use a 320 px preset rail and horizontal tiles; stack durations when scaled text
needs more space. Keep all duration and profile labels localized and wrapping.
The profile occupies a separate full-width secondary surface below a divider,
with a 72 px minimum height, 16 px padding and a neutral shield icon. An assigned
profile shows only its name in semibold text, without a "Blocking profile"
caption. Let long names wrap and grow the footer. Preserve the localized empty
and unavailable-profile messages; assignment alone does not indicate active
protection.

Use flat sections for the preset rhythm, shared profile, blocked categories,
allowed exceptions and expandable behavior. Resource management reuses the
manual category and per-resource allow/block controls. Show all presets that
share a profile so edits have a clear scope. Profile selection saves the preset's
association for the next Focus and remains available during a session; preserve
the running session's profile snapshot. Keep exit policy locked during a session,
while categories and exceptions remain editable.

Show computer and Chrome protection as two flat Settings rows with 32 px leading
icons, a divider, and trailing read-only Enabled / Disabled pills. Use the shared
Settings row geometry to stack labels and status on narrow layouts. Apps uses
the Lucide overlapping-window icon; Chrome uses the bundled
[Google Chrome logo](https://www.google.com/chrome/static/images/chrome-logo.svg).
Enabled requires confirmation that native protection is applied, or a fresh
device confirmation of the current rules revision. Availability and extension connection remain
secondary descriptions, separate from protection state. Pair status text with
check/pause icons and theme success/neutral colors. Keep Shared/Local Focus and
the expandable device, pairing and privacy details in the footer.
Keep Automatic categories with a Pro badge and the explanation
that search assigns categories while manual choices take priority visible after
devices and before the final action. Unverified subscription access is a pending
or error state; it must never be presented as Free. Existing assignments survive
subscription expiry. Pending writes and failed writes remain explicit.

Keep the preset list free of a timer or current-task summary.
The final action starts that preset when idle and returns to the current Focus when
a session exists. Missing assigned profiles block starts until reloaded or
explicitly replaced, including an explicit choice of no blocking.

## Held-modifier shortcut hints

Desktop native and desktop web views reveal informational shortcut hints after
one second of holding Command (macOS) or Control (Windows/Linux) alone. Each
window owns its observer and timer. Shortcut execution remains immediate and
unchanged. An ordinary key cancels the hold until the modifier is released;
autorepeat never rearms it. Additional modifiers retain already visible hints.
Release, window blur, context changes, recording a shortcut, and disposal reset
hints immediately. Touch interfaces retain their existing layout.

Use `ShortcutHintsHost` inside the zoomed application root, and
`ShortcutHintsScope` at existing local keyboard handlers. Focused local scopes
replace shell hints; modal scopes own their context for their mounted lifetime.
Unregistered dialogs and open context menus suppress shell hints. Recorders
explicitly disable hints. Register only commands handled in that context, and
omit unavailable actions. Plain Enter/Escape/navigation hints explain that the
primary modifier must first be released. Do not duplicate system text editing.
Shell badges use `shellKeyboardViewModelProvider`, existing command
names and binding formatting, including remaps and required modifiers. Blocking,
Habits and projects receive no invented navigation shortcuts.

Keep navigation labels and task counters stable while badges toggle. Search has
no permanently visible shortcut label. Focus badges show both configured Focus
bindings, including the alternate (Command/Control F by default).
Command/Control E toggles Pomo's persisted enabled preference through its existing
controller, guards concurrent writes and closing, and reports failures. The Pomo
button shows the configured shortcut on hold; the binding is editable alongside
the other app shortcuts. Adding it preserves existing user bindings, choosing a
free modified key when E is occupied.

On small icon buttons, anchor the full badge in an overlay sized to the viewport; flip its
placement near window edges instead of squeezing it into the button. Do not
show a floating shell help panel when the modifier is held; retain the in-place
badges and compact local hints. Compact dialog hints sit beside their actions,
with reserved space and wrapping for scaled text.
Hints ignore pointer events and cannot receive focus. Use the current palette,
Geist/GeistMono and Lucide icons in both themes. Fade in with `AppMotion.popup`
(180 ms), respecting Reduce Motion; removal is immediate. No preference or
persisted state is added. Validate hold logic and command projection with unit
tests, plus static and architecture checks; visual acceptance remains manual.

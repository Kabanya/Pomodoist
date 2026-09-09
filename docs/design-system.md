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
Switching editor tabs selects which palette to edit without changing brightness
mode. Invalid HEX input in either tab blocks saving. Saving errors keep the draft
open for retry. The editor itself uses Classic so even an unreadable custom
palette can be repaired; its two previews show the actual custom colors.

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
Navigation waits for pending title and description edits and retains failed
drafts. Close and Escape restore focus; nested menus handle Escape first.

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
phrase. The phrase is the only metadata state: clearing a token reveals the
existing context defaults. Preview and creation use the same parser, configured
duration and clock. Preserve IME composition, selection and unrelated tokens.
Quoted metadata names remain literal during date normalization. Ready voice
subtasks preview the project inherited from their parent's current phrase.
Details stay below the editable input; the separate window scrolls when needed.

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

Keep selection local until confirmation. Cancel, Escape and Back dismiss the
picker without changing the source phrase or saved schedule; restore focus to
the invoking control. Preserve each caller's date limits and interval rules.
Use shared popup motion and Reduce Motion, constrain panels to the viewport,
and keep their content reachable with scrolling and an on-screen keyboard.

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
followed by creation, Focus and full-search actions. Reuse local task data and
filtering. Task results open contextual details; creation opens an editable draft.
Arrow keys, Enter and Escape work without disrupting IME composition; restore
focus on closing. Keep result selection tied to stable identifiers and revalidate
a result before acting after data changes.

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
- Keep keyboard focus visible. Task row actions must be available through
  keyboard focus and touch, not only hover.
- Communicate state through text, icons, or semantics as well as color.
  Icon-only actions need accessible labels and tooltips where appropriate.
- On narrow screens, use wrapping, existing adaptive layouts, and scrolling.
  Do not shrink text or touch targets simply to eliminate overflow.

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

Test changed logic: theme conversion, animation events, bulk limits, state
preservation, duplicate suppression, and Reduce Motion. Reuse existing tests.
Do not add tests that only repeat constants or a separate architecture solely
for testability.

The user performs visual and manual checks. Widget, golden, integration, and
end-to-end tests, builds, app launches, browser checks, emulators, and profiling
are outside the agent's default styling scope unless the user requests them
separately. Passing analysis or unit tests does not establish visual quality.

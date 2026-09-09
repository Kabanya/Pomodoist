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

The table above describes **Classic**, the default palette. **Ocean** uses cool
blue accents and surfaces; **Forest** uses green accents and surfaces. Each theme
is a pair of light and dark palettes. Selecting a pair never changes the separate
System / Light / Dark preference or its shared web cookie.

Built-in themes are immutable. Customizing one creates a named local copy; copies
can be edited, renamed, duplicated and deleted. `AppThemeSettingsController`
persists the selected identifier and custom pairs together in SharedPreferences.
The shared desktop provider scope keeps Quick Add and the main window aligned.

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

### Today

Keep daily context to one text summary and one active Focus strip. The strip and
global mini player share the existing session, interval and clock providers.
Only replace the global player once the run and interval agree and remaining
time is available. Completed-today rows form a collapsed group with independent
selection, using the local completion day.

### Quick Add

Parsed date/time, project and priority chips edit recognized spans in the source
phrase. The phrase is the only metadata state: clearing a token reveals the
existing context defaults. Preview and creation use the same parser, configured
duration and clock. Preserve IME composition, selection and unrelated tokens.
Quoted metadata names remain literal during date normalization. Ready voice
subtasks preview the project inherited from their parent's current phrase.
Details stay below the editable input; the separate window scrolls when needed.

### Task row styles

Modern is the default shared task row layout; Classic preserves the previous
layout. The local `tasks.listStyle` preference changes only shared rows, including
search, planning lists and subtasks. Both styles share task actions, selection,
drag-and-drop and motion. Modern keeps desktop metadata and action slots aligned,
wraps metadata on narrow screens, and reveals actions on hover or keyboard focus.
Touch actions stay available. Project and timing colors retain their semantics.
Custom Kanban and Timeline blocks keep their specialized layouts.

### Focus completion actions

When the current task is open and a next scheduled task is available, completing
it and starting the next task is the primary action. Completing only the current
task and keeping it open remain explicit alternatives. Finishing a timer never
automatically completes a task. Show the next task alongside the actions; retain the
existing scheduling order and roll back task completion if starting Focus fails.
Guard repeated clicks and scope asynchronous dismissal to the completed run.
Actions remain independent of the decorative animation and Reduce Motion.

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

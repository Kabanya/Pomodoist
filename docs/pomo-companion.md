# Pomo desktop companion

Accepted direction: HTML concept 10, “Satellites”. The original 15 HTML concepts
and approved Blender sources are preserved. The runtime now uses a skinned glTF
model exported from the approved 3.0.2 Blender source. Future
layout variants are outside this iteration. Size is configurable locally.

## Delivered structure

1. Device-local preferences and pure reaction/focus policies under `domain/models/pomo`.
   Enabled defaults to false. Manual dismissal persists and overrides automatic
   visibility. Explicit restoration greets once and may show idle in focus-only
   mode until the next run ends. Quiet and Reduce Motion use static poses.
2. Ephemeral local completion notifications, staged inside owner-bound database
   transactions and published after commit. Task completion includes Kanban and
   descendants; undo/recomplete gets a new operation ID. History reads, remote
   hydration and rollback do not publish. Work-interval completion uses its stable
   interval ID. No new timer, completion coordinator, or statistics are introduced.
3. A single shared-scope desktop window, supported on macOS, Windows and capability-gated Linux. The
   local `multiview_desktop` 1.2.1 patch creates passive windows without activation.
   Pomo and Quick Add are utility windows: neither can replace the main app anchor.
   Native hit regions cover the pet, capsule and visible satellites only. Saved
   positions use display identity and work-area clamping; visible windows recheck
   display geometry and update their input region after a move.
   On macOS, both the native window and its `FlutterViewController` use a clear
   background. Clearing only `NSWindow` leaves Flutter's default black backing
   surface visible around the transparent mascot and controls.
4. Presentation: Pomo with a remaining-time ring and capsule. Pet activation toggles
   controls and requests Surprised; capsule activation only toggles controls.
   Drag gestures move the native window. Escape collapses controls.
   Right-clicking the pet opens the shared context menu with Hide Pomo, using the
   same persisted manual dismissal as the hide satellite. Escape and window blur
   dismiss the menu. Its visible bounds temporarily join the native input regions;
   the transparent exterior still passes input through to the desktop.
   The left satellite adds a task using the existing Quick Add window,
   right starts/pauses/resumes, top
   completes the current interval, upper-right hides; upper-left opens the compact size settings panel. Idle Start Focus opens the
   main Focus route. Repository and presentation checks respect ready, strictMode
   and allowPause restrictions.
5. Settings → Tasks & Focus and the Focus overflow menu expose restoration/hiding.
   Preferences include enable, focus-only, quiet, reduced motion, scale and position reset.
   Labels use the shared localization system; surfaces use the active app palette.
6. Native 3D rendering: `PomoModel` uses Thermion/Filament with a transparent
   Flutter texture, a shared skeleton, facial morph targets and eight glTF clips.
   Blender procedural materials are baked into color, roughness and normal maps;
   lighting and animation run in real time. Existing WebP stills are used only
   while loading or after a renderer failure; animated WebP is no longer played.

## Size and compact settings

The gear opens one reusable 320×256 utility window, preferably left of Pomo,
otherwise right, clamped to the display work area. It does not replace the main
app anchor. Escape, close and blur dismiss only this panel; hiding/disabling Pomo
closes it too. Main Settings → Tasks & Focus → Pomo always exposes the same size
control, including while Pomo is disabled; changing size never enables Pomo.

Size ranges from 25% to 250%, default 100%, in 5% control steps. Slider changes
are shared live drafts, committed on release or panel close; −/+, reset save
immediately. Both surfaces observe the same controller. Write failures restore
the saved value and display the existing localized Pomo error.

`pomo.preferences.v1` retains its key and existing fields, adding numeric `scale`
(as a factor, e.g. 1.35). Missing, nonnumeric or nonfinite values default to 1;
finite numeric values clamp to 0.25–2.5. No account/server schema changes.

`PomoLayout` supplies the pet, ring, capsule and all visible native input regions.
Controls stay at least 48 px and timer text at least 12 px, with nonoverlapping
rectangles throughout the range. Satellite hover/press changes only icon color;
keyboard focus uses a circular outline. The host resizes the existing window,
keeping the 3D scene mounted, serializes native layout transactions and
coalesces intermediate slider requests. Unchanged native sizes, positions and input
regions are not reapplied. Physical-pixel rounding is treated as settled geometry;
menu/focus changes do not reset transparency or reposition the settings panel. The mascot center is preserved before
work-area clamping. The applied scale temporarily shrinks to fit a smaller screen;
the chosen scale stays saved, and both percentages appear when different.

## Reaction contract

Priority: Sad > Happy > Greeting > Surprised > background. No reaction queue.
Greeting occurs once on actual appearance. Happy follows a successful local task
or work-interval completion. Events within one second coalesce; bulk completion
cannot queue celebrations. Tap reactions have a two-second cooldown. Manual hide
persists dismissal immediately, presents Sad for 900 ms, and caps the wait at
1.2 seconds. Disable is immediate. Quiet/reduced-motion closing has no decorative
wait. Hidden events are dropped, not replayed on restoration. Background state
uses calm, focused, resting and tired poses; tired starts after 50 minutes of
actual work across runs since the last completed break, excluding pauses.

Calm, Focus, Rest and Tired each repeat their own clip. Focus uses the approved
thinking pose with a hand at the chin (6 seconds); Rest and Tired each loop for
4 seconds. Ready/paused intervals still select Calm. Event reactions remain
finite and temporarily override the current background. Quiet, app Reduce Motion
and system Reduce Motion show the static pose belonging to that same emotion.
Quiet and Reduce Motion stop the render loop and set the corresponding 3D pose.
Loading or renderer failure shows the existing still for the current emotion.
Hidden windows release the texture, scene and animation resources. Changes are
applied sequentially, coalescing intermediate requests; obsolete asynchronous
work cannot restore a previous emotion after disposal.

Animated emotion changes blend skeletal poses and facial morphs over 250 ms.
The approved Thinking scene has distinct hand geometry and eye materials, so
its mesh variant also fades over those 250 ms while sharing the same skeleton.
These are live meshes, not an image crossfade. Reduced motion switches immediately.
Background clips loop; event clips remain finite. Resizing only changes the
render surface; it does not reload the model or restart the current clip.

## Validation contract

Unit tests and automated static checks are the default validation scope. App
launches and manual inspection require an explicit request; the size-settings
iteration includes a separately authorized macOS runtime check. Unit coverage includes
visibility/persistence, event priority and deduplication, strict/ready policies,
fatigue calculation, geometry, commit/rollback/Kanban completion, and work-interval
notifications. Existing repository regression tests cover shared mutation paths.

Run from `apps/flutter` with the pinned SDK:

```sh
../../.fvm/flutter_sdk/bin/flutter analyze --no-pub
../../.fvm/flutter_sdk/bin/flutter test --no-pub test/pomo test/kanban_repository_test.dart test/csv_task_import_test.dart test/core_features_test.dart test/account_recovery_store_test.dart
../../.fvm/flutter_sdk/bin/dart run tool/check_architecture_types.dart
python3 tool/pomo/validate_assets.py
```

Native Swift source is parsed/typechecked without opening the application.
Windows runner compilation and actual desktop behavior require their respective
platform validation; Dart tests and static checks do not establish visual quality
or OS behavior. Native host failures are exposed through the Pomo settings/error
state rather than treated as successful activation.

## 3D integration status

The real-time renderer is under development on `develop`. The application now
requires macOS 13 or later to support Thermion 0.5.0; macOS 12 is no longer
supported. CocoaPods and all application Xcode configurations use this minimum.
The existing macOS 14 widget extension minimum is unchanged. The full macOS build
has not been rerun after this change: current validation is limited to unit tests
at the user's request. The isolated `build/pomo-model-preview` harness targets
macOS 13 and does not load user accounts or Focus sessions. Windows runtime
verification is pending.

The pinned SDK passes all 37 Pomo tests and `flutter analyze`. Blender roundtrip
validation covers all eight clips' first, last and static poses; the largest
vertex difference is 0.000115 units. The isolated macOS harness completes 29
scripted emotion/motion/size/visibility updates without runtime errors, including
an interrupted transition. Native RGBA captures have transparent exterior pixels;
two explicitly rendered Focus frames differ. Interactive application inspection
and continuous background frame scheduling have not been visually verified.
Runtime captures and logs are under `build/design/pomo/2026-10-19-realtime-3d`.


## Compact 3D asset pipeline

The runtime master is `pomo_3_0_2_all_animations_linked.blend`. Its authoring
scenes and high-resolution geometry remain unchanged. The application exports
its eight supported emotions; the master's extra overview/study scenes are not
additional application states.

All bundled Pomo assets (compressed model, manifests and eight fallback stills)
must total at most **10,000,000 bytes**. Thermion's native libraries are measured
separately. This is an installed asset budget, not a guarantee about RAM or the
compressed installer. Only `pomo.glb.gz` is bundled; the raw intermediate stays
under `build/`. Loading decompresses it in a worker isolate and passes a standard
GLB buffer to Thermion. Corrupt assets use the existing still/error path.

Run from the repository root:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background apps/flutter/assets/branding/mascot/pomo_3_0_2_all_animations_linked.blend --python-exit-code 1 --python apps/flutter/tool/pomo/export_model.py -- build/pomo-model-export
python3 apps/flutter/tool/pomo/compact_model.py build/pomo-model-export build/pomo-model-candidate
/Applications/Blender.app/Contents/MacOS/Blender --background apps/flutter/assets/branding/mascot/pomo_3_0_2_all_animations_linked.blend --python-exit-code 1 --python apps/flutter/tool/pomo/validate_model.py -- build/pomo-model-candidate
python3 -m unittest discover -s apps/flutter/tool/pomo -p 'test_*.py'
```

After geometry and render comparison, replace only `pomo.glb.gz` and
`manifest.json` in `apps/flutter/assets/pomo/model/` with the candidate files,
then run the Pomo tests, including the complete bundle-size check.

### Repository storage and model updates

Keep the runtime asset at the stable path
`apps/flutter/assets/pomo/model/pomo.glb.gz`. This one self-contained file contains
the geometry, skeleton, textures, morph targets and eight application animation
clips. `.gitattributes` tracks this exact path through Git LFS with
`filter=lfs diff=lfs merge=lfs -text`. Git stores a small pointer containing the
content hash and size; Git LFS stores the model bytes separately. The working
tree still contains the complete compressed model at the same path. Other images
and media are not automatically moved to LFS by this rule.

Install Git LFS before cloning or updating the project, then run `git lfs install`
once on that machine. A normal clone/checkout downloads the model through LFS.
For an existing clone, or after a checkout that skipped LFS downloads, run
`git lfs pull` before building. Flutter build/test checkouts in GitHub Actions
set `lfs: true`; the Linux build container installs `git-lfs` before checkout.
Do not build with the text pointer in place of the model.

When changing the model or animations, edit the Blender source, export and
validate a candidate using the pipeline above, then replace the existing runtime
file under the **same filename and path**, together with its matching
`model/manifest.json`. Do not add version suffixes to the bundled filename.
Record the source version, source/model hashes, clip metadata and packing settings
in the manifest instead. If the Blender source filename or clip definitions
change, update the export configuration to match. Regenerate affected fallback
stills and their root manifest so loading/error poses match the new model.
Commit the asset, manifests, affected stills and any exporter changes together
using normal `git add`/`git commit`. The LFS clean filter stages a pointer for the
model; the pre-push hook uploads its bytes to the remote LFS store when a push is
explicitly authorized. Git history retains the version pointers, while LFS
retains the corresponding model contents. This setup does not migrate or rewrite
existing commits, including the local `pomo-huge-old` and `video-pomo` snapshots.

The compressed model, manifests, fallback stills, runtime code, export tools and
tests belong in the repository. Raw export intermediates, render comparisons and
caches remain under ignored `build/`. Blender authoring files under
`apps/flutter/assets/branding/mascot/` are currently ignored by `.gitignore`,
including the linked master and its dependencies. A fresh clone can build the
application from the bundled asset, but re-exporting requires those local Blender
sources. Keep a separate backup of that authoring project; the Git repository
does not currently preserve it.

The exporter preserves skeletal skinning and facial/arm-volume morph animation.
Only a dense hand above 10,000 vertices is simplified, to at most 16,000
triangles; the ordinary hands and body retain their geometry. Subdivision on the
dense hand is omitted in the runtime copy. The compact packer shares identical
buffer blocks and rounds positions to a 0.00001-unit grid, normals/tangents to
1/4096 and UVs to 1/65536. Animation times and weights are not quantized. Color
maps retain up to 4096 pixels; normal/roughness maps use up to 2048 pixels. PNG
texture pixels and the resulting GLB are then compressed without further loss.
The model remains real 3D geometry with editable joints and morph targets, not
rendered animation frames or camera-facing image planes.

The manifest records source/model hashes, compressed and decoded sizes, clip
scenes/timing/static poses, hand simplification and packing settings. Bake caches
are keyed by source hash and export profile. The Blender validation compares both
source-to-runtime and runtime-to-source surface distances at the first, last and
static poses, including the simplified hand. The maximum accepted distance is
0.001 scene units. Render comparisons are also required: surface-distance tests
cannot establish texture quality or native renderer behavior.

Dense accessors are intentional: sparse morphs previously lost geometry on
Metal. Bilinear atlas sampling without mipmaps avoids neighboring UV-island
bleeding. Quiet/Reduce Motion still stop the live 3D render loop at the matching
pose. The existing clip selection, event priorities and runtime transitions stay
unchanged by storage optimization.

## Rebuilding fallback stills

`tool/pomo/export_config.py` defines the eight source scenes and selected static
frames in the same 3.0.2 master. Render only that pose into a new per-clip directory
(the exporter rejects stale provenance). From `apps/flutter`:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background assets/branding/mascot/pomo_3_0_2_all_animations_linked.blend --python-exit-code 1 --python tool/pomo/render.py -- ../../build/pomo-stills/Focus Focus --metal
python3 tool/pomo/encode.py ../../build/pomo-stills assets/pomo Focus
python3 tool/pomo/validate_assets.py
```

Repeat for the other names from `CLIPS`; run one GPU export at a time. The
encoder writes lossless transparent 384×384 WebP stills and merges their source
metadata without changing other poses. Supplying a complete frame root to
`validate_assets.py` additionally compares each still with its Blender render.
Animated WebP files and their encoder are no longer part of the pipeline.

## Distinct-emotion integration verification (2026-10-19)

- 23 Pomo unit tests passed: 20 policy/controller/repository/lifecycle cases and
  three Flutter codec cases covering full loops, repeat boundaries and stills.
- Two export regression tests passed, covering stale/unverified/missing frames,
  merged-frame durations, still selection and preservation of unrelated assets.
- Flutter analysis passed. All nine manifest entries passed asset validation;
  the three new stills matched their selected source frames.
- The asset-only comparison presents the shipped WebP clips together. Application
  UI was not launched or manually verified; no app was connected for hot reload.

## Original companion verification results

- 190 selected unit tests passed, including repository regressions and Pomo policy,
  lifecycle, preference recovery, commit notifications, geometry and fatigue tests.
- Flutter analysis completed without issues.
- Swift bridge and vendored macOS plugin typecheck against the pinned Flutter
  framework; no application was launched.
- Asset validation passed for all six clips/stills.
- Full architecture analysis reports four existing violations in
  `focus_sound_settings_view_model.dart`; no Pomo violations remain.
- A fresh source review identified main-window anchoring, preference-read recovery
  and open-pause accounting defects. All were fixed; new regression tests reproduced
  the latter two before the fixes. Reduce Motion during a pending Sad close also
  has a regression test and immediately releases the decorative delay.
- Windows native code has not been compiled on a Windows toolchain here. No native
  runtime or visual acceptance is claimed.

## Size/settings verification (2026-10-19)

- 35 Pomo tests passed, including preference compatibility, the complete size
  range, screen fitting, panel placement/lifecycle, two-observer synchronization,
  pending-write reset ordering, native update coalescing and pixel-rounded frames.
- Flutter analysis passed using the pinned FVM SDK. The macOS development build
  succeeded after the native transparency/hit-test update.
- The development app was exercised with the main size control; the user also
  confirmed scaling works. The active Focus run was not started, paused, skipped
  or completed by these checks.
- Runtime interaction exposed window flicker. Native layout application now skips
  unchanged mutations, collapsed-menu notifications and panel repositioning. The
  macOS bridge configures transparency once per attachment and preserves its
  hit-test timer, changing mouse pass-through only when necessary.
- A fresh launch with the native fix restored the running Focus interval and
  continued its countdown; the connected runtime reported no errors. An earlier
  debug run logged lifecycle transition assertions; these did not recur during
  the fresh-launch observation.
- Automated UI routing to the passive companion window was unreliable; full
  visual acceptance of hover, keyboard focus and blur/Escape remains unconfirmed.
  Windows native compilation and runtime were not checked on this macOS host.

## Linux integration and verification

The Linux integration targets composited X11/XWayland, GNOME Wayland through
its Pomo extension and XWayland compatibility mode, and native Wayland
compositors exposing layer-shell protocol v4 or later. The vendored multiview plugin receives
transparency, passive-show and layer-role options before GTK realization.
The application runner exposes the same `pomodoist/pomo_window` method channel
as the other desktop platforms. Its `environment` and `cursor` probes and
`bounds`/`move` geometry use GTK logical coordinates outside the GNOME bridge;
display scale is metadata, not another coordinate multiplier. GNOME placement
uses Shell stage coordinates and actual Mutter frame bounds instead. Input regions include only the pet, visible
capsule, controls and context menu. The native Wayland placement uses output
selection and anchored layer margins rather than `gtk_window_move`.
Manual Wayland dragging uses `relative-pointer-unstable-v1` accelerated logical
deltas, independently of surface-local motion or a delayed surface commit. X11
uses global pointer displacement from the start of the drag. GTK frame-clock ticks apply movement directly at the display's refresh rate;
Dart samples at 33 ms intervals only for monitor policy and saved placement.
The host drains the last sample before releasing tracking. Wayland keeps the
source surface alive throughout the grab and transfers to a permitted destination
output after release, because changing layer-shell outputs remaps the surface
and loses the pointer grab. A compositor without relative-pointer
cannot start a native Wayland drag; other supported Pomo controls remain usable.
The vendored MIT protocol client links `wayland-client >= 1.20`; its license is
included in AppImage notices.

The single companion can follow the user's screen or remain pinned to an
output. X11 uses the native pointer probe; KDE Plasma 6 loads a temporary,
per-process KWin script through session D-Bus; Hyprland uses read-only socket IPC.
Sway follows the active workspace because its standard IPC does not expose the
global pointer location. Other layer-shell compositors retain manual output
selection when no tracking adapter is available. Temporary scripts and pointer/workspace
tracking resources stop when hidden, disabled, pinned or disposed; lightweight
environment/topology refresh remains active for settings and reconnection. Adapter
failures are retried and do not disable a working desktop surface.

`pomo.preferences.v1` adds `displayMode` (`followUser` by default),
`allowCrossDisplayDrag` (true), optional `pinnedDisplayId`, and `displayPositions`
with finite monitor-relative `x`/`y` offsets. Existing fields and defaults remain
compatible. Reset clears position history while preserving the monitor policy.
Monitor identities use GTK manufacturer/model/physical dimensions; identical
panels receive connection-lifetime suffixes because GTK3 lacks a portable
connector identity. Reconnecting indistinguishable panels may therefore require
reselecting a pin. GTK work-area information is compositor-dependent; verify
placement around panels during native acceptance.

Unsupported environments retain the Pomo section with a localized explanation,
a support mail draft, and a copy action containing the support address,
desktop/session/backend/distribution and app version. The application never
sends mail. The Linux distribution bundles `libgtk-layer-shell.so.0` with its
license/source notices, and build/setup tooling installs its development files.
AppRun prepends its bundled data directory while preserving the XDG default
`/usr/local/share:/usr/share` when `XDG_DATA_DIRS` is unset or empty. GTK still
needs the host MIME database and icon themes; hiding those paths can abort a
GNOME launch while loading the client-side titlebar icons. Explicit nonempty
data paths remain unchanged after the bundle prefix. Launcher regression tests
cover all three cases.

Automated validation covers preferences, capabilities, IPC parsing/lifecycle,
monitor selection/dwell/suspension, native geometry, creation-option encoding,
packaging, and static analysis. Native builds and visual acceptance require a
separately requested stage: X11/XWayland, KDE Wayland, Hyprland, Sway, and the
GNOME extension installation/activation states, with multiple monitors and mixed DPI. Dart tests and
native source syntax checks do not establish compositor behavior or GPU output.

The user authorized native build/run verification on 2026-10-23. A Flutter 3.47.0
development debug build runs on KDE Wayland with NVIDIA graphics. The live model
loads from the hydrated Git LFS asset. Linux texture presentation flips its
bottom-up GL rows; raster fallback images retain their original orientation.
The Linux window color decoder uses the same `backgroundColorA/R/G/B` wire fields
for creation and later updates, so applying options preserves transparency.
Pixel orientation tests cover Linux, macOS and Windows; native color contract
checks cover transparent and default opaque colors. The user confirmed upright
rendering, transparent exterior and satisfactory native frame-clock dragging on
KDE Wayland. A separate isolated XWayland app probe rendered the live model
upright after the EGLImage bridge fix. Runtime captures and logs are under
`build/design/pomo/2026-10-23-linux-runtime`. Other compositor acceptance,
monitor/DPI transitions and complete interaction acceptance remain pending.
Losing a native drag session cancels the Dart drag so output fallback can proceed;
legacy layer-shell close events from a removed output preserve the companion.

The Linux CMake integration resolves Thermion 0.5.0 native headers through the
application's explicit package map, including symlinked build directories and
encoded file URIs. A version-checked build-local Thermion override uses an X11
EGLImage-to-2D bridge and restores temporary EGL/GLX state; the shared dependency
cache remains unchanged. See `apps/flutter/linux/thermion/README.md` for the
upstream source checksum and offscreen GPU regression procedure.
Arch setup includes Git LFS for the model and libc++/libc++abi
for the renderer's native asset build.

The Thermion plugin retains sibling `$ORIGIN` lookup in its build ELF because
Flutter copies plugin files into the bundle without rewriting their install
RPATH. A relocation regression deletes the original build and native-assets
directories before loading the bundled dependency without `LD_LIBRARY_PATH`.
On X11, primary, secondary and modal Flutter view realization also preserves
GTK's current GLX context/cache and any native EGL binding. Flutter 3.47's
compositor initialization temporarily binds EGL, while GTK3 paints through GLX;
leaving that binding active can crash GTK on its next paint. The scoped native
helper clears the temporary binding and restores the previous API, context and
surfaces. Deferred window destruction and final reference release use the same
scope for shader cleanup; a destroyed GTK drawable is never restored. Wayland
retains its existing behavior. Unmapped-window GLX/EGL lifecycle regressions run
on software Mesa under Xvfb in CI.


### GNOME / standard Ubuntu integration

The first GNOME targets are Ubuntu 24.04 (Shell 46), 26.04 (Shell 50), and
26.10 (Shell 51), in their normal GNOME Wayland sessions. Other Shell majors
require a compatibility update and native acceptance before being declared
supported. The Linux binary chooses XWayland before GTK initializes, including
when launched directly or from a user installation; AppRun is not the policy
owner. Without a usable XWayland connection the main application can still use
Wayland, but Pomo reports the missing compatibility capability.

The per-user extension `pomo@pomodoist.com` preserves the existing Flutter and
Thermion renderer. It exports the versioned `com.pomodoist.Pomo.Gnome1` session
D-Bus interface. The native GIO bridge forwards existing Pomo window commands
and feeds Shell environment/pointer snapshots to the Dart monitor policy. Only
windows with a registered random role token, matching caller PID and an allowed
Pomodoist flavor application ID can be controlled. Registrations and subscriptions
are retired on caller loss. Main-window and Quick Add roles are never changed.

All global placement is authoritative in GNOME stage logical coordinates,
including monitor work areas, pointer samples over native Wayland applications
and actual `Meta.Window` frame bounds. Dragging captures the actual frame and
Shell pointer together and applies their delta on Shell frames through
`move_frame`; it never derives the origin from delayed GTK pointer events or
`XQueryPointer`. Resize requests are separate from movement, and constrained
results are read back. Local Flutter input regions use a measured viewport/frame
relationship rather than a guessed global XWayland scale. A GNOME-only fitted
stage canvas aligns the rendered companion/panel and transformed pointer hits;
menu bounds are mapped back into that same canvas before input-region encoding.
The canvas identity stays stable across viewport changes. GNOME display IDs have
their own namespace, so older saved X11 positions are not reinterpreted.

The existing 500 ms follow dwell, interaction suspension, pinning, cross-monitor
switch and disconnected-monitor preference recovery remain in the Dart policy.
Overview, session lock, extension disable or bridge loss stops native dragging
and hides utilities without writing a manual dismissal. Restoration follows the
existing enabled and visibility intent. The extension retains no cursor polling
or frame callbacks when their leases are inactive.

Both the ordinary Linux bundle and AppImage contain the extension's runtime
sources and a reproducible ZIP, built with the Python standard library. Settings
provide explicit installation, enable and update actions without administrator
rights or a network connection. First installation on an already running GNOME
session can require signing out and in again. A loaded older extension also
requires a new login after replacement; files on disk are not proof of active
protocol compatibility. Installation preserves other enabled extensions and does
not silently bypass the user's global extension-disable setting. Shell Eval,
unsafe mode and forced Shell restarts are not used.

The user authorized an existing-VM validation stage on 2026-10-23. The available
VM runs Arch Linux, GNOME Shell 51.1, Wayland, XWayland 24.1.14 and Mesa/virgl on
one 1280×800 monitor at scale 1. This is a compositor integration check, not
Ubuntu release acceptance. Offline extension installation required a new login.
After correcting bundle library lookup and the X11 realization binding leak,
the ordinary animated application passed ten cold starts with actual 3D imports,
no startup shader warnings and no crashes; the previous candidate crashed in
two of three starts. Observed interactions include transparent click-through to
a native Wayland window, Shell pointer samples over that window, actual Pomo
dragging, passive restoration, settings and Quick Add creation, manual
hide/show, extension disable/recovery and Overview suppression. Evidence is
under `build/design/pomo/2026-10-23-gnome-runtime`.
The final lifecycle candidate additionally passed three cold starts and five
real Quick Add open/close cycles without initialization or cleanup shader
warnings. The application and companion remained running afterward, with the
native Wayland target retaining focus. This also validates the deferred
destruction binding scope; it does not complete the remaining Ubuntu matrix.

The user additionally authorized Ubuntu and Xubuntu VM verification on
2026-10-23. A separate Noble guest uses the official Ubuntu cloud image with
the official `ubuntu-desktop-minimal` and `xubuntu-desktop` packages, tested in
separate login sessions. This checks desktop-package integration rather than an
ISO installation. The runtime is Ubuntu 24.04.5 LTS, GNOME Shell 46.0 on Wayland
or Xfce 4.18 on composited X11, with accelerated Mesa 25.2.8/virgl and one
1280×800 display at scale 1. Native development-flavor debug and release bundles
were built separately on Ubuntu 24.04 with Flutter 3.47.0 and Thermion 0.5.0;
the runtime guest has the documented native library prerequisites, without a
compiler or Flutter SDK. Build and runtime evidence is under
`build/design/pomo/2026-10-23-ubuntu-runtime`.

The native release bundle passed three animated cold starts in each desktop.
GNOME's actual in-app offline extension installation displayed the new-login
requirement and became active after signing in again, preserving Ubuntu's own
extensions. Observations include the upright 3D model, Shell pointer samples and
transparent click-through above a native Wayland client, passive focus,
dragging, manual disable/enable, extension recovery and Quick Add. In Xubuntu,
Pomo uses the existing X11 path without the GNOME extension; direct Quick Add
typing and Escape were verified from the desktop. An initial empty-Escape
observation did not reproduce in that deliberate keyboard check.

The first Ubuntu release AppImage exposed the missing XDG fallback described
above: the identical file failed on GNOME with an unset data path and rendered
successfully when only the standard data path was supplied. The repaired
AppImage passed direct GNOME launches with the variable both unset and empty,
without an external workaround. Its 149 ELF payloads are byte-identical to the
original release artifact; only the launcher changed. Runtime mappings confirm
that libc++, libc++abi and Thermion load from the AppImage mount. GNOME logs also
contain AT-SPI/atk-bridge warnings; accessibility compatibility was not accepted
by these rendering checks.

The repaired AppImage also passed Xubuntu launch, upright 3D, transparent
click-through to an X11 client, dragging with unchanged surface size, persisted
hide/show and three direct-typing/Escape Quick Add cycles. However, manual Enable
Pomo reproducibly transferred keyboard focus from the main window to the
companion in two checks, still present at 500 ms and 2.5 seconds after showing.
This fails passive-show acceptance on Xfwm despite the existing GTK
`focus-on-map=false` policy; it remains an open X11 integration defect. The
transparent-corner check itself preserved the underlying client's focus. Do not
declare Xubuntu acceptance complete until showing/restoring Pomo also preserves
focus. Logs, the focus-reproduction JSON and final captures are in the same
Ubuntu runtime evidence directory.

One first GNOME release Quick Add close emitted
`Failed to cleanup compositor shaders, unable to make OpenGL context current`.
The application remained running; four subsequent closes under a targeted
debugger did not reproduce it. A focused probe using the actual SDK shader
implementation reproduces the same warning when GTK's GLX context is current
during raw EGL cleanup, but no production stack confirmed that attribution.
The binding guard covers application-owned realization/destruction callbacks;
it does not establish that every asynchronous engine finalizer is guarded.
Keep this intermittent cleanup warning open rather than declaring the entire
window lifecycle warning-free. No engine hooks or warning suppression were added.

Full Ubuntu release acceptance remains pending. Core tests, method-channel tests,
native contract tests and packaging fixtures do not establish rendered output,
focus behavior, smoothness or fractional-DPI correctness on Ubuntu. The separate
acceptance stage still needs Ubuntu 26.04 and 26.10, extension updates, two
mixed-DPI monitors, fractional scaling and text clarity in XWayland compatibility
mode, Dock/Alt-Tab, Overview, locking, workspaces, renderer reactions and Reduce
Motion. The single-monitor Ubuntu 24.04 checks above do not establish that matrix.

### Desktop environment matrix verification (2026-10-23)

The user requested broader native checks across common Linux desktops. The
matrix uses the same release-mode development-flavor AppImage throughout:
SHA-256 `e238a560b1680d8f06ea307edb89e85c52b3c5f0065f78b95d794fc1c80e02c3`,
native source `12ad29b` and launcher correction `34661df`. Ubuntu sessions run
the AppImage directly; Arch Wayland sessions execute its extracted AppRun with
the identical payload. No product code or renderer was changed for these checks.

Ubuntu 24.04 session packages cover X11 desktop families; these minimal sessions
are not claims about the defaults of every corresponding distribution or ISO.
Arch VM Lab profiles cover native Wayland compositors. Actual session variables,
compositor capabilities, application protocol/window roles and native client
input are recorded rather than inferred from installed package names. Virtual
monitors and virgl rendering do not establish physical GPU, fractional/mixed-DPI
or physical hotplug acceptance. Detailed per-check results, screenshots, logs and
the validation contract are under `build/design/pomo/2026-10-23-desktop-matrix`.
Unsupported capabilities, application failures and invalid harness attempts are
reported separately; an untested check is never promoted to a pass.

The observed results are below. A working renderer is only one acceptance gate;
none of these rows establishes full Linux release acceptance.

| Desktop and actual session | Observed companion behavior | Remaining observed problems |
| --- | --- | --- |
| GNOME 46 / Ubuntu 24.04, Wayland with XWayland app; GNOME 51.1 / Arch repeat | Real 3D, transparency, native-Wayland click-through, dragging and three Quick Add typing/Escape cycles pass. Ubuntu offline extension installation and relogin were exercised earlier. | Earlier intermittent GTK shader cleanup and accessibility warnings remain open. Arch repeat also reports missing canberra GTK modules. |
| Plasma 6.8.1 / KWin Wayland | Native layer-shell 3D, transparency, drag, settings, Quick Add, cursor-driven monitor transfer and pinned-output fallback pass. | Default placement overlaps the reserved bottom panel. |
| Hyprland 0.56.2 / Wayland | Native layer-shell 3D, transparency, drag, settings, Quick Add, cursor following and pinned-output fallback pass. | Reserved top bar introduces a placement offset; surface can extend below the output. |
| Sway 1.12 / Wayland | Native layer-shell 3D, transparency, drag, Quick Add and pinned-output fallback pass. | Active-workspace following fails, settings closes immediately, and reserved bars cause bottom clipping. |
| Xfce 4.18 / Xfwm, X11 | Animated 3D, transparency, drag, position restoration and direct Quick Add typing/Escape pass. | Both Enable and actual Show steal keyboard focus. A shader cleanup warning also occurs after interaction. |
| Cinnamon 6.0.4 / Muffin, X11 | Animated 3D, transparency, drag, settings, position restoration, passive Show and task-switcher exclusion pass. | Global Quick Add fails to receive focus in three cycles, preventing direct typing/Escape. |
| MATE 1.26 / Marco, X11 | Animated 3D, transparency, drag, position restoration, passive Show and task-switcher exclusion pass. | Global Quick Add focus fails in three cycles; post-interaction shader cleanup warning. |
| Budgie 10.9.1 / budgie-wm, X11 | Animated 3D, transparency, drag, settings and task-switcher exclusion pass. | Global Quick Add focus fails in three cycles. A later launch is delayed with portal criticals before eventually mapping; actual Show remains untested. |
| LXQt 1.4 / Openbox, X11 | Without a compositor, Pomo is unsupported. One explicitly labeled picom variant renders animated transparent 3D and supports dragging. | First-session main window failed to map within 45 seconds, with portal/drawable errors in its log; a later uncomposited control maps normally. The cause is not established. |
| LXDE (lxsession 0.5.5) / Openbox, X11 | Main application starts; without a compositor, settings correctly explains that Pomo is unavailable. | One of three Quick Add cycles fails to receive focus. Companion rendering is unsupported in this session, not a renderer regression. |

The X11 baselines use compositing where actually present; LXQt and LXDE's
minimal sessions had none. Installing picom also installed a desktop autostart
entry: it was stopped for an immediate uncomposited LXQt control before the
single labeled composited probe. That probe does not establish default Lubuntu
behavior or three composited cold starts.

Plasma, Hyprland and Sway exercised two virtual outputs, with headless outputs
used where necessary. Pin selection used controlled local preferences before
restart, rather than the UI dropdown. Delayed follow observations include
process/persistence overhead and do not prove an exact 500 ms deadline. Valid
cross-output drag coverage is limited to the disabled-transition Hyprland case;
invalid grabs are retained as harness evidence, not passes or product failures.
Physical mixed/fractional DPI, full focus/lock/workspace behavior, reactions and
Reduce Motion remain separate acceptance work. No product fix was attempted
during this verification run.

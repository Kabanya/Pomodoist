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
3. A single shared-scope desktop window, supported on macOS and Windows. The
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

# Pomo memory and performance audit — 2026-10-31

The clearest avoidable CPU cost is continuous texture notification and Flutter
compositing in Quiet mode. A separate lifecycle defect freezes animation after
`hidden → inactive`. Native leak checks also confirm a small texture-provider
leak across repeated model loads. Dart model objects are reclaimed successfully.
This is a diagnostic audit; production code and dependencies were not changed.

## Measured environment and scope

- Physical Apple M3 Pro, 12 logical CPU cores, 18 GiB RAM; macOS 26.6.2.
- Pinned Flutter 3.47.0, Dart 3.13.0, DevTools 2.60.0; arm64 profile build,
  Impeller/Metal, resolved Thermion Flutter/Dart 0.5.0.
- HEAD `9260f2e1f83b955aed812393ea6c287cb12ac9e7`, plus the existing working
  changes recorded in the artifacts. This is not a clean-HEAD benchmark.
- Existing `tool/pomo_resource_profile.dart`: real guest Today screen and native
  Pomo window, temporary SQLite database, in-memory preferences, no account sync.
- Main view: 1600×1200 physical pixels at DPR 2; companion window: 656×656.
  Pomo scale 1.0, Calm animation and Quiet pose after warmup.
- No manual UI interaction, screenshots, account actions, or preference edits.

All generated data is in `build/resource-profile/2026-10-31/` at the repository
root. It is ignored by Git. The report is the only intended repository change.

## Method and controls

The audit used Dart/Flutter MCP connections through DTD and the VM service,
runtime-error inspection, VM memory counters, allocation profiles with explicit
GC, CPU samples, Dart/Embedder/GC timelines, Flutter frame timings, native
scheduler diagnostics, macOS `proc_pid_rusage`, `sample`, `vmmap`, `leaks`, and
an Xcode Instruments Time Profiler recording.

The original unattended launch could not foreground the app. With a mounted
model and native texture, the first animated interval had **zero scheduled
frames/s**, inactive lifecycle, and a stopped scheduler. Its apparent 2.11%
CPU and 554 MiB footprint do not describe working animation. The original
collector was interrupted after preserving this evidence under `cycles/`.

A fresh process then completed a controlled series: 60 seconds cold hidden,
then three animated → Quiet → hidden cycles. Each visible state has 10 seconds
warmup and 10 one-second samples; each hidden state has 60 one-second samples.
An artifact copy of the existing collector injects `testLifecycle=resumed` when
changing mode, using the fixture's existing extension. **These active figures
therefore use a synthetic resumed lifecycle, not the failing unattended
lifecycle.** No lifecycle fix or dependency patch was installed.

All ten controlled phases passed workload, error, engine-lifetime and
active-rendering guards. CPU export occurs after the process-memory samples.
CPU is a percentage of **one core**. Footprint is process-charged physical
memory; RSS is resident memory. Neither is a direct GPU-allocation measurement.
One-second control RPCs walk the widget tree and add measurement overhead;
absolute idle CPU includes that overhead.

This follows Flutter's guidance to use profile mode for
[performance](https://docs.flutter.dev/tools/devtools/performance) and
[CPU profiling](https://docs.flutter.dev/tools/devtools/cpu-profiler), and uses
the runtime interfaces behind the [Memory view](https://docs.flutter.dev/tools/devtools/memory).

## Current measurements

Visible values average the three equal-duration phases; warm-hidden values
average the three minute-long phases. These are whole-app costs, not Pomo-only
allocations. Subtracting cold from active states is descriptive, not a precise
allocation attribution.

| State | CPU, % of one core | Footprint, MiB | RSS, MiB | Native scheduled work/s |
|---|---:|---:|---:|---:|
| Cold Today, Pomo never loaded | 2.92 | 337.3 | 237.5 | 0 |
| Animated Pomo | 23.45 | 742.3 | 482.3 | ~30.1 |
| Quiet Pomo | 15.50 | 601.4 | 439.9 | ~30.0 |
| Hidden after use | 2.69 | 380.3 | 361.8 | 0 |

Animated CPU ranges 22.22–25.70% across phase means; Quiet ranges
13.21–16.70%. Quiet retains about 66% of animated whole-process CPU in this
sample. No recorded Flutter frame exceeded the collector's 16.67 ms
build/raster-stage threshold; per-phase Flutter build p95 was at most 4.65 ms
and raster p95 at most 6.70 ms. These timings do not measure completed native
Filament GPU frames or establish interaction smoothness on populated screens.

The separate ten-second Instruments recording contains 2,688 sample rows.
397 stacks include `Rasterizer::Draw`, 313 include `DrawLastLayerTrees`, 99
include `RenderManager::render`, 36 include `AppEntryPointFinder`, and 19 include
texture-frame notifications. These overlapping stack occurrences corroborate
work outside the native scene animation; they are not additive CPU percentages.
The export and parsed counts are in `time-profile-samples.xml` and
`instruments-summary.json`.

Footprint at approximately 60 seconds after hiding was **327.3, 356.3 and
308.5 MiB**, versus 304.9 MiB at the last cold sample. Every hidden interval
had no native engine or advancing scheduler counter. There is no monotonically
increasing whole-process footprint in these three cycles; that does not prove
absence of smaller native leaks or long-term growth.

## Findings and recommended order

### 1. Quiet still schedules native work and repaints external textures

`PomoModel._sync` disables continuous scene rendering and renders one frame for
Quiet ([source](../../apps/flutter/lib/ui/pomo/widgets/pomo_model.dart#L310)).
The process-wide native scheduler nevertheless continues at approximately 30/s.
`NativeRenderingLifecycleController._renderFrame` calls `_onFrameRendered`
after `app.render()`, and the descriptor registry marks **every registered
texture** available without testing whether that view actually rendered.

The first controlled Quiet interval contains **620 engine raster events in
10 seconds**, versus **622** during animation. These are aggregate engine
events across views, not 620 displayed Pomo frames. Only ten Dart framework
frame timings occur in each interval: much of the excess is external-texture
recomposition rather than rebuilding the entire widget tree at 60 Hz.
Native stack samples also contain texture-frame notifications and Flutter
compositing calls.

First optimization candidate: stop idle scheduling/texture notifications when
no continuously rendering view needs them, while preserving a notification for
the one-shot Quiet frame and reliable animation/lifecycle resume. A global pause
must account for other viewers and texture mutations. Keeping the static scene
would still retain native memory; switching Quiet to an existing still image
and releasing the renderer would be a separate product/visual choice.

Evidence: `controlled-cycles/*-timeline.json`; copied dependency sources
`native_rendering_lifecycle_controller.dart`,
`platform_texture_descriptor_registry.dart`, and `thermion_viewer_ffi.dart`.

### 2. Animation does not resume on hidden → inactive

In a separate process, the fixture set lifecycle hidden, then inactive. After
the extension's settling delay and an additional one-second observation, the
native counter advanced **zero frames**, with an inactive scheduler despite a
mounted model and texture. Moving to resumed restores scheduling.

The resolved lifecycle controller suspends on hidden/paused/detached and removes
the lifecycle pause only in the resumed branch. Its inactive branch does
nothing. Visible utility windows can encounter this unfocused state; the
unattended launch reproduced it before the synthetic probe.

This correctness issue must be included in any scheduler optimization's
regression checks. Low CPU from this frozen state is not an optimization.
Evidence: `diagnostics/report.json`, `lifecycle`; original `collector.log`.

### 3. Texture-provider objects leak across engine reloads

A third process, launched with a minimal environment, ran **without CPU-symbol
export or Instruments** before its leak series. Each cycle loaded a real
texture, hid Pomo, and waited for the engine to disappear. macOS `leaks` reported:

| Completed open/close cycles | Reported leaked allocations | Reported leaked bytes | StbProvider root leaks |
|---|---:|---:|---:|
| 0 | 0 | 0 | 0 |
| 1 | 30 | 3,936 | 1 |
| 5 | 149 | 17,856 | 5 |
| 10 | 244 | 30,112 | 9 |

`GltfResourceLoader_create` allocates Stb and KTX2 providers and registers them
with the resource loader. `GltfResourceLoader_destroy` deletes only the loader.
Filament's bundled `ResourceLoader.h`, lines 96–99, explicitly assigns provider
destruction to the client, after loader destruction. The StbProvider objects
identified by the leak detector therefore have a matching ownership omission
in the resolved native source.

The total includes provider-associated allocations; it is not an exact fixed
per-load byte charge. Conservative leak detection can also vary object counts.
This is a small accumulating native leak, **not an explanation for the hundreds
of MiB charged while Pomo is visible**. Fix provider ownership in Thermion or an
upstream release, preserving destruction order and shared PNG/JPEG provider
identity. Evidence: `clean-leaks/report.json`, individual leak reports, copied
`TGltfResourceLoader.cpp` and `ResourceLoader.h`.

### 4. Model morph data is a substantial optimization candidate

The 7,278,509-byte gzip expands to 40,387,312 bytes. Referenced buffer-view
payloads include **30,771,516 bytes of morph geometry**, 5,995,152 bytes of base
geometry, 1,425,380 bytes of animation data, and 1,700,168 bytes of encoded
images. The model has nine meshes/materials, 27 images, eight animations,
116,586 vertices, and 179,580 triangles across both regular/thinking variants.
Three arm meshes contain 184, 221 and 221 morph targets.

This identifies where most decoded asset bytes live. It does **not** isolate
their exact runtime GPU cost or prove they dominate CPU. A model/export
experiment that removes redundant corrective targets should be measured against
pose-equivalence checks before adoption; no geometry or visual changes were
made. Evidence: `model-summary.json`, `model-buffer-groups.json`.

### 5. Window-shell capture walks the complete main widget subtree

Native stack samples show recursive
`AppEntryPointFinder.findShallowestInSubtree.visit`. The local
[multiview implementation](../../apps/flutter/third_party/multiview_desktop/lib/src/shared_entry_app.dart#L33)
walks every descendant to locate the shallowest app entry point; its capture
loop runs after each framework frame. It continues below recognized entry
widgets and allocates new shell snapshots during the search.

This is an additional traversal/allocation candidate when the main screen is
large. The current empty Today workload does not quantify its contribution on
a populated account. Recursive sampler counts must not be read as a percentage
of process CPU. Any change must preserve nested Material/Cupertino/Widgets
entry precedence and runtime theme/locale propagation.

## Dart retention and repeated opening

In the separate diagnostic process, explicit-GC main-isolate heap usage was
34.35 MiB cold, 36.54 MiB animated and 36.52 MiB Quiet. This retained-Dart growth
is much smaller than the whole-process growth; the latter cannot be diagnosed
from Dart heap counters alone.

Ten automated open/close cycles completed. The open-control call and texture
readiness check took 0.509–0.515 seconds (median 0.512), dominated by the
fixture's mandatory 500 ms synthetic-lifecycle settling delay. These numbers
cannot establish actual model-loading or visual latency. Each close
ended with no native engine. After GC, `PomoModelState`, `PomoMorphClips`,
`ThermionViewerFFI`, `FFIAsset`, and `FFIFilamentApp` all had zero live instances.
Heap usage immediately before and after the ten cycles was 36,577,824 and
36,577,696 bytes, with equal 25,904-byte external usage. Heap capacity increased;
used heap did not. This supports successful Dart cleanup in this workload and
does not contradict the separate native-provider leak.

## Artifacts, reproduction, and limits

- `controlled-cycles/results.json`: all resource samples and Flutter timings;
  per-phase timeline files and deferred CPU export are alongside it.
- `controlled_resource_profile.py`: artifact copy of the existing collector,
  with only the explicit resumed lifecycle added to mode changes.
- `diagnose.py`, `diagnostics/`: per-state native samples, VM CPU exports,
  post-GC allocation profiles, vmmap summaries, lifecycle probe and ten cycles.
- `leak_cycles.py`, `clean-leaks/`: independent native leak reproduction.
- `clean-time-profiler.trace`: ten-second Instruments capture using a process
  and recorder with minimal environments; no GUI review is required to capture.
- `dependency-sources/`: relevant resolved sources and SHA-256 fingerprints.
- Working-tree status, source/model hashes and launch logs accompany the data.

Build the existing profile entrypoint as described in the
[earlier audit](2026-10-26-pomo-resource-profile.md). Run the original collector
to reproduce the uncorrected lifecycle behavior, or use the archived controlled
copy against a **fresh process** to reproduce the active-rendering comparison.
Run allocation/native diagnostics separately from process-memory sampling.
Do not use personal accounts/databases or change the dependency cache.

The deferred main-series CPU export retained only the ring buffer's final
~78 seconds, not every phase. Separate five-second state exports supplement it,
but their sample counts are small; no exhaustive CPU attribution is claimed.
Native symbol export and allocation diagnostics perturb memory: diagnostic
`vmmap` totals are not substituted into the controlled resource table.

No production fix, full test-suite run, release-build comparison, populated
account/scrolling workload, other emotions/scales, Linux/Windows/mobile run,
GPU utilization/completion measurement, energy/thermal measurement, manual
artistic review, or long-duration leak soak was performed. All runtime error
guards passed in the completed resource and diagnostic scenarios. These results
identify specific next changes; they do not certify absence of all leaks or
smoothness across the application.

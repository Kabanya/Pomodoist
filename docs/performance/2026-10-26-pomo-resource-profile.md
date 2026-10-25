# Pomo and application resource profile — 2026-10-26

## Device and workload

Measurements use the physical Mac: Apple M3 Pro, 12 logical CPU cores, 18 GiB
unified memory, macOS 26.6.2, arm64. The pinned Flutter 3.47.0 / Dart 3.13.0
SDK builds the application in **profile** mode, using Impeller/Metal and the
installed Thermion 0.5.0 / Filament renderer.

The profiling entrypoint mounts the real `PomodoistApp`, `PomoRuntime`,
`PomoWindowHost`, `PomoWindow` and `PomoModel`, with a temporary SQLite file and
in-memory platform preferences. The application shows the guest Today screen
with a fresh local database, without account sync. No personal tasks or saved
Pomo preferences are used. This is an idle application workload, not a populated
account, scrolling benchmark, or startup benchmark.

The main view is 800×600 logical pixels at DPR 2. Pomo uses its default 100%
scale, with a 208×208 logical-pixel model surface and a separate companion
window. The animated state uses Calm; the static state uses Quiet with the same
emotion. Focus sessions, transitions and other emotions are outside this sample.

## Method

`apps/flutter/tool/pomo_resource_profile.dart` exposes a profile-only VM service
extension. `apps/flutter/tool/pomo_resource_profile.py` runs the state changes
and collects data without manual UI interaction or screenshots:

1. Pomo disabled before the first model load.
2. Animated Pomo.
3. Quiet/static Pomo.
4. Pomo disabled after use.
5. Repeat animated, static, and disabled states in the same process.

Each phase has a 10-second warmup after the state-change RPC, then 20 samples at
one-second intervals. Assertions check that Today is mounted, startup is complete, Pomo
visibility matches the requested mode, a real native texture exists when
visible, and no Flutter/controller errors were reported.

The collector combines:

- Dart VM Service `getMemoryUsage`, `getProcessMemoryUsage`, CPU samples and
  Dart/Embedder/GC timeline exports, the same runtime interfaces used by DevTools.
- Flutter `SchedulerBinding.addTimingsCallback` for build/raster timings.
- Thermion's scheduled-frame counter and scheduler/lifecycle state to distinguish
  active rendering from a mounted texture whose renderer is paused.
- macOS `proc_pid_rusage` for process CPU, RSS and physical footprint. CPU deltas
  use the device's Mach timebase, calibrated against `time.process_time_ns()`.
  **100% CPU means one fully occupied core**, not the entire 12-core processor.

Footprint includes memory charged to the process, including compressed and
graphics/driver allocations; it differs from currently resident RSS. Dart heap
and Dart external memory do not account for all Filament/Metal allocations.
Native scheduled FPS counts accepted scheduler work, not displayed/completed GPU
frames. Flutter build/raster timings do not encompass the independent native 3D
rendering pipeline.

CPU profile symbolization/export happens **after all resource samples**: exporting
large native symbol tables between phases materially perturbs the application
service isolate's memory. The first exploratory run under `preliminary/` is
excluded from the resource conclusions. `background/` contains a fresh-process
series with deferred CPU export; its completed results are also copied to
`results.json` in the root directory. `foreground-attempt/` contains the subsequent
diagnostic attempt with explicit window show/focus calls and per-sample scheduler
state. That attempt lost the Today workload after its third phase; the automated
guard rejected the next phase, and its samples are excluded from the table.

Raw samples, timelines, the final CPU profile, environment information, model
metadata and source/dependency hashes are under
`build/resource-profile/2026-10-26/`. These generated files are ignored by Git.

## Reproduction

From `apps/flutter`, leave this command running:

```sh
../../.fvm/flutter_sdk/bin/flutter run --profile -d macos --flavor staging \
  --target tool/pomo_resource_profile.dart --no-pub \
  --host-vmservice-port 55291 --disable-service-auth-codes
```

From the repository root:

```sh
python3 apps/flutter/tool/pomo_resource_profile.py \
  http://127.0.0.1:55291/ build/resource-profile/2026-10-26
```

The Python collector requires only the standard library and macOS. The Dart
entrypoint uses the installed Thermion scheduler diagnostics; dependency source
hashes accompany the measurements. Revalidate this private diagnostic import
when changing the renderer version.

## Results and rendering-state qualification

The most important limitation is observable renderer suspension: the controller
can report `visible=true, animated=true` with a mounted native texture while the
Thermion scheduler is stopped or paused. After hiding and showing Pomo, one
recorded animated phase scheduled **zero** native frames. Calling the main
window's show/focus API did not reliably establish sustained native rendering.
The show/focus experiment is not part of the final reusable collector: the
collector observes the application's actual lifecycle.
Low CPU in these phases is a suspended-renderer measurement.

The `background/animated_1` trace contains 13 seconds of actual continuous
texture compositing, followed by 7 seconds of suspension. The active bins contain
58–66 engine raster events each, while the suspended bins contain 2–4. The
Thermion counter increased by 385 frames over the phase, consistent with about
30 scheduled frames/s during the active segment. The derived split and original
per-second samples are preserved in `active-rendering-analysis.json`.

These are observed averages from that same fresh-process series:

| State | CPU, % of one core | Process footprint, MiB | RSS, MiB |
|---|---:|---:|---:|
| Today, Pomo never loaded, 20 s | 1.16 | 355.9 | 243.9 |
| Pomo actively rendering, 13 validated seconds | 16.71 | 1353.2 | 661.2 |
| Quiet/static, 20 s | 1.31 | 1255.0 | 601.0 |
| Pomo disabled after first use, 20 s | 1.07 | 759.9 | 533.5 |

The exact static/disabled values and distributions are in
`background/results.json`. Active rendering adds about **997 MiB of process
footprint** and **15.5 percentage points of one CPU core** relative to the initial
idle application. These are workload-specific observations, not a portable
steady-state estimate: rendering did not remain active for the entire intended
20-second phase.

After the second show/static/hide cycle in that series, disabled-state footprint
averaged about 709 MiB, still above the initial 356 MiB. The retained accounting
can include renderer/driver caches, allocator capacity and profiling overhead;
these short runs do **not** prove a leak. Quiet stops ongoing rendering work but
keeps a loaded 3D scene and its substantial memory footprint.

Flutter timing callbacks in the active phase reported build p95 2.76 ms and
raster p95 2.91 ms, with no callback frame over 16.67 ms. Those callbacks mainly
measure the Flutter UI; native texture updates also generate engine raster work
without a corresponding Dart build callback. They are not evidence that the
mascot maintained a displayed FPS or met a GPU frame-time budget.

## Validation

The fresh-process `background/` series completed all seven phases and its
workload/texture/error assertions. The foreground experiment was rejected by the
Today-screen assertion as described above. Targeted Flutter analysis passed for
the profiling entrypoint; the Python collector's syntax and on-device CPU
timebase self-check passed. No product behavior tests or manual visual checks
were needed for these measurement-only tools.

## Asset accounting

The bundled compressed model is 8,646,683 bytes (8.25 MiB); its decoded GLB is
41,858,136 bytes (39.92 MiB). All bundled Pomo assets total 9,074,887 bytes
(8.65 MiB), excluding native renderer libraries. The model has 9 meshes, 8 clips
and 27 embedded images. Expanding all images arithmetically to RGBA8 totals
213 MiB before mipmaps or deduplication. This is an asset calculation, not a
measurement of GPU memory or an explanation of the entire process footprint.

## Scope and interpretation

Another release Pomodoist process was running during collection. Its resource
usage is excluded from the target PID's CPU/memory totals, but shared CPU/GPU
contention can affect timing. Environment snapshots preserve this condition.

The measurements do not establish release-build consumption, battery drain,
power in watts, GPU utilization, a memory leak, or behavior on iPhone, Android,
Windows or Linux. No product rendering, lifecycle, or memory-management code was
changed as part of this audit.

Flutter recommends profile-mode measurements and documents the difference
between Dart memory and process RSS:
[performance profiling](https://docs.flutter.dev/perf/ui-performance),
[DevTools memory](https://docs.flutter.dev/tools/devtools/memory).

# Pomo memory optimization — 2026-10-26

This implements the follow-up to the [initial resource audit](2026-10-26-pomo-resource-profile.md): cap runtime textures at 1024 pixels, release native source data, compact animation curves, destroy the native renderer when Pomo is hidden, and verify the result automatically on the physical Mac.

**Current dependency:** the application uses the unmodified hosted `thermion_flutter: 0.5.0`. The temporary local package and lifecycle patch were removed at the user's request. The successful long-run and native-capture results below describe the earlier patched build, not a new certification of the hosted dependency. The upstream `hidden` → `inactive` animation-resume defect remains unresolved; the runtime fixture retains its assertion so it exposes that failure rather than silently accepting a frozen scene.

## Changes

- The packer limits both color and data maps to a maximum side of **1024**, preserving aspect ratio and smaller images. Authoring files retain their original resolution. The 27 runtime images are now 21 images at 512×512 and six at 1024×1024. Their arithmetic RGBA8 size falls from **213 MiB to 45 MiB**, before mipmaps or deduplication; this is not measured GPU memory.
- The compressed GLB falls from **8,646,683 to 7,278,509 bytes** (15.8%); decoded GLB falls from 41,858,136 to 40,387,312 bytes. Meshes, materials, skeletons and animation accessor payloads are unchanged.
- After capturing node/bone/material metadata, the viewer calls `releaseSourceData()`. Animation curves use independent `Float32List` copies shared by accessor index, so they do not retain the decoded GLB. Calculated curve payload falls from at least 4.224 MiB of double slots to 1.392 MiB of float32 values, excluding collection overhead.
- Hiding Pomo waits for initialization and pending updates, stops rendering, releases its surface, viewer and swapchains, then destroys its native Filament engine. Cleanup attempts all stages even if an earlier stage fails. Reopening waits for the previous cleanup to finish. Quiet retains the scene for a quick return to animation.

The repeated runtime test also exposed an upstream lifecycle defect: a visible desktop utility window can transition from `hidden` to `inactive` without taking focus. Thermion resumes only on `resumed`, leaving animation suspended across subsequent engine reloads. For the measurements below, a temporary local copy of the official 0.5.0 package changed only that lifecycle branch: both visible states used the existing resume handler and its explicit-pause/surface guards. That copy has since been removed; both Thermion dependencies now resolve to upstream hosted 0.5.0. Neither package's pub cache was edited. The reviewed patch remains in the ignored measurement artifacts as `thermion-inactive.patch`, against upstream tag `v0.5.0` (commit `9d99b9e0ffb75f46d9e87cee88beb3e5b83f2e8f`). The original package archive SHA-256 is `a5890c72caa2116eb174b79c8307744b3c1cb69af946295df22c3c057cb2dc61`.

## Measurement method

The device is an Apple M3 Pro, 12 logical cores, 18 GiB unified memory, macOS 26.6.2, arm64. The pinned Flutter 3.47.0 / Dart 3.13.0 SDK runs a staging **profile** build with Metal/Impeller and Thermion/Filament. The profile entrypoint mounts the real guest Today screen and Pomo window with a temporary SQLite database and in-memory preferences. It does not use personal tasks or accounts. The main physical view is 2358×1658 at DPR 2 in the directly compared runs.

The collector uses Dart VM Service memory/timeline/CPU interfaces, Flutter frame timings, native scheduler diagnostics and macOS `proc_pid_rusage`. CPU is a percentage of one core. Physical footprint includes process-charged compressed and graphics/driver memory; RSS only measures resident memory, and Dart heap/external counters exclude much of the native renderer. Visible-phase values describe the warmed workload, not peak allocation during startup/model loading. CPU symbolization/export runs after all memory samples to avoid polluting later phases with symbol-table allocation.

The fresh baseline uses the original model and retains the native engine after hiding: two animated → Quiet → hidden cycles, 10 seconds of warmup and 20 seconds of samples per phase. The optimized comparison process completed seven full animated → Quiet → hidden cycles: 60 seconds cold hidden, 10 seconds warmup plus 10 seconds sampled for each visible phase, and 60 seconds sampled after each hide. The collector records snapshots approximately 5, 15 and 60 seconds after hiding. It checks the real Today workload, native texture, visibility, errors, engine absence after hide, and active native scheduler progression during animation.

That process exited during the eighth hidden interval. No matching native crash report was found for its PID; a contemporary crash report belongs to another release process, and the shared build artifacts were also replaced. The exit cause is unattributed. Only its seven completed cycles enter the comparison; the partial eighth cycle is excluded.

The subsequent ten-cycle stability run uses a separate copied bundle, executable and bundle identifier, outside the shared Flutter build directory. It retains sandbox/JIT/network permissions but omits restricted account and app-group entitlements unused by the guest harness; these generated-bundle changes do not modify production signing. The new identity opens a default 1600×1200 physical main view at DPR 2. Its measurements are reported separately rather than mixed into the equal-window comparison. Bundle identity, entitlements and signatures are recorded in `isolated-bundle.json`.

The baseline build overlapped the curve source edit, so its exact compiled curve representation is uncertain. It establishes original textures and retained-engine behavior; it does not isolate the contribution of each individual change. Curve equivalence and payload reduction were checked separately. These runs also use a larger main window than the initial audit; compare the fresh baseline below, rather than subtracting the earlier audit's numbers.

Another existing release Pomodoist process remained running. Its allocations are excluded from the measured PID, but shared CPU/GPU contention can affect timing. No manual UI interaction was required.

## Comparison with the same main-window size

These are phase averages, aggregated across the two baseline cycles and seven completed optimized cycles. Visible phases have different sampling lengths as described above; this is a device/workload comparison, not an isolated causal estimate for each change.

| State | Before footprint, MiB | After footprint, MiB | Before RSS, MiB | After RSS, MiB | Before / after CPU, % of one core |
|---|---:|---:|---:|---:|---:|
| Today, Pomo never loaded | 365.0 | 354.3 | 167.2 | 204.9 | 1.17 / 2.65 |
| Animated Pomo | 1365.7 | 853.3 | 672.2 | 479.9 | 24.45 / 30.67 |
| Quiet Pomo | 964.3 | 731.7 | 392.1 | 442.1 | 20.80 / 21.29 |

Animated process footprint falls by **512.4 MiB (37.5%)** and Quiet footprint by **232.6 MiB (24.1%)**. CPU does not improve in the animated or Quiet comparisons. Every included animated phase has an active, unpaused scheduler and approximately 30 accepted native frames/s throughout.

Hiding now destroys the native engine and stops native scheduled frames. After-hide Dart heap averages **39.3 MiB**, compared with **37.7 MiB** cold. However, whole-process RAM does **not** return exactly to its cold value: footprint at approximately 60 seconds after hiding ranges **371.0–593.4 MiB** across these seven cycles, compared with 335.8 MiB at the end of the cold interval. The series fluctuates rather than rising on every cycle. The new 60-second hidden-phase average is 486.9 MiB; the old 20-second sampled hidden-phase average was 470.5 MiB after a 10-second warmup, so those values do not demonstrate a reduction in retained process RAM. Hidden CPU averages 2.38% versus 6.08% before, with the same sampling-window qualification.

The native teardown, Dart-object reclamation and exact OS memory accounting are separate outcomes. Retained allocator/driver/profiler capacity can contribute to the remaining charge, but this run does not identify every retained allocation or establish that all residual memory is harmless caching.

## Completed isolated ten-cycle run (temporary patched build)

All **31 phases** completed in one process (PID 40431): cold hidden, then ten animated → Quiet → hidden cycles. Every phase passes workload/texture/error checks, every animated interval remains active at **29.99–30.18 native scheduled frames/s**, and all ten hidden intervals have no live native engine or advancing native frame counter. CPU/timeline export also completed after the final memory sample.

With this run's smaller default main window, cold footprint averages **335.8 MiB**, and the ten 60-second hidden phases average **336.7 MiB**. Animated footprint averages 749.0 MiB and Quiet 618.4 MiB; these are not substituted into the equal-window comparison above. Hidden CPU averages 1.29% of one core. The similar cold/hidden averages do not imply an exact per-close RAM return: individual after-hide samples vary substantially.

| Close cycle | Footprint after ~5 s, MiB | After ~15 s, MiB | After ~60 s, MiB |
|---|---:|---:|---:|
| 1 | 504.3 | 417.3 | 333.1 |
| 2 | 412.8 | 416.5 | 402.1 |
| 3 | 270.8 | 271.8 | 274.2 |
| 4 | 300.9 | 301.9 | 305.2 |
| 5 | 413.4 | 415.1 | 417.8 |
| 6 | 354.7 | 355.9 | 358.7 |
| 7 | 393.5 | 393.0 | 395.0 |
| 8 | 221.4 | 222.3 | 224.2 |
| 9 | 246.5 | 247.7 | 250.2 |
| 10 | 365.6 | 366.6 | 368.7 |

At the final 60-second sample, footprint is 368.7 MiB and RSS 439.0 MiB; cold footprint at 60 seconds was 314.6 MiB. The ten post-close 60-second footprints range **224.2–417.8 MiB**, with no monotonic increase. Dart heap at those snapshots ranges approximately 35–87 MiB, reflecting collection timing as well as live objects. By the later post-run diagnostic it had already dropped to **33.4 MiB before an explicit VM-Service GC**, then 33.0 MiB after it. This diagnostic happened after CPU export and is recorded separately; its process footprint must not be compared with the sampled phases. Production code does not force GC.

## Automated native checks (temporary patched build)

- Closing during initialization before a texture exists releases the engine.
- Reopening during an observed, deliberately delayed native teardown waits for cleanup and succeeds.
- Ten rapid open/close cycles succeed; each ends with the engine absent.
- A generated app-bundle corrupt-gzip fixture reports the expected error, releases the engine and successfully reloads after the original bytes are restored in `finally`. Repository assets are not corrupted by the fixture.
- A `hidden` → `inactive` lifecycle fixture resumes rendering and advances nine native scheduled frames in about 300 ms.
- Six animated emotion-transition captures are distinct and advance 57 native scheduled frames.
- Sixteen native image pairs cover all eight emotions at UI scales 100% and 250%. Both settings currently render to a **384×384 native texture**; these are captures of that texture, not full-window screenshots. Premultiplied visible-RGB RMSE is **0.00411–0.00765** on a 0–1 scale; maximum alpha MAE is 0.0000453. Geometry/accessor bytes compare exactly. This numerical check does not substitute for an artistic quality review.
- The old and new animation readers produce **120,832 exactly equal** sampled morph/bone values across all eight clips, loop settings and selected times.

## Reproduction and artifacts

From `apps/flutter`, start a fresh process:

```sh
../../.fvm/flutter_sdk/bin/flutter run --profile -d macos --flavor staging \
  --target tool/pomo_resource_profile.dart --no-pub \
  --host-vmservice-port 55294 --disable-service-auth-codes
```

From the repository root:

```sh
python3 apps/flutter/tool/pomo_resource_profile.py \
  http://127.0.0.1:55294/ build/resource-profile/reproduction \
  --seconds 10 --cycles 10
```

After collecting memory, restart into a fresh process before captures and failure fixtures:

```sh
python3 apps/flutter/tool/pomo/check_runtime.py \
  http://127.0.0.1:55294/ build/resource-profile/runtime-checks
```

The optional `--reference` argument compares native captures with an earlier capture directory. The optional `--model-file` argument accepts only an explicitly selected generated app-bundle model for the temporary bad-asset fixture; do not point it at a source asset. The collector uses the Python standard library and macOS; captures use the packer's existing Pillow/NumPy dependencies.

Local ignored artifacts are under `build/resource-profile/2026-10-26-optimized/`: `before/` holds the fresh baseline, `interrupted-target-exit/` the equal-window optimized comparison, `after/` the isolated long series, `final-captures-after/` the final runtime fixtures and image comparisons, and `captures-before/` the original-texture reference. Source hashes, official package archives and dependency audits accompany the results. `before-lifecycle-fix/` and earlier interrupted series are diagnostic evidence and are excluded from active-rendering comparisons.

## Validation scope

The targeted Flutter suite passes **39 tests** both with the measured temporary patch and after restoring the hosted 0.5.0 dependency. The pack/export Python suite passes **six tests**, asset validation passes all eight fallback stills, and targeted Dart analysis reports no issues. After dependency restoration, the long native profile was not repeated; its known lifecycle-resume failure remains open. The hosted rerun is recorded in `hosted-targeted-tests.log`, and `hosted-pub-get.log` records the dependency restoration. Profile builds were rebuilt/relaunched during measurement; the requested Dart-tool hot-restart attempt reports `Unknown method hotRestart` in that profile runtime. The full Flutter suite, run before the temporary lifecycle dependency patch, had **2,626 passes and six failures** outside the changed behavior:

- `Sway repository subscribes and maps workspace reports to native displays`: macOS D-Bus UID lookup.
- `Hyprland read-only socket requests run only while following`: macOS D-Bus UID lookup.
- `Sway pushes initial snapshot and workspace/output events without polling`: macOS D-Bus UID lookup.
- `unknown Wayland desktops remain fixed-monitor and stale sockets fail closed`: macOS D-Bus UID lookup.
- `timeline uses short quarter ticks and today indicator`: missing current-time indicator.
- `passes the selected identity and macOS icon bytes to the native host`: missing generated classic macOS icon asset.

The Linux Thermion path/runtime suite passes seven of eight checks on this Mac; its ELF relocation execution test requires Linux and fails on macOS's dynamic-library output. Native Linux, Windows, mobile and release-build behavior, GPU utilization, power/battery use and artistic visual quality remain unverified. Native scheduled frames count accepted scheduling work, not completed/displayed GPU frames. Quiet's global scheduler counter can advance even when its scene is not continuously rendered. No exact OS-level RAM return or absence of a long-term leak can be inferred solely from a finite profile run.

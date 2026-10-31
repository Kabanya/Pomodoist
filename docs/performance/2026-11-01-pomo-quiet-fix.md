# Pomo Quiet scheduling fix — 2026-11-01

Quiet now pauses Thermion's frame scheduler as well as scene animation.
Changing emotion or texture size renders and publishes a single frame. Returning
to animation enables the view and resumes the scheduler. The existing scene,
asset and teardown ownership remain intact; dependencies are unchanged.

Pomo is the only production Thermion viewer and owns its native engine. A future
second viewer sharing that engine would require coordinating this global pause.

## Before and after

Fresh native macOS profile processes used the same temporary guest workload,
pinned Flutter 3.47.0, Thermion 0.5.0 and M3 Pro as the
[initial audit](2026-10-31-pomo-profiling.md). Each process completed 60 seconds
cold hidden, 10 seconds warmup plus 10 seconds measurement per visible mode,
and 60 seconds hidden after teardown. The collector explicitly sets the fixture
lifecycle to resumed for visible modes. CPU is whole-process usage as a
percentage of one core, including the measurement RPC overhead.

| Quiet measurement, 10 seconds | Before | After |
| --- | ---: | ---: |
| Mean CPU, % of one core | 17.44 | 3.68 |
| Scheduler-accepted native frames | 295 | 0 |
| Engine raster events across views | 604 | 20 |

Quiet CPU fell approximately **79%** in this paired run. Raster events fell
approximately 97%; these events are not a count of displayed Pomo frames.
Animation remained active at **300 scheduled frames per 10 seconds** in both
processes. All workload, rendering and teardown guards passed.

This is one paired measurement, not a hardware-wide performance guarantee.
Background CPU also differed (2.50% before, 1.44% after), as did animated CPU
(32.90% versus 19.99%). The stopped native counter and reduced raster activity
are the direct evidence of eliminating Quiet's recurring work; the entire CPU
difference should not be attributed precisely to this patch.

Quiet still holds the native scene in memory: the post-fix measurement averaged
655 MiB process footprint. This change does not solve model memory use or the
separate native texture-provider leak identified in the audit.

## Automated regression check

Build/run `tool/pomo_resource_profile.dart` in profile mode, then run from
`apps/flutter`:

```sh
python3 tool/pomo/check_quiet.py HTTP_VM_SERVICE_URI OUTPUT_DIRECTORY
```

The profile fixture uses temporary SQLite data and in-memory preferences. Its
optional `renderCapture=false` reads the existing native target without
redrawing it. The check compares that target with a forced reference redraw.
The comparison limits mean channel error to 0.001 and RMS channel error to 0.1
on the 0–255 scale. A Focus comparison exposed one- and two-unit rounding
differences at a few edge pixels, making exact equality inappropriate. Other
pose changes must still produce distinct images.

Explicit scale requests now use `PomoController.changeScale`, matching the
settings path. Updating the stored preference alone did not resize an already
visible window, so the previous fixture could not validate live texture resize.
The default measurement path is unchanged.

Validation passed:

- The original build fails the new Quiet scheduler-pause assertion.
- All 129 existing Pomo tests pass; changed Dart files have no analyzer errors.
- All eight poses pass native target/reference comparisons at both 384×384 and
  960×960, with transparent backgrounds and distinct pose images.
- Quiet remains paused across live resize, emotion changes, Reduce Motion and
  a synthetic hidden/resumed lifecycle transition.
- Five two-second animation probes each advance 60–61 native frames and show
  different images, including a direct Quiet-to-animation switch while inactive.
- Three additional hide/reopen cycles and mode switches pass. Final teardown
  leaves no native engine, PomoModel or Texture; runtime error guards stay clear.
- Full native profile rebuilds pass. Hot reload reports that its compiler is
  disabled in AOT mode, so verification uses rebuilt processes.

## Artifacts and limits

Ignored artifacts are under `build/resource-profile/2026-10-31/quiet-fix/`:
`before/` and `after/` contain raw samples, timelines and deferred CPU exports;
`before-check.log` demonstrates the old scheduler-pause assertion failing;
`final-check/` contains the final regression report. The shared collector is
the controlled artifact copy documented in the initial audit.

The separate Thermion `hidden → inactive` lifecycle freeze remains outside
this patch. The check isolates it with an explicit resumed lifecycle when
reopening. Direct Quiet-to-animation switching while inactive is checked
separately. No dependency-cache modifications or simulated focus changes are
part of production behavior.

No Windows/Linux run, manual artistic review, long-duration leak soak, or
release-build benchmark was performed. Native render-target comparisons do not
constitute a visual review of the final composited desktop window.

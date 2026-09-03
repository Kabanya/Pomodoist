import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pomodoist/features/focus/domain/focus_models.dart';
import 'package:pomodoist/features/focus/presentation/focus_stage.dart';
import 'package:pomodoist/features/focus/presentation/focus_view_mode.dart';

import 'task_motion_profile_result_stub.dart'
    if (dart.library.js_interop) 'task_motion_profile_result_web.dart';

const _baseline = bool.fromEnvironment('FOCUS_MOTION_BASELINE');
const _repetitions = 20;

void main() => runApp(const MaterialApp(home: _FocusMotionProfile()));

class _FocusMotionProfile extends StatefulWidget {
  const _FocusMotionProfile();

  @override
  State<_FocusMotionProfile> createState() => _FocusMotionProfileState();
}

class _FocusMotionProfileState extends State<_FocusMotionProfile> {
  final _repository = _ProfileFocusRepository();
  final _timings = <FrameTiming>[];
  final _results = <String>[];
  late final TimingsCallback _timingsCallback;
  var _collecting = false;
  var _active = false;
  var _paused = false;
  var _breakPhase = false;
  var _full = true;

  @override
  void initState() {
    super.initState();
    _timingsCallback = (timings) {
      if (_collecting) _timings.addAll(timings);
    };
    SchedulerBinding.instance.addTimingsCallback(_timingsCallback);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_timingsCallback);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.utc(2026, 8, 29, 12);
    final interval = _interval(now);
    final stage = _active
        ? FocusActiveStage(
            run: _profileRun(now),
            interval: interval,
            intervals: [interval],
            remaining: Duration(minutes: _breakPhase ? 4 : 24, seconds: 30),
            presets: [_preset],
            selectedPreset: _preset,
            timerVisualStyle: FocusTimerVisualStyle.circle,
            compact: false,
            viewMode: _full ? FocusViewMode.full : FocusViewMode.minimal,
            repository: _repository,
            onViewModeChanged: (_) {},
            onPresetChanged: (_) {},
            onCustomizePreset: (_) {},
            onCreatePreset: () {},
          )
        : FocusIdleStage(
            presets: [_preset],
            selectedPreset: _preset,
            timerVisualStyle: FocusTimerVisualStyle.circle,
            compact: false,
            viewMode: _full ? FocusViewMode.full : FocusViewMode.minimal,
            onPresetSelected: (_) {},
            onViewModeChanged: (_) {},
            onStart: () async {},
            onCustomize: () {},
            onCreate: () {},
          );
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: _baseline),
      child: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: SizedBox(width: 1200, child: stage),
        ),
      ),
    );
  }

  FocusIntervalItem _interval(DateTime now) => FocusIntervalItem(
    id: _breakPhase ? 'break-2' : 'work-1',
    runId: 'run-1',
    type: _breakPhase ? 'shortBreak' : 'work',
    status: _paused ? 'paused' : 'running',
    plannedSeconds: _breakPhase ? 300 : 1500,
    startedAt: now,
    pausedAt: _paused ? now : null,
    pausedTotalSeconds: 0,
    sequenceNumber: _breakPhase ? 2 : 1,
    createdAt: now,
    updatedAt: now,
  );

  Future<void> _run() async {
    await Future<void>.delayed(const Duration(seconds: 1));
    await _measure(
      'start',
      prepare: () => _set(active: false, paused: false, breakPhase: false),
      action: () => _set(active: true),
    );
    await _measure(
      'pause',
      prepare: () => _set(active: true, paused: false, breakPhase: false),
      action: () => _set(paused: true),
    );
    await _measure(
      'resume',
      prepare: () => _set(active: true, paused: true, breakPhase: false),
      action: () => _set(paused: false),
    );
    await _measure(
      'phase',
      prepare: () => _set(active: true, paused: false, breakPhase: false),
      action: () => _set(breakPhase: true),
    );
    await _measure(
      'viewMode',
      prepare: () => _set(active: true, full: true),
      action: () => _set(full: false),
    );
    final result = '${_baseline ? 'baseline' : 'motion'}|${_results.join('|')}';
    publishTaskMotionProfileResult(result);
    debugPrint('FOCUS_MOTION_PROFILE_DONE $result');
  }

  void _set({bool? active, bool? paused, bool? breakPhase, bool? full}) {
    setState(() {
      _active = active ?? _active;
      _paused = paused ?? _paused;
      _breakPhase = breakPhase ?? _breakPhase;
      _full = full ?? _full;
    });
  }

  Future<void> _measure(
    String name, {
    required VoidCallback prepare,
    required VoidCallback action,
  }) async {
    prepare();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    action();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    _timings.clear();
    for (var index = 0; index < _repetitions; index++) {
      prepare();
      await Future<void>.delayed(const Duration(milliseconds: 320));
      _collecting = true;
      action();
      await Future<void>.delayed(const Duration(milliseconds: 320));
      _collecting = false;
    }
    final build = _timings
        .map((timing) => timing.buildDuration.inMicroseconds)
        .toList();
    final raster = _timings
        .map((timing) => timing.rasterDuration.inMicroseconds)
        .toList();
    final overBudget = _timings.where((timing) {
      const budget = Duration(microseconds: 16667);
      return timing.buildDuration > budget || timing.rasterDuration > budget;
    }).length;
    _results.add(
      '$name:${_timings.length},${_p95(build)},${_p95(raster)},$overBudget',
    );
  }

  int _p95(List<int> values) {
    if (values.isEmpty) return 0;
    values.sort();
    return values[((values.length - 1) * 0.95).ceil()];
  }
}

class _ProfileFocusRepository implements FocusRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _preset = FocusPresetItem(
  id: 'classic',
  userId: 'profile',
  name: 'Classic',
  workSeconds: 1500,
  shortBreakSeconds: 300,
  longBreakSeconds: 900,
  intervalsBeforeLongBreak: 4,
  autoStartBreaks: false,
  autoStartWork: false,
  allowPause: true,
  strictMode: false,
  isDefault: true,
  createdAt: DateTime.utc(2026, 8, 29),
  updatedAt: DateTime.utc(2026, 8, 29),
);

FocusRunItem _profileRun(DateTime now) => FocusRunItem(
  id: 'run-1',
  userId: 'profile',
  presetId: 'classic',
  status: 'active',
  startedAt: now,
  targetWorkIntervals: 4,
  completedWorkIntervals: 0,
  createdAt: now,
  updatedAt: now,
);

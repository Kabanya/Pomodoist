import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pomodoist/features/tasks/domain/task_models.dart';
import 'package:pomodoist/features/tasks/presentation/widgets/task_motion.dart';

import 'task_motion_profile_result_stub.dart'
    if (dart.library.js_interop) 'task_motion_profile_result_web.dart';

const _baseline = bool.fromEnvironment('MOTION_BASELINE');
const _repetitions = 20;

void main() => runApp(const MaterialApp(home: _MotionProfile()));

class _MotionProfile extends StatefulWidget {
  const _MotionProfile();

  @override
  State<_MotionProfile> createState() => _MotionProfileState();
}

class _MotionProfileState extends State<_MotionProfile> {
  final _completed = List<bool>.filled(500, false);
  final _timings = <FrameTiming>[];
  final _results = <String>[];
  late final TimingsCallback _timingsCallback;
  TaskMotionController? _motion;
  var _revision = 0;

  @override
  void initState() {
    super.initState();
    _timingsCallback = _timings.addAll;
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
    final list = ListView.builder(
      itemCount: _completed.length,
      itemExtent: 48,
      itemBuilder: (context, index) {
        final id = 'task-$index';
        final completed = _completed[index];
        final row = Row(
          children: [
            const SizedBox(width: 12),
            if (_baseline)
              Icon(
                completed ? Icons.check_circle : Icons.circle_outlined,
                size: 24,
              )
            else
              TaskCompletionControl(
                taskId: id,
                isCompleted: completed,
                color: Colors.indigo,
                fillColor: Colors.indigo,
                onPressed: null,
              ),
            const SizedBox(width: 12),
            Expanded(
              child: _baseline
                  ? Text('Task $index', style: _titleStyle(completed))
                  : AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 340),
                      style: _titleStyle(completed),
                      child: Text('Task $index'),
                    ),
            ),
          ],
        );
        return _baseline ? row : TaskMotionItem(taskId: id, child: row);
      },
    );
    if (_baseline) {
      return Scaffold(body: list);
    }
    return TaskMotionScope(
      builder: (context, motion) {
        _motion = motion;
        return Scaffold(body: list);
      },
    );
  }

  TextStyle _titleStyle(bool completed) => TextStyle(
    color: completed ? Colors.black45 : Colors.black87,
    decoration: completed ? TextDecoration.lineThrough : null,
  );

  Future<void> _run() async {
    await Future<void>.delayed(const Duration(seconds: 1));
    await _measure('completion', const Duration(milliseconds: 360), (_) {
      final completed = !_completed[0];
      setState(() => _completed[0] = completed);
      if (!_baseline) {
        final task = _task(0, completed: completed);
        completed ? _motion!.completed([task]) : _motion!.reopened([task]);
      }
    });
    await _measure('creation', const Duration(milliseconds: 180), (_) {
      if (_baseline) {
        setState(() => _revision++);
      } else {
        _motion!.created({'task-1'});
      }
    });
    await _measure('delete', const Duration(milliseconds: 240), (_) {
      if (_baseline) {
        setState(() => _revision++);
      } else {
        _motion!.deleted([_task(2)]);
      }
    });
    await _measure('landing', const Duration(milliseconds: 180), (_) {
      if (_baseline) {
        setState(() => _revision++);
      } else {
        _motion!.landed({'task-3'});
      }
    });
    await _measure('bulk6', const Duration(milliseconds: 360), (_) {
      _toggleRange(4, 6);
    });
    await _measure('bulk50', const Duration(milliseconds: 80), (_) {
      _toggleRange(4, 50);
    });
    final result = '${_baseline ? 'baseline' : 'motion'}|${_results.join('|')}';
    publishTaskMotionProfileResult(result);
    debugPrint('MOTION_PROFILE_DONE $result');
  }

  void _toggleRange(int start, int count) {
    final completed = !_completed[start];
    setState(() {
      for (var index = start; index < start + count; index++) {
        _completed[index] = completed;
      }
    });
    if (_baseline) {
      return;
    }
    final tasks = [
      for (var index = start; index < start + count; index++)
        _task(index, completed: completed),
    ];
    completed ? _motion!.completed(tasks) : _motion!.reopened(tasks);
  }

  Future<void> _measure(
    String name,
    Duration settle,
    void Function(int index) action,
  ) async {
    action(-1);
    await Future<void>.delayed(settle + const Duration(milliseconds: 300));
    _timings.clear();
    for (var index = 0; index < _repetitions; index++) {
      action(index);
      await Future<void>.delayed(settle);
    }
    await Future<void>.delayed(const Duration(milliseconds: 120));
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
    final result =
        '$name:${_timings.length},${_p95(build)},${_p95(raster)},$overBudget';
    _results.add(result);
    debugPrint(
      'MOTION_PROFILE mode=${_baseline ? 'baseline' : 'motion'} case=$name '
      'frames=${_timings.length} buildP95Us=${_p95(build)} '
      'rasterP95Us=${_p95(raster)} overBudget=$overBudget',
    );
  }

  int _p95(List<int> values) {
    if (values.isEmpty) {
      return 0;
    }
    values.sort();
    return values[((values.length - 1) * 0.95).ceil()];
  }

  TaskItem _task(int index, {bool completed = false}) {
    final now = DateTime.utc(2026, 8, 28);
    return TaskItem(
      id: 'task-$index',
      userId: 'profile',
      content: 'Task $index',
      projectId: 'project',
      priority: 4,
      status: completed ? 'completed' : 'open',
      completedFocusIntervals: 0,
      totalFocusSeconds: 0,
      orderKey: index.toString().padLeft(4, '0'),
      isDeleted: false,
      createdAt: now,
      updatedAt: now,
      completedAt: completed ? now : null,
    );
  }
}

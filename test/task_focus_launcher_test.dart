import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/features/focus/domain/focus_models.dart';
import 'package:pomodoist/features/tasks/domain/task_models.dart';
import 'package:pomodoist/features/tasks/presentation/task_focus_launcher.dart';

void main() {
  test(
    'starts with the selected preset and task estimate when no session exists',
    () async {
      final repository = _FocusRepository();
      final launcher = TaskFocusLauncher(repository);
      expect(
        await launcher.open(
          _task,
          preset: _preset,
          confirmSwitch: () async => fail('No confirmation needed'),
        ),
        isTrue,
      );
      final input = repository.starts.single;
      expect(input.taskId, _task.id);
      expect(input.projectId, _task.projectId);
      expect(input.presetId, _preset.id);
      expect(input.targetWorkIntervals, 3);
    },
  );

  for (final status in ['active', 'paused']) {
    test(
      'opens the same $status task without restarting or resuming',
      () async {
        final repository = _FocusRepository()
          ..active = _run('existing', _task.id, status: status);
        final launcher = TaskFocusLauncher(repository);
        expect(
          await launcher.open(
            _task,
            preset: _preset,
            confirmSwitch: () async => fail('No confirmation needed'),
          ),
          isTrue,
        );
        expect(repository.starts, isEmpty);
        expect(repository.active!.status, status);
        expect(repository.active!.id, 'existing');
      },
    );
  }

  test('a canceled switch preserves the other task session', () async {
    final repository = _FocusRepository()
      ..active = _run('existing', 'other', status: 'paused');
    final launcher = TaskFocusLauncher(repository);
    expect(
      await launcher.open(
        _task,
        preset: _preset,
        confirmSwitch: () async => false,
      ),
      isFalse,
    );
    expect(repository.starts, isEmpty);
    expect(repository.active!.taskId, 'other');
    expect(repository.active!.status, 'paused');
    expect(
      await launcher.open(
        _task,
        preset: _preset,
        confirmSwitch: () async => true,
      ),
      isTrue,
    );
    expect(repository.starts.length, 1);
  });

  test('a new session during confirmation needs its own consent', () async {
    final repository = _FocusRepository()..active = _run('first', 'other');
    final launcher = TaskFocusLauncher(repository);
    var confirmations = 0;
    expect(
      await launcher.open(
        _task,
        preset: _preset,
        confirmSwitch: () async {
          confirmations++;
          if (confirmations == 1) {
            repository.active = _run('second', 'third');
            return true;
          }
          return false;
        },
      ),
      isFalse,
    );
    expect(confirmations, 2);
    expect(repository.active!.id, 'second');
    expect(repository.starts, isEmpty);
  });

  test(
    'repeated starts are ignored while pending and failure releases the guard',
    () async {
      final pending = Completer<void>();
      final repository = _FocusRepository()..beforeStart = () => pending.future;
      final launcher = TaskFocusLauncher(repository);
      final first = launcher.open(
        _task,
        preset: _preset,
        confirmSwitch: () async => true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        await launcher.open(
          _task,
          preset: _preset,
          confirmSwitch: () async => true,
        ),
        isFalse,
      );
      expect(repository.starts.length, 1);
      final failed = expectLater(first, throwsStateError);
      pending.completeError(StateError('offline'));
      await failed;
      repository.beforeStart = null;
      expect(
        await launcher.open(
          _task,
          preset: _preset,
          confirmSwitch: () async => true,
        ),
        isTrue,
      );
      expect(repository.starts.length, 2);
    },
  );
}

final _now = DateTime.utc(2026, 9, 9);
final _task = TaskItem(
  id: 'task',
  userId: 'user',
  content: 'Task',
  projectId: 'project',
  priority: 4,
  status: 'open',
  estimatedFocusIntervals: 3,
  completedFocusIntervals: 1,
  totalFocusSeconds: 0,
  orderKey: '1',
  isDeleted: false,
  createdAt: _now,
  updatedAt: _now,
);
final _preset = FocusPresetItem(
  id: 'selected',
  userId: 'user',
  name: 'Preset',
  workSeconds: 1500,
  shortBreakSeconds: 300,
  longBreakSeconds: 900,
  intervalsBeforeLongBreak: 4,
  autoStartBreaks: false,
  autoStartWork: false,
  allowPause: true,
  strictMode: false,
  isDefault: false,
  createdAt: _now,
  updatedAt: _now,
);
FocusRunItem _run(String id, String? taskId, {String status = 'active'}) =>
    FocusRunItem(
      id: id,
      userId: 'user',
      taskId: taskId,
      presetId: 'preset',
      status: status,
      startedAt: _now,
      targetWorkIntervals: 4,
      completedWorkIntervals: 1,
      createdAt: _now,
      updatedAt: _now,
    );

class _FocusRepository implements FocusRepository {
  FocusRunItem? active;
  final starts = <StartFocusRunInput>[];
  Future<void> Function()? beforeStart;

  @override
  Stream<FocusRunItem?> watchActiveRun() => Stream.value(active);

  @override
  Future<String> startRun(StartFocusRunInput input, {DateTime? now}) async {
    starts.add(input);
    await beforeStart?.call();
    active = _run('new', input.taskId);
    return 'new';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pomodoist/config/shared_focus_effects.dart';
import 'package:pomodoist/data/services/audio/focus_sound_player.dart';
import 'package:pomodoist/data/services/notifications/notification_scheduler.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'package:pomodoist/domain/models/tasks/local_completion_event.dart';

class Sounds implements FocusSoundPlayer {
  final cues = <FocusSoundCue>[];
  @override
  Future<void> play(FocusSoundCue cue) async => cues.add(cue);
  @override
  Future<void> dispose() async {}
}

class Notifications extends NotificationScheduler {
  final ends = <DateTime>[];
  var cancels = 0;
  bool fail = false;
  @override
  Future<void> cancelFocusNotification() async {
    if (fail) throw StateError('Notification unavailable');
    cancels++;
  }

  @override
  Future<void> scheduleFocusIntervalEnd({
    required DateTime expectedEndAt,
    required String title,
    required String body,
  }) async => ends.add(expectedEndAt);
}

final now = DateTime.utc(2026, 10, 26, 12);
Map<String, dynamic> state({
  String run = 'r',
  String interval = 'i',
  String phase = 'work',
  String status = 'running',
  String runStatus = 'active',
  int count = 0,
  int revision = 1,
  String? action,
  DateTime? start,
  DateTime? serverNow,
  int pausedTotal = 0,
}) => {
  'id': run,
  'revision': revision,
  'serverNow': (serverNow ?? now).toIso8601String(),
  'effectAction': ?action,
  'taskTitle': 'Draft chapter',
  'run': {
    'id': run,
    'status': runStatus,
    'taskId': 'task',
    'completedWorkIntervals': count,
    'targetWorkIntervals': 1,
    'endedAt': runStatus == 'completed' ? now.toIso8601String() : null,
  },
  'interval': {
    'id': interval,
    'runId': run,
    'type': phase,
    'status': status,
    'startedAt': (start ?? now).toIso8601String(),
    'plannedSeconds': 1500,
    'pausedTotalSeconds': pausedTotal,
  },
};

void main() {
  late SharedPreferences prefs;
  late Sounds sounds;
  late Notifications notifications;
  late List<LocalCompletionEvent> intervals;
  late List<FocusRunCompletionEvent> runs;
  SharedFocusEffects create({String owner = 'u', bool celebrate = true}) =>
      SharedFocusEffects(
        owner: owner,
        preferences: prefs,
        notifications: notifications,
        sounds: sounds,
        onIntervalCompleted: intervals.add,
        onRunCompleted: runs.add,
        celebrationEnabled: () => celebrate,
        clock: () => now,
      );
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    sounds = Sounds();
    notifications = Notifications();
    intervals = [];
    runs = [];
  });

  test(
    'restore schedules current future end without replaying transient effects',
    () async {
      final effects = create();
      await effects.transition(state(), state());
      expect(notifications.ends, [now.add(const Duration(minutes: 25))]);
      expect(sounds.cues, isEmpty);
      await effects.transition(
        state(runStatus: 'completed'),
        state(runStatus: 'completed'),
      );
      expect(runs, isEmpty);
      expect(intervals, isEmpty);
      expect(notifications.cancels, 1);
    },
  );

  test(
    'start pause resume ready and stop reconcile notifications and sounds',
    () async {
      final effects = create();
      await effects.transition(null, null);
      final running = state();
      await effects.transition(null, running);
      await effects.transition(running, running);
      final paused = state(status: 'paused', revision: 2, action: 'pause');
      await effects.transition(running, paused);
      final resumed = state(revision: 3, action: 'resume', pausedTotal: 30);
      await effects.transition(paused, resumed);
      final ready = state(
        interval: 'b',
        phase: 'shortBreak',
        status: 'ready',
        revision: 4,
        action: 'skip',
      );
      await effects.transition(resumed, ready);
      final breakRunning = state(
        interval: 'b',
        phase: 'shortBreak',
        revision: 5,
        action: 'startReady',
      );
      await effects.transition(ready, breakRunning);
      await effects.transition(
        breakRunning,
        state(runStatus: 'stopped', status: 'stopped', revision: 6),
      );
      expect(sounds.cues, [
        FocusSoundCue.start,
        FocusSoundCue.pause,
        FocusSoundCue.resume,
        FocusSoundCue.start,
      ]);
      expect(notifications.ends, [
        now.add(const Duration(minutes: 25)),
        now.add(const Duration(minutes: 25, seconds: 30)),
        now.add(const Duration(minutes: 25)),
      ]);
      expect(intervals, isEmpty);
      expect(runs, isEmpty);
      expect(notifications.cancels, 4); // Initial idle, pause, ready, stop.
    },
  );

  test(
    'work completion publishes once across repeated responses and process recreation',
    () async {
      final previous = state();
      final next = state(
        interval: 'b',
        phase: 'shortBreak',
        status: 'ready',
        count: 1,
        revision: 2,
        action: 'complete',
      );
      final effects = create();
      await effects.transition(null, previous);
      await Future.wait([
        effects.transition(previous, next),
        effects.transition(previous, next),
      ]);
      expect(intervals.single.operationId, 'interval:i');
      expect(intervals.single.entityId, 'i');
      expect(intervals.single.isTask, isFalse);
      expect(sounds.cues, [FocusSoundCue.complete]);
      final restored = create();
      await restored.transition(null, previous);
      await restored.transition(previous, next);
      expect(intervals, hasLength(1));
      expect(sounds.cues, hasLength(1));
    },
  );

  test(
    'final break skip presents linked-task completion once and honors setting',
    () async {
      final previous = state(interval: 'b', phase: 'longBreak', count: 1);
      final next = state(
        interval: 'b',
        phase: 'longBreak',
        status: 'skipped',
        runStatus: 'completed',
        count: 1,
        revision: 2,
        action: 'skip',
      );
      final effects = create();
      await effects.transition(null, previous);
      await effects.transition(previous, next);
      await effects.transition(previous, next);
      expect(sounds.cues, [FocusSoundCue.complete]);
      expect(runs.single.runId, 'r');
      expect(runs.single.taskTitle, 'Draft chapter');
      expect(runs.single.completedWorkIntervals, 1);
      expect(intervals, isEmpty);
      final disabled = create(owner: 'other', celebrate: false);
      await disabled.transition(null, previous);
      await disabled.transition(previous, next);
      expect(runs, hasLength(1));
    },
  );

  test(
    'non-final break skip stays quiet while manual break completion sounds',
    () async {
      final previous = state(interval: 'b', phase: 'shortBreak');
      final ready = state(
        interval: 'w2',
        status: 'ready',
        revision: 2,
        action: 'skip',
      );
      final effects = create();
      await effects.transition(null, previous);
      await effects.transition(previous, ready);
      expect(sounds.cues, isEmpty);
      final completed = {...ready, 'revision': 3, 'effectAction': 'complete'};
      await effects.transition(previous, completed);
      expect(sounds.cues, [FocusSoundCue.complete]);
      expect(intervals, isEmpty);
    },
  );

  test(
    'server expiry read completes known break and corrects notification clock',
    () async {
      final server = now.add(const Duration(hours: 2));
      final previous = state(
        interval: 'b',
        phase: 'shortBreak',
        start: server.subtract(const Duration(minutes: 25)),
        serverNow: server.subtract(const Duration(seconds: 1)),
      );
      final effects = create();
      await effects.transition(null, previous);
      expect(notifications.ends.single, now.add(const Duration(seconds: 1)));
      await effects.transition(
        previous,
        state(
          interval: 'w2',
          status: 'ready',
          revision: 2,
          action: 'read',
          serverNow: server,
        ),
      );
      expect(sounds.cues, [FocusSoundCue.complete]);
    },
  );

  test('terminal restore is silent and restart only reschedules', () async {
    final effects = create();
    await effects.transition(
      null,
      state(runStatus: 'completed', status: 'completed'),
    );
    expect(sounds.cues, isEmpty);
    expect(runs, isEmpty);
    final running = state();
    await effects.transition(null, running);
    final reset = state(
      revision: 2,
      action: 'restart',
      start: now.add(const Duration(seconds: 20)),
    );
    await effects.transition(running, reset);
    expect(sounds.cues, [FocusSoundCue.start]);
    expect(
      notifications.ends.last,
      now.add(const Duration(minutes: 25, seconds: 20)),
    );
  });
  test(
    'adoption retains notification without replaying the local start sound',
    () async {
      final effects = create();
      await effects.transition(null, null);
      await effects.transition(null, state(action: 'adopt'));
      expect(notifications.ends, hasLength(1));
      expect(sounds.cues, isEmpty);
    },
  );

  test(
    'uses RPC observation time and presentation failures leave completion accepted',
    () async {
      final previous = {
        ...state(),
        'effectObservedAt': now
            .subtract(const Duration(seconds: 2))
            .toIso8601String(),
      };
      final effects = create();
      await effects.transition(null, previous);
      expect(
        notifications.ends.single,
        now.add(const Duration(minutes: 24, seconds: 58)),
      );
      notifications.fail = true;
      final next = state(
        interval: 'b',
        phase: 'shortBreak',
        status: 'ready',
        count: 1,
        revision: 2,
        action: 'complete',
      );
      await effects.transition(previous, next);
      expect(intervals, hasLength(1));
      expect(sounds.cues, [FocusSoundCue.complete]);
      expect(
        prefs.getStringList('distractions.effects.v1.u'),
        contains('interval:i'),
      );
    },
  );
}

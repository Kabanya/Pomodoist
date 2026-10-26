import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pomodoist/config/focus_dependencies.dart';
import 'package:pomodoist/config/local_completion_dependencies.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/data/services/audio/focus_sound_player.dart';
import 'package:pomodoist/data/services/notifications/notification_scheduler.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'package:pomodoist/domain/models/tasks/local_completion_event.dart';

final sharedFocusEffectsProvider = Provider.family<SharedFocusEffects, String>((
  ref,
  owner,
) {
  return SharedFocusEffects(
    owner: owner,
    preferences: ref.watch(sharedPreferencesProvider).value,
    notifications: ref.watch(notificationSchedulerProvider),
    sounds: ref.watch(focusSoundPlayerProvider),
    onIntervalCompleted: ref.watch(localCompletionEventsProvider).publish,
    onRunCompleted: ref.watch(focusCompletionRepositoryProvider).present,
    celebrationEnabled: () =>
        ref.read(focusCompletionCelebrationEnabledProvider),
  );
});

/// Presentation effects for persisted, authoritative shared Focus transitions.
///
/// The first observation only reconciles the notification: restored history must
/// not replay celebrations or sound. Effects never mutate Focus/task history.
class SharedFocusEffects {
  SharedFocusEffects({
    required this.owner,
    required this.preferences,
    required this.notifications,
    required this.sounds,
    required this.onIntervalCompleted,
    required this.onRunCompleted,
    required this.celebrationEnabled,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final String owner;
  final SharedPreferences? preferences;
  final NotificationScheduler notifications;
  final FocusSoundPlayer sounds;
  final void Function(LocalCompletionEvent event) onIntervalCompleted;
  final void Function(FocusRunCompletionEvent event) onRunCompleted;
  final bool Function() celebrationEnabled;
  final DateTime Function() _now;
  bool _initialized = false;
  String? _notificationState;
  Set<String>? _claimed;
  Future<void> _tail = Future.value();
  String get _key => 'distractions.effects.v1.$owner';

  /// Call after saving the accepted session, while command serialization is held.
  /// `next.effectAction` may carry the local command name to distinguish skip
  /// from early completion; it is presentation metadata, never sent to the server.
  Future<void> transition(
    Map<String, dynamic>? previous,
    Map<String, dynamic>? next,
  ) {
    final result = _tail.then((_) => _transition(previous, next));
    // Presentation failures cannot invalidate an accepted Focus command.
    _tail = result.catchError((Object _) {});
    return _tail;
  }

  Future<void> _transition(Map? previous, Map? next) async {
    final baseline = !_initialized;
    _initialized = true;
    await _notification(next);
    if (baseline || next?['effectAction'] == 'adopt') return;
    final oldRun = _map(previous?['run']), run = _map(next?['run']);
    final oldInterval = _map(previous?['interval']);
    final interval = _map(next?['interval']);
    final sameRun = oldRun?['id'] == run?['id'] && run?['id'] != null;
    final wasActive = _active(oldRun);
    final completedRun = sameRun && wasActive && run?['status'] == 'completed';
    final completedWork =
        sameRun &&
        wasActive &&
        oldInterval?['type'] == 'work' &&
        _integer(run?['completedWorkIntervals']) >
            _integer(oldRun?['completedWorkIntervals']);
    final advancedBreak =
        sameRun &&
        wasActive &&
        oldInterval != null &&
        oldInterval['type'] != 'work' &&
        oldInterval['status'] == 'running' &&
        oldInterval['id'] != interval?['id'] &&
        next?['effectAction'] != 'skip' &&
        (next?['effectAction'] == 'complete' || _expired(previous, next));

    FocusSoundCue? cue;
    if (completedRun || completedWork || advancedBreak) {
      cue = FocusSoundCue.complete;
    } else if (sameRun && interval?['id'] == oldInterval?['id']) {
      if (oldInterval?['status'] == 'running' &&
          interval?['status'] == 'paused') {
        cue = FocusSoundCue.pause;
      } else if (oldInterval?['status'] == 'paused' &&
          interval?['status'] == 'running') {
        cue = FocusSoundCue.resume;
      } else if (oldInterval?['status'] == 'ready' &&
          interval?['status'] == 'running') {
        cue = FocusSoundCue.start;
      }
    } else if (_active(run) && interval?['status'] == 'running' && !sameRun) {
      cue = FocusSoundCue.start;
    }
    if (cue != null &&
        await _claim('sound:${run?['id']}:${next?['revision']}:${cue.name}')) {
      await _bestEffort(() => sounds.play(cue!));
    }
    if (completedWork &&
        oldInterval?['id'] is String &&
        await _claim('interval:${oldInterval!['id']}')) {
      await _bestEffort(
        () async => onIntervalCompleted(
          LocalCompletionEvent(
            operationId: 'interval:${oldInterval['id']}',
            entityId: oldInterval['id'] as String,
            isTask: false,
          ),
        ),
      );
    }
    if (completedRun &&
        await _claim('run:${run!['id']}') &&
        celebrationEnabled()) {
      final ended = DateTime.tryParse('${run['endedAt']}');
      await _bestEffort(
        () async => onRunCompleted(
          FocusRunCompletionEvent(
            runId: run['id'] as String,
            taskId: run['taskId'] as String?,
            taskTitle: next?['taskTitle'] as String?,
            completedWorkIntervals: _integer(run['completedWorkIntervals']),
            targetWorkIntervals: _integer(run['targetWorkIntervals']),
            completedAt: ended == null ? _now() : _localTime(ended, next),
          ),
        ),
      );
    }
  }

  Future<bool> _claim(String id) async {
    _claimed ??= (preferences?.getStringList(_key) ?? []).toSet();
    if (!_claimed!.add(id)) return false;
    // Session/revision IDs are monotonic; bound local presentation bookkeeping.
    while (_claimed!.length > 1024) {
      _claimed!.remove(_claimed!.first);
    }
    try {
      return preferences == null ||
          await preferences!.setStringList(_key, _claimed!.toList());
    } on Object {
      return false; // Prefer a missed transient effect to an unrecorded replay.
    }
  }

  Future<void> _notification(Map? next) async {
    final run = _map(next?['run']), interval = _map(next?['interval']);
    final signature = jsonEncode([run?['id'], run?['status'], interval]);
    if (_notificationState == signature) return;
    try {
      final end = _expectedEnd(interval);
      final localEnd = end == null ? null : _localTime(end, next);
      if (_active(run) &&
          interval?['status'] == 'running' &&
          localEnd != null &&
          localEnd.isAfter(_now())) {
        await notifications.scheduleFocusIntervalEnd(
          expectedEndAt: localEnd,
          title: 'pomodoist',
          body: notifications.focusCompletedBody(interval!['type'] as String),
        );
      } else {
        await notifications.cancelFocusNotification();
      }
      _notificationState = signature;
    } on Object {
      // Retry reconciliation on the next accepted observation.
    }
  }

  DateTime _localTime(DateTime serverTime, Map? session) {
    final serverNow = DateTime.tryParse('${session?['serverNow']}');
    final observed =
        DateTime.tryParse('${session?['effectObservedAt']}') ?? _now();
    return serverNow == null
        ? serverTime
        : serverTime.subtract(serverNow.difference(observed));
  }

  bool _expired(Map? previous, Map? next) {
    final end = _expectedEnd(_map(previous?['interval']));
    final observed = DateTime.tryParse('${next?['serverNow']}');
    return end != null && observed != null && !observed.isBefore(end);
  }
}

Map? _map(Object? value) => value is Map ? value : null;
int _integer(Object? value) => value is num ? value.toInt() : 0;
bool _active(Map? run) => ['active', 'paused'].contains(run?['status']);
DateTime? _expectedEnd(Map? interval) {
  final start = DateTime.tryParse('${interval?['startedAt']}');
  return start?.add(
    Duration(
      seconds:
          _integer(interval?['plannedSeconds']) +
          _integer(interval?['pausedTotalSeconds']),
    ),
  );
}

Future<void> _bestEffort(Future<void> Function() action) async {
  try {
    await action();
  } on Object {
    /* Presentation is advisory. */
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/data/repositories/settings/preferences_repository.dart';
import 'package:pomodoist/ui/habits/view_models/habit_presentation_view_model.dart';
import 'package:pomodoist/utils/result.dart';

void main() {
  test('progress capability uses outer width and excludes native mobile', () {
    for (final platform in TargetPlatform.values) {
      final desktop = {
        TargetPlatform.linux,
        TargetPlatform.macOS,
        TargetPlatform.windows,
      }.contains(platform);
      expect(
        habitProgressAvailable(959, isWeb: true, platform: platform),
        isFalse,
      );
      expect(
        habitProgressAvailable(960, isWeb: true, platform: platform),
        isTrue,
      );
      expect(
        habitProgressAvailable(960, isWeb: false, platform: platform),
        desktop,
      );
      expect(
        habitProgressAvailable(2000, isWeb: false, platform: platform),
        desktop,
      );
    }
  });

  ProviderContainer open(_Preferences preferences) {
    final container = ProviderContainer(
      overrides: [preferencesRepositoryProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);
    container.read(habitPresentationProvider);
    return container;
  }

  test(
    'defaults to rhythm, ignores obsolete key and restores persisted choice',
    () async {
      final preferences = _Preferences()
        ..values['habits.viewMode.v1'] = 'progress';
      final first = open(preferences);
      expect(first.read(habitPresentationProvider).loading, isTrue);
      await pumpEventQueue();
      expect(
        first.read(habitPresentationProvider).value,
        HabitPresentation.rhythm,
      );
      expect(preferences.readKeys, [habitPresentationKey]);
      await first
          .read(habitPresentationProvider.notifier)
          .select(HabitPresentation.progress);
      final reopened = open(preferences);
      await pumpEventQueue();
      expect(
        reopened.read(habitPresentationProvider).value,
        HabitPresentation.progress,
      );
    },
  );

  test(
    'read failure can retry and unknown stored values fall back safely',
    () async {
      final preferences = _Preferences()..readError = true;
      final container = open(preferences);
      await pumpEventQueue();
      expect(container.read(habitPresentationProvider).error, isTrue);
      preferences.readError = false;
      preferences.values[habitPresentationKey] = 'unknown';
      await container.read(habitPresentationProvider.notifier).retry();
      expect(container.read(habitPresentationProvider).error, isFalse);
      expect(
        container.read(habitPresentationProvider).value,
        HabitPresentation.rhythm,
      );
    },
  );

  test(
    'failed save retains session choice; retries serialize only preference writes',
    () async {
      final preferences = _Preferences()..writeError = true;
      final container = open(preferences);
      await pumpEventQueue();
      final vm = container.read(habitPresentationProvider.notifier);
      await vm.select(HabitPresentation.progress);
      expect(
        container.read(habitPresentationProvider).value,
        HabitPresentation.progress,
      );
      expect(container.read(habitPresentationProvider).error, isTrue);
      preferences.writeError = false;
      preferences.gate = Completer<void>();
      final retry = vm.retry();
      expect(container.read(habitPresentationProvider).saving, isTrue);
      await vm.select(HabitPresentation.rhythm);
      expect(preferences.writes, 2);
      preferences.gate!.complete();
      await retry;
      expect(container.read(habitPresentationProvider).saving, isFalse);
      expect(container.read(habitPresentationProvider).error, isFalse);
      expect(preferences.values[habitPresentationKey], 'progress');
    },
  );
}

class _Preferences implements PreferencesRepository {
  final values = <String, Object>{};
  List<String> readKeys = [];
  bool readError = false, writeError = false;
  int writes = 0;
  Completer<void>? gate;
  @override
  Future<Result<Map<String, Object>>> read(
    Iterable<String> keys, {
    bool reload = false,
  }) async {
    readKeys = keys.toList();
    if (readError) {
      return Result.error(Exception('read failed'), StackTrace.current);
    }
    return Result.ok({
      for (final key in keys)
        if (values.containsKey(key)) key: values[key]!,
    });
  }

  @override
  Future<Result<void>> write(Map<String, Object?> changes) async {
    writes++;
    if (gate != null) await gate!.future;
    if (writeError) {
      return Result.error(Exception('write failed'), StackTrace.current);
    }
    values.addAll(changes.cast<String, Object>());
    return const Result.ok(null);
  }
}

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/data/repositories/settings/preferences_repository.dart';
import 'package:pomodoist/data/repositories/settings/app_icon_repository.dart';
import 'package:pomodoist/config/app_icon_dependencies.dart';
import 'package:pomodoist/domain/models/settings/app_icon_choice.dart';
import 'package:pomodoist/ui/settings/view_models/app_icon_settings_view_model.dart';
import 'package:pomodoist/utils/result.dart';

void main() {
  test('new or unknown preferences use icon-light-pomo', () async {
    for (final stored in [null, 'unknown']) {
      final harness = Harness(stored);
      await harness.load();
      expect(harness.state.choice, AppIconChoice.pomo);
      expect(harness.platform.current, AppIconChoice.pomo);
      harness.dispose();
    }
  });

  test('restores classic and persists switching back to pomo', () async {
    final harness = Harness('classic');
    addTearDown(harness.dispose);
    await harness.load();
    expect(harness.platform.current, AppIconChoice.classic);
    await harness.controller.select(AppIconChoice.pomo);
    expect(harness.preferences.value, 'icon-light-pomo');
    expect(harness.state.choice, AppIconChoice.pomo);
    final calls = harness.platform.calls;
    await harness.controller.select(AppIconChoice.pomo);
    expect(harness.platform.calls, calls);
  });

  test('OS failure preserves selection and does not save', () async {
    final harness = Harness(null);
    addTearDown(harness.dispose);
    await harness.load();
    harness.platform.fail = true;
    await harness.controller.select(AppIconChoice.classic);
    expect(harness.state.choice, AppIconChoice.pomo);
    expect(harness.preferences.writes, 0);
    expect(harness.state.error, isNotNull);
    expect(harness.state.isSaving, isFalse);
  });

  test('failed persistence rolls native icon back and permits retry', () async {
    final harness = Harness(null);
    addTearDown(harness.dispose);
    await harness.load();
    harness.preferences.fail = true;
    await harness.controller.select(AppIconChoice.classic);
    expect(harness.platform.current, AppIconChoice.pomo);
    expect(harness.state.choice, AppIconChoice.pomo);
    expect(harness.state.error, isNotNull);
    harness.preferences.fail = false;
    await harness.controller.select(AppIconChoice.classic);
    expect(harness.state.error, isNull);
    expect(harness.preferences.value, 'classic');
  });

  test('failed rollback reports the actual native selection', () async {
    final harness = Harness(null);
    addTearDown(harness.dispose);
    await harness.load();
    harness.preferences.fail = true;
    harness.platform.failingChoice = AppIconChoice.pomo;
    await harness.controller.select(AppIconChoice.classic);
    expect(harness.preferences.value, isNull);
    expect(harness.state.choice, AppIconChoice.classic);
    expect(harness.state.error, isNotNull);
    expect(harness.state.isSaving, isFalse);
  });

  test('selection is blocked during loading and native application', () async {
    final harness = Harness(null);
    addTearDown(harness.dispose);
    final controller = harness.controller;
    await controller.select(AppIconChoice.classic);
    await harness.load();
    expect(harness.preferences.writes, 0);
    final gate = Completer<void>();
    harness.platform.gate = gate.future;
    final selecting = controller.select(AppIconChoice.classic);
    await controller.select(AppIconChoice.pomo);
    expect(harness.state.isSaving, isTrue);
    gate.complete();
    await selecting;
    expect(harness.preferences.value, 'classic');
  });

  test('load failure is visible and retry restores saved choice', () async {
    final harness = Harness('classic');
    addTearDown(harness.dispose);
    harness.preferences.failRead = true;
    await harness.load();
    expect(harness.state.isLoaded, isFalse);
    expect(harness.state.error, isNotNull);
    harness.preferences.failRead = false;
    await harness.controller.load();
    expect(harness.state.choice, AppIconChoice.classic);
    expect(harness.state.isLoaded, isTrue);
    expect(harness.state.error, isNull);
  });
}

class Harness {
  Harness(String? stored) : preferences = MemoryPreferences(stored) {
    container = ProviderContainer(
      overrides: [
        preferencesRepositoryProvider.overrideWithValue(preferences),
        appIconRepositoryProvider.overrideWithValue(platform),
      ],
    );
    subscription = container.listen(appIconSettingsProvider, (_, _) {});
  }
  final MemoryPreferences preferences;
  final platform = RecordingPlatform();
  late final ProviderContainer container;
  late final ProviderSubscription<AppIconSettingsState> subscription;
  AppIconSettingsViewModel get controller =>
      container.read(appIconSettingsProvider.notifier);
  AppIconSettingsState get state => container.read(appIconSettingsProvider);
  Future<void> load() async {
    await controller.ready;
    await container.pump();
  }

  void dispose() {
    subscription.close();
    container.dispose();
  }
}

class RecordingPlatform implements AppIconRepository {
  AppIconChoice current = AppIconChoice.pomo;
  bool fail = false;
  AppIconChoice? failingChoice;
  int calls = 0;
  Future<void>? gate;
  @override
  Future<AppIconChoice> read() async => current;
  @override
  Future<void> apply(AppIconChoice choice) async {
    calls++;
    await gate;
    if (fail || choice == failingChoice) throw StateError('OS refused icon');
    current = choice;
  }
}

class MemoryPreferences implements PreferencesRepository {
  MemoryPreferences(this.value);
  String? value;
  bool fail = false;
  bool failRead = false;
  int writes = 0;
  @override
  Future<Result<Map<String, Object>>> read(
    Iterable<String> keys, {
    bool reload = false,
  }) async => failRead
      ? Result.error(StateError('read failed'), StackTrace.current)
      : Result.ok({'app.icon': ?value});
  @override
  Future<Result<void>> write(Map<String, Object?> values) async {
    writes++;
    if (fail) {
      return Result.error(StateError('save failed'), StackTrace.current);
    }
    value = values['app.icon'] as String?;
    return const Result.ok(null);
  }
}

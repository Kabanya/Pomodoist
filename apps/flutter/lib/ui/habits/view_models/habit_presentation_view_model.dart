import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/data/repositories/settings/preferences_repository.dart';

enum HabitPresentation { rhythm, progress }

const habitPresentationKey = 'habits.presentation.v1';

bool habitProgressAvailable(
  double width, {
  bool isWeb = kIsWeb,
  TargetPlatform? platform,
}) =>
    width >= 960 &&
    (isWeb ||
        const {
          TargetPlatform.macOS,
          TargetPlatform.windows,
          TargetPlatform.linux,
        }.contains(platform ?? defaultTargetPlatform));

class HabitPresentationState {
  const HabitPresentationState({
    this.value = HabitPresentation.rhythm,
    this.loading = false,
    this.saving = false,
    this.error = false,
  });
  final HabitPresentation value;
  final bool loading, saving, error;
}

final habitPresentationProvider =
    NotifierProvider<HabitPresentationViewModel, HabitPresentationState>(
      HabitPresentationViewModel.new,
    );

class HabitPresentationViewModel extends Notifier<HabitPresentationState> {
  late PreferencesRepository _preferences;
  bool _loaded = false;

  @override
  HabitPresentationState build() {
    _preferences = ref.watch(preferencesRepositoryProvider);
    unawaited(_load());
    return const HabitPresentationState(loading: true);
  }

  Future<void> _load() async {
    try {
      final values = (await _preferences.read([
        habitPresentationKey,
      ])).getOrThrow();
      if (!ref.mounted) return;
      _loaded = true;
      state = HabitPresentationState(
        value:
            HabitPresentation.values
                .where((v) => v.name == values[habitPresentationKey])
                .firstOrNull ??
            HabitPresentation.rhythm,
      );
    } catch (_) {
      if (ref.mounted) state = const HabitPresentationState(error: true);
    }
  }

  Future<void> select(HabitPresentation value) async {
    if (state.loading || state.saving) return;
    _loaded = true;
    await _save(value);
  }

  Future<void> _save(HabitPresentation value) async {
    state = HabitPresentationState(value: value, saving: true);
    try {
      (await _preferences.write({
        habitPresentationKey: value.name,
      })).getOrThrow();
      if (ref.mounted) state = HabitPresentationState(value: value);
    } catch (_) {
      if (ref.mounted) {
        state = HabitPresentationState(value: value, error: true);
      }
    }
  }

  Future<void> retry() async {
    if (state.loading || state.saving) return;
    if (_loaded) {
      await _save(state.value);
    } else {
      state = const HabitPresentationState(loading: true);
      await _load();
    }
  }
}

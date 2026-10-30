import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/data/repositories/settings/preferences_repository.dart';
import 'package:pomodoist/data/repositories/settings/app_icon_repository.dart';
import 'package:pomodoist/config/app_icon_dependencies.dart';
import 'package:pomodoist/domain/models/settings/app_icon_choice.dart';

final appIconSettingsProvider =
    NotifierProvider<AppIconSettingsViewModel, AppIconSettingsState>(
      AppIconSettingsViewModel.new,
    );

class AppIconSettingsState {
  const AppIconSettingsState({
    this.choice = AppIconChoice.pomo,
    this.isLoaded = false,
    this.isSaving = false,
    this.error,
  });
  final AppIconChoice choice;
  final bool isLoaded;
  final bool isSaving;
  final Object? error;
}

class AppIconSettingsViewModel extends Notifier<AppIconSettingsState> {
  late PreferencesRepository _preferences;
  late AppIconRepository _platform;
  late Future<void> ready;

  @override
  AppIconSettingsState build() {
    _preferences = ref.watch(preferencesRepositoryProvider);
    _platform = ref.watch(appIconRepositoryProvider);
    ready = Future.microtask(load);
    return const AppIconSettingsState();
  }

  Future<void> load() async {
    if (state.isSaving) return;
    state = AppIconSettingsState(choice: state.choice, isSaving: true);
    try {
      final values = (await _preferences.read(['app.icon'])).getOrThrow();
      final choice = AppIconChoice.fromId(values['app.icon']);
      await _platform.apply(choice);
      if (ref.mounted) {
        state = AppIconSettingsState(choice: choice, isLoaded: true);
      }
    } catch (error) {
      if (ref.mounted) state = AppIconSettingsState(error: error);
    }
  }

  Future<void> refresh() async {
    if (state.isSaving) throw StateError('Icon is busy');
    final values = (await _preferences.read(['app.icon'])).getOrThrow();
    final choice = AppIconChoice.fromId(values['app.icon']);
    if (!state.isLoaded || choice != state.choice) await load();
  }

  Future<void> selectStrict(
    AppIconChoice choice, {
    bool Function()? isCurrent,
  }) async {
    if (!state.isLoaded || state.isSaving) throw StateError('Icon is busy');
    await select(choice, isCurrent: isCurrent);
    if (!ref.mounted) throw StateError('Icon controller disposed');
    if (state.error != null) throw state.error!;
    if (state.choice != choice) throw StateError('Icon was not applied');
  }

  Future<void> select(
    AppIconChoice choice, {
    bool Function()? isCurrent,
  }) async {
    if (!state.isLoaded || state.isSaving || choice == state.choice) return;
    final previous = state.choice;
    state = AppIconSettingsState(
      choice: previous,
      isLoaded: true,
      isSaving: true,
    );
    try {
      await _platform.apply(choice);
      try {
        if (isCurrent != null && !isCurrent()) {
          throw StateError('Settings session expired');
        }
        (await _preferences.write({'app.icon': choice.id})).getOrThrow();
      } catch (_) {
        await _platform.apply(previous);
        rethrow;
      }
      if (ref.mounted) {
        state = AppIconSettingsState(choice: choice, isLoaded: true);
      }
    } catch (error) {
      var current = previous;
      try {
        current = await _platform.read();
      } catch (_) {
        /* Keep the last acknowledged choice. */
      }
      if (ref.mounted) {
        state = AppIconSettingsState(
          choice: current,
          isLoaded: true,
          error: error,
        );
      }
    }
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/config/theme_mode_dependencies.dart';

export 'package:pomodoist/config/theme_mode_dependencies.dart'
    show sharedThemeCookieReaderProvider, sharedThemeCookieWriterProvider;

const appThemeModePreferenceKey = 'app.themeMode';

enum AppThemeMode {
  system(ThemeMode.system),
  light(ThemeMode.light),
  dark(ThemeMode.dark);

  const AppThemeMode(this.themeMode);

  final ThemeMode themeMode;

  String get storageValue => name;

  static AppThemeMode? tryFromStorageValue(String? value) {
    for (final mode in AppThemeMode.values) {
      if (mode.storageValue == value) return mode;
    }
    return null;
  }

  static AppThemeMode fromStorageValue(String? value) {
    return tryFromStorageValue(value) ?? AppThemeMode.system;
  }
}

AppThemeMode? appThemeModeFromCookieHeader(String cookieHeader) {
  for (final cookie in cookieHeader.split(';')) {
    final parts = cookie.trim().split('=');
    if (parts.length == 2 && parts.first == 'pomodoist-theme') {
      return AppThemeMode.tryFromStorageValue(parts.last);
    }
  }
  return null;
}

final appThemeModeProvider =
    NotifierProvider<AppThemeModeController, AppThemeMode>(
      AppThemeModeController.new,
    );

class AppThemeModeController extends Notifier<AppThemeMode> {
  bool _loaded = false;
  bool _hasLocalSelection = false;
  AppLifecycleListener? _lifecycleListener;

  @override
  AppThemeMode build() {
    _lifecycleListener ??= AppLifecycleListener(
      onResume: () {
        unawaited(_loadStoredThemeMode(allowSharedOverride: true));
      },
    );
    ref.onDispose(() => _lifecycleListener?.dispose());

    final sharedMode = appThemeModeFromCookieHeader(
      ref.read(sharedThemeCookieReaderProvider)(),
    );
    if (!_loaded) {
      _loaded = true;
      unawaited(_loadStoredThemeMode());
    }
    return sharedMode ?? AppThemeMode.system;
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    _hasLocalSelection = true;
    ref.read(sharedThemeCookieWriterProvider)(mode.storageValue);
    if (state != mode) {
      state = mode;
    }
    (await ref.read(preferencesRepositoryProvider).write({
      appThemeModePreferenceKey: mode.storageValue,
    })).getOrThrow();
  }

  Future<void> _loadStoredThemeMode({bool allowSharedOverride = false}) async {
    final preferences = ref.read(preferencesRepositoryProvider);
    final values = (await preferences.read(const [
      appThemeModePreferenceKey,
    ])).getOrThrow();
    final sharedMode = appThemeModeFromCookieHeader(
      ref.read(sharedThemeCookieReaderProvider)(),
    );
    final storedMode = AppThemeMode.tryFromStorageValue(
      values[appThemeModePreferenceKey] as String?,
    );
    if (!ref.mounted || (_hasLocalSelection && !allowSharedOverride)) return;

    if (sharedMode != null) {
      if (storedMode != sharedMode) {
        (await preferences.write({
          appThemeModePreferenceKey: sharedMode.storageValue,
        })).getOrThrow();
      }
      if (ref.mounted && (!_hasLocalSelection || allowSharedOverride)) {
        state = sharedMode;
      }
      return;
    }

    if (storedMode != null) {
      ref.read(sharedThemeCookieWriterProvider)(storedMode.storageValue);
    }
    if (ref.mounted && (!_hasLocalSelection || allowSharedOverride)) {
      state = storedMode ?? AppThemeMode.system;
    }
  }
}

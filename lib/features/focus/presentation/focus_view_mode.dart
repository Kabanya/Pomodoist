import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const focusViewModePreferenceKey = 'focus.viewMode';
const focusTimerVisualStylePreferenceKey = 'focus.timerVisualStyle';
const lastFocusPresetIdPreferenceKey = 'focus.lastPresetId';
const focusCompletionCelebrationEnabledPreferenceKey =
    'focus.completionCelebration.enabled';

enum FocusViewMode {
  full('full'),
  minimal('minimal');

  const FocusViewMode(this.storageValue);

  final String storageValue;

  static FocusViewMode fromStorageValue(String? value) {
    return switch (value) {
      'full' => FocusViewMode.full,
      _ => FocusViewMode.minimal,
    };
  }
}

enum FocusTimerVisualStyle {
  bar('bar'),
  circle('circle');

  const FocusTimerVisualStyle(this.storageValue);

  final String storageValue;

  static FocusTimerVisualStyle fromStorageValue(String? value) {
    return switch (value) {
      'circle' => FocusTimerVisualStyle.circle,
      'bar' => FocusTimerVisualStyle.bar,
      _ => FocusTimerVisualStyle.circle,
    };
  }
}

final sharedPreferencesProvider = FutureProvider<SharedPreferences?>((ref) {
  return _sharedPreferences();
});

Future<SharedPreferences?> _sharedPreferences() async {
  try {
    return await SharedPreferences.getInstance();
  } on MissingPluginException {
    return null;
  }
}

final focusViewModeProvider =
    NotifierProvider<FocusViewModeController, FocusViewMode>(
      FocusViewModeController.new,
    );

final focusTimerVisualStyleProvider =
    NotifierProvider<FocusTimerVisualStyleController, FocusTimerVisualStyle>(
      FocusTimerVisualStyleController.new,
    );

final lastFocusPresetIdProvider =
    NotifierProvider<LastFocusPresetIdController, String?>(
      LastFocusPresetIdController.new,
    );

final focusCompletionCelebrationEnabledProvider =
    NotifierProvider<FocusCompletionCelebrationEnabledController, bool>(
      FocusCompletionCelebrationEnabledController.new,
    );

class FocusCompletionCelebrationEnabledController extends Notifier<bool> {
  bool _loaded = false;
  bool _hasLocalSelection = false;

  @override
  bool build() {
    if (!_loaded) {
      _loaded = true;
      unawaited(_loadStoredValue());
    }
    return true;
  }

  Future<void> setEnabled(bool enabled) async {
    _hasLocalSelection = true;
    state = enabled;
    final prefs = await ref.read(sharedPreferencesProvider.future);
    await prefs?.setBool(
      focusCompletionCelebrationEnabledPreferenceKey,
      enabled,
    );
  }

  Future<void> _loadStoredValue() async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    final stored =
        prefs?.getBool(focusCompletionCelebrationEnabledPreferenceKey) ?? true;
    if (ref.mounted && !_hasLocalSelection) {
      state = stored;
    }
  }
}

class FocusViewModeController extends Notifier<FocusViewMode> {
  bool _loaded = false;
  bool _hasLocalSelection = false;

  @override
  FocusViewMode build() {
    if (!_loaded) {
      _loaded = true;
      unawaited(_loadStoredMode());
    }
    return FocusViewMode.minimal;
  }

  Future<void> setMode(FocusViewMode mode) async {
    _hasLocalSelection = true;
    if (state != mode) {
      state = mode;
    }
    final prefs = await ref.read(sharedPreferencesProvider.future);
    await prefs?.setString(focusViewModePreferenceKey, mode.storageValue);
  }

  Future<void> _loadStoredMode() async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    final stored = FocusViewMode.fromStorageValue(
      prefs?.getString(focusViewModePreferenceKey),
    );
    if (ref.mounted && !_hasLocalSelection) {
      state = stored;
    }
  }
}

class FocusTimerVisualStyleController extends Notifier<FocusTimerVisualStyle> {
  bool _loaded = false;
  bool _hasLocalSelection = false;

  @override
  FocusTimerVisualStyle build() {
    if (!_loaded) {
      _loaded = true;
      unawaited(_loadStoredStyle());
    }
    return FocusTimerVisualStyle.circle;
  }

  Future<void> setStyle(FocusTimerVisualStyle style) async {
    _hasLocalSelection = true;
    if (state != style) {
      state = style;
    }
    final prefs = await ref.read(sharedPreferencesProvider.future);
    await prefs?.setString(
      focusTimerVisualStylePreferenceKey,
      style.storageValue,
    );
  }

  Future<void> _loadStoredStyle() async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    final stored = FocusTimerVisualStyle.fromStorageValue(
      prefs?.getString(focusTimerVisualStylePreferenceKey),
    );
    if (ref.mounted && !_hasLocalSelection) {
      state = stored;
    }
  }
}

class LastFocusPresetIdController extends Notifier<String?> {
  bool _loaded = false;
  bool _hasLocalSelection = false;

  @override
  String? build() {
    if (!_loaded) {
      _loaded = true;
      unawaited(_loadStoredPresetId());
    }
    return null;
  }

  Future<void> setPresetId(String? id) async {
    _hasLocalSelection = true;
    state = id;
    final prefs = await ref.read(sharedPreferencesProvider.future);
    if (prefs == null) {
      return;
    }
    if (id == null || id.trim().isEmpty) {
      await prefs.remove(lastFocusPresetIdPreferenceKey);
    } else {
      await prefs.setString(lastFocusPresetIdPreferenceKey, id);
    }
  }

  Future<void> _loadStoredPresetId() async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    final stored = prefs?.getString(lastFocusPresetIdPreferenceKey);
    if (ref.mounted && !_hasLocalSelection) {
      state = stored;
    }
  }
}

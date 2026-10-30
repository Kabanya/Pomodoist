import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/focus_dependencies.dart';
import 'package:pomodoist/config/keyboard_shortcuts.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/data/services/platform/global_shortcut_codec.dart';
import 'package:pomodoist/domain/models/focus/focus_view_mode.dart';
import 'package:pomodoist/domain/models/platform/global_shortcut.dart';
import 'package:pomodoist/domain/models/settings/app_icon_choice.dart';
import 'package:pomodoist/domain/models/settings/bottom_navigation_preferences.dart';
import 'package:pomodoist/domain/models/settings/status_item_style.dart';
import 'package:pomodoist/domain/models/settings/task_preferences.dart';
import 'package:pomodoist/domain/models/settings/theme_image.dart';
import 'package:pomodoist/domain/models/tasks/task_time.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/view_models/app_theme_mode_view_model.dart';
import 'package:pomodoist/ui/core/view_models/app_zoom_view_model.dart';
import 'package:pomodoist/ui/settings/view_models/app_icon_settings_view_model.dart';
import 'package:pomodoist/ui/settings/view_models/bottom_navigation_view_model.dart';
import 'package:pomodoist/ui/settings/view_models/keyboard_shortcuts_view_model.dart';
import 'package:pomodoist/ui/settings/view_models/status_item_style_view_model.dart';
import 'package:pomodoist/ui/settings/view_models/task_settings_view_model.dart';
import 'package:pomodoist/ui/settings/view_models/theme_settings_view_model.dart';

class _SettingsError implements Exception {
  const _SettingsError(this.code, this.message);
  final String code;
  final String message;
}

/// Local settings only. The caller owns device leases and request serialization.
class AgentAppSettingsAdapter {
  AgentAppSettingsAdapter(
    this.ref, {
    required this.isCurrent,
    this.importImage,
  });
  final Ref ref;
  final bool Function() isCurrent;
  final Future<PreparedThemeImage> Function(Uri)? importImage;

  TargetPlatform get _platform => ref.read(shortcutTargetPlatformProvider);
  bool get _mac => !kIsWeb && _platform == TargetPlatform.macOS;
  bool get _global =>
      !kIsWeb &&
      const {
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      }.contains(_platform);

  static Map<String, dynamic> capabilitiesFor(
    TargetPlatform platform, {
    required bool isWeb,
  }) => {
    'operations': ['read', 'shortcut', 'appearance'],
    'shortcuts': {
      'commands': [
        for (final command in AppShortcutCommand.values) command.name,
        if (!isWeb &&
            const {
              TargetPlatform.macOS,
              TargetPlatform.windows,
              TargetPlatform.linux,
            }.contains(platform))
          'globalQuickAdd',
      ],
      'binding': [
        'physicalKeyId',
        'keyLabel',
        'meta',
        'control',
        'alt',
        'shift',
      ],
      if (!isWeb &&
          const {
            TargetPlatform.macOS,
            TargetPlatform.windows,
            TargetPlatform.linux,
          }.contains(platform))
        'globalBinding': [
          'keyCode',
          'keyLabel',
          'meta',
          'control',
          'alt',
          'shift',
        ],
    },
    'appearance': {
      'themeMode': [for (final value in AppThemeMode.values) value.name],
      'theme': [...builtinAppThemes.map((value) => value.id), 'custom'],
      'customTheme': {
        'roles': [for (final value in AppThemeColor.values) value.name],
        'backgroundTypes': [
          'color',
          'photo',
          if (!isWeb && platform == TargetPlatform.macOS) 'macosGlass',
        ],
        'imageZones': [
          for (final value in ThemeBackgroundZone.values) value.name,
        ],
        'imagePalettes': ['light', 'dark'],
      },
      'icon': [for (final value in AppIconChoice.values) value.id],
      if (!isWeb && platform == TargetPlatform.macOS)
        'statusItemStyle': [
          for (final value in StatusItemStyle.values) value.name,
        ],
      'bottomNavigation': {
        'styles': [
          for (final value in BottomNavigationStyle.values) value.name,
        ],
        'destinations': [
          for (final value in BottomNavigationDestination.values) value.name,
        ],
        'maxDestinations': bottomNavigationMaxDestinations,
      },
      'taskDetailLayout': [
        for (final value in TaskDetailLayout.values) value.name,
      ],
      'taskListStyle': [for (final value in TaskListStyle.values) value.name],
      'taskBranchStyle': [
        for (final value in TaskBranchStyle.values) value.name,
      ],
      'taskRowSpacing': [for (final value in TaskRowSpacing.values) value.name],
      'taskTimeDisplayMode': [
        for (final value in TaskTimeDisplayMode.values) value.name,
      ],
      if (!isWeb) 'zoom': {'min': appZoomMinimum, 'max': appZoomMaximum},
      'focusTimerStyle': [
        for (final value in FocusTimerVisualStyle.values) value.name,
      ],
      'focusViewMode': [for (final value in FocusViewMode.values) value.name],
    },
  };

  bool _current() => ref.mounted && isCurrent();

  void _checkCurrent() {
    if (!_current()) {
      throw const _SettingsError(
        'session_expired',
        'Settings session is no longer current',
      );
    }
  }

  Future<AppThemeSettings> _ready() async {
    (await ref.read(preferencesRepositoryProvider).read(const [], reload: true))
        .getOrThrow();
    _checkCurrent();
    await ref.read(keyboardShortcutsProvider.notifier).reload();
    _checkCurrent();
    final savedTheme = await ref
        .read(appThemeSettingsProvider.notifier)
        .refreshSaved();
    _checkCurrent();
    await ref.read(appThemeModeProvider.notifier).ready;
    _checkCurrent();
    await ref.read(appThemeModeProvider.notifier).refresh();
    _checkCurrent();
    if (!kIsWeb) {
      await ref.read(appZoomProvider.notifier).refresh();
      _checkCurrent();
      if (ref.read(appZoomProvider.notifier).loadError != null) {
        throw const _SettingsError(
          'settings_unavailable',
          'Interface zoom could not be loaded',
        );
      }
    }
    (await ref.read(taskPreferencesRepositoryProvider).load(reload: true))
        .getOrThrow();
    _checkCurrent();
    (await ref.read(focusPreferencesRepositoryProvider).load(reload: true))
        .getOrThrow();
    _checkCurrent();
    await ref.read(bottomNavigationProvider.notifier).refresh();
    _checkCurrent();
    await ref.read(appIconSettingsProvider.notifier).ready;
    _checkCurrent();
    await ref.read(appIconSettingsProvider.notifier).refresh();
    _checkCurrent();
    final icon = ref.read(appIconSettingsProvider);
    if (!icon.isLoaded) {
      throw const _SettingsError(
        'settings_unavailable',
        'Application icon could not be loaded',
      );
    }
    return savedTheme;
  }

  Map<String, dynamic> _values({AppThemeSettings? savedTheme}) {
    final AppThemeSettings theme =
        savedTheme ?? ref.read<AppThemeSettings>(appThemeSettingsProvider);
    final tasks = ref.read(taskPreferencesRepositoryProvider).state;
    final focus = ref.read(focusPreferencesRepositoryProvider).state;
    final navigation = ref.read(bottomNavigationProvider).requireValue;
    return {
      'shortcuts': {
        'bindings': {
          for (final entry in ref.read(keyboardShortcutsProvider).entries)
            entry.key.name: entry.value.toJson(),
        },
        if (_global)
          'globalQuickAdd': {
            'enabled': ref
                .read(keyboardShortcutsViewModelProvider)
                .global
                .enabled,
            'binding': ref
                .read(keyboardShortcutsViewModelProvider)
                .global
                .binding
                .toJson(),
          },
      },
      'themeMode': ref.read(appThemeModeProvider).name,
      'theme': theme.selectedId,
      'customTheme': theme.customTheme.toJson(),
      'icon': ref.read(appIconSettingsProvider).choice.id,
      if (_mac)
        'statusItemStyle': ref.read(statusItemStyleProvider).style?.name,
      'bottomNavigation': {
        'style': navigation.style.name,
        'destinations': navigation.destinations
            .map((value) => value.name)
            .toList(),
      },
      'taskDetailLayout': tasks.detailLayout.name,
      'taskListStyle': tasks.listStyle.name,
      'taskBranchStyle': tasks.branchStyle.name,
      'taskRowSpacing': tasks.rowSpacing.name,
      'taskTimeDisplayMode': tasks.timeDisplayMode.name,
      if (!kIsWeb) 'zoom': ref.read(appZoomProvider),
      'focusTimerStyle': focus.timerStyle.name,
      'focusViewMode': focus.viewMode.name,
    };
  }

  Object? _canonical(Object? value) => switch (value) {
    Map value => {
      for (final key in value.keys.cast<String>().toList()..sort())
        key: _canonical(value[key]),
    },
    List value => value.map(_canonical).toList(),
    _ => value,
  };
  String _version(Object? value) =>
      sha256.convert(utf8.encode(jsonEncode(_canonical(value)))).toString();
  Map<String, dynamic> _error(Object error) =>
      error is ThemeSettingsConflictException
      ? {
          'status': 'error',
          'code': 'version_conflict',
          'message': 'Theme settings changed since they were read',
        }
      : error is _SettingsError
      ? {'status': 'error', 'code': error.code, 'message': error.message}
      : {
          'status': 'error',
          'code': error is ArgumentError || error is FormatException
              ? 'invalid_value'
              : error is StateError
              ? 'busy'
              : 'settings_unavailable',
          'message': 'Could not apply local settings',
        };

  Future<Map<String, dynamic>> snapshot() async {
    try {
      // Hold auto-dispose controllers through their asynchronous native reads.
      final shortcuts = ref.listen(
        keyboardShortcutsViewModelProvider,
        (_, _) {},
      );
      final status = _mac
          ? ref.listen(statusItemStyleProvider, (_, _) {})
          : null;
      try {
        final savedTheme = await _ready();
        await ref
            .read(keyboardShortcutsViewModelProvider.notifier)
            .waitUntilReady();
        _checkCurrent();
        await ref.read(keyboardShortcutsViewModelProvider.notifier).reload();
        _checkCurrent();
        if (_mac) {
          await ref.read(statusItemStyleProvider.notifier).refresh();
          _checkCurrent();
          if (ref.read(statusItemStyleProvider).style == null) {
            throw const _SettingsError(
              'settings_unavailable',
              'Menu bar style could not be loaded',
            );
          }
        }
        final values = _values(savedTheme: savedTheme);
        return {
          'status': 'applied',
          'values': values,
          'versions': {
            for (final entry in values.entries)
              entry.key: _version(entry.value),
          },
          'capabilities': capabilitiesFor(_platform, isWeb: kIsWeb),
        };
      } finally {
        shortcuts.close();
        status?.close();
      }
    } catch (error) {
      return _error(error);
    }
  }

  T _enum<T extends Enum>(List<T> values, Object? value) =>
      values.where((entry) => entry.name == value).firstOrNull ??
      (throw const _SettingsError('invalid_value', 'Unknown setting value'));
  Map<String, dynamic> _map(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const _SettingsError('invalid_value', 'Expected an object');
    }
    return value;
  }

  void _keys(Map value, Set<String> allowed) {
    if (value.keys.any((key) => !allowed.contains(key))) {
      throw const _SettingsError('invalid_value', 'Unknown setting field');
    }
  }

  Future<Map<String, dynamic>> apply(Map<String, dynamic> command) async {
    final shortcuts = ref.listen(keyboardShortcutsViewModelProvider, (_, _) {});
    final status = _mac ? ref.listen(statusItemStyleProvider, (_, _) {}) : null;
    try {
      _checkCurrent();
      if (await ref.read(sharedPreferencesProvider.future) == null) {
        throw const _SettingsError(
          'settings_unavailable',
          'Local settings storage is unavailable',
        );
      }
      _checkCurrent();
      final before = await snapshot();
      if (before['status'] != 'applied') return before;
      _checkCurrent();
      final setting = command['setting'];
      final values = before['values'] as Map;
      if (setting is! String || !values.containsKey(setting)) {
        throw const _SettingsError(
          'unsupported',
          'Setting is not supported on this device',
        );
      }
      if (command['expected_version'] != null &&
          command['expected_version'] != _version(values[setting])) {
        throw const _SettingsError(
          'version_conflict',
          'Setting changed since it was read',
        );
      }
      final value = command['value'];
      if (command['operation'] == 'shortcut' && setting == 'shortcuts') {
        await _shortcut(_map(value));
      } else if (command['operation'] == 'appearance' &&
          setting != 'shortcuts') {
        await _appearance(setting, value);
      } else {
        throw const _SettingsError('unsupported', 'Unsupported operation');
      }
      _checkCurrent();
      final after = _values();
      return {
        'status': 'applied',
        'setting': setting,
        'value': after[setting],
        'version': _version(after[setting]),
      };
    } catch (error) {
      return !ref.mounted || !isCurrent()
          ? _error(
              const _SettingsError(
                'session_expired',
                'Settings session is no longer current',
              ),
            )
          : _error(error);
    } finally {
      shortcuts.close();
      status?.close();
    }
  }

  // Flutter maps USB HID keys to canonical identities independently of labels.
  LogicalKeyboardKey? _logicalKey(int physicalKeyId) =>
      kFuchsiaToLogicalKey[physicalKeyId | LogicalKeyboardKey.fuchsiaPlane];

  String _keyLabel(String label) =>
      switch (label == ' ' ? 'SPACE' : label.trim().toUpperCase()) {
        'ESC' => 'ESCAPE',
        'RETURN' => 'ENTER',
        'FORWARD DELETE' => 'DELETE',
        'SPACEBAR' => 'SPACE',
        '←' => 'ARROW LEFT',
        '→' => 'ARROW RIGHT',
        '↑' => 'ARROW UP',
        '↓' => 'ARROW DOWN',
        final value => value,
      };

  LogicalKeyboardKey? _globalKey(GlobalQuickAddBinding binding) =>
      switch (_platform) {
        TargetPlatform.macOS => _logicalKey(
          kMacOsToPhysicalKey[binding.keyCode]?.usbHidUsage ?? 0,
        ),
        TargetPlatform.windows => kWindowsToLogicalKey[binding.keyCode],
        TargetPlatform.linux =>
          kFuchsiaToLogicalKey.values
              .where(
                (key) => _keyLabel(key.keyLabel) == _keyLabel(binding.keyLabel),
              )
              .firstOrNull,
        _ => null,
      };

  bool _matchesGlobal(AppShortcutBinding app, GlobalQuickAddBinding global) {
    if (app.meta != global.meta ||
        app.control != global.control ||
        app.alt != global.alt ||
        app.shift != global.shift) {
      return false;
    }
    return _platform == TargetPlatform.macOS
        ? kMacOsToPhysicalKey[global.keyCode]?.usbHidUsage == app.physicalKeyId
        : _logicalKey(app.physicalKeyId) != null &&
              _logicalKey(app.physicalKeyId) == _globalKey(global);
  }

  String _canonicalKeyLabel(LogicalKeyboardKey? key) {
    if (key == null) {
      throw const _SettingsError('invalid_value', 'Unsupported key');
    }
    return key == LogicalKeyboardKey.space ? 'Space' : key.keyLabel;
  }

  Future<void> _shortcut(Map<String, dynamic> value) async {
    _keys(value, {'command', 'binding', 'enabled'});
    if (!value.containsKey('binding')) {
      throw const _SettingsError(
        'invalid_value',
        'Binding is required; use null to reset',
      );
    }
    if (value['binding'] != null) {
      _keys(_map(value['binding']), {
        value['command'] == 'globalQuickAdd' ? 'keyCode' : 'physicalKeyId',
        'keyLabel',
        'meta',
        'control',
        'alt',
        'shift',
      });
    }
    if (value['binding'] != null) {
      value = {
        ...value,
        'binding': {
          'meta': false,
          'control': false,
          'alt': false,
          'shift': false,
          ..._map(value['binding']),
        },
      };
    }
    final vm = ref.read(keyboardShortcutsViewModelProvider.notifier);
    if (value['command'] == 'globalQuickAdd') {
      if (!_global) {
        throw const _SettingsError(
          'unsupported',
          'Global shortcut is unavailable',
        );
      }
      final raw = value['binding'];
      var binding = raw == null
          ? GlobalQuickAddBinding.defaultFor(
              isMacOS: _platform == TargetPlatform.macOS,
            )
          : decodeGlobalShortcut(raw);
      if (binding.keyCode < 0 ||
          binding.keyLabel.trim().isEmpty ||
          !(binding.meta || binding.control || binding.alt)) {
        throw const _SettingsError('invalid_value', 'Invalid global shortcut');
      }
      if (ref
          .read(keyboardShortcutsProvider)
          .values
          .any((app) => _matchesGlobal(app, binding))) {
        throw const _SettingsError(
          'shortcut_conflict',
          'Shortcut is already assigned',
        );
      }
      if (appZoomBindings(
        _platform,
      ).keys.any((entry) => _matchesGlobal(entry, binding))) {
        throw const _SettingsError(
          'shortcut_conflict',
          'Shortcut is reserved for zoom',
        );
      }
      binding = decodeGlobalShortcut({
        ...binding.toJson(),
        'keyLabel': _canonicalKeyLabel(_globalKey(binding)),
      });
      if (value.containsKey('enabled') && value['enabled'] is! bool) {
        throw const _SettingsError(
          'invalid_value',
          'Enabled must be a boolean',
        );
      }
      _checkCurrent();
      await vm.setGlobalShortcut(binding, isCurrent: _current);
      _checkCurrent();
      if (value.containsKey('enabled')) {
        await vm.setGlobalEnabled(
          value['enabled'] as bool,
          isCurrent: _current,
        );
      }
    } else {
      if (value.containsKey('enabled')) {
        throw const _SettingsError(
          'invalid_value',
          'Enabled only applies to the global shortcut',
        );
      }
      final command = _enum(AppShortcutCommand.values, value['command']);
      var binding = value['binding'] == null
          ? defaultAppShortcutBindings(_platform)[command]!
          : AppShortcutBinding.tryFromJson(value['binding']);
      if (binding == null) {
        throw const _SettingsError('invalid_value', 'Invalid shortcut binding');
      }
      if (vm.conflictsWithZoom(binding) ||
          (_global &&
              _matchesGlobal(
                binding,
                ref.read(keyboardShortcutsViewModelProvider).global.binding,
              ))) {
        throw const _SettingsError(
          'shortcut_conflict',
          'Shortcut is already assigned or reserved',
        );
      }
      binding = AppShortcutBinding.tryFromJson({
        ...binding.toJson(),
        'keyLabel': _canonicalKeyLabel(_logicalKey(binding.physicalKeyId)),
      })!;
      _checkCurrent();
      if (await vm.setBinding(command, binding) != null) {
        throw const _SettingsError(
          'shortcut_conflict',
          'Shortcut is already assigned',
        );
      }
    }
  }

  Future<void> _appearance(String setting, Object? value) async {
    _checkCurrent();
    final tasks = ref.read(taskListSettingsViewModelProvider.notifier);
    switch (setting) {
      case 'themeMode':
        await ref
            .read(appThemeModeProvider.notifier)
            .setThemeMode(_enum(AppThemeMode.values, value));
      case 'theme':
        _themeReady();
        if (value is! String ||
            !ref
                .read(appThemeSettingsProvider)
                .themes
                .any((theme) => theme.id == value)) {
          throw const _SettingsError('invalid_value', 'Unknown theme');
        }
        await ref
            .read(appThemeSettingsProvider.notifier)
            .selectTheme(value, isCurrent: _current);
      case 'customTheme':
        await _customTheme(_map(value));
      case 'icon':
        final choice = AppIconChoice.values
            .where((choice) => choice.id == value)
            .firstOrNull;
        if (choice == null) {
          throw const _SettingsError('invalid_value', 'Unknown icon');
        }
        await ref
            .read(appIconSettingsProvider.notifier)
            .selectStrict(choice, isCurrent: _current);
      case 'statusItemStyle':
        await ref
            .read(statusItemStyleProvider.notifier)
            .selectStrict(_enum(StatusItemStyle.values, value));
      case 'bottomNavigation':
        final map = _map(value);
        _keys(map, {'style', 'destinations'});
        final names = map['destinations'];
        if (names is! List ||
            names.length > bottomNavigationMaxDestinations ||
            names.toSet().length != names.length) {
          throw const _SettingsError(
            'invalid_value',
            'Invalid bottom navigation destinations',
          );
        }
        final next = BottomNavigationPreferences(
          style: _enum(BottomNavigationStyle.values, map['style']),
          destinations: names.map(
            (name) => _enum(BottomNavigationDestination.values, name),
          ),
        );
        await ref
            .read(bottomNavigationProvider.notifier)
            .save(next, isCurrent: _current);
      case 'taskDetailLayout':
        await tasks.setDetailLayout(_enum(TaskDetailLayout.values, value));
      case 'taskListStyle':
        await tasks.setStyle(_enum(TaskListStyle.values, value));
      case 'taskBranchStyle':
        await tasks.setBranchStyle(_enum(TaskBranchStyle.values, value));
      case 'taskRowSpacing':
        await tasks.setSpacing(_enum(TaskRowSpacing.values, value));
      case 'taskTimeDisplayMode':
        (await ref
                .read(taskPreferencesRepositoryProvider)
                .setTimeDisplayMode(_enum(TaskTimeDisplayMode.values, value)))
            .getOrThrow();
      case 'zoom':
        if (value is! int || value < appZoomMinimum || value > appZoomMaximum) {
          throw const _SettingsError(
            'invalid_value',
            'Zoom is outside the supported range',
          );
        }
        await ref.read(appZoomProvider.notifier).setPercent(value);
      case 'focusTimerStyle':
        (await ref
                .read(focusPreferencesRepositoryProvider)
                .setTimerStyle(_enum(FocusTimerVisualStyle.values, value)))
            .getOrThrow();
      case 'focusViewMode':
        (await ref
                .read(focusPreferencesRepositoryProvider)
                .setViewMode(_enum(FocusViewMode.values, value)))
            .getOrThrow();
    }
  }

  void _themeReady() {
    final state = ref.read(appThemeSettingsProvider);
    if (!state.isLoaded ||
        state.isSaving ||
        state.isPreparingImage ||
        state.preview != null) {
      throw const _SettingsError('busy', 'Theme editor is busy');
    }
  }

  Future<void> _customTheme(Map<String, dynamic> value) async {
    _themeReady();
    _keys(value, {
      'light',
      'dark',
      'backgrounds',
      'image_url',
      'image_palette',
      'image_zone',
    });
    final before = ref.read(appThemeSettingsProvider);
    final version = _version(before.customTheme.toJson());
    AppThemePalette palette(AppThemePalette current, Object? patch) {
      if (patch == null) return current;
      final map = _map(patch);
      _keys(map, current.toJson().keys.toSet());
      return AppThemePalette.fromJson({...current.toJson(), ...map});
    }

    var backgrounds = before.customTheme.backgrounds;
    if (value.containsKey('backgrounds')) {
      final patch = _map(value['backgrounds']);
      final existing = backgrounds.toJson();
      final images = Map<String, dynamic>.from(
        backgrounds.toJson()['images'] as Map,
      );
      final patchImages = patch.containsKey('images')
          ? _map(patch['images'])
          : <String, dynamic>{};
      final raw = <String, dynamic>{
        ...existing,
        ...patch,
        'images': <String, dynamic>{
          ...images,
          for (final entry in patchImages.entries)
            entry.key: {
              ..._map(
                images[entry.key] ??
                    <String, dynamic>{
                      'dim': entry.key.endsWith('.light') ? .4 : .5,
                      'blur': 0,
                    },
              ),
              ..._map(entry.value),
            },
        },
      };
      _validateBackgrounds(raw);
      backgrounds = ThemeBackgrounds.fromJson(raw);
      // An agent may retain known local references, never invent local files.
      if (!before.customTheme.backgrounds.imageIds.containsAll(
        backgrounds.imageIds,
      )) {
        throw const _SettingsError('invalid_value', 'Unknown image reference');
      }
    }
    var custom = before.customTheme.copyWith(
      light: palette(before.customTheme.light, value['light']),
      dark: palette(before.customTheme.dark, value['dark']),
      backgrounds: backgrounds,
    );
    PreparedThemeImage? prepared;
    if (value.containsKey('image_url')) {
      final raw = value['image_url'];
      final uri = raw is String ? Uri.tryParse(raw) : null;
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          importImage == null) {
        throw const _SettingsError(
          'invalid_value',
          'A public HTTPS image URL is required',
        );
      }
      final zone = _enum(ThemeBackgroundZone.values, value['image_zone']);
      final brightness = _enum(Brightness.values, value['image_palette']);
      prepared = await importImage!(uri);
      _checkCurrent();
      _themeReady();
      if (_version(ref.read(appThemeSettingsProvider).customTheme.toJson()) !=
          version) {
        throw const _SettingsError(
          'version_conflict',
          'Custom theme changed during image import',
        );
      }
      custom = custom.copyWith(
        backgrounds: backgrounds
            .copyWith(type: ThemeBackgroundType.photo)
            .withImage(
              zone,
              brightness,
              backgrounds
                  .imageFor(zone, brightness)
                  .copyWith(imageId: prepared.id),
            ),
      );
    } else if (value.containsKey('image_zone') ||
        value.containsKey('image_palette')) {
      throw const _SettingsError('invalid_value', 'Image URL is required');
    }
    _checkCurrent();
    await ref
        .read(appThemeSettingsProvider.notifier)
        .saveCustomFromAgent(
          custom,
          image: prepared,
          isCurrent: () => ref.mounted && isCurrent(),
        );
  }

  void _validateBackgrounds(Map<String, dynamic> raw) {
    _keys(raw, {'type', 'mode', 'glassLightDim', 'glassDarkDim', 'images'});
    _enum(ThemeBackgroundType.values, raw['type']);
    if (raw['type'] == 'macosGlass' && !_mac) {
      throw const _SettingsError(
        'unsupported',
        'Glass backgrounds require macOS',
      );
    }
    _enum(ThemeBackgroundMode.values, raw['mode']);
    void number(Object? value, num max) {
      if (value is! num || !value.isFinite || value < 0 || value > max) {
        throw const _SettingsError(
          'invalid_value',
          'Background value is outside the supported range',
        );
      }
    }

    number(raw['glassLightDim'], 1);
    number(raw['glassDarkDim'], 1);
    final images = _map(raw['images']);
    _keys(images, {
      for (final zone in ThemeBackgroundZone.values)
        for (final palette in Brightness.values) '${zone.name}.${palette.name}',
    });
    for (final value in images.values) {
      final image = _map(value);
      _keys(image, {'imageId', 'dim', 'blur'});
      if (image['imageId'] != null &&
          (image['imageId'] is! String ||
              !isThemeImageId(image['imageId'] as String))) {
        throw const _SettingsError('invalid_value', 'Invalid image reference');
      }
      number(image['dim'], 1);
      number(image['blur'], 20);
    }
  }
}

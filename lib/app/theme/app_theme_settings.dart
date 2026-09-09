import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';

const appThemeSettingsPreferenceKey = 'app.themeSettings';
const appThemeSettingsLegacyBackupKey = 'app.themeSettings.v1Backup';
const defaultCustomTheme = AppThemeDefinition(
  id: 'custom',
  name: 'Custom',
  light: AppTheme.classicLight,
  dark: AppTheme.classicDark,
);

class AppThemeDefinition {
  const AppThemeDefinition({
    required this.id,
    required this.name,
    required this.light,
    required this.dark,
  });

  final String id;
  final String name;
  final AppThemePalette light;
  final AppThemePalette dark;

  bool get isBuiltIn => builtinAppThemes.any((theme) => theme.id == id);

  AppThemeDefinition copyWith({
    String? id,
    String? name,
    AppThemePalette? light,
    AppThemePalette? dark,
  }) => AppThemeDefinition(
    id: id ?? this.id,
    name: name ?? this.name,
    light: light ?? this.light,
    dark: dark ?? this.dark,
  );

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'light': light.toJson(),
    'dark': dark.toJson(),
  };

  factory AppThemeDefinition.fromJson(Object? json) {
    if (json is! Map || json['id'] is! String) {
      throw const FormatException('Invalid custom theme');
    }
    final id = json['id'] as String;
    if (id != 'custom' && !(id.startsWith('custom:') && id.length > 7)) {
      throw const FormatException('Invalid custom theme identifier');
    }
    return AppThemeDefinition(
      id: 'custom',
      name: 'Custom',
      light: AppThemePalette.fromJson(json['light']),
      dark: AppThemePalette.fromJson(json['dark']),
    );
  }
}

final builtinAppThemes = List<AppThemeDefinition>.unmodifiable([
  const AppThemeDefinition(
    id: 'classic',
    name: 'Classic',
    light: AppTheme.classicLight,
    dark: AppTheme.classicDark,
  ),
  AppThemeDefinition(
    id: 'ocean',
    name: 'Ocean',
    light: AppTheme.classicLight.copyWith(
      canvas: const Color(0xFFF8FAFC),
      surface: const Color(0xFFFFFFFF),
      surfaceTint: const Color(0xFFF1F5F9),
      surfaceHover: const Color(0xFFE8EEF5),
      primaryText: const Color(0xFF0F172A),
      secondaryText: const Color(0xFF64748B),
      mutedText: const Color(0xFF64748B),
      border: const Color(0xFFE2E8F0),
      accent: const Color(0xFF2563EB),
      accentFill: const Color(0xFF2563EB),
      accentTint: const Color(0xFFEFF6FF),
    ),
    dark: AppTheme.classicDark.copyWith(
      canvas: const Color(0xFF0B1120),
      surface: const Color(0xFF111B2E),
      surfaceTint: const Color(0xFF18253B),
      surfaceHover: const Color(0xFF20314A),
      primaryText: const Color(0xFFF1F5F9),
      secondaryText: const Color(0xFF94A3B8),
      mutedText: const Color(0xFF94A3B8),
      border: const Color(0xFF2A3B53),
      accent: const Color(0xFF60A5FA),
      accentFill: const Color(0xFF2563EB),
      accentTint: const Color(0xFF152D50),
    ),
  ),
  AppThemeDefinition(
    id: 'forest',
    name: 'Forest',
    light: AppTheme.classicLight.copyWith(
      canvas: const Color(0xFFF7FAF7),
      surface: const Color(0xFFFFFFFF),
      surfaceTint: const Color(0xFFEEF4EE),
      surfaceHover: const Color(0xFFE3ECE3),
      primaryText: const Color(0xFF18251C),
      secondaryText: const Color(0xFF617064),
      mutedText: const Color(0xFF617064),
      border: const Color(0xFFDCE6DC),
      accent: const Color(0xFF15803D),
      accentFill: const Color(0xFF15803D),
      accentTint: const Color(0xFFE8F5EB),
    ),
    dark: AppTheme.classicDark.copyWith(
      canvas: const Color(0xFF0C140F),
      surface: const Color(0xFF142019),
      surfaceTint: const Color(0xFF1D2C22),
      surfaceHover: const Color(0xFF27382C),
      primaryText: const Color(0xFFF0F7F1),
      secondaryText: const Color(0xFF9DB2A2),
      mutedText: const Color(0xFF9DB2A2),
      border: const Color(0xFF304637),
      accent: const Color(0xFF4ADE80),
      accentFill: const Color(0xFF15803D),
      accentTint: const Color(0xFF163723),
    ),
  ),
  AppThemeDefinition(
    id: 'sepia',
    name: 'Sepia',
    light: AppTheme.classicLight.copyWith(
      canvas: const Color(0xFFFAF7F2),
      surface: const Color(0xFFFFFDF9),
      surfaceTint: const Color(0xFFF2EDE5),
      surfaceHover: const Color(0xFFE9E0D3),
      primaryText: const Color(0xFF2E251B),
      secondaryText: const Color(0xFF756655),
      mutedText: const Color(0xFF756655),
      border: const Color(0xFFE2D7C8),
      accent: const Color(0xFF8B5E34),
      accentFill: const Color(0xFF8B5E34),
      accentTint: const Color(0xFFF4E8D8),
    ),
    dark: AppTheme.classicDark.copyWith(
      canvas: const Color(0xFF17130F),
      surface: const Color(0xFF211B15),
      surfaceTint: const Color(0xFF2B231B),
      surfaceHover: const Color(0xFF362B20),
      primaryText: const Color(0xFFF5EBDD),
      secondaryText: const Color(0xFFB9AA98),
      mutedText: const Color(0xFFB9AA98),
      border: const Color(0xFF44382B),
      accent: const Color(0xFFD6AD7B),
      accentFill: const Color(0xFF8B5E34),
      accentTint: const Color(0xFF382A1A),
    ),
  ),
  AppThemeDefinition(
    id: 'graphite',
    name: 'Graphite',
    light: AppTheme.classicLight.copyWith(
      canvas: const Color(0xFFFAFAFA),
      surface: const Color(0xFFFFFFFF),
      surfaceTint: const Color(0xFFF4F4F5),
      surfaceHover: const Color(0xFFE4E4E7),
      primaryText: const Color(0xFF18181B),
      secondaryText: const Color(0xFF71717A),
      mutedText: const Color(0xFF71717A),
      border: const Color(0xFFD4D4D8),
      accent: const Color(0xFF27272A),
      accentFill: const Color(0xFF27272A),
      accentTint: const Color(0xFFEDEDEE),
    ),
    dark: AppTheme.classicDark.copyWith(
      canvas: const Color(0xFF0F0F10),
      surface: const Color(0xFF18181B),
      surfaceTint: const Color(0xFF222225),
      surfaceHover: const Color(0xFF2D2D31),
      primaryText: const Color(0xFFFAFAFA),
      secondaryText: const Color(0xFFA1A1AA),
      mutedText: const Color(0xFFA1A1AA),
      border: const Color(0xFF3A3A40),
      accent: const Color(0xFFE4E4E7),
      accentFill: const Color(0xFFE4E4E7),
      accentTint: const Color(0xFF2D2D31),
      onAccent: const Color(0xFF18181B),
    ),
  ),
]);

class AppThemeSettings {
  const AppThemeSettings({
    this.selectedId = 'classic',
    this.customTheme = defaultCustomTheme,
    this.preview,
    this.isLoaded = false,
    this.isSaving = false,
    this.loadFailed = false,
  });

  final String selectedId;
  final AppThemeDefinition customTheme;
  final AppThemeDefinition? preview;
  final bool isLoaded;
  final bool isSaving;
  final bool loadFailed;

  Iterable<AppThemeDefinition> get themes => [...builtinAppThemes, customTheme];
  AppThemeDefinition themeById(String id) => themes.firstWhere(
    (theme) => theme.id == id,
    orElse: () => builtinAppThemes.first,
  );
  AppThemeDefinition get activeTheme => preview ?? themeById(selectedId);

  AppThemeSettings copyWith({
    String? selectedId,
    AppThemeDefinition? customTheme,
    AppThemeDefinition? preview,
    bool clearPreview = false,
    bool? isLoaded,
    bool? isSaving,
    bool? loadFailed,
  }) => AppThemeSettings(
    selectedId: selectedId ?? this.selectedId,
    customTheme: customTheme ?? this.customTheme,
    preview: clearPreview ? null : preview ?? this.preview,
    isLoaded: isLoaded ?? this.isLoaded,
    isSaving: isSaving ?? this.isSaving,
    loadFailed: loadFailed ?? this.loadFailed,
  );

  String encode() => jsonEncode({
    'version': 2,
    'selectedId': selectedId,
    'customTheme': customTheme.toJson(),
  });

  static AppThemeSettings decode(Object? raw) {
    const fallback = AppThemeSettings(isLoaded: true);
    if (raw is! String) return fallback;
    try {
      final json = jsonDecode(raw);
      if (json is! Map || (json['version'] != 1 && json['version'] != 2)) {
        return fallback;
      }
      var custom = defaultCustomTheme;
      var selected = json['selectedId'];
      if (json['version'] == 1) {
        final copies = json['customThemes'];
        if (copies is List) {
          for (final record in copies) {
            if (record is! Map || record['id'] != selected) continue;
            try {
              custom = AppThemeDefinition.fromJson(record);
              selected = 'custom';
              break;
            } on FormatException {
              // A damaged legacy record must not prevent migration.
              continue;
            }
          }
        }
      } else {
        try {
          custom = AppThemeDefinition.fromJson(json['customTheme']);
        } on FormatException {
          // Keep the selected preset usable if Custom is damaged.
        }
      }
      final validSelection =
          selected is String &&
          (selected == 'custom' ||
              builtinAppThemes.any((theme) => theme.id == selected));
      return AppThemeSettings(
        isLoaded: true,
        customTheme: custom,
        selectedId: validSelection ? selected : 'classic',
      );
    } on FormatException {
      return fallback;
    }
  }
}

final appThemePreferencesProvider =
    Provider<Future<SharedPreferences> Function()>(
      (ref) => SharedPreferences.getInstance,
    );

final appThemeSettingsProvider =
    NotifierProvider<AppThemeSettingsController, AppThemeSettings>(
      AppThemeSettingsController.new,
    );

class AppThemeSettingsController extends Notifier<AppThemeSettings> {
  Future<void>? _loading;
  String? _legacySettings;

  @override
  AppThemeSettings build() {
    unawaited(load().catchError((Object _) {}));
    return const AppThemeSettings();
  }

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final prefs = await ref.read(appThemePreferencesProvider)();
      final raw = prefs.get(appThemeSettingsPreferenceKey);
      if (raw is String) {
        try {
          final json = jsonDecode(raw);
          if (json is Map && json['version'] == 1) _legacySettings = raw;
        } on FormatException {
          // The decoder below supplies defaults for malformed settings.
        }
      }
      if (ref.mounted) state = AppThemeSettings.decode(raw);
    } catch (_) {
      _loading = null;
      if (ref.mounted) state = state.copyWith(loadFailed: true);
      rethrow;
    }
  }

  void _requireReady() {
    if (!state.isLoaded || state.isSaving) {
      throw StateError('Theme settings are busy');
    }
  }

  Future<void> selectTheme(String id) async {
    await load();
    _requireReady();
    if (state.preview != null || !state.themes.any((theme) => theme.id == id)) {
      throw ArgumentError.value(id, 'id');
    }
    await _persist(state.copyWith(selectedId: id));
  }

  void beginEdit() {
    _requireReady();
    if (state.preview != null) throw StateError('Theme editor is already open');
    state = state.copyWith(preview: state.customTheme);
  }

  void resetPreviewToClassic() {
    _requireReady();
    if (state.preview == null) throw StateError('No theme draft');
    state = state.copyWith(preview: defaultCustomTheme);
  }

  void updatePreview(AppThemeDefinition draft) {
    _requireReady();
    if (state.preview?.id != draft.id) {
      throw ArgumentError('Not the current draft');
    }
    state = state.copyWith(preview: draft);
  }

  void cancelPreview() {
    if (!ref.mounted || state.isSaving || state.preview == null) return;
    state = state.copyWith(clearPreview: true);
  }

  Future<void> savePreview() async {
    _requireReady();
    final draft = state.preview;
    if (draft == null) throw StateError('No theme draft');
    final saved = AppThemeDefinition.fromJson(draft.toJson());
    await _persist(
      state.copyWith(
        selectedId: 'custom',
        customTheme: saved,
        clearPreview: true,
      ),
    );
  }

  Future<void> _persist(AppThemeSettings next) async {
    state = state.copyWith(isSaving: true);
    SharedPreferences? prefs;
    try {
      prefs = await ref.read(appThemePreferencesProvider)();
      final legacy = _legacySettings;
      if (legacy != null &&
          !prefs.containsKey(appThemeSettingsLegacyBackupKey)) {
        if (!await prefs.setString(appThemeSettingsLegacyBackupKey, legacy)) {
          throw StateError('Could not back up legacy theme settings');
        }
      }
      if (!await prefs.setString(
        appThemeSettingsPreferenceKey,
        next.encode(),
      )) {
        throw StateError('Could not save theme settings');
      }
      _legacySettings = null;
      if (ref.mounted) state = next.copyWith(isSaving: false);
    } catch (_) {
      // Legacy preferences update their cache before the disk write succeeds.
      try {
        await prefs?.reload();
      } catch (_) {
        /* Keep the draft available. */
      }
      if (ref.mounted) state = state.copyWith(isSaving: false);
      rethrow;
    }
  }
}

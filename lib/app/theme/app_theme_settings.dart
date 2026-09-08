import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'app_theme.dart';

const appThemeSettingsPreferenceKey = 'app.themeSettings';

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
    if (json is! Map ||
        json['id'] is! String ||
        !(json['id'] as String).startsWith('custom:') ||
        (json['id'] as String).length <= 7 ||
        json['name'] is! String ||
        (json['name'] as String).trim().isEmpty) {
      throw const FormatException('Invalid custom theme');
    }
    return AppThemeDefinition(
      id: json['id'] as String,
      name: (json['name'] as String).trim(),
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
]);

class AppThemeSettings {
  const AppThemeSettings({
    this.selectedId = 'classic',
    this.customThemes = const [],
    this.preview,
    this.isLoaded = false,
    this.isSaving = false,
    this.loadFailed = false,
  });

  final String selectedId;
  final List<AppThemeDefinition> customThemes;
  final AppThemeDefinition? preview;
  final bool isLoaded;
  final bool isSaving;
  final bool loadFailed;

  Iterable<AppThemeDefinition> get themes => [
    ...builtinAppThemes,
    ...customThemes,
  ];
  AppThemeDefinition themeById(String id) => themes.firstWhere(
    (theme) => theme.id == id,
    orElse: () => builtinAppThemes.first,
  );
  AppThemeDefinition get activeTheme => preview ?? themeById(selectedId);

  AppThemeSettings copyWith({
    String? selectedId,
    List<AppThemeDefinition>? customThemes,
    AppThemeDefinition? preview,
    bool clearPreview = false,
    bool? isLoaded,
    bool? isSaving,
    bool? loadFailed,
  }) => AppThemeSettings(
    selectedId: selectedId ?? this.selectedId,
    customThemes: customThemes == null
        ? this.customThemes
        : List.unmodifiable(customThemes),
    preview: clearPreview ? null : preview ?? this.preview,
    isLoaded: isLoaded ?? this.isLoaded,
    isSaving: isSaving ?? this.isSaving,
    loadFailed: loadFailed ?? this.loadFailed,
  );

  String encode() => jsonEncode({
    'version': 1,
    'selectedId': selectedId,
    'customThemes': customThemes.map((theme) => theme.toJson()).toList(),
  });

  static AppThemeSettings decode(Object? raw) {
    const fallback = AppThemeSettings(isLoaded: true);
    if (raw is! String) return fallback;
    try {
      final json = jsonDecode(raw);
      if (json is! Map ||
          json['version'] != 1 ||
          json['customThemes'] is! List) {
        return fallback;
      }
      final themes = <AppThemeDefinition>[];
      final ids = <String>{};
      for (final record in json['customThemes'] as List) {
        try {
          final theme = AppThemeDefinition.fromJson(record);
          if (ids.add(theme.id)) themes.add(theme);
        } on FormatException {
          // One damaged copy must not hide the other saved themes.
          continue;
        }
      }
      final selected = json['selectedId'];
      final validSelection =
          selected is String &&
          (ids.contains(selected) ||
              builtinAppThemes.any((theme) => theme.id == selected));
      return AppThemeSettings(
        isLoaded: true,
        customThemes: List.unmodifiable(themes),
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

  @override
  AppThemeSettings build() {
    unawaited(load().catchError((Object _) {}));
    return const AppThemeSettings();
  }

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final prefs = await ref.read(appThemePreferencesProvider)();
      if (ref.mounted)
        state = AppThemeSettings.decode(
          prefs.get(appThemeSettingsPreferenceKey),
        );
    } catch (_) {
      _loading = null;
      if (ref.mounted) state = state.copyWith(loadFailed: true);
      rethrow;
    }
  }

  void _requireReady() {
    if (!state.isLoaded || state.isSaving)
      throw StateError('Theme settings are busy');
  }

  Future<void> selectTheme(String id) async {
    await load();
    _requireReady();
    if (state.preview != null || !state.themes.any((theme) => theme.id == id)) {
      throw ArgumentError.value(id, 'id');
    }
    await _persist(state.copyWith(selectedId: id));
  }

  void beginEdit(String id, {required String name, bool duplicate = false}) {
    _requireReady();
    if (state.preview != null || !state.themes.any((theme) => theme.id == id)) {
      throw StateError('Cannot open theme editor');
    }
    final source = state.themeById(id);
    state = state.copyWith(
      preview: source.copyWith(
        id: source.isBuiltIn || duplicate
            ? 'custom:${const Uuid().v4()}'
            : source.id,
        name: name,
      ),
    );
  }

  void updatePreview(AppThemeDefinition draft) {
    _requireReady();
    if (state.preview?.id != draft.id)
      throw ArgumentError('Not the current draft');
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
    final themes = [...state.customThemes];
    final index = themes.indexWhere((theme) => theme.id == saved.id);
    if (index < 0) {
      themes.add(saved);
    } else {
      themes[index] = saved;
    }
    await _persist(
      state.copyWith(
        selectedId: saved.id,
        customThemes: themes,
        clearPreview: true,
      ),
    );
  }

  Future<void> deleteTheme(String id) async {
    await load();
    _requireReady();
    if (state.preview != null ||
        !state.customThemes.any((theme) => theme.id == id)) {
      throw ArgumentError.value(id, 'id');
    }
    await _persist(
      state.copyWith(
        selectedId: state.selectedId == id ? 'classic' : state.selectedId,
        customThemes: state.customThemes
            .where((theme) => theme.id != id)
            .toList(),
      ),
    );
  }

  Future<void> _persist(AppThemeSettings next) async {
    state = state.copyWith(isSaving: true);
    SharedPreferences? prefs;
    try {
      prefs = await ref.read(appThemePreferencesProvider)();
      if (!await prefs.setString(
        appThemeSettingsPreferenceKey,
        next.encode(),
      )) {
        throw StateError('Could not save theme settings');
      }
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

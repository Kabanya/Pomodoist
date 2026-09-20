import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pomodoist/config/theme_settings_dependencies.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/themes/theme_backgrounds.dart';

export 'package:pomodoist/ui/core/themes/theme_backgrounds.dart';
export 'package:pomodoist/config/theme_settings_dependencies.dart'
    show
        themeImagePreparerProvider,
        themeImageRepositoryProvider,
        themeSettingsRepositoryProvider;
export 'package:pomodoist/data/repositories/settings/theme_image_repository.dart';
export 'package:pomodoist/data/repositories/settings/theme_settings_repository.dart'
    show appThemeSettingsPreferenceKey, appThemeSettingsLegacyBackupKey;

part '../services/theme_settings_codec.dart';

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
    this.backgrounds = const ThemeBackgrounds(),
  });

  final String id;
  final String name;
  final AppThemePalette light;
  final AppThemePalette dark;
  final ThemeBackgrounds backgrounds;

  bool get isBuiltIn => builtinAppThemes.any((theme) => theme.id == id);

  AppThemeDefinition copyWith({
    String? id,
    String? name,
    AppThemePalette? light,
    AppThemePalette? dark,
    ThemeBackgrounds? backgrounds,
  }) => AppThemeDefinition(
    id: id ?? this.id,
    name: name ?? this.name,
    light: light ?? this.light,
    dark: dark ?? this.dark,
    backgrounds: backgrounds ?? this.backgrounds,
  );

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'light': light.toJson(),
    'dark': dark.toJson(),
    'backgrounds': backgrounds.toJson(),
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
      backgrounds: ThemeBackgrounds.fromJson(json['backgrounds']),
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
    this.isPreparingImage = false,
  });

  final String selectedId;
  final AppThemeDefinition customTheme;
  final AppThemeDefinition? preview;
  final bool isLoaded;
  final bool isSaving;
  final bool loadFailed;
  final bool isPreparingImage;

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
    bool? isPreparingImage,
  }) => AppThemeSettings(
    selectedId: selectedId ?? this.selectedId,
    customTheme: customTheme ?? this.customTheme,
    preview: clearPreview ? null : preview ?? this.preview,
    isLoaded: isLoaded ?? this.isLoaded,
    isSaving: isSaving ?? this.isSaving,
    loadFailed: loadFailed ?? this.loadFailed,
    isPreparingImage: isPreparingImage ?? this.isPreparingImage,
  );
}

final themeImageBytesProvider = FutureProvider.autoDispose
    .family<Uint8List?, String>(
      (ref, id) => ref.read(appThemeSettingsProvider.notifier).readImage(id),
    );

final appThemeSettingsProvider =
    NotifierProvider<AppThemeSettingsController, AppThemeSettings>(
      AppThemeSettingsController.new,
    );

class AppThemeSettingsController extends Notifier<AppThemeSettings> {
  Future<void>? _loading;
  String? _legacySettings;
  int _imageSelection = 0;
  final Map<String, Uint8List> _pendingImages = {};

  Future<Uint8List?> readImage(String id) async =>
      _pendingImages[id] ??
      await ref.read(themeSettingsStorageUseCaseProvider).readImage(id);

  void cancelImageSelection() {
    _imageSelection++;
    if (ref.mounted && state.isPreparingImage) {
      state = state.copyWith(isPreparingImage: false);
    }
  }

  Future<void> chooseBackground(
    ThemeBackgroundZone zone,
    Brightness brightness,
    Future<XFile?> Function() pickFile,
  ) async {
    _requireReady();
    if (state.preview == null) throw StateError('No theme draft');
    final selection = ++_imageSelection;
    bool current() =>
        ref.mounted && state.preview != null && selection == _imageSelection;
    state = state.copyWith(isPreparingImage: true);
    try {
      final file = await pickFile();
      if (!current() || file == null) return;
      final prepared = await ref
          .read(themeImageImportRepositoryProvider)
          .prepare(file);
      if (!current()) return;
      final id = prepared.id;
      _pendingImages[id] = prepared.bytes;
      // A previously missing image may have been cached by a preview.
      ref.invalidate(themeImageBytesProvider(id));
      final draft = state.preview!;
      updatePreview(
        draft.copyWith(
          backgrounds: draft.backgrounds
              .copyWith(type: ThemeBackgroundType.photo)
              .withImage(
                zone,
                brightness,
                draft.backgrounds
                    .imageFor(zone, brightness)
                    .copyWith(imageId: id),
              ),
        ),
      );
    } catch (_) {
      if (current()) rethrow;
    } finally {
      if (current()) state = state.copyWith(isPreparingImage: false);
    }
  }

  @override
  AppThemeSettings build() {
    unawaited(load().catchError((Object _) {}));
    return const AppThemeSettings();
  }

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final repository = ref.read(themeSettingsRepositoryProvider);
      final raw = (await repository.read()).getOrThrow();
      final decoded = ThemeSettingsCodec.decode(raw);
      _legacySettings = decoded.legacyRaw;
      if (ref.mounted) state = decoded.settings;
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
    cancelImageSelection();
    _pendingImages.clear();
    state = state.copyWith(preview: state.customTheme);
  }

  void resetPreviewToClassic() {
    _requireReady();
    if (state.preview == null) throw StateError('No theme draft');
    cancelImageSelection();
    _pendingImages.clear();
    state = state.copyWith(preview: defaultCustomTheme);
  }

  void updatePreview(AppThemeDefinition draft) {
    _requireReady();
    if (state.preview?.id != draft.id) {
      throw ArgumentError('Not the current draft');
    }
    if (state.preview!.backgrounds.type != draft.backgrounds.type ||
        state.preview!.backgrounds.mode != draft.backgrounds.mode) {
      cancelImageSelection();
    }
    final imageIds = draft.backgrounds.imageIds;
    _pendingImages.removeWhere((id, _) => !imageIds.contains(id));
    state = state.copyWith(preview: draft);
  }

  void cancelPreview() {
    if (!ref.mounted || state.isSaving || state.preview == null) return;
    cancelImageSelection();
    _pendingImages.clear();
    state = state.copyWith(clearPreview: true);
  }

  Future<void> savePreview() async {
    _requireReady();
    final draft = state.preview;
    if (draft == null) throw StateError('No theme draft');
    if (state.isPreparingImage) {
      throw StateError('Image is still being prepared');
    }
    cancelImageSelection();
    final saved = AppThemeDefinition.fromJson(draft.toJson());
    await _persist(
      state.copyWith(
        selectedId: 'custom',
        customTheme: saved,
        clearPreview: true,
      ),
      savingPreview: true,
    );
  }

  Future<void> _persist(
    AppThemeSettings next, {
    bool savingPreview = false,
  }) async {
    state = state.copyWith(isSaving: true);
    final repository = ref.read(themeSettingsRepositoryProvider);
    try {
      final latestRaw = (await repository.read(reload: true)).getOrThrow();
      if (!savingPreview) {
        // Selecting a preset must not overwrite a Custom saved in another tab.
        next = next.copyWith(
          customTheme: ThemeSettingsCodec.decode(
            latestRaw,
          ).settings.customTheme,
        );
      }
      await ref
          .read(themeSettingsStorageUseCaseProvider)
          .save(
            value: ThemeSettingsCodec.encode(next),
            retainedImageIds: next.customTheme.backgrounds.imageIds,
            pendingImages: Map.unmodifiable(_pendingImages),
            legacyBackup: _legacySettings,
            verifyRetainedImages: savingPreview,
          );
      _legacySettings = null;
      _pendingImages.clear();
      if (ref.mounted) state = next.copyWith(isSaving: false);
    } catch (_) {
      // Legacy preferences update their cache before the disk write succeeds.
      try {
        (await repository.read(reload: true)).getOrThrow();
      } catch (_) {
        /* Keep the draft available. */
      }
      if (ref.mounted) state = state.copyWith(isSaving: false);
      rethrow;
    }
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/theme/app_theme.dart';
import 'package:pomodoist/app/theme/app_theme_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Replace only disk writes to exercise persistence failures.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> loadedContainer() async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(appThemeSettingsProvider.notifier).load();
    return container;
  }

  String legacySettings(String selected) => jsonEncode({
    'version': 1,
    'selectedId': selected,
    'customThemes': [
      {'id': 'custom:broken', 'name': 'Broken'},
      builtinAppThemes.first
          .copyWith(
            id: 'custom:saved',
            name: 'Old name',
            light: AppTheme.classicLight.copyWith(
              canvas: const Color(0xFFEEDDCC),
            ),
            dark: AppTheme.classicDark.copyWith(
              canvas: const Color(0xFF112233),
            ),
          )
          .toJson(),
      builtinAppThemes.first
          .copyWith(id: 'custom:other', name: 'Other copy')
          .toJson(),
    ],
  });

  test(
    'six selectable themes include a permanent Custom initialized from Classic',
    () async {
      final container = await loadedContainer();
      final settings = container.read(appThemeSettingsProvider);
      expect(settings.themes.map((theme) => theme.id), [
        'classic',
        'ocean',
        'forest',
        'sepia',
        'graphite',
        'custom',
      ]);
      expect(
        settings.customTheme.light.toJson(),
        AppTheme.classicLight.toJson(),
      );
      expect(settings.customTheme.dark.toJson(), AppTheme.classicDark.toJson());
      await container
          .read(appThemeSettingsProvider.notifier)
          .selectTheme('custom');
      expect(
        (await loadedContainer()).read(appThemeSettingsProvider).activeTheme.id,
        'custom',
      );
    },
  );

  test(
    'editing reuses Custom and persists both palettes without changing built-ins',
    () async {
      final container = await loadedContainer();
      final controller = container.read(appThemeSettingsProvider.notifier);
      await controller.selectTheme('ocean');
      controller.beginEdit();
      final draft = container.read(appThemeSettingsProvider).preview!;
      expect(draft.light.toJson(), AppTheme.classicLight.toJson());
      controller.updatePreview(
        draft.copyWith(
          light: draft.light.withColor(
            AppThemeColor.canvas,
            const Color(0xFFEEDDCC),
          ),
          dark: draft.dark.withColor(
            AppThemeColor.canvas,
            const Color(0xFF112233),
          ),
        ),
      );
      await controller.savePreview();
      final restored = await loadedContainer();
      final settings = restored.read(appThemeSettingsProvider);
      expect(settings.selectedId, 'custom');
      expect(settings.customTheme.name, 'Custom');
      expect(settings.customTheme.light.canvas, const Color(0xFFEEDDCC));
      expect(settings.customTheme.dark.canvas, const Color(0xFF112233));
      expect(
        settings.themeById('classic').light.toJson(),
        AppTheme.classicLight.toJson(),
      );
      final editor = restored.read(appThemeSettingsProvider.notifier);
      editor.beginEdit();
      expect(
        restored.read(appThemeSettingsProvider).preview!.dark.canvas,
        const Color(0xFF112233),
      );
      await editor.savePreview();
      expect(restored.read(appThemeSettingsProvider).themes, hasLength(6));
    },
  );

  test(
    'cancel never persists a live preview and restores the previous selection',
    () async {
      final container = await loadedContainer();
      final controller = container.read(appThemeSettingsProvider.notifier);
      await controller.selectTheme('forest');
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(appThemeSettingsPreferenceKey);
      controller.beginEdit();
      expect(container.read(appThemeSettingsProvider).activeTheme.id, 'custom');
      expect(prefs.getString(appThemeSettingsPreferenceKey), saved);
      controller.cancelPreview();
      expect(container.read(appThemeSettingsProvider).activeTheme.id, 'forest');
      expect(
        (await loadedContainer()).read(appThemeSettingsProvider).activeTheme.id,
        'forest',
      );
    },
  );

  test(
    'reset changes only the draft until saved and cancellation keeps custom colors',
    () async {
      SharedPreferences.setMockInitialValues({
        appThemeSettingsPreferenceKey: legacySettings('custom:saved'),
      });
      final container = await loadedContainer();
      final controller = container.read(appThemeSettingsProvider.notifier);
      controller.beginEdit();
      controller.resetPreviewToClassic();
      expect(
        container.read(appThemeSettingsProvider).preview!.light.toJson(),
        AppTheme.classicLight.toJson(),
      );
      expect(
        container.read(appThemeSettingsProvider).preview!.dark.toJson(),
        AppTheme.classicDark.toJson(),
      );
      controller.cancelPreview();
      expect(
        container.read(appThemeSettingsProvider).activeTheme.light.canvas,
        const Color(0xFFEEDDCC),
      );
      controller.beginEdit();
      controller.resetPreviewToClassic();
      await controller.savePreview();
      final saved = (await loadedContainer()).read(appThemeSettingsProvider);
      expect(saved.selectedId, 'custom');
      expect(saved.customTheme.light.toJson(), AppTheme.classicLight.toJson());
      expect(saved.customTheme.dark.toJson(), AppTheme.classicDark.toJson());
    },
  );

  test(
    'migration preserves the active legacy pair and backs up all copies before writing v2',
    () async {
      final raw = legacySettings('custom:saved');
      SharedPreferences.setMockInitialValues({
        appThemeSettingsPreferenceKey: raw,
      });
      final container = await loadedContainer();
      final settings = container.read(appThemeSettingsProvider);
      expect(settings.activeTheme.id, 'custom');
      expect(settings.activeTheme.name, 'Custom');
      expect(settings.activeTheme.light.canvas, const Color(0xFFEEDDCC));
      expect(settings.activeTheme.dark.canvas, const Color(0xFF112233));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(appThemeSettingsPreferenceKey), raw);
      expect(prefs.getString(appThemeSettingsLegacyBackupKey), isNull);
      final controller = container.read(appThemeSettingsProvider.notifier);
      await controller.selectTheme('sepia');
      expect(prefs.getString(appThemeSettingsLegacyBackupKey), raw);
      final encoded =
          jsonDecode(prefs.getString(appThemeSettingsPreferenceKey)!) as Map;
      expect(encoded['version'], 2);
      expect(encoded.containsKey('customThemes'), isFalse);
      expect(encoded['customTheme']['id'], 'custom');
      final restored = (await loadedContainer()).read(appThemeSettingsProvider);
      expect(restored.selectedId, 'sepia');
      expect(restored.customTheme.dark.canvas, const Color(0xFF112233));
      await controller.selectTheme('graphite');
      expect(prefs.getString(appThemeSettingsLegacyBackupKey), raw);
    },
  );

  test(
    'inactive old copies do not replace the Classic basis and corrupt selections fall back',
    () async {
      for (final selected in ['forest', 'custom:broken', 'missing']) {
        SharedPreferences.setMockInitialValues({
          appThemeSettingsPreferenceKey: legacySettings(selected),
        });
        final settings = (await loadedContainer()).read(
          appThemeSettingsProvider,
        );
        expect(
          settings.selectedId,
          selected == 'forest' ? 'forest' : 'classic',
        );
        expect(
          settings.customTheme.light.toJson(),
          AppTheme.classicLight.toJson(),
        );
        expect(settings.themes, hasLength(6));
      }
      for (final raw in ['{broken', '[]', 'null', 42]) {
        SharedPreferences.setMockInitialValues({
          appThemeSettingsPreferenceKey: raw,
        });
        final settings = (await loadedContainer()).read(
          appThemeSettingsProvider,
        );
        expect(settings.selectedId, 'classic');
        expect(settings.isLoaded, isTrue);
      }
      SharedPreferences.setMockInitialValues({
        appThemeSettingsPreferenceKey: jsonEncode({
          'version': 2,
          'selectedId': 'graphite',
          'customTheme': {'id': 'custom'},
        }),
      });
      final settings = (await loadedContainer()).read(appThemeSettingsProvider);
      expect(settings.selectedId, 'graphite');
      expect(
        settings.customTheme.light.toJson(),
        AppTheme.classicLight.toJson(),
      );
    },
  );

  test(
    'editing waits for storage and a failed initial read can be retried',
    () async {
      SharedPreferences.setMockInitialValues({
        appThemeSettingsPreferenceKey: legacySettings('forest'),
      });
      final pending = Completer<SharedPreferences>();
      var fail = true;
      final container = ProviderContainer(
        overrides: [
          appThemePreferencesProvider.overrideWithValue(
            () => fail ? pending.future : SharedPreferences.getInstance(),
          ),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(appThemeSettingsProvider.notifier);
      expect(controller.beginEdit, throwsStateError);
      final loading = expectLater(controller.load(), throwsStateError);
      pending.completeError(StateError('Unavailable'));
      await loading;
      expect(container.read(appThemeSettingsProvider).loadFailed, isTrue);
      fail = false;
      await controller.load();
      controller.beginEdit();
      controller.cancelPreview();
      expect(container.read(appThemeSettingsProvider).activeTheme.id, 'forest');
      expect(container.read(appThemeSettingsProvider).loadFailed, isFalse);
    },
  );

  for (final failedKey in [
    appThemeSettingsLegacyBackupKey,
    appThemeSettingsPreferenceKey,
  ]) {
    test(
      'failed write to $failedKey preserves the original data and draft for retry',
      () async {
        final raw = legacySettings('forest');
        SharedPreferences.setMockInitialValues({
          appThemeSettingsPreferenceKey: raw,
        });
        final container = await loadedContainer();
        final controller = container.read(appThemeSettingsProvider.notifier);
        final originalStore = SharedPreferencesStorePlatform.instance;
        final failing = _FailingStore(
          await originalStore.getAll(),
          'flutter.$failedKey',
        );
        SharedPreferencesStorePlatform.instance = failing;
        addTearDown(
          () => SharedPreferencesStorePlatform.instance = originalStore,
        );
        controller.beginEdit();
        final draft = container.read(appThemeSettingsProvider).preview!;
        controller.updatePreview(
          draft.copyWith(
            light: draft.light.copyWith(canvas: const Color(0xFFEEDDCC)),
          ),
        );
        await expectLater(controller.savePreview(), throwsStateError);
        final settings = container.read(appThemeSettingsProvider);
        expect(settings.preview!.light.canvas, const Color(0xFFEEDDCC));
        expect(settings.selectedId, 'forest');
        expect(settings.isSaving, isFalse);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(appThemeSettingsPreferenceKey), raw);
        expect(
          (await loadedContainer()).read(appThemeSettingsProvider).selectedId,
          'forest',
        );
        failing.fail = false;
        await controller.savePreview();
        expect(prefs.getString(appThemeSettingsLegacyBackupKey), raw);
        final restored = (await loadedContainer()).read(
          appThemeSettingsProvider,
        );
        expect(restored.selectedId, 'custom');
        expect(restored.customTheme.light.canvas, const Color(0xFFEEDDCC));
      },
    );
  }
}

class _FailingStore extends InMemorySharedPreferencesStore {
  _FailingStore(Map<String, Object> data, this.failedKey)
    : super.withData(data);
  final String failedKey;
  bool fail = true;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (fail && key == failedKey) return false;
    return super.setValue(valueType, key, value);
  }
}

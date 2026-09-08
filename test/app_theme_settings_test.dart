import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/theme/app_theme.dart';
import 'package:pomodoist/app/theme/app_theme_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
// The platform store is replaced only to exercise a failed disk write.
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

  test(
    'a failed initial read can be retried without changing saved selection',
    () async {
      SharedPreferences.setMockInitialValues({
        appThemeSettingsPreferenceKey: jsonEncode({
          'version': 1,
          'selectedId': 'forest',
          'customThemes': [],
        }),
      });
      var fail = true;
      final container = ProviderContainer(
        overrides: [
          appThemePreferencesProvider.overrideWithValue(
            () => fail
                ? Future<SharedPreferences>.error(StateError('Unavailable'))
                : SharedPreferences.getInstance(),
          ),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(appThemeSettingsProvider.notifier);
      await expectLater(controller.load(), throwsStateError);
      expect(container.read(appThemeSettingsProvider).loadFailed, isTrue);
      fail = false;
      await controller.load();
      expect(container.read(appThemeSettingsProvider).activeTheme.id, 'forest');
      expect(container.read(appThemeSettingsProvider).loadFailed, isFalse);
    },
  );

  test(
    'saving a built-in copy persists both palettes without changing the original',
    () async {
      final container = await loadedContainer();
      final controller = container.read(appThemeSettingsProvider.notifier);
      controller.beginEdit('ocean', name: 'My ocean');
      final draft = container.read(appThemeSettingsProvider).preview!;
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
      expect(settings.customThemes, hasLength(1));
      expect(settings.activeTheme.name, 'My ocean');
      expect(settings.activeTheme.light.canvas, const Color(0xFFEEDDCC));
      expect(settings.activeTheme.dark.canvas, const Color(0xFF112233));
      expect(
        settings.themeById('ocean').light.canvas,
        isNot(const Color(0xFFEEDDCC)),
      );
      expect(settings.preview, isNull);
    },
  );

  test(
    'cancel restores the selection and never persists the live preview',
    () async {
      final container = await loadedContainer();
      final controller = container.read(appThemeSettingsProvider.notifier);
      await controller.selectTheme('forest');
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(appThemeSettingsPreferenceKey);
      controller.beginEdit('classic', name: 'Unsaved');
      expect(
        container.read(appThemeSettingsProvider).activeTheme.name,
        'Unsaved',
      );
      expect(prefs.getString(appThemeSettingsPreferenceKey), saved);
      controller.cancelPreview();
      expect(container.read(appThemeSettingsProvider).activeTheme.id, 'forest');
      expect(container.read(appThemeSettingsProvider).customThemes, isEmpty);
      expect(
        (await loadedContainer()).read(appThemeSettingsProvider).activeTheme.id,
        'forest',
      );
    },
  );

  test(
    'editing keeps identity, duplicating makes a new copy, deleting active falls back',
    () async {
      final container = await loadedContainer();
      final controller = container.read(appThemeSettingsProvider.notifier);
      controller.beginEdit('classic', name: 'First');
      await controller.savePreview();
      final firstId = container.read(appThemeSettingsProvider).selectedId;
      controller.beginEdit(firstId, name: 'Renamed');
      await controller.savePreview();
      expect(container.read(appThemeSettingsProvider).selectedId, firstId);
      expect(
        container.read(appThemeSettingsProvider).customThemes.single.name,
        'Renamed',
      );
      controller.beginEdit(firstId, name: 'Second', duplicate: true);
      await controller.savePreview();
      final secondId = container.read(appThemeSettingsProvider).selectedId;
      expect(secondId, isNot(firstId));
      await controller.deleteTheme(secondId);
      final restored = (await loadedContainer()).read(appThemeSettingsProvider);
      expect(restored.selectedId, 'classic');
      expect(restored.customThemes.single.id, firstId);
      await expectLater(controller.deleteTheme('classic'), throwsArgumentError);
    },
  );

  test(
    'corrupt records are ignored independently and an unknown selection falls back',
    () async {
      final valid = builtinAppThemes.first
          .copyWith(id: 'custom:valid', name: 'Valid')
          .toJson();
      SharedPreferences.setMockInitialValues({
        appThemeSettingsPreferenceKey: jsonEncode({
          'version': 1,
          'selectedId': 'missing',
          'customThemes': [
            null,
            {'id': 'bad'},
            valid,
            valid,
          ],
        }),
      });
      final settings = (await loadedContainer()).read(appThemeSettingsProvider);
      expect(settings.selectedId, 'classic');
      expect(settings.customThemes.single.name, 'Valid');
      for (final raw in ['{broken', '[]', 'null', 42]) {
        SharedPreferences.setMockInitialValues({
          appThemeSettingsPreferenceKey: raw,
        });
        final restored = (await loadedContainer()).read(
          appThemeSettingsProvider,
        );
        expect(restored.activeTheme.id, 'classic');
        expect(restored.customThemes, isEmpty);
        expect(restored.isLoaded, isTrue);
      }
    },
  );

  test(
    'editing waits for initial storage load instead of overwriting saved themes',
    () async {
      SharedPreferences.setMockInitialValues({
        appThemeSettingsPreferenceKey: jsonEncode({
          'version': 1,
          'selectedId': 'forest',
          'customThemes': [],
        }),
      });
      final pending = Completer<SharedPreferences>();
      final container = ProviderContainer(
        overrides: [
          appThemePreferencesProvider.overrideWithValue(() => pending.future),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(appThemeSettingsProvider.notifier);
      expect(
        () => controller.beginEdit('classic', name: 'Too early'),
        throwsStateError,
      );
      pending.complete(await SharedPreferences.getInstance());
      await controller.load();
      controller.beginEdit('ocean', name: 'After load');
      controller.cancelPreview();
      expect(container.read(appThemeSettingsProvider).activeTheme.id, 'forest');
    },
  );

  test(
    'failed writes keep the draft and committed theme, and allow retry',
    () async {
      final container = await loadedContainer();
      final controller = container.read(appThemeSettingsProvider.notifier);
      await controller.selectTheme('ocean');
      final originalStore = SharedPreferencesStorePlatform.instance;
      final stored = await originalStore.getAll();
      final failing = _FailingStore(stored);
      SharedPreferencesStorePlatform.instance = failing;
      addTearDown(
        () => SharedPreferencesStorePlatform.instance = originalStore,
      );
      controller.beginEdit('forest', name: 'Keep my draft');
      await expectLater(controller.savePreview(), throwsStateError);
      final settings = container.read(appThemeSettingsProvider);
      expect(settings.preview!.name, 'Keep my draft');
      expect(settings.selectedId, 'ocean');
      expect(settings.customThemes, isEmpty);
      expect(settings.isSaving, isFalse);
      expect(
        (await loadedContainer()).read(appThemeSettingsProvider).selectedId,
        'ocean',
      );
      failing.fail = false;
      await controller.savePreview();
      expect(
        (await loadedContainer())
            .read(appThemeSettingsProvider)
            .activeTheme
            .name,
        'Keep my draft',
      );
    },
  );
}

class _FailingStore extends InMemorySharedPreferencesStore {
  _FailingStore(super.data) : super.withData();
  bool fail = true;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (fail) return false;
    return super.setValue(valueType, key, value);
  }
}

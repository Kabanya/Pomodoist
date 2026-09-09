import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/theme/app_theme_settings.dart';
import 'package:pomodoist/app/theme/theme_image_store.dart';
import 'package:pomodoist/app/theme/theme_image_preparation.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Replace disk writes only; no widget binding or app is mounted.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  test('background kind migrates photos and safely decodes glass settings', () {
    final old = {
      'images': {
        'main.light': {'imageId': 'a' * 64},
      },
    };
    expect(ThemeBackgrounds.fromJson(old).type, ThemeBackgroundType.photo);
    expect(ThemeBackgrounds.fromJson({}).type, ThemeBackgroundType.color);
    final glass = ThemeBackgrounds.fromJson({
      ...old,
      'type': 'macosGlass',
      'glassLightDim': -1,
      'glassDarkDim': 2,
    });
    expect(glass.glassDim(Brightness.light), 0);
    expect(glass.glassDim(Brightness.dark), 1);
    expect(ThemeBackgrounds.fromJson(glass.toJson()).toJson(), glass.toJson());
    final damaged = ThemeBackgrounds.fromJson({
      'type': 'bad',
      'glassLightDim': double.nan,
      'glassDarkDim': 'bad',
    });
    expect(damaged.type, ThemeBackgroundType.color);
    expect(damaged.glassDim(Brightness.light), .4);
    expect(damaged.glassDim(Brightness.dark), .5);
    for (final isMacOS in [false, true]) {
      for (final ready in [false, true]) {
        for (final reduced in [false, true]) {
          expect(
            glass.effectiveType(
              isMacOS: isMacOS,
              glassReady: ready,
              reduceTransparency: reduced,
            ),
            isMacOS && ready && !reduced
                ? ThemeBackgroundType.macosGlass
                : ThemeBackgroundType.color,
          );
        }
      }
    }
    for (final type in ThemeBackgroundType.values) {
      final switched = glass.copyWith(type: type);
      expect(switched.imageIds, glass.imageIds);
      expect(switched.glassDim(Brightness.dark), 1);
      expect(
        switched.resolve(ThemeBackgroundZone.main, Brightness.light).imageId,
        type == ThemeBackgroundType.photo ? 'a' * 64 : null,
      );
    }
  });

  test(
    'Custom retains separate background slots in its serialized settings',
    () {
      final imageId = 'a' * 64;
      final json = defaultCustomTheme.toJson()
        ..['backgrounds'] = {
          'mode': 'separate',
          'images': {
            'main.light': {'imageId': imageId, 'dim': .3, 'blur': 8.0},
            'sidebar.dark': {'imageId': 'b' * 64, 'dim': .6, 'blur': 2.0},
          },
        };
      final restored = AppThemeDefinition.fromJson(json);
      expect(restored.backgrounds.type, ThemeBackgroundType.photo);
      expect(
        restored.backgrounds.toJson()['images'],
        (json['backgrounds'] as Map)['images'],
      );
      expect(restored.light.canvas, defaultCustomTheme.light.canvas);
      expect(restored.dark.canvas, defaultCustomTheme.dark.canvas);
    },
  );

  test('background modes resolve each zone without losing inactive slots', () {
    var backgrounds = const ThemeBackgrounds(type: ThemeBackgroundType.photo);
    for (final zone in ThemeBackgroundZone.values) {
      for (final brightness in Brightness.values) {
        backgrounds = backgrounds.withImage(
          zone,
          brightness,
          ThemeBackgroundImage(
            imageId: '${zone.index + brightness.index * 3 + 1}' * 64,
            dim: brightness == Brightness.light ? .4 : .5,
          ),
        );
      }
    }
    for (final mode in ThemeBackgroundMode.values) {
      final changed = backgrounds.copyWith(mode: mode);
      expect(changed.imageIds, hasLength(6));
      for (final brightness in Brightness.values) {
        for (final zone in ThemeBackgroundZone.values) {
          final resolved = changed.resolve(zone, brightness);
          final expected =
              mode == ThemeBackgroundMode.mainOnly &&
                  zone != ThemeBackgroundZone.main
              ? null
              : changed
                    .imageFor(
                      mode == ThemeBackgroundMode.wholeApp
                          ? ThemeBackgroundZone.main
                          : zone,
                      brightness,
                    )
                    .imageId;
          expect(resolved.imageId, expected);
        }
      }
    }
    final empty = const ThemeBackgrounds().withImage(
      ThemeBackgroundZone.main,
      Brightness.light,
      ThemeBackgroundImage(imageId: 'a' * 64, dim: .4),
    );
    expect(
      empty.resolve(ThemeBackgroundZone.main, Brightness.dark).imageId,
      isNull,
    );
    expect(empty.resolve(ThemeBackgroundZone.main, Brightness.dark).dim, .5);
  });

  test('legacy and damaged background settings preserve palette colors', () {
    final json = defaultCustomTheme.toJson()..remove('backgrounds');
    expect(AppThemeDefinition.fromJson(json).backgrounds.imageIds, isEmpty);
    json['backgrounds'] = {
      'mode': 'unknown',
      'images': {
        'main.light': {'imageId': '../outside', 'dim': -1, 'blur': 200},
        'sidebar.dark': {
          'imageId': 'b' * 64,
          'dim': 'invalid',
          'blur': double.nan,
        },
        'invented.light': {'imageId': 'c' * 64},
      },
    };
    final theme = AppThemeDefinition.fromJson(json);
    expect(theme.light.toJson(), defaultCustomTheme.light.toJson());
    expect(theme.backgrounds.mode, ThemeBackgroundMode.mainOnly);
    final main = theme.backgrounds.imageFor(
      ThemeBackgroundZone.main,
      Brightness.light,
    );
    expect(main.imageId, isNull);
    expect(main.dim, 0);
    expect(main.blur, 20);
    expect(
      theme.backgrounds
          .imageFor(ThemeBackgroundZone.sidebar, Brightness.dark)
          .dim,
      .5,
    );
    expect(theme.backgrounds.imageIds, {'b' * 64});
  });

  group('background editor controller', () {
    late _ImageStore images;
    late List<String> events;
    late _Preferences preferences;
    late ProviderContainer container;
    late AppThemeSettingsController controller;
    final pixels = Uint8List.fromList([1, 2, 3]);

    setUp(() async {
      events = [];
      SharedPreferences.setMockInitialValues({});
      preferences = _Preferences(events);
      SharedPreferencesStorePlatform.instance = preferences;
      images = _ImageStore(events);
      container = ProviderContainer(
        overrides: [
          themeImageStoreProvider.overrideWithValue(images),
          themeImagePreparerProvider.overrideWithValue((bytes) async => bytes),
        ],
      );
      controller = container.read(appThemeSettingsProvider.notifier);
      await controller.load();
      controller.beginEdit();
    });
    tearDown(() => container.dispose());

    Future<void> choose([Brightness brightness = Brightness.light]) =>
        controller.chooseBackground(
          ThemeBackgroundZone.main,
          brightness,
          () async => XFile.fromData(
            brightness == Brightness.light
                ? pixels
                : Uint8List.fromList([7, 8, 9]),
          ),
        );

    test(
      'glass and color saves retain photos, tint pairs and resumable drafts',
      () async {
        await choose();
        await choose(Brightness.dark);
        await controller.savePreview();
        final ids = images.data.keys.toSet();
        for (final type in [
          ThemeBackgroundType.macosGlass,
          ThemeBackgroundType.color,
        ]) {
          controller.beginEdit();
          final draft = container.read(appThemeSettingsProvider).preview!;
          controller.updatePreview(
            draft.copyWith(
              backgrounds: draft.backgrounds.copyWith(
                type: type,
                glassLightDim: .2,
                glassDarkDim: .7,
              ),
            ),
          );
          events.clear();
          await controller.savePreview();
          expect(events, ['preferences', 'retain']);
          expect(images.data.keys.toSet(), ids);
          controller.beginEdit();
          final resumed = container.read(appThemeSettingsProvider).preview!;
          expect(resumed.backgrounds.type, type);
          expect(resumed.backgrounds.glassDim(Brightness.light), .2);
          expect(resumed.backgrounds.glassDim(Brightness.dark), .7);
          controller.resetPreviewToClassic();
          final reset = container
              .read(appThemeSettingsProvider)
              .preview!
              .backgrounds;
          expect(reset.type, ThemeBackgroundType.color);
          expect(reset.imageIds, isEmpty);
          expect(reset.glassDim(Brightness.light), .4);
          expect(reset.glassDim(Brightness.dark), .5);
          controller.cancelPreview();
          expect(
            container
                .read(appThemeSettingsProvider)
                .activeTheme
                .backgrounds
                .toJson(),
            resumed.backgrounds.toJson(),
          );
        }
      },
    );

    test(
      'failed glass settings write keeps the draft and cancel restores photos',
      () async {
        await choose();
        await controller.savePreview();
        controller.beginEdit();
        final original = container.read(appThemeSettingsProvider).preview!;
        final draft = original.copyWith(
          backgrounds: original.backgrounds.copyWith(
            type: ThemeBackgroundType.macosGlass,
            glassDarkDim: .25,
          ),
        );
        controller.updatePreview(draft);
        preferences.fail = true;
        await expectLater(controller.savePreview(), throwsStateError);
        expect(container.read(appThemeSettingsProvider).preview, same(draft));
        expect(images.data.keys.toSet(), original.backgrounds.imageIds);
        controller.cancelPreview();
        expect(
          container.read(appThemeSettingsProvider).activeTheme.backgrounds.type,
          ThemeBackgroundType.photo,
        );
      },
    );

    test(
      'a late photo choice cannot change a newly selected background kind',
      () async {
        await choose();
        final selected = Completer<XFile?>();
        final pending = controller.chooseBackground(
          ThemeBackgroundZone.main,
          Brightness.light,
          () => selected.future,
        );
        final draft = container.read(appThemeSettingsProvider).preview!;
        controller.updatePreview(
          draft.copyWith(
            backgrounds: draft.backgrounds.copyWith(
              type: ThemeBackgroundType.macosGlass,
            ),
          ),
        );
        selected.complete(XFile.fromData(Uint8List.fromList([4, 5, 6])));
        await pending;
        final current = container.read(appThemeSettingsProvider);
        expect(
          current.preview!.backgrounds.type,
          ThemeBackgroundType.macosGlass,
        );
        expect(
          current.preview!.backgrounds.imageIds,
          draft.backgrounds.imageIds,
        );
        expect(current.isPreparingImage, isFalse);
      },
    );

    test(
      'previews stay in memory, save both variants and resume saved settings',
      () async {
        await choose();
        await choose(Brightness.dark);
        final draft = container.read(appThemeSettingsProvider).preview!;
        final id = draft.backgrounds
            .imageFor(ThemeBackgroundZone.main, Brightness.light)
            .imageId!;
        expect(draft.backgrounds.imageIds, hasLength(2));
        expect(await controller.readImage(id), pixels);
        expect(images.data, isEmpty);
        expect(events, isEmpty);
        await controller.savePreview();
        expect(events, ['write', 'write', 'preferences', 'retain']);
        expect(images.data[id], pixels);
        expect(container.read(appThemeSettingsProvider).selectedId, 'custom');
        controller.beginEdit();
        expect(
          container
              .read(appThemeSettingsProvider)
              .preview!
              .backgrounds
              .toJson(),
          draft.backgrounds.toJson(),
        );
        final persisted = (await SharedPreferences.getInstance()).getString(
          appThemeSettingsPreferenceKey,
        )!;
        expect(
          AppThemeSettings.decode(persisted).customTheme.backgrounds.toJson(),
          draft.backgrounds.toJson(),
        );
        expect(persisted, isNot(contains(base64Encode(pixels))));
      },
    );

    test(
      'cancel and reset restore previous photo until a reset is saved',
      () async {
        await choose();
        await controller.savePreview();
        final saved = Map<String, Uint8List>.of(images.data);
        controller.beginEdit();
        controller.resetPreviewToClassic();
        expect(
          container
              .read(appThemeSettingsProvider)
              .preview!
              .backgrounds
              .imageIds,
          isEmpty,
        );
        expect(images.data.keys, saved.keys);
        controller.cancelPreview();
        expect(
          container
              .read(appThemeSettingsProvider)
              .activeTheme
              .backgrounds
              .imageIds,
          saved.keys.toSet(),
        );
        controller.beginEdit();
        controller.resetPreviewToClassic();
        await controller.savePreview();
        expect(images.data, isEmpty);
      },
    );

    test('cancelled file choice preserves current background', () async {
      await choose();
      final before = container.read(appThemeSettingsProvider).preview;
      await controller.chooseBackground(
        ThemeBackgroundZone.sidebar,
        Brightness.dark,
        () async => null,
      );
      expect(container.read(appThemeSettingsProvider).preview, same(before));
      expect(
        container.read(appThemeSettingsProvider).isPreparingImage,
        isFalse,
      );
    });

    test(
      'late selections cannot modify another zone, a new editor or a reset',
      () async {
        for (final interrupt in [
          () => controller.cancelImageSelection(),
          () {
            controller.cancelPreview();
            controller.beginEdit();
          },
          () => controller.resetPreviewToClassic(),
        ]) {
          final selected = Completer<XFile?>();
          final pending = controller.chooseBackground(
            ThemeBackgroundZone.main,
            Brightness.light,
            () => selected.future,
          );
          interrupt();
          selected.complete(XFile.fromData(pixels));
          await pending;
          expect(
            container
                .read(appThemeSettingsProvider)
                .preview!
                .backgrounds
                .imageIds,
            isEmpty,
          );
          expect(
            container.read(appThemeSettingsProvider).isPreparingImage,
            isFalse,
          );
        }
      },
    );

    test(
      'late preparation and errors are discarded after context changes',
      () async {
        final prepared = Completer<Uint8List>();
        final started = Completer<void>();
        final other = ProviderContainer(
          overrides: [
            themeImageStoreProvider.overrideWithValue(images),
            themeImagePreparerProvider.overrideWithValue((bytes) {
              started.complete();
              return prepared.future;
            }),
          ],
        );
        addTearDown(other.dispose);
        final editor = other.read(appThemeSettingsProvider.notifier);
        await editor.load();
        editor.beginEdit();
        final pending = editor.chooseBackground(
          ThemeBackgroundZone.main,
          Brightness.light,
          () async => XFile.fromData(pixels),
        );
        await started.future;
        await expectLater(editor.savePreview(), throwsStateError);
        editor.cancelImageSelection();
        prepared.completeError(const FormatException('bad image'));
        await pending;
        expect(
          other.read(appThemeSettingsProvider).preview!.backgrounds.imageIds,
          isEmpty,
        );
      },
    );

    test('oversized input is rejected before bytes are read', () async {
      await choose();
      final previous = container.read(appThemeSettingsProvider).preview;
      await expectLater(
        controller.chooseBackground(
          ThemeBackgroundZone.main,
          Brightness.light,
          () async => _OversizedFile(),
        ),
        throwsA(isA<ThemeImageTooLargeException>()),
      );
      expect(container.read(appThemeSettingsProvider).preview, same(previous));
      expect(
        container.read(appThemeSettingsProvider).isPreparingImage,
        isFalse,
      );
    });

    test(
      'image and preferences failures retain draft and old files for retry',
      () async {
        await choose();
        await controller.savePreview();
        final oldIds = images.data.keys.toSet();
        controller.beginEdit();
        await controller.chooseBackground(
          ThemeBackgroundZone.main,
          Brightness.light,
          () async => XFile.fromData(Uint8List.fromList([4, 5, 6])),
        );
        final draft = container.read(appThemeSettingsProvider).preview!;
        images.failWrite = true;
        events.clear();
        await expectLater(controller.savePreview(), throwsStateError);
        expect(events, ['write']);
        expect(container.read(appThemeSettingsProvider).preview, same(draft));
        expect(images.data.keys.toSet(), oldIds);
        images.failWrite = false;
        preferences.fail = true;
        events.clear();
        await expectLater(controller.savePreview(), throwsStateError);
        expect(events, ['write', 'preferences']);
        expect(images.data.keys.toSet().containsAll(oldIds), isTrue);
        expect(container.read(appThemeSettingsProvider).preview, same(draft));
        preferences.fail = false;
        await controller.savePreview();
        expect(images.data.keys.toSet(), draft.backgrounds.imageIds);
        expect(container.read(appThemeSettingsProvider).preview, isNull);
      },
    );

    test(
      'reset after a failed first save cleans staged files only after success',
      () async {
        await choose();
        preferences.fail = true;
        await expectLater(controller.savePreview(), throwsStateError);
        expect(images.data, isNotEmpty);
        controller.resetPreviewToClassic();
        expect(images.data, isNotEmpty);
        preferences.fail = false;
        events.clear();
        await controller.savePreview();
        expect(events, ['preferences', 'retain']);
        expect(images.data, isEmpty);
      },
    );

    test('replaced and removed draft images release their bytes', () async {
      await choose();
      final first = container
          .read(appThemeSettingsProvider)
          .preview!
          .backgrounds
          .imageIds
          .single;
      await controller.chooseBackground(
        ThemeBackgroundZone.main,
        Brightness.light,
        () async => XFile.fromData(Uint8List.fromList([4, 5, 6])),
      );
      expect(await controller.readImage(first), isNull);
      final draft = container.read(appThemeSettingsProvider).preview!;
      final current = draft.backgrounds.imageIds.single;
      controller.updatePreview(
        draft.copyWith(
          backgrounds: draft.backgrounds.withImage(
            ThemeBackgroundZone.main,
            Brightness.light,
            draft.backgrounds
                .imageFor(ThemeBackgroundZone.main, Brightness.light)
                .copyWith(clearImage: true),
          ),
        ),
      );
      expect(await controller.readImage(current), isNull);
    });

    test(
      'a stale tab selecting a preset preserves the latest saved Custom',
      () async {
        await choose();
        await controller.savePreview();
        final stale = ProviderContainer(
          overrides: [themeImageStoreProvider.overrideWithValue(images)],
        );
        addTearDown(stale.dispose);
        final staleController = stale.read(appThemeSettingsProvider.notifier);
        await staleController.load();
        controller.beginEdit();
        await controller.chooseBackground(
          ThemeBackgroundZone.main,
          Brightness.light,
          () async => XFile.fromData(Uint8List.fromList([4, 5, 6])),
        );
        await controller.savePreview();
        final latestIds = images.data.keys.toSet();
        await staleController.selectTheme('ocean');
        final latest = stale.read(appThemeSettingsProvider);
        expect(latest.selectedId, 'ocean');
        expect(latest.customTheme.backgrounds.imageIds, latestIds);
        expect(images.data.keys.toSet(), latestIds);
      },
    );

    test(
      'a stale draft with a deleted image cannot replace valid settings',
      () async {
        await choose();
        await controller.savePreview();
        final stale = ProviderContainer(
          overrides: [themeImageStoreProvider.overrideWithValue(images)],
        );
        addTearDown(stale.dispose);
        final staleController = stale.read(appThemeSettingsProvider.notifier);
        await staleController.load();
        staleController.beginEdit();
        controller.beginEdit();
        await controller.chooseBackground(
          ThemeBackgroundZone.main,
          Brightness.light,
          () async => XFile.fromData(Uint8List.fromList([4, 5, 6])),
        );
        await controller.savePreview();
        final saved = (await SharedPreferences.getInstance()).getString(
          appThemeSettingsPreferenceKey,
        );
        final latestIds = images.data.keys.toSet();
        events.clear();
        await expectLater(staleController.savePreview(), throwsStateError);
        expect(events, isEmpty);
        expect(stale.read(appThemeSettingsProvider).preview, isNotNull);
        expect(images.data.keys.toSet(), latestIds);
        expect(
          (await SharedPreferences.getInstance()).getString(
            appThemeSettingsPreferenceKey,
          ),
          saved,
        );
      },
    );

    test('cleanup failure does not roll back saved preferences', () async {
      await choose();
      images.failCleanup = true;
      await controller.savePreview();
      expect(container.read(appThemeSettingsProvider).preview, isNull);
      expect(container.read(appThemeSettingsProvider).selectedId, 'custom');
      expect(
        (await SharedPreferences.getInstance()).getString(
          appThemeSettingsPreferenceKey,
        ),
        isNotNull,
      );
    });
  });
}

class _ImageStore extends ThemeImageStore {
  _ImageStore(this.events);
  final List<String> events;
  final Map<String, Uint8List> data = {};
  bool failWrite = false;
  bool failCleanup = false;
  @override
  Future<Uint8List?> read(String id) async => data[id];
  @override
  Future<void> write(String id, Uint8List bytes) async {
    events.add('write');
    if (failWrite) throw StateError('disk full');
    data[id] = bytes;
  }

  @override
  Future<void> retain(Set<String> ids) async {
    events.add('retain');
    if (failCleanup) throw StateError('cleanup failed');
    data.removeWhere((id, _) => !ids.contains(id));
  }
}

class _Preferences extends InMemorySharedPreferencesStore {
  _Preferences(this.events) : super.withData({});
  final List<String> events;
  bool fail = false;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.$appThemeSettingsPreferenceKey') {
      events.add('preferences');
      if (fail) return false;
    }
    return super.setValue(type, key, value);
  }
}

class _OversizedFile extends XFile {
  _OversizedFile() : super('unused');
  @override
  Future<int> length() async => themeImageMaxBytes + 1;
  @override
  Future<Uint8List> readAsBytes() =>
      throw StateError('Must check size before reading');
}

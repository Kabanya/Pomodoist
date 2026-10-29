import 'dart:convert';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:pomodoist/domain/models/platform/global_shortcut.dart';
import 'package:pomodoist/data/services/platform/global_shortcut_codec.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/app_icon_dependencies.dart';
import 'package:pomodoist/config/status_item_style_dependencies.dart';
import 'package:pomodoist/data/repositories/settings/status_item_style_repository.dart';
import 'package:pomodoist/domain/models/settings/status_item_style.dart';
import 'package:pomodoist/domain/models/settings/task_preferences.dart';
import 'package:pomodoist/ui/settings/view_models/status_item_style_view_model.dart';
import 'package:pomodoist/config/keyboard_shortcuts.dart';
import 'package:pomodoist/config/focus_dependencies.dart';
import 'package:pomodoist/ui/settings/view_models/task_settings_view_model.dart';
import 'package:pomodoist/data/repositories/settings/app_icon_repository.dart';
import 'package:pomodoist/domain/models/settings/app_icon_choice.dart';
import 'package:pomodoist/config/agent_app_settings_adapter.dart';
import 'package:pomodoist/ui/settings/view_models/theme_settings_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

final adapterProvider = Provider(
  (ref) => AgentAppSettingsAdapter(ref, isCurrent: () => true),
);

class IconRepository implements AppIconRepository {
  AppIconChoice choice = AppIconChoice.pomo;
  bool fail = false;
  Future<void>? gate;
  Completer<void>? started;
  @override
  Future<void> apply(AppIconChoice next) async {
    started?.complete();
    await gate;
    if (fail) throw StateError('Native icon unavailable');
    choice = next;
  }

  @override
  Future<AppIconChoice> read() async => choice;
}

class Images extends ThemeImageRepository {
  final values = <String, Uint8List>{};
  Future<void>? gate;
  Completer<void>? entered;
  @override
  Future<T> protect<T>(Future<T> Function() action) async {
    entered?.complete();
    await gate;
    return action();
  }

  @override
  Future<Uint8List?> read(String id) async => values[id];
  @override
  Future<void> write(String id, Uint8List bytes) async {
    values[id] = bytes;
  }

  @override
  Future<void> retain(Set<String> ids) async {
    values.removeWhere((key, _) => !ids.contains(key));
  }
}

class StatusRepository implements StatusItemStyleRepository {
  bool fail = false;
  @override
  Stream<StatusItemStyle> get changes => const Stream.empty();
  @override
  Future<StatusItemStyle> read() async => StatusItemStyle.classic;
  @override
  Future<StatusItemStyle> select(StatusItemStyle value) async {
    if (fail) throw StateError('Native menu unavailable');
    return value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  ProviderContainer create([TargetPlatform platform = TargetPlatform.android]) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('pomodoist/quick_add'),
          (call) async => call.method == 'getGlobalShortcut'
              ? GlobalQuickAddBinding.defaultFor(
                  isMacOS: platform == TargetPlatform.macOS,
                ).toJson()
              : null,
        );
    final container = ProviderContainer(
      overrides: [
        shortcutTargetPlatformProvider.overrideWithValue(platform),
        appIconRepositoryProvider.overrideWithValue(IconRepository()),
        statusItemStyleRepositoryProvider.overrideWithValue(StatusRepository()),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('snapshots hydrate and versions follow writes', () async {
    SharedPreferences.setMockInitialValues({'tasks.listStyle': 'classic'});
    final adapter = create().read(adapterProvider);
    final first = await adapter.snapshot();
    expect(first['status'], 'applied');
    expect(utf8.encode(jsonEncode(first)).length, lessThan(32768));
    expect((first['values'] as Map)['taskListStyle'], 'classic');
    final result = await adapter.apply({
      'operation': 'appearance',
      'setting': 'taskListStyle',
      'value': 'modern',
      'expected_version': (first['versions'] as Map)['taskListStyle'],
    });
    expect(result['status'], 'applied');
    expect(
      (await SharedPreferences.getInstance()).getString('tasks.listStyle'),
      'modern',
    );
    expect(
      (await adapter.apply({
        'operation': 'appearance',
        'setting': 'taskListStyle',
        'value': 'classic',
        'expected_version': (first['versions'] as Map)['taskListStyle'],
      }))['code'],
      'version_conflict',
    );
  });
  test(
    'rejects invalid values, reserved shortcuts and unsupported global',
    () async {
      final adapter = create().read(adapterProvider);
      expect(
        (await adapter.apply({
          'operation': 'appearance',
          'setting': 'zoom',
          'value': 999,
        }))['code'],
        'invalid_value',
      );
      expect(
        (await adapter.apply({
          'operation': 'shortcut',
          'setting': 'shortcuts',
          'value': {'command': 'globalQuickAdd', 'binding': null},
        }))['code'],
        'unsupported',
      );
      final binding = appZoomBindings(
        TargetPlatform.android,
      ).keys.first.toJson();
      expect(
        (await adapter.apply({
          'operation': 'shortcut',
          'setting': 'shortcuts',
          'value': {'command': 'search', 'binding': binding},
        }))['code'],
        'shortcut_conflict',
      );
    },
  );
  test(
    'custom palette preserves untouched roles and rejects an open draft',
    () async {
      final c = create();
      final adapter = c.read(adapterProvider);
      expect(
        (await adapter.apply({
          'operation': 'appearance',
          'setting': 'customTheme',
          'value': {
            'light': {'accent': '#123456'},
          },
        }))['status'],
        'applied',
      );
      final state = c.read(appThemeSettingsProvider);
      expect(state.customTheme.light.toJson()['accent'], '#123456');
      expect(state.customTheme.dark.toJson(), defaultCustomTheme.dark.toJson());
      c.read(appThemeSettingsProvider.notifier).beginEdit();
      expect(
        (await adapter.apply({
          'operation': 'appearance',
          'setting': 'theme',
          'value': 'ocean',
        }))['code'],
        'busy',
      );
      expect(c.read(appThemeSettingsProvider).preview, isNotNull);
    },
  );
  test('session change during image preparation blocks persistence', () async {
    var current = true;
    final prepared = Completer<({String id, Uint8List bytes})>();
    final started = Completer<void>();
    final provider = Provider(
      (ref) => AgentAppSettingsAdapter(
        ref,
        isCurrent: () => current,
        importImage: (_) {
          started.complete();
          return prepared.future;
        },
      ),
    );
    final c = create();
    final applying = c.read(provider).apply({
      'operation': 'appearance',
      'setting': 'customTheme',
      'value': {
        'image_url': 'https://example.com/image.png',
        'image_zone': 'main',
        'image_palette': 'light',
      },
    });
    await started.future;
    current = false;
    prepared.complete((id: 'theme-test-image', bytes: Uint8List(1)));
    expect((await applying)['code'], 'session_expired');
    expect(
      (await SharedPreferences.getInstance()).getString(
        appThemeSettingsPreferenceKey,
      ),
      isNull,
    );
  });
  test('strict native icon failure is not reported as applied', () async {
    final icon = IconRepository();
    final c = ProviderContainer(
      overrides: [
        shortcutTargetPlatformProvider.overrideWithValue(
          TargetPlatform.android,
        ),
        appIconRepositoryProvider.overrideWithValue(icon),
      ],
    );
    addTearDown(c.dispose);
    final adapter = c.read(adapterProvider);
    await adapter.snapshot();
    icon.fail = true;
    expect(
      (await adapter.apply({
        'operation': 'appearance',
        'setting': 'icon',
        'value': 'classic',
      }))['status'],
      'error',
    );
    expect(
      (await SharedPreferences.getInstance()).getString('app.icon'),
      isNull,
    );
  });
  test('manual changes invalidate a previously read version', () async {
    final c = create();
    final adapter = c.read(adapterProvider);
    final first = await adapter.snapshot();
    await c
        .read(taskListSettingsViewModelProvider.notifier)
        .setStyle(TaskListStyle.classic);
    final result = await adapter.apply({
      'operation': 'appearance',
      'setting': 'taskListStyle',
      'value': 'modern',
      'expected_version': (first['versions'] as Map)['taskListStyle'],
    });
    expect(result['code'], 'version_conflict');
  });
  test(
    'native icon completion after session expiry rolls back before preferences',
    () async {
      var current = true;
      final icon = IconRepository();
      final provider = Provider(
        (ref) => AgentAppSettingsAdapter(ref, isCurrent: () => current),
      );
      final c = ProviderContainer(
        overrides: [
          shortcutTargetPlatformProvider.overrideWithValue(
            TargetPlatform.android,
          ),
          appIconRepositoryProvider.overrideWithValue(icon),
        ],
      );
      addTearDown(c.dispose);
      final adapter = c.read(provider);
      await adapter.snapshot();
      final gate = Completer<void>();
      icon.gate = gate.future;
      icon.started = Completer<void>();
      final applying = adapter.apply({
        'operation': 'appearance',
        'setting': 'icon',
        'value': 'classic',
      });
      await icon.started!.future;
      icon.started = null;
      current = false;
      gate.complete();
      expect((await applying)['code'], 'session_expired');
      expect(icon.choice, AppIconChoice.pomo);
      expect(
        (await SharedPreferences.getInstance()).getString('app.icon'),
        isNull,
      );
    },
  );
  test(
    'image import stores only a local reference and preserves other zones',
    () async {
      final images = Images();
      final id = 'a' * 64;
      final provider = Provider(
        (ref) => AgentAppSettingsAdapter(
          ref,
          isCurrent: () => true,
          importImage: (_) async =>
              (id: id, bytes: Uint8List.fromList([1, 2, 3])),
        ),
      );
      final c = ProviderContainer(
        overrides: [
          shortcutTargetPlatformProvider.overrideWithValue(
            TargetPlatform.android,
          ),
          appIconRepositoryProvider.overrideWithValue(IconRepository()),
          themeImageRepositoryProvider.overrideWithValue(images),
        ],
      );
      addTearDown(c.dispose);
      final adapter = c.read(provider);
      final result = await adapter.apply({
        'operation': 'appearance',
        'setting': 'customTheme',
        'value': {
          'dark': {'accent': '#123456'},
          'image_url': 'https://example.com/private-source.png',
          'image_zone': 'sidebar',
          'image_palette': 'dark',
        },
      });
      expect(result['status'], 'applied');
      expect(images.values[id], [1, 2, 3]);
      final theme = c.read(appThemeSettingsProvider).customTheme;
      expect(
        theme.backgrounds
            .imageFor(ThemeBackgroundZone.sidebar, Brightness.dark)
            .imageId,
        id,
      );
      expect(
        theme.backgrounds
            .imageFor(ThemeBackgroundZone.main, Brightness.light)
            .imageId,
        isNull,
      );
      expect(
        builtinAppThemes.first.dark.toJson(),
        defaultCustomTheme.dark.toJson(),
      );
      final stored = (await SharedPreferences.getInstance()).getString(
        appThemeSettingsPreferenceKey,
      )!;
      expect(stored, isNot(contains('https:')));
      expect(result.toString(), isNot(contains('bytes')));
      expect(
        (await adapter.apply({
          'operation': 'appearance',
          'setting': 'customTheme',
          'value': {
            'light': {'accent': '#654321'},
          },
        }))['status'],
        'applied',
      );
      expect(
        c.read(appThemeSettingsProvider).customTheme.backgrounds.imageIds,
        {id},
      );
      expect(
        (await adapter.apply({
          'operation': 'appearance',
          'setting': 'customTheme',
          'value': {
            'backgrounds': {'mode': 'separate'},
          },
        }))['status'],
        'applied',
      );
      expect(
        (await adapter.apply({
          'operation': 'appearance',
          'setting': 'customTheme',
          'value': {
            'backgrounds': {
              'images': {
                'sidebar.dark': {'dim': .75},
              },
            },
          },
        }))['status'],
        'applied',
      );
      final patched = c.read(appThemeSettingsProvider).customTheme.backgrounds;
      expect(patched.mode, ThemeBackgroundMode.separate);
      expect(
        patched.imageFor(ThemeBackgroundZone.sidebar, Brightness.dark).imageId,
        id,
      );
      expect(
        patched.imageFor(ThemeBackgroundZone.sidebar, Brightness.dark).dim,
        .75,
      );
    },
  );
  test('unavailable persistence cannot acknowledge a settings write', () async {
    final c = ProviderContainer(
      overrides: [
        shortcutTargetPlatformProvider.overrideWithValue(
          TargetPlatform.android,
        ),
        appIconRepositoryProvider.overrideWithValue(IconRepository()),
        sharedPreferencesProvider.overrideWith((_) async => null),
      ],
    );
    addTearDown(c.dispose);
    expect(
      (await c.read(adapterProvider).apply({
        'operation': 'appearance',
        'setting': 'zoom',
        'value': 110,
      }))['code'],
      'settings_unavailable',
    );
  });
  test('strict status item setter propagates native failures', () async {
    final repository = StatusRepository();
    final c = ProviderContainer(
      overrides: [
        statusItemStyleRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(c.dispose);
    final subscription = c.listen(statusItemStyleProvider, (_, _) {});
    addTearDown(subscription.close);
    final controller = c.read(statusItemStyleProvider.notifier);
    await Future<void>.delayed(Duration.zero);
    await controller.refresh();
    repository.fail = true;
    await expectLater(
      controller.selectStrict(StatusItemStyle.modern),
      throwsStateError,
    );
    expect(c.read(statusItemStyleProvider).style, StatusItemStyle.classic);
  });
  test(
    'global and internal shortcuts reject app and reserved zoom conflicts',
    () async {
      final adapter = create(TargetPlatform.windows).read(adapterProvider);
      for (final binding in [
        defaultAppShortcutBindings(
          TargetPlatform.windows,
        )[AppShortcutCommand.search]!,
        appZoomBindings(TargetPlatform.windows).keys.first,
      ]) {
        final global =
            {
                ...binding.toJson(),
                'keyCode': kWindowsToLogicalKey.entries
                    .firstWhere(
                      (entry) =>
                          entry.value ==
                          kFuchsiaToLogicalKey[binding.physicalKeyId |
                              LogicalKeyboardKey.fuchsiaPlane],
                    )
                    .key,
              }
              ..remove('physicalKeyId')
              ..removeWhere((key, value) => value == false);
        expect(
          (await adapter.apply({
            'operation': 'shortcut',
            'setting': 'shortcuts',
            'value': {'command': 'globalQuickAdd', 'binding': global},
          }))['code'],
          'shortcut_conflict',
        );
      }
      expect(
        (await adapter.apply({
          'operation': 'shortcut',
          'setting': 'shortcuts',
          'value': {
            'command': 'search',
            'binding': {
              'physicalKeyId': PhysicalKeyboardKey.space.usbHidUsage,
              'keyLabel': 'Space',
              'control': true,
              'alt': true,
              'meta': false,
              'shift': false,
            },
          },
        }))['code'],
        'shortcut_conflict',
      );
    },
  );
  test(
    'theme save checks concurrent saved state after waiting for the image lock',
    () async {
      final images = Images();
      final gate = Completer<void>();
      images.gate = gate.future;
      images.entered = Completer<void>();
      final c = ProviderContainer(
        overrides: [
          shortcutTargetPlatformProvider.overrideWithValue(
            TargetPlatform.android,
          ),
          appIconRepositoryProvider.overrideWithValue(IconRepository()),
          themeImageRepositoryProvider.overrideWithValue(images),
        ],
      );
      addTearDown(c.dispose);
      final applying = c.read(adapterProvider).apply({
        'operation': 'appearance',
        'setting': 'customTheme',
        'value': {
          'light': {'accent': '#123456'},
        },
      });
      await images.entered!.future;
      final prefs = await SharedPreferences.getInstance();
      final concurrent = jsonEncode({
        'version': 2,
        'selectedId': 'ocean',
        'customTheme': defaultCustomTheme.toJson(),
      });
      await prefs.setString(appThemeSettingsPreferenceKey, concurrent);
      gate.complete();
      expect((await applying)['code'], 'version_conflict');
      expect(prefs.getString(appThemeSettingsPreferenceKey), concurrent);
    },
  );
  test(
    'macOS native codes reject spoofed labels for zoom and global conflicts',
    () async {
      final adapter = create(TargetPlatform.macOS).read(adapterProvider);
      expect(
        (await adapter.apply({
          'operation': 'shortcut',
          'setting': 'shortcuts',
          'value': {
            'command': 'globalQuickAdd',
            'binding': {'keyCode': 24, 'keyLabel': 'Q', 'meta': true},
          },
        }))['code'],
        'shortcut_conflict',
      );
      expect(
        (await adapter.apply({
          'operation': 'shortcut',
          'setting': 'shortcuts',
          'value': {
            'command': 'search',
            'binding': {
              'physicalKeyId': PhysicalKeyboardKey.space.usbHidUsage,
              'keyLabel': 'Q',
              'alt': true,
            },
          },
        }))['code'],
        'shortcut_conflict',
      );
      expect(
        (await adapter.apply({
          'operation': 'shortcut',
          'setting': 'shortcuts',
          'value': {
            'command': 'globalQuickAdd',
            'binding': {'keyCode': 0, 'keyLabel': 'Q', 'alt': true},
          },
        }))['status'],
        'applied',
      );
    },
  );
  test(
    'another container manual edits refresh snapshots and reject stale versions for every group',
    () async {
      final a = create();
      final b = create();
      final adapter = a.read(adapterProvider);
      final other = b.read(adapterProvider);
      final initial = await adapter.snapshot();
      final commands = <String, Object>{
        'themeMode': 'dark',
        'theme': 'ocean',
        'customTheme': {
          'light': {'accent': '#123456'},
        },
        'icon': 'classic',
        'bottomNavigation': {
          'style': 'labels',
          'destinations': ['today', 'focus'],
        },
        'taskDetailLayout': 'descriptionFirst',
        'taskListStyle': 'classic',
        'taskBranchStyle': 'grouped',
        'taskRowSpacing': 'spacious',
        'taskTimeDisplayMode': 'range',
        'zoom': 140,
        'focusTimerStyle': 'bar',
        'focusViewMode': 'full',
      };
      for (final entry in commands.entries) {
        expect(
          (await other.apply({
            'operation': 'appearance',
            'setting': entry.key,
            'value': entry.value,
          }))['status'],
          'applied',
          reason: entry.key,
        );
      }
      // A manual controller edit in another tab changes the full shared shortcut map.
      final search = AppShortcutBinding(
        physicalKeyId: PhysicalKeyboardKey.keyY.usbHidUsage,
        keyLabel: 'Y',
        control: true,
        alt: true,
      );
      await b
          .read(keyboardShortcutsProvider.notifier)
          .setBinding(AppShortcutCommand.search, search);
      final fresh = await adapter.snapshot();
      expect((fresh['values'] as Map)['zoom'], 140);
      expect((fresh['values'] as Map)['taskListStyle'], 'classic');
      expect(
        ((fresh['values'] as Map)['shortcuts'] as Map)['bindings']['search'],
        search.toJson(),
      );
      for (final entry in commands.entries) {
        expect(
          (await adapter.apply({
            'operation': 'appearance',
            'setting': entry.key,
            'value': entry.value,
            'expected_version': (initial['versions'] as Map)[entry.key],
          }))['code'],
          'version_conflict',
          reason: entry.key,
        );
      }
      expect(
        (await adapter.apply({
          'operation': 'shortcut',
          'setting': 'shortcuts',
          'value': {
            'command': 'today',
            'binding': {
              'physicalKeyId': PhysicalKeyboardKey.keyU.usbHidUsage,
              'keyLabel': 'U',
              'control': true,
              'alt': true,
            },
          },
          'expected_version': (initial['versions'] as Map)['shortcuts'],
        }))['code'],
        'version_conflict',
      );
      expect(
        a.read(keyboardShortcutsProvider)[AppShortcutCommand.search],
        search,
      );
    },
  );
  test(
    'captured shifted and Cyrillic key labels keep physical identity on roundtrip',
    () async {
      final c = create(TargetPlatform.macOS);
      final adapter = c.read(adapterProvider);
      final controller = c.read(keyboardShortcutsProvider.notifier);
      await controller.load();
      for (final (physical, label, shift) in [
        (PhysicalKeyboardKey.keyF, 'А', false),
        (PhysicalKeyboardKey.equal, '+', true),
        (PhysicalKeyboardKey.backspace, 'Delete', false),
      ]) {
        final binding = AppShortcutBinding(
          physicalKeyId: physical.usbHidUsage,
          keyLabel: label,
          alt: true,
          shift: shift,
        );
        await controller.setBinding(AppShortcutCommand.search, binding);
        final snapshot = await adapter.snapshot();
        final value =
            (((snapshot['values'] as Map)['shortcuts'] as Map)['bindings']
                as Map)['search'];
        final result = await adapter.apply({
          'operation': 'shortcut',
          'setting': 'shortcuts',
          'value': {'command': 'search', 'binding': value},
        });
        expect(result['status'], 'applied', reason: result.toString());
        expect(
          c
              .read(keyboardShortcutsProvider)[AppShortcutCommand.search]!
              .physicalKeyId,
          physical.usbHidUsage,
        );
      }
    },
  );
  test(
    'failed image import preserves the saved custom theme and preferences',
    () async {
      final provider = Provider(
        (ref) => AgentAppSettingsAdapter(
          ref,
          isCurrent: () => true,
          importImage: (_) async => throw StateError('CORS unavailable'),
        ),
      );
      final c = create();
      final adapter = c.read(provider);
      expect(
        (await adapter.apply({
          'operation': 'appearance',
          'setting': 'customTheme',
          'value': {
            'light': {'accent': '#123456'},
          },
        }))['status'],
        'applied',
      );
      final prefs = await SharedPreferences.getInstance();
      final before = prefs.getString(appThemeSettingsPreferenceKey);
      final custom = c.read(appThemeSettingsProvider).customTheme.toJson();
      final result = await adapter.apply({
        'operation': 'appearance',
        'setting': 'customTheme',
        'value': {
          'light': {'accent': '#654321'},
          'image_url': 'https://example.com/image.png',
          'image_zone': 'main',
          'image_palette': 'light',
        },
      });
      expect(result['status'], 'error');
      expect(prefs.getString(appThemeSettingsPreferenceKey), before);
      expect(c.read(appThemeSettingsProvider).customTheme.toJson(), custom);
    },
  );
  test('removed persisted keys reset snapshot values to defaults', () async {
    final c = create();
    final adapter = c.read(adapterProvider);
    expect(
      (await adapter.apply({
        'operation': 'appearance',
        'setting': 'taskListStyle',
        'value': 'classic',
      }))['status'],
      'applied',
    );
    await (await SharedPreferences.getInstance()).remove(
      taskListStylePreferenceKey,
    );
    expect(
      ((await adapter.snapshot())['values'] as Map)['taskListStyle'],
      'modern',
    );
  });
  test('capabilities omit native macOS options elsewhere', () {
    final web = AgentAppSettingsAdapter.capabilitiesFor(
      TargetPlatform.macOS,
      isWeb: true,
    );
    expect((web['appearance'] as Map).containsKey('zoom'), isFalse);
    final android = AgentAppSettingsAdapter.capabilitiesFor(
      TargetPlatform.android,
      isWeb: false,
    );
    expect(android.toString(), isNot(contains('statusItemStyle')));
    expect(android.toString(), isNot(contains('globalQuickAdd')));
    final mac = AgentAppSettingsAdapter.capabilitiesFor(
      TargetPlatform.macOS,
      isWeb: false,
    );
    expect(mac.toString(), contains('statusItemStyle'));
    expect(mac.toString(), contains('globalQuickAdd'));
  });
}

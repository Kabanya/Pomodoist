import 'package:pomodoist/ui/settings/view_models/global_shortcut_labels.dart';
import 'package:pomodoist/data/services/platform/global_shortcut_codec.dart';
import 'package:drift/native.dart';
import 'package:dbus/dbus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/data/repositories/platform/global_quick_add_repository.dart';
import 'package:pomodoist/data/services/platform/linux_global_shortcuts.dart';
import 'package:pomodoist/config/platform/platform_quick_add.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/data/services/platform/global_quick_add_service.dart';
import 'package:pomodoist/data/repositories/platform/global_quick_add_repository_impl.dart';
import 'package:pomodoist/config/keyboard_shortcuts.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/notifications/notification_scheduler.dart';
import 'package:pomodoist/data/services/audio/focus_sound_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pomodoist/data/services/local/preferences_service.dart';
import 'package:pomodoist/utils/result.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('disposed quick add does not register a late shortcut', () async {
    final calls = <MethodCall>[];
    const channel = MethodChannel(quickAddChannelName);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final container = ProviderContainer(
      overrides: [
        shortcutTargetPlatformProvider.overrideWithValue(TargetPlatform.macOS),
      ],
    );
    final controller = container.read(globalQuickAddRepositoryProvider);
    container.dispose();
    await controller.ready;
    expect(calls, isEmpty);
  });

  test('platform quick add bridge creates a task', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final container = _container(db);
    addTearDown(container.dispose);
    addTearDown(db.close);

    final controller = container.read(globalQuickAddServiceProvider);
    final result = await controller.handleMethodCall(
      const MethodCall(quickAddCreateTaskMethod, 'Новая задача из хоткея'),
    );

    expect(result, isA<String>());
    final task = await container
        .read(taskRepositoryProvider)
        .watchTask(result! as String)
        .first;
    expect(task?.content, 'Новая задача из хоткея');
  });

  test('platform quick add bridge rejects empty input', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final container = _container(db);
    addTearDown(container.dispose);
    addTearDown(db.close);

    final controller = container.read(globalQuickAddServiceProvider);

    expect(
      controller.handleMethodCall(
        const MethodCall(quickAddCreateTaskMethod, '   '),
      ),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'empty_task',
        ),
      ),
    );
  });

  test('platform quick add bridge returns the effective hint', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        notificationSchedulerProvider.overrideWithValue(
          _NoopNotificationScheduler(),
        ),
        quickAddHintTextProvider.overrideWithValue('Plan the next review'),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(db.close);

    final controller = container.read(globalQuickAddServiceProvider);
    final result = await controller.handleMethodCall(
      const MethodCall(quickAddGetHintMethod),
    );

    expect(result, 'Plan the next review');
  });

  test(
    'failed shortcut persistence restores registration and enabled state',
    () async {
      final bindings = <Object?>[];
      final enabledStates = <Object?>[];
      const channel = MethodChannel(quickAddChannelName);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == quickAddGetGlobalShortcutMethod) {
          return {
            'keyCode': 49,
            'keyLabel': 'Space',
            'meta': false,
            'control': false,
            'alt': true,
            'shift': false,
          };
        }
        if (call.method == quickAddSetGlobalShortcutMethod) {
          bindings.add(call.arguments);
        }
        if (call.method == quickAddSetGlobalShortcutEnabledMethod) {
          enabledStates.add(call.arguments);
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final service = GlobalQuickAddService(
        platform: TargetPlatform.macOS,
        createTask: (_) async => '',
        readHint: () async => '',
        showWindow: () async {},
        closeWindow: () async {},
      );
      addTearDown(service.dispose);
      final repository = LocalGlobalQuickAddRepository(
        service,
        _FailedPreferences(),
      );
      addTearDown(repository.dispose);
      await repository.ready;
      await expectLater(repository.setEnabled(false), throwsStateError);
      expect(repository.state.enabled, isTrue);
      expect(enabledStates.last, isTrue);
      await expectLater(
        repository.setShortcut(
          const GlobalQuickAddBinding(keyCode: 13, keyLabel: 'J', alt: true),
        ),
        throwsStateError,
      );
      expect(repository.state.binding.keyLabel, 'Space');
      expect(repository.state.registrationError, isA<StateError>());
      expect((bindings.last as Map)['keyLabel'], 'Space');
    },
  );

  test('global quick add defaults use native desktop labels', () {
    expect(
      GlobalQuickAddBinding.defaultFor(
        isMacOS: true,
      ).labelFor(TargetPlatform.macOS),
      '⌥Space',
    );
    expect(
      GlobalQuickAddBinding.defaultFor(
        isMacOS: false,
      ).labelFor(TargetPlatform.windows),
      'Ctrl+Alt+Space',
    );
    expect(
      GlobalQuickAddBinding.defaultFor(
        isMacOS: false,
      ).labelFor(TargetPlatform.linux),
      'Ctrl+Alt+Space',
    );
    expect(
      GlobalQuickAddBinding.defaultFor(isMacOS: false).portalTrigger,
      'CTRL+ALT+space',
    );
  });

  test(
    'disabling global quick add persists and unregisters the hotkey',
    () async {
      final calls = <MethodCall>[];
      const channel = MethodChannel(quickAddChannelName);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return switch (call.method) {
              quickAddGetGlobalShortcutMethod => {
                'keyCode': 49,
                'keyLabel': 'Space',
                'meta': false,
                'control': false,
                'alt': true,
                'shift': false,
              },
              quickAddSetGlobalShortcutEnabledMethod => null,
              _ => null,
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final db = AppDatabase(NativeDatabase.memory());
      final container = _container(db);
      addTearDown(container.dispose);
      addTearDown(db.close);
      final controller = container.read(globalQuickAddRepositoryProvider);
      await controller.ready;

      await controller.setEnabled(false);

      expect(controller.state.enabled, isFalse);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          globalQuickAddEnabledPreferenceKey,
        ),
        isFalse,
      );
      expect(
        calls.where(
          (call) =>
              call.method == quickAddSetGlobalShortcutEnabledMethod &&
              call.arguments == false,
        ),
        hasLength(1),
      );
    },
  );

  test('changing the global shortcut persists the accepted binding', () async {
    const channel = MethodChannel(quickAddChannelName);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return switch (call.method) {
            quickAddGetGlobalShortcutMethod => {
              'keyCode': 49,
              'keyLabel': 'Space',
              'meta': false,
              'control': false,
              'alt': true,
              'shift': false,
            },
            _ => null,
          };
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final db = AppDatabase(NativeDatabase.memory());
    final container = _container(db);
    addTearDown(container.dispose);
    addTearDown(db.close);
    final controller = container.read(globalQuickAddRepositoryProvider);
    await controller.ready;
    const binding = GlobalQuickAddBinding(
      keyCode: 13,
      keyLabel: 'J',
      control: true,
      alt: true,
    );

    await controller.setShortcut(binding);

    final stored = (await SharedPreferences.getInstance()).getString(
      globalQuickAddBindingPreferenceKey,
    );
    expect(stored, contains('"keyLabel":"J"'));
    expect(stored, contains('"control":true'));
  });

  test('a disabled shortcut is applied only when re-enabled', () async {
    final calls = <MethodCall>[];
    const channel = MethodChannel(quickAddChannelName);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            quickAddGetGlobalShortcutMethod => {
              'keyCode': 49,
              'keyLabel': 'Space',
              'meta': false,
              'control': false,
              'alt': true,
              'shift': false,
            },
            _ => null,
          };
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final db = AppDatabase(NativeDatabase.memory());
    final container = _container(db);
    addTearDown(container.dispose);
    addTearDown(db.close);
    final controller = container.read(globalQuickAddRepositoryProvider);
    await controller.ready;
    await controller.setEnabled(false);
    calls.clear();

    await controller.setShortcut(
      const GlobalQuickAddBinding(
        keyCode: 13,
        keyLabel: 'J',
        control: true,
        alt: true,
      ),
    );

    expect(calls, isEmpty);
    await controller.setEnabled(true);
    expect(calls.map((call) => call.method), [
      quickAddSetGlobalShortcutMethod,
      quickAddSetGlobalShortcutEnabledMethod,
    ]);
  });

  test('registration conflict keeps the previous working binding', () async {
    const channel = MethodChannel(quickAddChannelName);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == quickAddGetGlobalShortcutMethod) {
            return {
              'keyCode': 49,
              'keyLabel': 'Space',
              'meta': false,
              'control': false,
              'alt': true,
              'shift': false,
            };
          }
          if (call.method == quickAddSetGlobalShortcutMethod) {
            throw PlatformException(code: 'shortcut_unavailable');
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final db = AppDatabase(NativeDatabase.memory());
    final container = _container(db);
    addTearDown(container.dispose);
    addTearDown(db.close);
    final controller = container.read(globalQuickAddRepositoryProvider);
    await controller.ready;

    await expectLater(
      controller.setShortcut(
        const GlobalQuickAddBinding(
          keyCode: 13,
          keyLabel: 'J',
          control: true,
          alt: true,
        ),
      ),
      throwsA(isA<PlatformException>()),
    );

    expect(controller.state.binding.keyLabel, 'Space');
    expect(controller.state.registrationError, isA<PlatformException>());
  });

  test(
    'disabled Linux startup removes a stale managed portal binding',
    () async {
      SharedPreferences.setMockInitialValues({
        globalQuickAddEnabledPreferenceKey: false,
      });
      final portal = _FakeLinuxPortal();
      final db = AppDatabase(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          notificationSchedulerProvider.overrideWithValue(
            _NoopNotificationScheduler(),
          ),
          globalQuickAddServiceProvider.overrideWith((ref) {
            final service = GlobalQuickAddService(
              platform: TargetPlatform.linux,
              linuxPortal: portal,
              createTask: (_) async => throw UnimplementedError(),
              readHint: () async => '',
              showWindow: () async {},
              closeWindow: () async {},
            );
            ref.onDispose(service.dispose);
            return service;
          }),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(db.close);

      final controller = container.read(globalQuickAddRepositoryProvider);
      await controller.ready;

      expect(controller.state.enabled, isFalse);
      expect(portal.disableCalls, 1);
    },
  );
}

ProviderContainer _container(AppDatabase db) {
  return ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      focusSoundPlayerProvider.overrideWithValue(_SilentFocusSoundPlayer()),
      notificationSchedulerProvider.overrideWithValue(
        _NoopNotificationScheduler(),
      ),
    ],
  );
}

class _NoopNotificationScheduler extends NotificationScheduler {
  @override
  Future<void> initialize() async {}

  @override
  Future<Set<String>> pendingTaskStartTaskIds() async => const {};

  @override
  Future<void> scheduleTaskStart({
    required String taskId,
    required DateTime startAt,
    required String title,
    required String body,
  }) async {}

  @override
  Future<void> cancelTaskStart(String taskId) async {}
}

class _FakeLinuxPortal extends LinuxGlobalShortcutsPortal {
  _FakeLinuxPortal()
    : super(
        client: DBusClient(
          DBusAddress('unix:path=/tmp/pomodoist-unused-dbus'),
          authClient: DBusAuthClient(uid: '1000'),
        ),
        sandboxed: false,
        manageHyprlandShortcut: false,
      );

  int disableCalls = 0;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<void> disable() async {
    disableCalls++;
  }

  @override
  Future<void> dispose() async {}
}

class _SilentFocusSoundPlayer implements FocusSoundPlayer {
  @override
  Future<void> play(FocusSoundCue cue) async {}
  @override
  Future<void> dispose() async {}
}

class _FailedPreferences extends PreferencesService {
  _FailedPreferences() : super(SharedPreferences.getInstance);
  @override
  Future<Result<void>> write(Map<String, Object?> values) async =>
      Failure(StateError('disk failure'), StackTrace.current);
}

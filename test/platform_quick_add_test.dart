import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/app/linux_global_shortcuts.dart';
import 'package:pomodoist/app/platform_quick_add.dart';
import 'package:pomodoist/app/providers.dart';
import 'package:pomodoist/core/db/app_database.dart';
import 'package:pomodoist/core/notifications/notification_scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('platform quick add bridge creates a task', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final container = _container(db);
    addTearDown(container.dispose);
    addTearDown(db.close);

    final controller = container.read(platformQuickAddControllerProvider);
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

    final controller = container.read(platformQuickAddControllerProvider);

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

    final controller = container.read(platformQuickAddControllerProvider);
    final result = await controller.handleMethodCall(
      const MethodCall(quickAddGetHintMethod),
    );

    expect(result, 'Plan the next review');
  });

  test('global quick add defaults use native desktop labels', () {
    expect(
      GlobalQuickAddBinding.defaultFor(
        TargetPlatform.macOS,
      ).labelFor(TargetPlatform.macOS),
      '⌥Space',
    );
    expect(
      GlobalQuickAddBinding.defaultFor(
        TargetPlatform.windows,
      ).labelFor(TargetPlatform.windows),
      'Ctrl+Alt+Space',
    );
    expect(
      GlobalQuickAddBinding.defaultFor(
        TargetPlatform.linux,
      ).labelFor(TargetPlatform.linux),
      'Ctrl+Alt+Space',
    );
    expect(
      GlobalQuickAddBinding.defaultFor(TargetPlatform.linux).portalTrigger,
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
      final controller = container.read(platformQuickAddControllerProvider);
      await controller.ready;

      await controller.setGlobalQuickAddEnabled(false);

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
    final controller = container.read(platformQuickAddControllerProvider);
    await controller.ready;
    const binding = GlobalQuickAddBinding(
      keyCode: 13,
      keyLabel: 'J',
      control: true,
      alt: true,
    );

    await controller.setGlobalShortcut(binding);

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
    final controller = container.read(platformQuickAddControllerProvider);
    await controller.ready;
    await controller.setGlobalQuickAddEnabled(false);
    calls.clear();

    await controller.setGlobalShortcut(
      const GlobalQuickAddBinding(
        keyCode: 13,
        keyLabel: 'J',
        control: true,
        alt: true,
      ),
    );

    expect(calls, isEmpty);
    await controller.setGlobalQuickAddEnabled(true);
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
    final controller = container.read(platformQuickAddControllerProvider);
    await controller.ready;

    await expectLater(
      controller.setGlobalShortcut(
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
          platformQuickAddControllerProvider.overrideWith((ref) {
            final controller = PlatformQuickAddController(
              ref,
              platform: TargetPlatform.linux,
              linuxPortal: portal,
            );
            controller.initialize();
            ref.onDispose(controller.dispose);
            return controller;
          }),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(db.close);

      final controller = container.read(platformQuickAddControllerProvider);
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
  _FakeLinuxPortal() : super();

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

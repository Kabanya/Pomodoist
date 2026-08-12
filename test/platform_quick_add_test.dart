import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

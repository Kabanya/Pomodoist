import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/platform/platform_quick_add.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/config/update_dependencies.dart';
import 'package:pomodoist/data/repositories/notifications/notification_repository.dart';
import 'package:pomodoist/data/repositories/updates/update_repository.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/notifications/notification_scheduler.dart';
import 'package:pomodoist/domain/models/notifications/notification_copy.dart';
import 'package:pomodoist/domain/models/planning/quick_add_parser.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/routing/router.dart';
import 'package:pomodoist/ui/quick_add/view_models/global_quick_add_view_model.dart';
import 'package:pomodoist/ui/tasks/view_models/quick_add_details_view_model.dart';
import 'package:pomodoist/ui/tasks/view_models/quick_add_view_model.dart';
import 'package:pomodoist/utils/clock.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoopNotificationScheduler extends NotificationScheduler {
  @override
  Future<void> initialize() async {}

  @override
  Future<void> refreshLanguage() async {}

  @override
  Future<Set<String>> pendingTaskStartTaskIds() async => const {};

  @override
  Future<void> requestNotificationPermissions() async {}

  @override
  Future<void> scheduleTaskStart({
    required String taskId,
    required DateTime startAt,
    required String title,
    required String body,
  }) async {}

  @override
  Future<void> cancelTaskStart(String taskId) async {}

  @override
  Future<void> scheduleReengagementReminder({
    required DateTime firstAt,
    required NotificationCopy copy,
  }) async {}

  @override
  Future<void> cancelReengagementReminder() async {}

  @override
  Future<void> scheduleFocusIntervalEnd({
    required DateTime expectedEndAt,
    required String title,
    required String body,
  }) async {}

  @override
  Future<void> cancelFocusNotification() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('main provider scope constructs and tears down with fakes', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        notificationSchedulerProvider.overrideWithValue(
          _NoopNotificationScheduler(),
        ),
        accountBootstrapInitializerProvider.overrideWithValue(() async => null),
      ],
    );

    await container.read(appStartupProvider.future);
    expect(
      container.read(notificationRepositoryProvider),
      isA<NotificationRepository>(),
    );
    expect(container.read(updateRepositoryProvider), isA<UpdateRepository>());
    expect(container.read(taskRepositoryProvider), isNotNull);
    expect(container.read(appDatabaseProvider), same(db));

    container.dispose();
    await db.close();
  });

  test('Quick Add provider scope constructs with fakes', () async {
    final now = DateTime(2026, 9, 20, 9);
    final container = ProviderContainer(
      overrides: [
        projectsProvider.overrideWith(
          (ref) => Stream.value(const <ProjectItem>[]),
        ),
        labelsProvider.overrideWith((ref) => Stream.value(const <LabelItem>[])),
        quickAddParserProvider.overrideWithValue(const QuickAddParser()),
        focusTickerProvider.overrideWith((ref) => Stream.value(now)),
        clockProvider.overrideWithValue(FixedClock(now)),
      ],
    );
    final identity = Object();
    final quickAddListener = container.listen(
      quickAddViewModelProvider(identity),
      (_, _) {},
      fireImmediately: true,
    );
    final detailsListener = container.listen(
      quickAddDetailsViewModelProvider,
      (_, _) {},
      fireImmediately: true,
    );

    expect(container.read(quickAddWindowLanguageProvider), isNotNull);
    expect(container.read(quickAddViewModelProvider(identity)).draft, isEmpty);
    expect(container.read(quickAddDetailsViewModelProvider).projects, isEmpty);
    expect(container.read(globalQuickAddRepositoryProvider), isNotNull);

    quickAddListener.close();
    detailsListener.close();
    container.dispose();
  });

  test('auth redirect decision follows account state changes', () {
    final signedOut = ProviderContainer(
      overrides: [accountSignedInProvider.overrideWithValue(false)],
    );
    addTearDown(signedOut.dispose);
    expect(
      webAppRedirectFor(
        isWeb: true,
        signedIn: signedOut.read(accountSignedInProvider),
        uri: Uri.parse('/today'),
      ),
      '/login?returnTo=%2Ftoday',
    );

    final signedIn = ProviderContainer(
      overrides: [accountSignedInProvider.overrideWithValue(true)],
    );
    addTearDown(signedIn.dispose);
    expect(
      webAppRedirectFor(
        isWeb: true,
        signedIn: signedIn.read(accountSignedInProvider),
        uri: Uri.parse('/today'),
      ),
      isNull,
    );
    expect(
      webAppRedirectFor(
        isWeb: true,
        signedIn: signedIn.read(accountSignedInProvider),
        uri: Uri.parse('/login'),
      ),
      isNull,
    );
  });
}

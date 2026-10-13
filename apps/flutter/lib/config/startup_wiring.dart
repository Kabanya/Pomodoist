import 'package:pomodoist/config/habit_notification_dependencies.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/platform/watch_companion.dart';
import 'package:pomodoist/config/providers.dart';

/// Keeps application-lifetime service subscriptions alive while mounted.
///
/// This is composition, not presentation: the UI only observes whether startup
/// finished, while these source-owning providers stay subscribed for as long as
/// the application scope exists.
final startupBackgroundWiringProvider = Provider<void>((ref) {
  ref.watch(accountSyncLifecycleProvider);
  ref.watch(recurringTaskMaterializationProvider);
  ref.watch(taskStartNotificationCoordinatorProvider);
  ref.watch(habitReminderStatusProvider);
  ref.watch(reengagementNotificationCoordinatorProvider);
  ref.watch(watchCompanionServiceProvider);
  ref.watch(quickAddHintRepositoryProvider);
});

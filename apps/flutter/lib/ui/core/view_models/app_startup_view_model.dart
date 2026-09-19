import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/config/platform/watch_companion.dart';

final appStartupViewModelProvider =
    AsyncNotifierProvider<AppStartupViewModel, void>(AppStartupViewModel.new);

class AppStartupViewModel extends AsyncNotifier<void> {
  @override
  Future<void> build() async {
    await ref.watch(appStartupProvider.future);
    await ref.watch(accountSyncStartupProvider.future);
    ref.watch(accountSyncLifecycleProvider);
    ref.watch(googleCalendarSyncLifecycleProvider);
    ref.watch(recurringTaskMaterializationProvider);
    ref.watch(taskStartNotificationCoordinatorProvider);
    ref.watch(reengagementNotificationCoordinatorProvider);
    ref.watch(watchCompanionControllerProvider);
    ref.watch(quickAddHintControllerProvider);
  }

  void retry() {
    ref.invalidate(appStartupProvider);
    ref.invalidate(accountSyncStartupProvider);
    ref.invalidateSelf();
  }
}

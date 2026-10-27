import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/utils/startup_diagnostics.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/config/startup_wiring.dart';

final appStartupViewModelProvider =
    AsyncNotifierProvider<AppStartupViewModel, void>(AppStartupViewModel.new);

class AppStartupViewModel extends AsyncNotifier<void> {
  @override
  Future<void> build() async {
    await ref.watch(appStartupProvider.future);
    await ref.watch(accountSyncStartupProvider.future);
    ref.watch(startupBackgroundWiringProvider);
    traceStartupStage('interface-ready');
  }

  void retry() {
    if (state.isLoading) return;
    ref.invalidate(appStartupProvider);
    ref.invalidate(accountSyncStartupProvider);
    ref.invalidateSelf();
  }
}

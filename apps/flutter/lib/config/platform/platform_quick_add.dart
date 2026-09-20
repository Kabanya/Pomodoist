import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/keyboard_shortcuts.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/data/repositories/platform/global_quick_add_repository.dart';
import 'package:pomodoist/data/repositories/platform/global_quick_add_repository_impl.dart';
import 'package:pomodoist/data/services/platform/global_quick_add_service.dart';
import 'package:pomodoist/ui/quick_add/widgets/global_quick_add_window.dart';

final globalQuickAddServiceProvider = Provider<GlobalQuickAddService>((ref) {
  final service = GlobalQuickAddService(
    platform: ref.watch(shortcutTargetPlatformProvider),
    createTask: (input) async {
      await ref.read(appStartupProvider.future);
      return (await ref.read(quickAddUseCaseProvider).createTask(input))
          .getOrThrow();
    },
    readHint: () async => ref.read(effectiveQuickAddHintProvider),
    showWindow: globalQuickAddWindowManager.show,
    closeWindow: globalQuickAddWindowManager.close,
  );
  ref.onDispose(service.dispose);
  return service;
});

final globalQuickAddRepositoryProvider = Provider<GlobalQuickAddRepository>((
  ref,
) {
  final repository = LocalGlobalQuickAddRepository(
    ref.watch(globalQuickAddServiceProvider),
    ref.watch(preferencesServiceProvider),
  );
  ref.onDispose(repository.dispose);
  return repository;
});

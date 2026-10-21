import 'package:pomodoist/data/repositories/pomo/pomo_activity_repository_impl.dart';
import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:pomodoist/ui/pomo/view_models/pomo_controller.dart';
import 'package:multiview_desktop/multiview_desktop.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/config/local_completion_dependencies.dart';
import 'package:pomodoist/data/repositories/pomo/pomo_preferences_repository.dart';
import 'package:pomodoist/data/repositories/pomo/pomo_preferences_repository_impl.dart';
import 'package:pomodoist/domain/models/pomo/pomo_focus.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'package:pomodoist/routing/router.dart';
import 'package:pomodoist/ui/pomo/widgets/pomo_window_host.dart';
import 'package:pomodoist/ui/pomo/widgets/pomo_window.dart';
import 'package:pomodoist/ui/quick_add/widgets/global_quick_add_window.dart';

final pomoPreferencesProvider = Provider<PomoPreferencesRepository>((ref) {
  final repository = LocalPomoPreferencesRepository(
    ref.watch(preferencesServiceProvider),
  );
  ref.onDispose(repository.dispose);
  return repository;
});
PomoController _buildPomoController(Ref ref) {
  final preferences = ref.watch(pomoPreferencesProvider);
  late final PomoController controller;
  final host = PomoWindowHost(
    builder: (_, id) => const PomoWindow(),
    settingsBuilder: (_, id) => const PomoWindow(settingsPanel: true),
    onLayout: (scale) => controller.appliedScale(scale),
    savePosition: (position, display) => preferences.update(
      (p) => p.copyWith(x: position.dx, y: position.dy, displayId: display),
    ),
    onError: (error) {
      unawaited(controller.perform(() => Future<void>.error(error)));
    },
  );
  controller = PomoController(preferences, host);
  final subscription = ref
      .watch(localCompletionEventsProvider)
      .stream
      .listen(controller.completed);
  ref.onDispose(() => unawaited(subscription.cancel()));
  return controller;
}

final _pomoIntervalsProvider = StreamProvider<List<FocusIntervalItem>>((ref) {
  return LocalPomoActivityRepository(
    ref.watch(appDatabaseProvider),
  ).watchSinceBreak();
});
PomoFocus _buildPomoFocus(Ref ref) {
  final run = ref.watch(activeFocusRunProvider).value;
  final interval = ref.watch(activeFocusIntervalProvider).value;
  final preset = ref
      .watch(focusPresetsProvider)
      .value
      ?.where((p) => p.id == run?.presetId)
      .firstOrNull;
  final remaining = ref.watch(activeFocusRemainingProvider);
  final history =
      ref.watch(_pomoIntervalsProvider).value ?? const <FocusIntervalItem>[];
  return PomoFocus(
    run: run,
    interval: interval,
    preset: preset,
    remaining: remaining,
    workSinceBreak: pomoWorkSinceBreak(
      history,
      ref.watch(focusTickerProvider).value ?? DateTime.now(),
    ),
  );
}

List<Override> get pomoOverrides => [
  pomoControllerProvider.overrideWith(_buildPomoController),
  pomoFocusProvider.overrideWith(_buildPomoFocus),
  pomoActionsProvider.overrideWith(
    (ref) => (
      toggleFocus: () => pomoToggleFocus(ref),
      completeInterval: () => pomoCompleteInterval(ref),
      quickAdd: pomoQuickAdd,
    ),
  ),
];

/// Mounted once above all Flutter views, inside the shared ProviderScope.
class PomoRuntime extends ConsumerStatefulWidget {
  const PomoRuntime({required this.child, super.key});
  final Widget child;
  @override
  ConsumerState<PomoRuntime> createState() => _PomoRuntimeState();
}

class _PomoRuntimeState extends ConsumerState<PomoRuntime> {
  @override
  void initState() {
    super.initState();
    if (pomoSupported) {
      Future.microtask(() => ref.read(pomoControllerProvider).initialize());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (pomoSupported) {
      ref.listen(
        pomoFocusProvider,
        (_, next) => Future.microtask(() {
          if (mounted) ref.read(pomoControllerProvider).updateFocus(next);
        }),
      );
      // Start stream subscriptions even when the companion is disabled.
      final focus = ref.watch(pomoFocusProvider);
      final controller = ref.read(pomoControllerProvider);
      if (controller.focus.run?.id != focus.run?.id ||
          controller.focus.interval?.id != focus.interval?.id) {
        Future.microtask(() {
          if (mounted) controller.updateFocus(focus);
        });
      }
    }
    return widget.child;
  }
}

Future<void> pomoToggleFocus(Ref ref) async {
  final focus = ref.read(pomoFocusProvider);
  if (!focus.hasRun) {
    await pomoOpenFocus(ref);
    return;
  }
  if (!focus.canToggle) return;
  final repo = ref.read(focusRepositoryProvider);
  (await (focus.ready
          ? repo.startReadyInterval()
          : focus.paused
          ? repo.resumeActiveInterval()
          : repo.pauseActiveInterval()))
      .getOrThrow();
}

Future<void> pomoCompleteInterval(Ref ref) async {
  if (!ref.read(pomoFocusProvider).canComplete) return;
  (await ref.read(focusRepositoryProvider).completeActiveInterval())
      .getOrThrow();
}

Future<void> pomoOpenFocus(Ref ref) async {
  ref.read(routerProvider).go('/focus');
  final id = MultiViewDesktop.getAnchorId();
  if (id != null) {
    final w = MultiViewDesktop.fromId(id);
    await w.show();
    await w.focus();
  }
}

Future<void> pomoQuickAdd() => globalQuickAddWindowManager.show();

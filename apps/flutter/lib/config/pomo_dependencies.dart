import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pomodoist/data/repositories/pomo/pomo_environment_repository_impl.dart';
import 'package:pomodoist/ui/pomo/view_models/pomo_environment_view_model.dart';
import 'package:pomodoist/domain/models/pomo/pomo_models.dart';
import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:pomodoist/ui/pomo/view_models/pomo_controller.dart';
import 'package:multiview_desktop/multiview_desktop.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/config/focus_dependencies.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/config/local_completion_dependencies.dart';
import 'package:pomodoist/data/repositories/pomo/pomo_preferences_repository.dart';
import 'package:pomodoist/data/repositories/pomo/pomo_preferences_repository_impl.dart';
import 'package:pomodoist/domain/models/pomo/pomo_focus.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'package:pomodoist/ui/pomo/view_models/pomo_window_host.dart';
import 'package:pomodoist/ui/pomo/widgets/pomo_window.dart';
import 'package:pomodoist/config/platform/platform_quick_add.dart';

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
  final environment = pomoIsLinux
      ? ref.watch(pomoEnvironmentRepositoryProvider)
      : null;
  final host = PomoWindowHost(
    environment: environment,
    readPreferences: () => preferences.state,
    builder: (_, id) => const PomoWindow(),
    settingsBuilder: (_, id) => const PomoWindow(settingsPanel: true),
    onLayout: (scale) => controller.appliedScale(scale),
    savePosition: (position, display) => preferences.update((p) {
      final monitor = environment?.state.displays
          .where((d) => d.id == display)
          .firstOrNull;
      return p.copyWith(
        x: position.dx,
        y: position.dy,
        displayId: display,
        displayPositions: monitor == null
            ? p.displayPositions
            : {
                ...p.displayPositions,
                display: PomoDisplayPosition(
                  x: position.dx - monitor.workX,
                  y: position.dy - monitor.workY,
                ),
              },
      );
    }),
    onError: (error) {
      unawaited(controller.perform(() => Future<void>.error(error)));
    },
  );
  controller = PomoController(preferences, host, hostAvailable: !pomoIsLinux);
  final placement = preferences.changes.listen((p) {
    unawaited(controller.perform(() => host.updatePlacementPreferences(p)));
  });
  ref.onDispose(() => unawaited(placement.cancel()));
  final subscription = ref
      .watch(localCompletionEventsProvider)
      .stream
      .listen(controller.completed);
  ref.onDispose(() => unawaited(subscription.cancel()));
  return controller;
}

PomoFocus _buildPomoFocus(Ref ref) {
  final run = ref.watch(activeFocusRunProvider).value;
  final interval = ref.watch(activeFocusIntervalProvider).value;
  final preset = ref
      .watch(focusPresetsProvider)
      .value
      ?.where((p) => p.id == run?.presetId)
      .firstOrNull;
  final remaining = ref.watch(activeFocusRemainingProvider);
  return PomoFocus(
    run: run,
    interval: interval,
    preset: preset,
    remaining: remaining,
  );
}

bool get pomoIsLinux =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

List<Override> get pomoOverrides => [
  pomoEnvironmentRepositoryProvider.overrideWith((ref) {
    final repository = LinuxPomoEnvironmentRepository();
    ref.onDispose(repository.dispose);
    return repository;
  }),
  pomoAppVersionProvider.overrideWith((ref) async {
    final info = await PackageInfo.fromPlatform();
    return info.buildNumber.isEmpty
        ? info.version
        : '${info.version} (${info.buildNumber})';
  }),
  pomoControllerProvider.overrideWith(_buildPomoController),
  pomoFocusProvider.overrideWith(_buildPomoFocus),
  pomoActionsProvider.overrideWith(
    (ref) => (
      openApp: pomoOpenApp,
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
      if (pomoIsLinux) {
        final environment = ref.watch(pomoEnvironmentStateProvider).value;
        final controller = ref.read(pomoControllerProvider);
        final available = environment?.available == true;
        if (controller.hostAvailable != available) {
          Future.microtask(() {
            if (mounted) unawaited(controller.setHostAvailable(available));
          });
        }
      }
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
  final repo = ref.read(focusRepositoryProvider);
  final preferences = ref.read(focusPreferencesRepositoryProvider);
  await preferences.ready;
  final (run, interval, presets) = await (
    repo.watchActiveRun().first,
    repo.watchActiveInterval().first,
    repo.watchPresets().first,
  ).wait;
  if (!ref.mounted) return;
  final focus = PomoFocus(
    run: run,
    interval: interval,
    preset: presets.where((p) => p.id == run?.presetId).firstOrNull,
  );
  if (!focus.hasRun) {
    final preset = selectedFocusPresetOrDefault(
      presets,
      preferences.state.lastPresetId,
    );
    (await repo.startRun(
      StartFocusRunInput(presetId: preset?.id),
    )).getOrThrow();
    return;
  }
  if (!focus.canToggle) return;
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

Future<void> pomoOpenApp() async {
  final id = MultiViewDesktop.getAnchorId();
  if (id == null) throw StateError('Main application window is unavailable');
  final window = MultiViewDesktop.fromId(id);
  if (await window.isMinimized()) await window.restore();
  await window.show();
  await window.focus();
}

Future<void> pomoQuickAdd() => globalQuickAddWindowManager.show();

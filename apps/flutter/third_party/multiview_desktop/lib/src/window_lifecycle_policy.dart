import 'dart:async';

import 'package:flutter/widgets.dart';

/// Keeps secondary windows rendering while the implicit window is hidden.
void keepDesktopFramesAlive(bool Function() hasWindows) {
  // Finish hidden notifications before updating both the binding and observers.
  scheduleMicrotask(() {
    final binding = WidgetsBinding.instance;
    if (!hasWindows() || binding.lifecycleState != AppLifecycleState.hidden) {
      return;
    }
    // ignore: invalid_use_of_protected_member
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  });
}

/// Utilities participate in rendering, but cannot replace the main app window.
List<int> appWindowCandidates({
  required Iterable<({int id, int? parentId})> windows,
  required Set<int> utilityIds,
  required Set<int> liveIds,
  int? excludingId,
}) =>
    (windows
        .where(
          (window) =>
              window.parentId == null &&
              window.id != excludingId &&
              !utilityIds.contains(window.id) &&
              liveIds.contains(window.id),
        )
        .map((window) => window.id)
        .toList()
      ..sort());

/// The Linux embedder reports the implicit window's lifecycle for the engine.
/// Secondary GTK windows must also keep Flutter's keyboard focus resumed.
class LinuxWindowLifecycle {
  LinuxWindowLifecycle({
    required this.hasFocusedWindow,
    required this.readState,
    required this.applyState,
  });

  final Future<bool> Function() hasFocusedWindow;
  final AppLifecycleState? Function() readState;
  final void Function(AppLifecycleState) applyState;
  int _revision = 0;
  bool _disposed = false;

  Future<void> synchronize() async {
    final revision = ++_revision;
    bool focused;
    try {
      focused = await hasFocusedWindow();
    } catch (_) {
      return;
    }
    if (_disposed || revision != _revision) return;
    final state = readState();
    if (state == null || state == AppLifecycleState.detached) return;
    final desired = focused
        ? AppLifecycleState.resumed
        : AppLifecycleState.inactive;
    if (state != desired) applyState(desired);
  }

  void dispose() {
    _disposed = true;
    _revision++;
  }
}

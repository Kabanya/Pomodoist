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

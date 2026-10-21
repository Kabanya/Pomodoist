import 'package:flutter/foundation.dart';

import 'app_shell_patch.dart';
import 'app_shell_snapshot.dart';

/// Internal store for the live `AppShellSnapshot`.
///
/// Not exported from the public API. Use `AppShellController` instead.
@internal
class AppShellRegistry extends ChangeNotifier {
  AppShellSnapshot? _snapshot;

  AppShellSnapshot? get snapshot => _snapshot;

  void replace(AppShellSnapshot? next) {
    if (_snapshot == next) return;
    _snapshot = next;
    notifyListeners();
  }

  void patch(AppShellPatch patch) => replace(patch.applyTo(_snapshot));
}

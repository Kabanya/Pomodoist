import 'dart:async';

import 'package:flutter/foundation.dart';

/// One voice session per overlay, with observable activity for shell controls.
class VoiceQuickAddSessionSlot<T extends Object> extends ChangeNotifier
    implements ValueListenable<bool> {
  T? _current;

  T? get current => _current;

  @override
  bool get value => _current != null;

  T open(T session) {
    if (_current != null) return _current!;
    _current = session;
    notifyListeners();
    return session;
  }

  void finish(T session) {
    if (!identical(_current, session)) return;
    _current = null;
    // A host can finish during widget disposal. Notify outside the tree lock,
    // reading the current session if another opener runs before this callback.
    scheduleMicrotask(() {
      if (hasListeners) notifyListeners();
    });
  }
}

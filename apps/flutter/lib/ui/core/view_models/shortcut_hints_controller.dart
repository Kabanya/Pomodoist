import 'dart:async';
import 'package:flutter/foundation.dart';

/// Observes a modifier hold without participating in shortcut dispatch.
final class ShortcutHintsController extends ChangeNotifier {
  Timer? _timer;
  bool _blocked = false;
  bool _primary = false;
  bool _enabled = true;
  bool _focused = true;
  Object? _context;

  void setContext(Object? context, {required bool enabled}) {
    if (_context != context || _enabled != enabled) reset();
    _context = context;
    _enabled = enabled;
  }

  void setFocused(bool focused) {
    if (_focused != focused) reset();
    _focused = focused;
  }

  bool _visible = false;
  bool get visible => _visible;

  void key({
    required bool primary,
    bool primaryDown = false,
    bool ordinaryDown = false,
    bool otherModifier = false,
    bool repeat = false,
  }) {
    _primary = primary;
    if (!primary) {
      reset();
      _blocked = false;
    } else if (!_enabled || !_focused) {
      reset();
    } else if (ordinaryDown || (otherModifier && !_visible)) {
      reset();
    } else if (primaryDown && !repeat && !_blocked && _timer == null) {
      _timer = Timer(const Duration(seconds: 1), () {
        _timer = null;
        _visible = true;
        notifyListeners();
      });
    }
  }

  /// Context, recording and window focus changes require a fresh hold.
  void reset() {
    _timer?.cancel();
    _timer = null;
    _blocked = _primary;
    if (_visible) {
      _visible = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

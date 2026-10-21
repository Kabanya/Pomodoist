import 'dart:async';

/// Serial native layout transactions, coalescing obsolete intermediate requests.
class PomoLayoutUpdates {
  PomoLayoutUpdates(this.apply);
  final Future<void> Function() apply;
  Completer<void>? _pending;
  bool _requested = false;
  bool get running => _pending != null;
  Future<void> get settled => _pending?.future ?? Future.value();
  Future<void> request() {
    _requested = true;
    final existing = _pending;
    if (existing != null) return existing.future;
    final next = _pending = Completer<void>();
    unawaited(_drain(next));
    return next.future;
  }

  Future<void> _drain(Completer<void> next) async {
    try {
      while (_requested) {
        _requested = false;
        await apply();
      }
      _pending = null;
      next.complete();
    } on Object catch (e, stack) {
      _requested = false;
      _pending = null;
      next.completeError(e, stack);
    }
  }
}

// Coordinates `CloseMode.softCascade` by waiting for each secondary window to finish closing.
import 'dart:async';

///
/// Each view ID gets a `Completer` completed with `true` when the window closes
/// or `false` when the user cancels via `ViewsManager.cancelCascadeClose`.
class CascadeCloseService {
  CascadeCloseService();

  // viewId -> completer: true = closed, false = cancelled (preventClose).
  final Map<int, Completer<bool>> _closeCompleters = {};

  void clear() => _closeCompleters.clear();

  /// Completes the cascade for `id` with `false` and clears pending completers.
  void abort(int id) {
    final completer = _closeCompleters[id];
    if (completer == null || completer.isCompleted) return;

    completer.complete(false);
    // Clear remaining completers so their future completion (e.g. user later
    // closes those windows independently) does not re-trigger the cascade.
    _closeCompleters.remove(id);
    for (final c in _closeCompleters.values) {
      if (!c.isCompleted) c.complete(false);
    }
    clear();
  }

  /// Registers `id` as the next window in a cascade close sequence.
  void attachWindow(int id) => _closeCompleters.putIfAbsent(id, () => Completer<bool>());

  /// Signals that `id` finished its soft-close cycle successfully.
  void completeWindow(int id) => _closeCompleters[id]?.complete(true);

  /// Waits until `id` closes or the cascade is aborted; then removes its completer.
  Future<bool> waitWindow(int id) async {
    final res = await _closeCompleters[id]?.future ?? true;
    detachWindow(id);

    return res;
  }

  void detachWindow(int id) => _closeCompleters.remove(id);
}

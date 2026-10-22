import 'pomo_models.dart';

/// Monitor selection independent of native geometry and presentation.
class PomoDisplayPolicy {
  String? currentDisplayId;
  String? _candidate;
  DateTime? _since;
  String? _followRequested;
  String? _manualRequested;

  void placed(String displayId) {
    currentDisplayId = displayId;
    if (_followRequested == displayId) _followRequested = null;
    if (_manualRequested == displayId) _manualRequested = null;
  }

  String? follow(String? displayId, DateTime now, {bool suspended = false}) {
    if (suspended || displayId == null || displayId == currentDisplayId) {
      _followRequested = null;
      _candidate = null;
      _since = null;
      return null;
    }
    if (_candidate != displayId) {
      _candidate = displayId;
      _since = now;
      return null;
    }
    if (now.difference(_since!) < const Duration(milliseconds: 500)) {
      return null;
    }
    _followRequested = displayId;
    return displayId;
  }

  String resolve(
    List<String> available,
    String primary,
    PomoPreferences prefs,
  ) {
    final desired = prefs.displayMode == PomoDisplayMode.pinned
        ? prefs.pinnedDisplayId
        : _manualRequested ?? _followRequested ?? currentDisplayId;
    return available.contains(desired) ? desired! : primary;
  }

  String? dragTarget(String? displayId, PomoPreferences prefs) =>
      prefs.displayMode == PomoDisplayMode.pinned ||
          !prefs.allowCrossDisplayDrag
      ? currentDisplayId
      : displayId ?? currentDisplayId;

  void cancelFollow() {
    _followRequested = null;
    _candidate = null;
    _since = null;
  }

  void request(String displayId) {
    cancelFollow();
    _manualRequested = displayId;
  }

  void clear() {
    currentDisplayId = null;
    _candidate = null;
    _since = null;
    _followRequested = null;
    _manualRequested = null;
  }
}

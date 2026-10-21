/// Interface for listening to screen change events.
abstract mixin class ScreenListener {
  /// Called when a screen event occurs (e.g. display-added, display-removed).
  void onScreenEvent(String eventName) {}
}

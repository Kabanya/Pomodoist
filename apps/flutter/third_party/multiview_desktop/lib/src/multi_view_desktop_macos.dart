import 'package:flutter/foundation.dart';
import 'package:multiview_desktop/src/views_manager.dart';

/// macOS-only window APIs for a [MultiViewDesktop] instance.
///
/// Access via `MultiViewDesktop.of(context).macos` or
/// `MultiViewDesktop.fromId(id).macos`.
///
/// On non-macOS platforms these methods are no-ops / return safe defaults
/// (handled by the native manager).
class MultiViewDesktopMacos {
  /// Creates a macOS facade for [realId]. Prefer [MultiViewDesktop.macos].
  @internal
  MultiViewDesktopMacos(this._realId, this._manager);

  final int _realId;
  final ViewsManager _manager;

  /// Returns whether the window is excluded from Mission Control / Exposé.
  Future<bool> isHideFromCollection() async {
    return await _manager.isHideFromCollection(_realId);
  }

  /// Hides or shows the window in Mission Control and Exposé.
  Future<void> hideFromCollection(bool isHideFromCollection) async {
    await _manager.hideFromCollection(_realId, isHideFromCollection);
  }

  /// Returns whether the window is pinned to all Spaces.
  Future<bool> isVisibleOnAllWorkspaces() async {
    return await _manager.isVisibleOnAllWorkspaces(_realId);
  }

  /// Pins or unpins the window across all Spaces.
  Future<void> setVisibleOnAllWorkspaces(bool visible, {bool visibleOnFullScreen = false}) async {
    await _manager.setVisibleOnAllWorkspaces(_realId, visible, visibleOnFullScreen: visibleOnFullScreen);
  }

  /// Sets the dock icon badge label. Pass `null` or empty to clear.
  Future<void> setBadgeLabel({String? label}) async {
    await _manager.setBadgeLabel(_realId, label);
  }

  /// Returns whether this window is on the currently active Mission Control Space.
  ///
  /// On Windows and Linux always returns `true`.
  Future<bool> isOnActiveSpace() async {
    return await _manager.isOnActiveSpace(_realId);
  }
}

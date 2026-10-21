import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:multiview_desktop/multiview_desktop.dart';

/// `WindowCommunicator` backed by in-memory broadcast `StreamController`s.
/// Uses shifted ids cause has public API to add listeners by id
class WindowCommunicatorImpl implements WindowCommunicator {
  WindowCommunicatorImpl();

  // Per-view streams, keyed by viewId.
  final Map<int, StreamController<dynamic>> _viewControllers = {};

  final Map<int, Map<int, StreamController<dynamic>>> _linkedViewControllers = {};

  // Single broadcast stream shared across all views.
  final StreamController<dynamic> _broadcastController = StreamController<dynamic>.broadcast();

  // -------------------------------------------------------------------------
  // Point-to-point
  // -------------------------------------------------------------------------

  @override
  Stream<dynamic> onDirect(BuildContext context, {int? viewId}) {
    final currentViewId = MultiViewDesktop.getIdByContext(context);
    int listenableId = viewId ?? currentViewId;
    int? parentId = viewId == null || viewId == currentViewId ? null : currentViewId;

    final stream = _getStreamById(listenableId, parentId: parentId);
    return stream;
  }

  Stream<dynamic> _getStreamById(int viewId, {int? parentId}) {
    if (parentId != null) {
      _linkedViewControllers
          .putIfAbsent(parentId, () => {})
          .putIfAbsent(viewId, () => StreamController<dynamic>.broadcast());

      return _linkedViewControllers[parentId]![viewId]!.stream;
    }

    _viewControllers.putIfAbsent(viewId, () => StreamController<dynamic>.broadcast());
    return _viewControllers[viewId]!.stream;
  }

  @override
  void send(int targetViewId, dynamic message) {
    _viewControllers[targetViewId]?.add(message);

    for (final children in _linkedViewControllers.values) {
      for (final entry in children.entries) {
        if (entry.key == targetViewId) {
          entry.value.add(message);
        }
      }
    }
  }

  // -------------------------------------------------------------------------
  // Broadcast
  // -------------------------------------------------------------------------

  @override
  Stream<dynamic> get onBroadcast => _broadcastController.stream;

  @override
  void broadcast(dynamic message) {
    _broadcastController.add(message);
  }

  // -------------------------------------------------------------------------
  // Internal cleanup
  // -------------------------------------------------------------------------

  /// Closes and removes the per-view stream and children for `viewId`.
  ///
  /// Called automatically by the library when a view is removed from the
  /// `ViewCollection`.  Do not call this manually.
  @internal
  Future<void> disposeViewByShiftedId(int viewId) async {
    _viewControllers.remove(viewId)?.close();
    await _disposeLinkedViewByShiftedId(viewId);
  }

  Future<void> _disposeLinkedViewByShiftedId(int parentViewId) async {
    for (final entry in _linkedViewControllers[parentViewId]?.entries ?? <MapEntry<int, StreamController<dynamic>>>[]) {
      await entry.value.close();
    }
    _linkedViewControllers.remove(parentViewId);
  }

  @override
  Future<void> dispose() async {
    for (final view in _viewControllers.keys) {
      await disposeViewByShiftedId(view);
    }
    _viewControllers.clear();
    _linkedViewControllers.clear();
  }
}
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'display.dart';
import 'screen_listener.dart';

export 'display.dart';
export 'screen_listener.dart';

/// Queries connected displays and cursor position via native macOS APIs.
///
/// Coordinates are in Flutter logical space (Y-down, origin at primary top-left).
class ScreenRetriever {
  ScreenRetriever._();

  static final ScreenRetriever instance = ScreenRetriever._();

  static const _methodChannel = MethodChannel('multiview_desktop/screen_retriever');

  static const _eventChannel = EventChannel('multiview_desktop/screen_retriever_event');

  StreamSubscription<dynamic>? _eventSubscription;
  final ObserverList<ScreenListener> _listeners = ObserverList<ScreenListener>();

  bool get hasListeners => _listeners.isNotEmpty;

  void _handleScreenEvent(dynamic event) {
    final type = (event as Map)['type'] as String;
    for (final listener in _listeners) {
      listener.onScreenEvent(type);
    }
  }

  /// Subscribes to display hot-plug events (`display-added`, `display-removed`).
  void addListener(ScreenListener listener) {
    if (!hasListeners) {
      _eventSubscription = _eventChannel.receiveBroadcastStream().listen(_handleScreenEvent);
    }
    _listeners.add(listener);
  }

  void removeListener(ScreenListener listener) {
    _listeners.remove(listener);
    if (!hasListeners) {
      _eventSubscription?.cancel();
      _eventSubscription = null;
    }
  }

  Map<String, dynamic> get _defaultArguments {
    final mediaQueryData = MediaQueryData.fromView(WidgetsBinding.instance.platformDispatcher.views.first);
    return {'devicePixelRatio': mediaQueryData.devicePixelRatio};
  }

  /// Returns the current cursor position in Flutter logical coordinates
  /// (Y-down, origin at top-left of the primary screen).
  Future<Offset> getCursorScreenPoint() async {
    final result = await _methodChannel.invokeMethod<Map>('getCursorScreenPoint', _defaultArguments);
    if (result == null) throw Exception('Unable to get cursor screen point.');
    return Offset((result['dx'] as num).toDouble(), (result['dy'] as num).toDouble());
  }

  /// Returns the primary display (first entry in the system screen list).
  Future<Display> getPrimaryDisplay() async {
    final result = await _methodChannel.invokeMethod<Map>('getPrimaryDisplay', _defaultArguments);
    if (result == null) throw Exception('Unable to get primary display.');
    final res =  Display.fromJson(result.cast<String, dynamic>());

    return res;
  }

  /// Returns every connected display.
  Future<List<Display>> getAllDisplays() async {
    final result = await _methodChannel.invokeMethod<Map>('getAllDisplays', _defaultArguments);
    if (result == null || result['displays'] == null) {
      throw Exception('Unable to get all displays.');
    }
    final displays = (result['displays'] as List)
        .map((item) => Display.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    if (displays.isEmpty) throw Exception('Unable to get all displays.');
    return displays;
  }
}

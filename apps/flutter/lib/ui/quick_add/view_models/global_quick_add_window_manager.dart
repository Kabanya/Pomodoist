import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:multiview_desktop/multiview_desktop.dart';
import 'package:pomodoist/data/repositories/settings/preferences_repository.dart';
import 'package:pomodoist/domain/models/app_flavor.dart';
import 'package:pomodoist/ui/quick_add/widgets/global_quick_add_window.dart';

const globalQuickAddCompactSize = Size(680, 200);
const globalQuickAddCommentSize = Size(680, 340);
const globalQuickAddVoiceSize = Size(720, 720);
const globalQuickAddMinimumSize = Size(420, 200);
const globalQuickAddMaximumSize = Size(900, 800);
const quickAddWindowSizeKey = 'quickAdd.windowSize';

Size globalQuickAddWindowSize({
  Size baseSize = globalQuickAddCompactSize,
  required bool voiceExpanded,
  required bool commentExpanded,
  Size workArea = globalQuickAddMaximumSize,
}) {
  final width = voiceExpanded
      ? math.max(baseSize.width, globalQuickAddVoiceSize.width)
      : baseSize.width;
  final height = math.max(
    baseSize.height,
    voiceExpanded
        ? globalQuickAddVoiceSize.height
        : commentExpanded
        ? globalQuickAddCommentSize.height
        : 0.0,
  );
  final maximum = Size(
    math.min(globalQuickAddMaximumSize.width, workArea.width),
    math.min(globalQuickAddMaximumSize.height, workArea.height),
  );
  return Size(
    width.clamp(
      math.min(globalQuickAddMinimumSize.width, maximum.width),
      maximum.width,
    ),
    height.clamp(
      math.min(globalQuickAddMinimumSize.height, maximum.height),
      maximum.height,
    ),
  );
}

class GlobalQuickAddWindowManager extends WindowObserver {
  GlobalQuickAddWindowManager({required this.preferences});

  final PreferencesRepository preferences;
  int? _viewId;
  Future<int>? _opening;
  bool _voiceExpanded = false;
  bool _commentExpanded = false;
  Size _baseSize = globalQuickAddCompactSize;
  Size get baseSize => _baseSize;
  bool _loadedSize = false;
  Future<void>? _loadingSize;
  Future<void> _savingSize = Future.value();
  Future<void> _resizing = Future.value();

  Future<void> restoreSize() {
    if (_loadedSize) return Future.value();
    return _loadingSize ??= _readSize();
  }

  Future<void> _readSize() async {
    try {
      final values = (await preferences.read([
        quickAddWindowSizeKey,
      ])).getOrThrow();
      if (_loadedSize) return;
      final saved = values[quickAddWindowSizeKey];
      if (saved is! String) return;
      final decoded = jsonDecode(saved);
      if (decoded case {'width': final num width, 'height': final num height}) {
        if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
          return;
        }
        _baseSize = globalQuickAddWindowSize(
          baseSize: Size(width.toDouble(), height.toDouble()),
          voiceExpanded: false,
          commentExpanded: false,
        );
      }
    } catch (error) {
      debugPrint('Could not restore Quick Add window size: $error');
    } finally {
      _loadedSize = true;
    }
  }

  Future<void> rememberSize(Size size) {
    if (!size.width.isFinite || !size.height.isFinite || size.isEmpty) {
      return Future.value();
    }
    _loadedSize = true;
    _baseSize = globalQuickAddWindowSize(
      baseSize: size,
      voiceExpanded: false,
      commentExpanded: false,
    );
    final saved = jsonEncode({
      'width': _baseSize.width,
      'height': _baseSize.height,
    });
    return _savingSize = _savingSize.then((_) async {
      try {
        (await preferences.write({quickAddWindowSizeKey: saved})).getOrThrow();
      } catch (error) {
        debugPrint('Could not save Quick Add window size: $error');
      }
    });
  }

  Future<void> show() async {
    final existingId = _viewId;
    if (existingId != null &&
        MultiViewDesktop.allWindowViewIds.contains(existingId)) {
      final window = MultiViewDesktop.fromId(existingId);
      await window.show();
      await window.focus();
      return;
    }

    final pending = _opening;
    if (pending != null) {
      final id = await pending;
      await MultiViewDesktop.fromId(id).focus();
      return;
    }

    final opening = _open();
    _opening = opening;
    try {
      await opening;
    } finally {
      _opening = null;
    }
  }

  Future<int> _open() async {
    await restoreSize();
    final area = await _workArea();
    final size = globalQuickAddWindowSize(
      baseSize: _baseSize,
      voiceExpanded: false,
      commentExpanded: false,
      workArea: area?.size ?? globalQuickAddMaximumSize,
    );
    _voiceExpanded = false;
    _commentExpanded = false;
    final id = await openWindow(
      (context, id) => GlobalQuickAddWindowApp(
        onClose: () => unawaited(close()),
        onVoiceModeChanged: (active) => unawaited(setVoiceMode(active)),
        onCommentExpandedChanged: (active) =>
            unawaited(setCommentExpanded(active)),
      ),
      options: WindowOptions(
        size: size,
        isUtility: true,
        minimumSize: Size(
          math.min(420, size.width),
          math.min(200, size.height),
        ),
        maximumSize: globalQuickAddMaximumSize,
        title: appFlavor.displayName,
        alwaysOnTop: true,
      ),
    );
    _viewId = id;
    // macOS creates a content size, but getSize/setSize use the whole frame.
    await _resize();
    return id;
  }

  Future<void> close() async {
    final pending = _opening;
    final id = _viewId ?? (pending == null ? null : await pending);
    _viewId = null;
    if (id != null && MultiViewDesktop.allWindowViewIds.contains(id)) {
      await MultiViewDesktop.fromId(id).closeWindow();
    }
  }

  Future<void> setVoiceMode(bool active) async {
    _voiceExpanded = active;
    await _resize();
  }

  Future<void> setCommentExpanded(bool active) async {
    _commentExpanded = active;
    await _resize();
  }

  Future<void> _resize() => _resizing = _resizing.then((_) => _applySize());

  Future<Rect?> _workArea([int? id]) async {
    try {
      if (id != null) {
        final center = (await MultiViewDesktop.fromId(id).getBounds()).center;
        final displays = await ScreenRetriever.instance.getAllDisplays();
        for (final display in displays) {
          final area =
              (display.visiblePosition ?? Offset.zero) &
              (display.visibleSize ?? display.size);
          if (area.contains(center)) return area;
        }
      }
      final display = await ScreenRetriever.instance.getPrimaryDisplay();
      return (display.visiblePosition ?? Offset.zero) &
          (display.visibleSize ?? display.size);
    } catch (error) {
      debugPrint('Could not read Quick Add display area: $error');
      return null;
    }
  }

  Future<void> _applySize() async {
    final id = _viewId;
    if (id == null || !MultiViewDesktop.allWindowViewIds.contains(id)) return;
    try {
      final area = await _workArea(id);
      if (_viewId != id) return;
      final window = MultiViewDesktop.fromId(id);
      final size = globalQuickAddWindowSize(
        baseSize: _baseSize,
        voiceExpanded: _voiceExpanded,
        commentExpanded: _commentExpanded,
        workArea: area?.size ?? globalQuickAddMaximumSize,
      );
      await window.setMinimumSize(
        Size(math.min(420, size.width), math.min(200, size.height)),
      );
      await window.setSize(size);
      if (area != null) {
        final bounds = await window.getBounds();
        await window.setPosition(
          Offset(
            bounds.left.clamp(
              area.left,
              math.max(area.left, area.right - bounds.width),
            ),
            bounds.top.clamp(
              area.top,
              math.max(area.top, area.bottom - bounds.height),
            ),
          ),
        );
      }
    } catch (error) {
      debugPrint('Could not resize Quick Add window: $error');
    }
  }

  @override
  void onWindowEvent(int viewId, String eventName) {
    if (viewId == _viewId && eventName == 'resized') {
      unawaited(_rememberWindowSize(viewId));
    }
  }

  Future<void> _rememberWindowSize(int id) async {
    try {
      final size = await MultiViewDesktop.fromId(id).getSize();
      if (_viewId == id) await rememberSize(size);
    } catch (error) {
      debugPrint('Could not read Quick Add window size: $error');
    }
  }

  @override
  void onWindowClosed(int viewId) {
    if (_viewId == viewId) _viewId = null;
  }
}

import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:multiview_desktop/multiview_desktop.dart';
import 'package:pomodoist/domain/models/pomo/pomo_models.dart';
import '../view_models/pomo_controller.dart';
import 'pomo_geometry.dart';
import 'pomo_layout_updates.dart';

class PomoWindowHost implements PomoHost {
  PomoWindowHost({
    required this.builder,
    required this.settingsBuilder,
    required this.savePosition,
    required this.onError,
    required this.onLayout,
  });
  final Widget Function(BuildContext, int) builder, settingsBuilder;
  final Future<void> Function(Offset, String) savePosition;
  final void Function(Object) onError;
  final void Function(double) onLayout;
  static const _channel = MethodChannel('pomodoist/pomo_window');
  static const panelSize = Size(320, 256);
  int? id, settingsId;
  bool _expanded = false, _panelVisible = false;
  bool _shown = false;
  bool _capsuleVisible = true;
  double _wantedScale = 1;
  PomoLayout layout = PomoLayout(1);
  PomoPreferences? _placement;
  Rect? _appliedBounds;
  Rect? _contextMenu;
  (int, double, bool, bool, double, Rect?)? _configured;
  late final _updates = PomoLayoutUpdates(_applyLayout);
  Future<int>? _openingPanel;
  Timer? _screens, _saveTimer;
  String? _screenSignature;
  MultiViewDesktop? get window =>
      id == null ? null : MultiViewDesktop.fromId(id!);
  MultiViewDesktop? get _panel =>
      settingsId == null ? null : MultiViewDesktop.fromId(settingsId!);

  @override
  Future<void> show(PomoPreferences preferences) async {
    try {
      if (id == null || !MultiViewDesktop.allWindowViewIds.contains(id)) {
        id = await openWindow(
          builder,
          options: WindowOptions(
            size: layout.size,
            backgroundColor: const Color(0x00000000),
            title: 'Pomo',
            titleBarStyle: TitleBarStyle.hidden,
            windowButtonVisibility: false,
            alwaysOnTop: true,
            focusOnShow: false,
            isUtility: true,
          ),
        );
      }
      final w = window!;
      await w.setAsFrameless();
      await w.setHasShadow(false);
      await w.setResizable(false);
      await w.setPreventClose(true);
      _wantedScale = preferences.scale;
      _capsuleVisible = preferences.showTimer;
      _placement = preferences;
      _expanded = false;
      _contextMenu = null;
      await _requestLayout();
      await w.show();
      _shown = true;
      _screens?.cancel();
      _screens = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(_checkScreens()),
      );
    } on Object {
      await hide();
      rethrow;
    }
  }

  Future<void> _requestLayout() => _updates.request();
  Future<void> _applyLayout() async {
    final w = window!;
    final displays = await ScreenRetriever.instance.getAllDisplays();
    if (displays.isEmpty) throw StateError('No desktop display available');
    final initial = _placement;
    _placement = null;
    final geometry = await _bounds();
    final bounds = geometry?.$1;
    final saved = initial == null
        ? bounds?.topLeft
        : initial.x == null
        ? null
        : Offset(initial.x!, initial.y!);
    final petCenter = initial == null && bounds != null
        ? bounds.topLeft + layout.pet.center
        : null;
    var display = displays.where((d) => d.id == initial?.displayId).firstOrNull;
    display ??= displays
        .where(
          (d) =>
              ((d.visiblePosition ?? Offset.zero) & (d.visibleSize ?? d.size))
                  .contains(petCenter ?? saved ?? const Offset(-1e9, -1e9)),
        )
        .firstOrNull;
    display ??= await ScreenRetriever.instance.getPrimaryDisplay();
    final area =
        (display.visiblePosition ?? Offset.zero) &
        (display.visibleSize ?? display.size);
    final next = PomoLayout.fitting(_wantedScale, area.size);
    final position = next.position(
      area,
      saved: petCenter == null ? saved : petCenter - next.pet.center,
    );
    final resize =
        bounds == null ||
        !next.matchesWindowSize(bounds.size, pixelRatio: geometry!.$2);
    if (resize) {
      // Resizable is disabled; avoid stale OS min/max constraints during changes.
      await w.setMinimumSize(Size.zero);
      await w.setMaximumSize(const Size(10000, 10000));
      await w.setSize(next.size);
    }
    final desired = position & next.size;
    final changed =
        _appliedBounds == null ||
        !PomoLayout.matchesWindowBounds(
          desired,
          _appliedBounds!,
          pixelRatio: geometry?.$2 ?? 1,
        );
    // A size change can shift the native frame; restore the pet's center once.
    if (resize ||
        !PomoLayout.matchesWindowBounds(
          desired,
          bounds,
          pixelRatio: geometry.$2,
        )) {
      await _channel.invokeMethod<void>('move', {
        'viewId': w.nativeViewId,
        'x': position.dx,
        'y': position.dy,
        'scale': (display.scaleFactor ?? 1).toDouble(),
      });
    }
    _appliedBounds = desired;
    layout = next;
    final configuration = (
      w.nativeViewId,
      next.scale,
      _expanded,
      _capsuleVisible,
      (display.scaleFactor ?? 1).toDouble(),
      _contextMenu,
    );
    if (_configured != configuration) {
      await _configure();
      _configured = configuration;
    }
    onLayout(next.scale);
    if (changed) {
      _saveTimer?.cancel();
      _saveTimer = Timer(const Duration(milliseconds: 350), () {
        unawaited(
          savePosition(position, display!.id).catchError((Object e) {
            onError(e);
          }),
        );
      });
      if (_panelVisible) await _positionPanel(area, desired);
    }
  }

  Future<void> _configure() => _channel.invokeMethod<void>('configure', {
    'viewId': window!.nativeViewId,
    'regions': [
      for (final r in layout.regions(
        _expanded,
        capsuleVisible: _capsuleVisible,
        contextMenu: _contextMenu,
      ))
        {
          'x': r.left,
          'y': r.top,
          'width': r.width,
          'height': r.height,
          'rounded': r == layout.capsule,
          'rectangle': r == _contextMenu,
        },
    ],
  });
  Future<void> setContextMenuBounds(Rect? bounds) {
    if (_contextMenu == bounds) return Future.value();
    _contextMenu = bounds;
    return window == null || !_shown ? Future.value() : _requestLayout();
  }

  @override
  Future<void> setCapsuleVisible(bool visible) {
    if (_capsuleVisible == visible) return Future.value();
    _capsuleVisible = visible;
    return window == null || !_shown ? Future.value() : _requestLayout();
  }

  Future<void> _checkScreens() async {
    try {
      final displays = await ScreenRetriever.instance.getAllDisplays();
      final signature = displays
          .map(
            (d) =>
                '${d.id}:${d.visiblePosition}:${d.visibleSize}:${d.scaleFactor}',
          )
          .join('|');
      if (_screenSignature != null && _screenSignature != signature) {
        await _requestLayout();
      }
      _screenSignature = signature;
    } on Object catch (e) {
      onError(e);
    }
  }

  Future<void> moved() async {
    if (_updates.running || !_shown) return;
    try {
      final geometry = await _bounds();
      if (geometry == null ||
          (_appliedBounds != null &&
              PomoLayout.matchesWindowBounds(
                _appliedBounds!,
                geometry.$1,
                pixelRatio: geometry.$2,
              ))) {
        return;
      }
      // Also refits when dragging onto a display with a smaller work area/DPI.
      await _requestLayout();
    } on Object catch (e) {
      onError(e);
    }
  }

  Future<(Rect, double)?> _bounds() async {
    if (window == null) return null;
    final data = await _channel.invokeMapMethod<String, num>('bounds', {
      'viewId': window!.nativeViewId,
    });
    if (data == null) throw StateError('Missing native window geometry');
    return (
      Rect.fromLTWH(
        data['x']!.toDouble(),
        data['y']!.toDouble(),
        data['width']!.toDouble(),
        data['height']!.toDouble(),
      ),
      data['scale']!.toDouble(),
    );
  }

  @override
  Future<void> resetPosition() {
    _placement = const PomoPreferences();
    return _requestLayout();
  }

  @override
  Future<void> setMenu(bool expanded) {
    if (_expanded == expanded) return Future.value();
    _expanded = expanded;
    return window == null ? Future.value() : _requestLayout();
  }

  @override
  Future<void> setScale(double scale) {
    if (_wantedScale == scale) return Future.value();
    _wantedScale = scale;
    return window == null ? Future.value() : _requestLayout();
  }

  @override
  Future<void> openSettings() async {
    if (settingsId == null ||
        !MultiViewDesktop.allWindowViewIds.contains(settingsId)) {
      final opening = _openingPanel ??= openWindow(
        settingsBuilder,
        options: const WindowOptions(
          size: panelSize,
          minimumSize: panelSize,
          maximumSize: panelSize,
          title: 'Pomo settings',
          titleBarStyle: TitleBarStyle.hidden,
          windowButtonVisibility: false,
          alwaysOnTop: true,
          focusOnShow: false,
          isUtility: true,
        ),
      );
      try {
        settingsId = await opening;
      } finally {
        _openingPanel = null;
      }
    }
    final panel = _panel!;
    await panel.setResizable(false);
    await panel.setPreventClose(true);
    final bounds = (await _bounds())!.$1;
    final displays = await ScreenRetriever.instance.getAllDisplays();
    final display =
        displays
            .where(
              (d) => ((d.visiblePosition ?? Offset.zero) & d.size).contains(
                bounds.center,
              ),
            )
            .firstOrNull ??
        await ScreenRetriever.instance.getPrimaryDisplay();
    final area =
        (display.visiblePosition ?? Offset.zero) &
        (display.visibleSize ?? display.size);
    await _positionPanel(area, bounds);
    _panelVisible = true;
    await panel.show();
    await panel.focus();
  }

  Future<void> _positionPanel(Rect area, Rect pomo) =>
      _panel!.setPosition(PomoLayout.panelPosition(area, pomo, panelSize));
  @override
  Future<void> closeSettings() async {
    _panelVisible = false;
    final opening = _openingPanel;
    if (opening != null) {
      settingsId = await opening;
    }
    if (_panel != null &&
        MultiViewDesktop.allWindowViewIds.contains(settingsId)) {
      await _panel!.cancelCascadeClose();
      await _panel!.hide();
    }
  }

  @override
  Future<void> hide() async {
    _shown = false;
    _screens?.cancel();
    _screens = null;
    _saveTimer?.cancel();
    await _updates.settled;
    _saveTimer?.cancel();
    _configured = null;
    _contextMenu = null;
    await closeSettings();
    final w = window;
    if (w == null || !MultiViewDesktop.allWindowViewIds.contains(id)) return;
    try {
      await w.cancelCascadeClose();
      await _channel.invokeMethod<void>('detach', {'viewId': w.nativeViewId});
    } finally {
      await w.hide();
    }
  }
}

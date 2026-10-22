import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:multiview_desktop/multiview_desktop.dart';
import 'package:pomodoist/domain/models/pomo/pomo_models.dart';
import 'package:pomodoist/domain/models/pomo/pomo_display_policy.dart';
import 'package:pomodoist/data/repositories/pomo/pomo_environment_repository.dart';
import '../models/pomo_host.dart';
import '../widgets/pomo_geometry.dart';
import '../widgets/pomo_layout_updates.dart';

class PomoWindowHost implements PomoHost {
  PomoWindowHost({
    required this.builder,
    required this.settingsBuilder,
    required this.savePosition,
    required this.onError,
    required this.onLayout,
    this.environment,
    this.readPreferences,
  });
  final PomoEnvironmentRepository? environment;
  final PomoPreferences Function()? readPreferences;
  final _displayPolicy = PomoDisplayPolicy();
  Rect? _displayArea;
  Offset? _dragPosition;
  String? _dragDisplayId;
  Future<void>? _startingDrag, _endingDrag;
  Timer? _dragTimer;
  late final _dragSamples = PomoLayoutUpdates(_sampleDrag);
  bool _pointerOver = false,
      _pointerDown = false,
      _dragging = false,
      _panelTransition = false;
  Timer? _followTimer;
  (PomoDisplayMode, String?, bool)? _placementSettings;
  bool get isLinux => environment != null;
  bool get _isWayland => environment?.state.backend == 'wayland';
  PomoPreferences get _preferences =>
      readPreferences?.call() ?? const PomoPreferences();
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
      if (environment case final repository?) {
        await repository.initialize();
        if (!repository.state.available) {
          throw StateError('Pomo desktop surface is unavailable');
        }
      }
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
            linuxDesktopOverlay: isLinux,
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
      await _syncFollowing();
      _followTimer?.cancel();
      if (isLinux) {
        _followTimer = Timer.periodic(
          const Duration(milliseconds: 100),
          (_) => _followUserDisplay(),
        );
      }
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

  Future<List<Display>> _displays() async {
    final repository = environment;
    if (repository == null) return ScreenRetriever.instance.getAllDisplays();
    return [
      for (final d in repository.state.displays)
        Display(
          id: d.id,
          name: d.name,
          size: Size(d.width, d.height),
          visiblePosition: Offset(d.workX, d.workY),
          visibleSize: Size(d.workWidth, d.workHeight),
          scaleFactor: d.scale,
        ),
    ];
  }

  Future<Display> _primary(List<Display> displays) async => environment == null
      ? ScreenRetriever.instance.getPrimaryDisplay()
      : displays
                .where((d) => d.id == environment!.state.primaryDisplayId)
                .firstOrNull ??
            displays.first;

  Rect _area(Display display) =>
      (display.visiblePosition ?? Offset.zero) &
      (display.visibleSize ?? display.size);

  Future<void> updatePlacementPreferences(PomoPreferences preferences) async {
    if (!isLinux) return;
    final next = (
      preferences.displayMode,
      preferences.pinnedDisplayId,
      preferences.allowCrossDisplayDrag,
    );
    if (_placementSettings == next) return;
    _placementSettings = next;
    await _syncFollowing();
    if (_shown) await _requestLayout();
  }

  Future<void> _syncFollowing() async {
    final repository = environment;
    if (repository == null) return;
    if (_shown && _preferences.displayMode == PomoDisplayMode.followUser) {
      await repository.startFollowing();
    } else {
      await repository.stopFollowing();
    }
  }

  void _followUserDisplay() {
    if (!_shown || _preferences.displayMode != PomoDisplayMode.followUser) {
      return;
    }
    final requested = _displayPolicy.follow(
      environment!.state.userDisplayId,
      DateTime.now(),
      suspended:
          _dragging ||
          _pointerOver ||
          _pointerDown ||
          _expanded ||
          _panelVisible ||
          _panelTransition ||
          _contextMenu != null,
    );
    if (requested != null) {
      unawaited(
        _requestLayout().catchError((Object error) {
          onError(error);
        }),
      );
    }
  }

  void pointerOver(bool value) {
    _pointerOver = value;
    if (value) _displayPolicy.cancelFollow();
  }

  void pointerDown(bool value) {
    _pointerDown = value;
    if (value) _displayPolicy.cancelFollow();
  }

  Future<void> beginDrag() async {
    if (!isLinux || !_shown || _dragging || _endingDrag != null) return;
    _displayPolicy.cancelFollow();
    _dragging = true;
    _dragPosition = _appliedBounds?.topLeft;
    _startingDrag = _beginNativeDrag();
    await _startingDrag;
  }

  Future<void> _beginNativeDrag() async {
    try {
      // Cancelled follow/resize work must settle before capturing the drag origin.
      await _updates.settled;
      if (!_shown || _endingDrag != null) return;
      _dragPosition = _appliedBounds?.topLeft;
      final started = await _channel.invokeMethod<bool>('dragBegin', {
        'viewId': window!.nativeViewId,
        'displayId': _displayPolicy.currentDisplayId,
        'allowCrossDisplayDrag':
            _preferences.displayMode == PomoDisplayMode.followUser &&
            _preferences.allowCrossDisplayDrag,
      });
      if (started != true) {
        throw StateError('Stable pointer tracking unavailable');
      }
      if (!_shown || _endingDrag != null) return;
      // Native GTK frame-clock ticks own movement. Sampling only maintains
      // monitor policy and saved placement, without limiting movement frequency.
      _dragTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
        unawaited(dragTo().catchError((Object error) => onError(error)));
      });
    } on Object {
      _dragging = false;
      _dragPosition = null;
      rethrow;
    }
  }

  Future<void> dragTo() => !_dragging || _endingDrag != null
      ? Future.value()
      : _dragSamples.request();

  Future<void> _sampleDrag() async {
    await _startingDrag;
    if (!_dragging || !_shown || window == null) return;
    final data = await _channel.invokeMapMethod<String, Object?>(
      'dragPosition',
      {'viewId': window!.nativeViewId},
    );
    if (!_dragging || !_shown) return;
    if (data == null) {
      // Output removal can release native tracking without a Flutter pan-end.
      // Leave the sampler before ending: endDrag drains this same queue.
      if (_endingDrag == null) {
        scheduleMicrotask(() {
          if (!_dragging || _endingDrag != null) return;
          _dragPosition = null;
          _dragDisplayId = null;
          unawaited(endDrag().catchError((Object error) => onError(error)));
        });
      }
      return;
    }
    final position = Offset(
      (data['x'] as num).toDouble(),
      (data['y'] as num).toDouble(),
    );
    if (position == _dragPosition) return;
    final point = position + layout.pet.center;
    final pointed = environment!.state.displays
        .where((d) => d.contains(point.dx, point.dy))
        .firstOrNull
        ?.id;
    final target = _displayPolicy.dragTarget(pointed, _preferences);
    if (_isWayland) {
      // Changing a layer-shell output remaps the surface and drops its pointer
      // grab. Keep the source surface alive until release, then perform handoff.
      _dragDisplayId = target;
    } else if (target != null) {
      _displayPolicy.request(target);
    }
    _dragPosition = position;
    await _requestLayout();
  }

  Future<void> endDrag() {
    if (!_dragging) return _endingDrag ?? Future.value();
    return _endingDrag ??= _finishDrag().whenComplete(() => _endingDrag = null);
  }

  Future<void> _finishDrag() async {
    _dragTimer?.cancel();
    _dragTimer = null;
    try {
      await _startingDrag;
      await _dragSamples.request();
      await _updates.settled;
    } finally {
      _dragging = false;
      _startingDrag = null;
      try {
        if (window case final current?) {
          await _channel.invokeMethod<void>('dragEnd', {
            'viewId': current.nativeViewId,
          });
        }
        if (_shown) {
          if (_isWayland && _dragDisplayId != null) {
            _displayPolicy.request(_dragDisplayId!);
          }
          await _requestLayout();
        }
      } finally {
        _dragPosition = null;
        _dragDisplayId = null;
      }
    }
  }

  Future<void> _requestLayout() => _updates.request();
  Future<void> _applyLayout() async {
    final w = window!;
    final displays = await _displays();
    if (displays.isEmpty) throw StateError('No desktop display available');
    final initial = _placement;
    _placement = null;
    final geometry = await _bounds();
    final bounds = geometry?.$1;
    var saved = initial == null
        ? bounds?.topLeft
        : initial.x == null
        ? null
        : Offset(initial.x!, initial.y!);
    var petCenter = initial == null && bounds != null
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
    display ??= await _primary(displays);
    if (isLinux) {
      final prefs = _preferences;
      final selected = _displayPolicy.resolve(
        displays.map((d) => d.id).toList(),
        (await _primary(displays)).id,
        prefs,
      );
      display = displays.firstWhere((d) => d.id == selected);
      if (_dragPosition case final dragging?) {
        saved = dragging;
        petCenter = null;
      } else if (_displayPolicy.currentDisplayId != selected ||
          initial != null) {
        final targetArea = _area(display);
        final remembered = prefs.displayPositions[selected];
        if (remembered != null) {
          saved = targetArea.topLeft + Offset(remembered.x, remembered.y);
        } else if (_displayArea case final previousArea?
            when _appliedBounds != null) {
          final previous = _appliedBounds!;
          double ratio(double offset, double extent) =>
              extent <= 0 ? 0 : (offset / extent).clamp(0, 1);
          final fitting = PomoLayout.fitting(_wantedScale, targetArea.size);
          saved =
              targetArea.topLeft +
              Offset(
                ratio(
                      previous.left - previousArea.left,
                      previousArea.width - previous.width,
                    ) *
                    (targetArea.width - fitting.size.width),
                ratio(
                      previous.top - previousArea.top,
                      previousArea.height - previous.height,
                    ) *
                    (targetArea.height - fitting.size.height),
              );
        } else {
          saved = initial?.displayId == selected && initial?.x != null
              ? Offset(initial!.x!, initial.y!)
              : null;
        }
        petCenter = null;
      }
    }
    final area =
        (display.visiblePosition ?? Offset.zero) &
        (display.visibleSize ?? display.size);
    final next = PomoLayout.fitting(_wantedScale, area.size);
    final position = next.position(
      area,
      saved: petCenter == null ? saved : petCenter - next.pet.center,
    );
    final requested = position & next.size;
    final desired = isLinux ? PomoLayout.gtkBounds(requested, area) : requested;
    final resize =
        bounds == null ||
        !PomoLayout.matchesWindowBounds(
          Offset.zero & desired.size,
          Offset.zero & bounds.size,
          pixelRatio: geometry!.$2,
        );
    if (resize) {
      // Resizable is disabled; avoid stale OS min/max constraints during changes.
      await w.setMinimumSize(Size.zero);
      await w.setMaximumSize(const Size(10000, 10000));
      await w.setSize(desired.size);
    }
    if (isLinux &&
        display.id !=
            _displayPolicy.resolve(
              displays.map((d) => d.id).toList(),
              (await _primary(displays)).id,
              _preferences,
            )) {
      unawaited(_requestLayout());
      return;
    }
    final changed =
        _appliedBounds == null ||
        !PomoLayout.matchesWindowBounds(
          desired,
          _appliedBounds!,
          pixelRatio: geometry?.$2 ?? 1,
        );
    // A size change can shift the native frame; restore the pet's center once.
    if (!_dragging &&
        (resize ||
            !PomoLayout.matchesWindowBounds(
              desired,
              bounds,
              pixelRatio: geometry.$2,
            ))) {
      await _channel.invokeMethod<void>('move', {
        'viewId': w.nativeViewId,
        'x': desired.left,
        'y': desired.top,
        'scale': (display.scaleFactor ?? 1).toDouble(),
        if (isLinux) 'displayId': display.id,
      });
    }
    _appliedBounds = desired;
    if (isLinux) {
      _displayPolicy.placed(display.id);
      _displayArea = area;
    }
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
          savePosition(desired.topLeft, display!.id).catchError((Object e) {
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
    if (bounds != null) _displayPolicy.cancelFollow();
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
      final displays = await _displays();
      final signature = displays
          .map(
            (d) =>
                '${d.id}:${d.visiblePosition}:${d.visibleSize}:${d.scaleFactor}',
          )
          .join('|');
      if (_screenSignature != signature) {
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
    final data = await _channel.invokeMapMethod<String, Object?>('bounds', {
      'viewId': window!.nativeViewId,
    });
    if (data == null) throw StateError('Missing native window geometry');
    return (
      Rect.fromLTWH(
        (data['x'] as num).toDouble(),
        (data['y'] as num).toDouble(),
        (data['width'] as num).toDouble(),
        (data['height'] as num).toDouble(),
      ),
      (data['scale'] as num).toDouble(),
    );
  }

  @override
  Future<void> resetPosition() {
    _placement = _preferences.copyWith(resetPosition: true);
    _displayArea = null;
    _appliedBounds = null;
    return _requestLayout();
  }

  @override
  Future<void> setMenu(bool expanded) {
    if (_expanded == expanded) return Future.value();
    _expanded = expanded;
    if (expanded) _displayPolicy.cancelFollow();
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
    _panelTransition = true;
    _displayPolicy.cancelFollow();
    try {
      if (settingsId == null ||
          !MultiViewDesktop.allWindowViewIds.contains(settingsId)) {
        final opening = _openingPanel ??= openWindow(
          settingsBuilder,
          options: WindowOptions(
            linuxDesktopOverlay: isLinux,
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
      final displays = await _displays();
      final display =
          displays
              .where(
                (d) => ((d.visiblePosition ?? Offset.zero) & d.size).contains(
                  bounds.center,
                ),
              )
              .firstOrNull ??
          await _primary(displays);
      final area =
          (display.visiblePosition ?? Offset.zero) &
          (display.visibleSize ?? display.size);
      await _positionPanel(area, bounds);
      _panelVisible = true;
      await panel.show();
      await panel.focus();
    } finally {
      _panelTransition = false;
    }
  }

  Future<void> _positionPanel(Rect area, Rect pomo) async {
    final position = PomoLayout.panelPosition(area, pomo, panelSize);
    if (isLinux) {
      await _channel.invokeMethod<void>('move', {
        'viewId': _panel!.nativeViewId,
        'x': position.dx,
        'y': position.dy,
        'scale': 1.0,
        'displayId': _displayPolicy.currentDisplayId,
      });
    } else {
      await _panel!.setPosition(position);
    }
  }

  @override
  Future<void> closeSettings() async {
    _panelTransition = true;
    _displayPolicy.cancelFollow();
    try {
      final opening = _openingPanel;
      if (opening != null) {
        settingsId = await opening;
      }
      if (_panel != null &&
          MultiViewDesktop.allWindowViewIds.contains(settingsId)) {
        await _panel!.cancelCascadeClose();
        await _panel!.hide();
      }
    } finally {
      _panelVisible = false;
      _panelTransition = false;
    }
  }

  @override
  Future<void> hide() async {
    _shown = false;
    _followTimer?.cancel();
    _followTimer = null;
    _pointerOver = _pointerDown = false;
    try {
      await endDrag();
    } on Object catch (error) {
      onError(error);
    }
    if (environment case final repository?) {
      try {
        await repository.stopFollowing();
      } on Object catch (error) {
        onError(error);
      }
    }
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

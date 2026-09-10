import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../../../app/app_l10n.dart';
import '../../../../app/theme/app_motion.dart';

/// Shared displacement and one-action-per-gesture tracking for touch/trackpads.
@visibleForTesting
class VoicePanelSwipe {
  Offset _distance = Offset.zero;
  bool _expanded = false;
  bool _cancelled = true;
  Duration? _lastScroll;

  void begin({required bool expanded}) {
    _distance = Offset.zero;
    _expanded = expanded;
    _cancelled = false;
    _lastScroll = null;
  }

  void cancel() => _cancelled = true;

  void add(Offset delta) {
    if (_cancelled) return;
    _distance += delta;
    final towardTarget = _expanded ? _distance.dy : -_distance.dy;
    if ((_distance.dx.abs() > kTouchSlop &&
            _distance.dx.abs() > _distance.dy.abs()) ||
        towardTarget < -kTouchSlop) {
      cancel();
    }
  }

  void scroll(Offset delta, Duration timeStamp, {required bool expanded}) {
    // Wheel events have no gesture-end event, including browser trackpads.
    if (_lastScroll == null ||
        timeStamp - _lastScroll! > const Duration(milliseconds: 200)) {
      begin(expanded: expanded);
    }
    _lastScroll = timeStamp;
    add(-delta); // Scroll offsets have the opposite sign to content motion.
  }

  bool? takeAction() {
    final towardTarget = _expanded ? _distance.dy : -_distance.dy;
    if (_cancelled || towardTarget < 48) return null;
    cancel();
    return !_expanded;
  }
}

/// Only explicit panel chrome accepts collapse/expand gestures.
/// Keep scrollable content outside this area, including when it reaches an edge.
class VoicePanelSwipeArea extends StatelessWidget {
  const VoicePanelSwipeArea({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      context.findAncestorStateOfType<_VoicePanelMotionState>()?._swipeSurface(
        child,
      ) ??
      child;
}

/// A retained voice editor that folds into a draggable, corner-snapping capsule.
class VoicePanelMotion extends StatefulWidget {
  const VoicePanelMotion({
    super.key,
    required this.expanded,
    required this.panel,
    required this.indicator,
    required this.stopButton,
    required this.expandButton,
    required this.onCollapse,
    required this.onExpand,
    this.reservedInsets = EdgeInsets.zero,
  });

  final bool expanded;
  final Widget panel;
  final Widget indicator;
  final Widget stopButton;
  final Widget expandButton;
  final VoidCallback onCollapse;
  final VoidCallback onExpand;
  final EdgeInsets reservedInsets;

  @override
  State<VoicePanelMotion> createState() => _VoicePanelMotionState();
}

class _VoicePanelMotionState extends State<VoicePanelMotion> {
  static const _capsule = Size(168, 64);
  static const _duration = AppMotion.panel;
  final _panelFocus = FocusNode();
  final _dragFocus = FocusNode();
  final _swipe = VoicePanelSwipe();
  final _touchPointers = <int>{};
  final _dragPointers = <int>{};
  int? _panZoomPointer;
  Alignment _corner = Alignment.bottomRight;
  Rect _bounds = Rect.zero;
  Rect? _displayed;
  Offset? _dragPosition;
  double _panelHeight = 64;

  @override
  void didUpdateWidget(VoicePanelMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expanded != oldWidget.expanded) {
      _dragPosition = null;
      _swipe.cancel();
    }
    if (widget.expanded && !oldWidget.expanded) _panelFocus.requestFocus();
  }

  @override
  void dispose() {
    _panelFocus.dispose();
    _dragFocus.dispose();
    super.dispose();
  }

  Offset _clamp(Offset position) => Offset(
    position.dx.clamp(
      _bounds.left,
      math.max(_bounds.left, _bounds.right - 168),
    ),
    position.dy.clamp(_bounds.top, math.max(_bounds.top, _bounds.bottom - 64)),
  );

  void _startDrag(DragStartDetails details) {
    _swipe.cancel();
    _dragFocus.requestFocus();
    setState(() => _dragPosition = _displayed!.topLeft);
  }

  void _updateDrag(DragUpdateDetails details) {
    setState(() => _dragPosition = _clamp(_dragPosition! + details.delta));
  }

  void _endDrag([DragEndDetails? details]) {
    final position = _dragPosition;
    if (position == null) return;
    final projected =
        position +
        const Offset(84, 32) +
        (details?.velocity.pixelsPerSecond ?? Offset.zero) * .18;
    setState(() {
      _corner = Alignment(
        projected.dx < _bounds.center.dx ? -1 : 1,
        projected.dy < _bounds.center.dy ? -1 : 1,
      );
      _dragPosition = null;
    });
  }

  void _beginSwipe() {
    _swipe.begin(expanded: widget.expanded);
  }

  void _applySwipe() {
    final expanded = _swipe.takeAction();
    if (expanded == true) widget.onExpand();
    if (expanded == false) widget.onCollapse();
  }

  void _pointerDown(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.mouse) return;
    _touchPointers.add(event.pointer);
    if (_touchPointers.length == 1 && _panZoomPointer == null) {
      _beginSwipe();
    } else {
      _swipe.cancel();
    }
  }

  void _pointerEnd(PointerEvent event) {
    _touchPointers.remove(event.pointer);
    _dragPointers.remove(event.pointer);
    if (_touchPointers.isEmpty) _swipe.cancel();
  }

  void _pointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        _touchPointers.isNotEmpty ||
        _panZoomPointer != null ||
        _dragPosition != null) {
      return;
    }
    _swipe.scroll(
      event.scrollDelta,
      event.timeStamp,
      expanded: widget.expanded,
    );
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed ||
        keys.isMetaPressed ||
        keys.isAltPressed ||
        keys.isShiftPressed) {
      _swipe.cancel();
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
      _applySwipe();
      if (event.scrollDelta.dy.abs() > event.scrollDelta.dx.abs()) {
        resolved.respond(allowPlatformDefault: false);
      }
    });
  }

  Widget _swipeSurface(Widget child) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: _pointerDown,
    onPointerMove: (event) {
      if (!_touchPointers.contains(event.pointer) ||
          _dragPointers.contains(event.pointer)) {
        return;
      }
      _swipe.add(event.localDelta);
      _applySwipe();
    },
    onPointerUp: _pointerEnd,
    onPointerCancel: _pointerEnd,
    onPointerPanZoomStart: (event) {
      _panZoomPointer = event.pointer;
      _beginSwipe();
      if (_touchPointers.isNotEmpty) _swipe.cancel();
    },
    onPointerPanZoomUpdate: (event) {
      if (event.scale != 1 || event.rotation != 0) _swipe.cancel();
      _swipe.add(event.localPanDelta);
      _applySwipe();
    },
    onPointerPanZoomEnd: (_) {
      _panZoomPointer = null;
      _swipe.cancel();
    },
    onPointerSignal: _pointerSignal,
    child: child,
  );

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape && widget.expanded) {
      widget.onCollapse();
      return KeyEventResult.handled;
    }
    if (widget.expanded || !_dragFocus.hasFocus) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) {
      widget.onExpand();
      return KeyEventResult.handled;
    }
    final corner = switch (key) {
      LogicalKeyboardKey.arrowLeft => Alignment(-1, _corner.y),
      LogicalKeyboardKey.arrowRight => Alignment(1, _corner.y),
      LogicalKeyboardKey.arrowUp => Alignment(_corner.x, -1),
      LogicalKeyboardKey.arrowDown => Alignment(_corner.x, 1),
      _ => null,
    };
    if (corner == null) return KeyEventResult.ignored;
    setState(() {
      _corner = corner;
      _dragPosition = null;
    });
    return KeyEventResult.handled;
  }

  Widget _handle({Key? key, Widget? child}) => MouseRegion(
    cursor: _dragPosition == null
        ? SystemMouseCursors.grab
        : SystemMouseCursors.grabbing,
    child: Listener(
      onPointerDown: (event) => _dragPointers.add(event.pointer),
      onPointerUp: (event) => _dragPointers.remove(event.pointer),
      onPointerCancel: (event) => _dragPointers.remove(event.pointer),
      child: GestureDetector(
        key: key,
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        supportedDevices: const {
          PointerDeviceKind.mouse,
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
          PointerDeviceKind.invertedStylus,
        },
        onTap: _dragFocus.requestFocus,
        onPanStart: _startDrag,
        onPanUpdate: _updateDrag,
        onPanEnd: _endDrag,
        onPanCancel: _endDrag,
        child: child,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final colors = Theme.of(context).colorScheme;
    final duration = media.disableAnimations ? Duration.zero : _duration;
    final padding = EdgeInsets.fromLTRB(
      math.max(
            math.max(media.viewPadding.left, media.viewInsets.left),
            widget.reservedInsets.left,
          ) +
          16,
      math.max(
            math.max(media.viewPadding.top, media.viewInsets.top),
            widget.reservedInsets.top,
          ) +
          16,
      math.max(
            math.max(media.viewPadding.right, media.viewInsets.right),
            widget.reservedInsets.right,
          ) +
          16,
      math.max(
            math.max(media.viewPadding.bottom, media.viewInsets.bottom),
            widget.reservedInsets.bottom,
          ) +
          16,
    );
    return Focus(
      focusNode: _panelFocus,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _bounds = Rect.fromLTRB(
            padding.left,
            padding.top,
            math.max(padding.left, constraints.maxWidth - padding.right),
            math.max(padding.top, constraints.maxHeight - padding.bottom),
          );
          final panelWidth = math.min(640.0, _bounds.width);
          final panelHeight = math.min(_panelHeight, _bounds.height);
          final compactPosition = _clamp(
            _dragPosition ??
                Offset(
                  _corner.x < 0 ? _bounds.left : _bounds.right - _capsule.width,
                  _corner.y < 0
                      ? _bounds.top
                      : _bounds.bottom - _capsule.height,
                ),
          );
          final target = widget.expanded
              ? Rect.fromLTWH(
                  _bounds.center.dx - panelWidth / 2,
                  _bounds.bottom - panelHeight,
                  panelWidth,
                  panelHeight,
                )
              : compactPosition & _capsule;
          return Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !widget.expanded,
                  child: AnimatedOpacity(
                    opacity: widget.expanded ? 1 : 0,
                    duration: duration,
                    child: ModalBarrier(
                      key: const Key('voice-panel-barrier'),
                      color: Colors.black54,
                      onDismiss: widget.onCollapse,
                      semanticsLabel: context.l10n.voiceCollapse,
                    ),
                  ),
                ),
              ),
              TweenAnimationBuilder<Rect?>(
                tween: RectTween(end: target),
                duration: _dragPosition == null ? duration : Duration.zero,
                curve: Curves.easeOutCubic,
                builder: (context, animatedRect, _) {
                  final width = math.min(animatedRect!.width, _bounds.width);
                  final height = math.min(animatedRect.height, _bounds.height);
                  final rect = Rect.fromLTWH(
                    animatedRect.left.clamp(
                      _bounds.left,
                      _bounds.right - width,
                    ),
                    animatedRect.top.clamp(
                      _bounds.top,
                      _bounds.bottom - height,
                    ),
                    width,
                    height,
                  );
                  _displayed = rect;
                  return Positioned.fromRect(
                    rect: rect,
                    child: Material(
                      color: colors.surface,
                      elevation: 3,
                      shadowColor: colors.shadow.withValues(alpha: .22),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: colors.outlineVariant),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Offstage(
                            offstage: !widget.expanded && rect == target,
                            child: IgnorePointer(
                              ignoring: !widget.expanded,
                              child: ExcludeFocus(
                                excluding: !widget.expanded,
                                child: ExcludeSemantics(
                                  excluding: !widget.expanded,
                                  child: AnimatedOpacity(
                                    opacity: widget.expanded ? 1 : 0,
                                    duration: duration,
                                    child: TickerMode(
                                      enabled: widget.expanded,
                                      child: OverflowBox(
                                        alignment: Alignment.topLeft,
                                        minWidth: panelWidth,
                                        maxWidth: panelWidth,
                                        minHeight: 0,
                                        maxHeight: _bounds.height,
                                        child: _MeasurePanel(
                                          onSize: (size) {
                                            if (mounted &&
                                                _panelHeight != size.height) {
                                              setState(
                                                () =>
                                                    _panelHeight = size.height,
                                              );
                                            }
                                          },
                                          child: widget.panel,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Offstage(
                            offstage: widget.expanded && rect == target,
                            child: IgnorePointer(
                              ignoring: widget.expanded,
                              child: VoicePanelSwipeArea(
                                child: ExcludeFocus(
                                  excluding: widget.expanded,
                                  child: ExcludeSemantics(
                                    excluding: widget.expanded,
                                    child: AnimatedOpacity(
                                      opacity: widget.expanded ? 0 : 1,
                                      duration: duration,
                                      child: OverflowBox(
                                        alignment: Alignment.topLeft,
                                        minWidth: 168,
                                        maxWidth: 168,
                                        minHeight: 64,
                                        maxHeight: 64,
                                        child: Stack(
                                          key: const Key('voice-mini-panel'),
                                          children: [
                                            Padding(
                                              padding: const EdgeInsets.all(8),
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Focus(
                                                    focusNode: _dragFocus,
                                                    onFocusChange: (_) =>
                                                        setState(() {}),
                                                    child: Semantics(
                                                      label: context
                                                          .l10n
                                                          .voiceMovePanel,
                                                      button: true,
                                                      onTap: widget.onExpand,
                                                      child: _handle(
                                                        key: const Key(
                                                          'voice-drag-handle',
                                                        ),
                                                        child: SizedBox.square(
                                                          dimension: 48,
                                                          child: DecoratedBox(
                                                            decoration: BoxDecoration(
                                                              shape: BoxShape
                                                                  .circle,
                                                              border:
                                                                  _dragFocus
                                                                      .hasFocus
                                                                  ? Border.all(
                                                                      color: colors
                                                                          .primary,
                                                                      width: 2,
                                                                    )
                                                                  : null,
                                                            ),
                                                            child: widget
                                                                .indicator,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  SizedBox.square(
                                                    dimension: 48,
                                                    child: widget.stopButton,
                                                  ),
                                                  SizedBox.square(
                                                    dimension: 48,
                                                    child: widget.expandButton,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MeasurePanel extends SingleChildRenderObjectWidget {
  const _MeasurePanel({required this.onSize, required super.child});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) => _PanelSize(onSize);

  @override
  void updateRenderObject(BuildContext context, _PanelSize renderObject) {
    renderObject.onSize = onSize;
  }
}

class _PanelSize extends RenderProxyBox {
  _PanelSize(this.onSize);

  ValueChanged<Size> onSize;
  Size? _lastSize;

  @override
  void performLayout() {
    super.performLayout();
    if (_lastSize == size) return;
    _lastSize = size;
    final measured = size;
    WidgetsBinding.instance.addPostFrameCallback((_) => onSize(measured));
  }
}

import 'package:pomodoist/ui/core/widgets/shortcut_hints.dart';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pomodoist/ui/core/widgets/app_action_menu.dart';
import 'package:pomodoist/ui/tasks/widgets/voice_panel_clearance.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show ShadAnchorAuto, ShadContextMenu, ShadContextMenuController;

/// Shad menus expect overlay coordinates, which differ from screen coordinates
/// when the entire interface is zoomed. Keep that conversion at the trigger.
class AppContextMenuRegion extends StatefulWidget {
  const AppContextMenuRegion({
    required this.items,
    required this.child,
    this.controller,
    this.enableLongPress = true,
    super.key,
  });

  final List<Widget> items;
  final Widget child;
  final ShadContextMenuController? controller;
  final bool enableLongPress;

  @override
  State<AppContextMenuRegion> createState() => _AppContextMenuRegionState();
}

class _AppContextMenuRegionState extends State<AppContextMenuRegion> {
  ShadContextMenuController? _ownedController;
  ShadContextMenuController get _controller =>
      widget.controller ?? (_ownedController ??= ShadContextMenuController());
  Offset? _position;
  ({ShadAnchorAuto anchor, double maxHeight})? _placement;
  bool _restoreBrowserMenu = false;
  bool _menuOpen = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updatePlacement);
  }

  @override
  void didUpdateWidget(covariant AppContextMenuRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      (oldWidget.controller ?? _ownedController)?.removeListener(
        _updatePlacement,
      );
      _controller.addListener(_updatePlacement);
    }
  }

  void _show(Offset globalPosition) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    _position = overlay.globalToLocal(globalPosition);
    _controller.show();
    _updatePlacement();
  }

  void _updatePlacement() {
    if (!mounted) return;
    if (_menuOpen != _controller.isOpen) {
      setState(() => _menuOpen = _controller.isOpen);
    }
    if (!_controller.isOpen) {
      _position = null;
      return;
    }
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final box = context.findRenderObject() as RenderBox;
    final media = MediaQuery.of(context);
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    final bottomInset = math.max(
      math.max(media.padding.bottom, media.viewInsets.bottom),
      voicePanelBottomClearanceOf(context).value,
    );
    final viewport = Rect.fromLTRB(
      media.padding.left,
      media.padding.top,
      overlay.size.width - media.padding.right,
      math.max(media.padding.top, overlay.size.height - bottomInset),
    );
    final placement = _position == null
        ? actionMenuPlacement(origin & box.size, viewport)
        : contextMenuPlacement(_position!, origin, viewport);
    if (_placement != placement) setState(() => _placement = placement);
  }

  @override
  void dispose() {
    _controller.removeListener(_updatePlacement);
    _ownedController?.dispose();
    if (_restoreBrowserMenu) BrowserContextMenu.enableContextMenu();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    MediaQuery.of(context);
    if (_controller.isOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _updatePlacement());
    }
    return ShortcutHintsScope(
      modal: _menuOpen,
      enabled: false,
      hints: const [],
      child: ShadContextMenu(
        controller: _controller,
        anchor: _placement?.anchor,
        items: scrollableActionMenuItems(
          context,
          widget.items,
          maxHeight: _placement?.maxHeight,
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _controller.hide(),
          onSecondaryTapDown: (details) async {
            if (kIsWeb && BrowserContextMenu.enabled) {
              _restoreBrowserMenu = true;
              await BrowserContextMenu.disableContextMenu();
            }
            if (mounted && defaultTargetPlatform != TargetPlatform.windows) {
              _show(details.globalPosition);
            }
          },
          onSecondaryTapUp: (details) {
            if (defaultTargetPlatform == TargetPlatform.windows) {
              _show(details.globalPosition);
            }
            if (_restoreBrowserMenu) {
              _restoreBrowserMenu = false;
              BrowserContextMenu.enableContextMenu();
            }
          },
          onLongPressStart: widget.enableLongPress
              ? (details) => _show(details.globalPosition)
              : null,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Position pointer menus in overlay coordinates, using the roomier side.
({ShadAnchorAuto anchor, double maxHeight}) contextMenuPlacement(
  Offset position,
  Offset origin,
  Rect viewport,
) {
  final click = Offset(
    position.dx.clamp(viewport.left, viewport.right),
    position.dy.clamp(viewport.top, viewport.bottom),
  );
  final placement = actionMenuPlacement(click & Size.zero, viewport);
  return (
    anchor: ShadAnchorAuto(
      targetAnchor: Alignment.topLeft,
      followerAnchor: placement.anchor.followerAnchor,
      offset: click - origin + placement.anchor.offset,
    ),
    maxHeight: placement.maxHeight,
  );
}

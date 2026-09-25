import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pomodoist/ui/core/widgets/app_action_menu.dart';
import 'package:pomodoist/ui/tasks/widgets/voice_panel_clearance.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show ShadContextMenu, ShadContextMenuController, ShadGlobalAnchor;

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
  double? _menuMaxHeight;
  bool _restoreBrowserMenu = false;

  void _show(Offset globalPosition) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    // The shell's bottom chrome covers the lower part of the overlay, so the
    // menu must fit entirely above it. Cap its height, and when the click sits
    // too low for that cap, lift the anchor by the difference so the last row
    // still lands above the chrome instead of being clipped behind it.
    final media = MediaQuery.of(context);
    final click = overlay.globalToLocal(globalPosition);
    final limit = math.min(
      overlay.size.height - media.padding.bottom,
      overlay.size.height -
          media.padding.bottom -
          voicePanelBottomClearanceOf(context).value,
    );
    const gap = 8.0;
    // Anchor the menu's last row just above the click so every row stays within
    // the visible area, even when only the capped part of a long menu fits.
    final maxHeight = math.min(
      math.max(44.0, limit - click.dy - gap),
      math.max(44.0, limit - media.padding.top - gap),
    );
    setState(() {
      _menuMaxHeight = maxHeight;
      _position = Offset(
        click.dx,
        math.max(media.padding.top + gap, limit - maxHeight - gap),
      );
    });
    _controller.show();
  }

  @override
  void dispose() {
    _ownedController?.dispose();
    if (_restoreBrowserMenu) BrowserContextMenu.enableContextMenu();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ShadContextMenu(
    controller: _controller,
    anchor: _position == null ? null : ShadGlobalAnchor(_position!),
    items: scrollableActionMenuItems(
      context,
      widget.items,
      maxHeight: _menuMaxHeight,
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
  );
}

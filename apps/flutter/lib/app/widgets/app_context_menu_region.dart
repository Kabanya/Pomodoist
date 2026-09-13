import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show ShadContextMenu, ShadContextMenuController, ShadGlobalAnchor;

/// Shad menus expect overlay coordinates, which differ from screen coordinates
/// when the entire interface is zoomed. Keep that conversion at the trigger.
class AppContextMenuRegion extends StatefulWidget {
  const AppContextMenuRegion({
    required this.items,
    required this.child,
    this.controller,
    super.key,
  });

  final List<Widget> items;
  final Widget child;
  final ShadContextMenuController? controller;

  @override
  State<AppContextMenuRegion> createState() => _AppContextMenuRegionState();
}

class _AppContextMenuRegionState extends State<AppContextMenuRegion> {
  ShadContextMenuController? _ownedController;
  ShadContextMenuController get _controller =>
      widget.controller ?? (_ownedController ??= ShadContextMenuController());
  Offset? _position;
  bool _restoreBrowserMenu = false;

  void _show(Offset globalPosition) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    setState(() => _position = overlay.globalToLocal(globalPosition));
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
    items: widget.items,
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
      onLongPressStart: (details) => _show(details.globalPosition),
      child: widget.child,
    ),
  );
}

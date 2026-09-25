import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Shared explicit-activation overflow button, using the app's menu theme.
class AppActionMenu extends StatefulWidget {
  const AppActionMenu({
    required this.tooltip,
    required this.items,
    this.enabled = true,
    this.width = 48,
    this.constraints,
    this.child = const Icon(LucideIcons.ellipsis),
    super.key,
  });

  final String tooltip;
  final List<Widget> items;
  final bool enabled;
  final double? width;
  final BoxConstraints? constraints;
  final Widget child;

  @override
  State<AppActionMenu> createState() => _AppActionMenuState();
}

class _AppActionMenuState extends State<AppActionMenu> {
  final _controller = ShadPopoverController();
  ({ShadAnchorAuto anchor, double maxHeight})? _placement;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updatePlacement);
  }

  void _updatePlacement() {
    if (!mounted || !_controller.isOpen) return;
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || overlay == null || !overlay.hasSize) {
      return;
    }
    final media = MediaQuery.of(context);
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    final placement = actionMenuPlacement(
      origin & box.size,
      Rect.fromLTRB(
        media.padding.left,
        media.padding.top,
        overlay.size.width - media.padding.right,
        overlay.size.height -
            math.max(media.padding.bottom, media.viewInsets.bottom),
      ),
    );
    if (_placement != placement) setState(() => _placement = placement);
  }

  @override
  void dispose() {
    _controller.removeListener(_updatePlacement);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Re-evaluate after window, keyboard or interface zoom changes.
    MediaQuery.of(context);
    if (_controller.isOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _updatePlacement());
    }
    return Tooltip(
      message: widget.tooltip,
      child: ShadMenubar(
        padding: EdgeInsets.zero,
        border: ShadBorder.none,
        backgroundColor: Colors.transparent,
        items: [
          ShadMenubarItem(
            controller: _controller,
            anchor: _placement?.anchor,
            padding: const EdgeInsets.all(4),
            enabled: widget.enabled,
            width: widget.width,
            height: 48,
            buttonPadding: EdgeInsets.zero,
            constraints: widget.constraints,
            items: scrollableActionMenuItems(
              context,
              widget.items,
              maxHeight: _placement?.maxHeight,
            ),
            child: Semantics(label: widget.tooltip, child: widget.child),
          ),
        ],
      ),
    );
  }
}

/// Both rectangles use overlay coordinates, including when the UI is zoomed.
({ShadAnchorAuto anchor, double maxHeight}) actionMenuPlacement(
  Rect trigger,
  Rect viewport,
) {
  final above = math.max(0.0, trigger.top - viewport.top);
  final below = math.max(0.0, viewport.bottom - trigger.bottom);
  final openBelow = below >= above;
  final openLeft =
      trigger.left - viewport.left > viewport.right - trigger.right;
  final y = openBelow ? 1.0 : -1.0;
  final x = openLeft ? 1.0 : -1.0;
  return (
    anchor: ShadAnchorAuto(
      offset: Offset(0, openBelow ? 4 : -4),
      targetAnchor: Alignment(x, y),
      // Shad's automatic anchor shifts by half the follower's width and by
      // its full height for y=-1; these are not CompositedTransformFollower anchors.
      followerAnchor: Alignment(-x, y),
    ),
    // Leave room for the gap, viewport margin and menu padding/border.
    maxHeight: math.max(0.0, (openBelow ? below : above) - 24),
  );
}

/// Preserve access to every action on short screens and with large text.
List<Widget> scrollableActionMenuItems(
  BuildContext context,
  List<Widget> items, {
  double? maxHeight,
}) {
  if (items.isEmpty) return items;
  final media = MediaQuery.of(context);
  return [
    ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight:
            maxHeight ??
            math.max(
              44,
              media.size.height -
                  media.padding.vertical -
                  media.viewInsets.bottom -
                  32,
            ),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: items,
        ),
      ),
    ),
  ];
}

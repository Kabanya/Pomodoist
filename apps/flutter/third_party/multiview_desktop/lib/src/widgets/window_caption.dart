import 'dart:io';

import 'package:flutter/material.dart';

import '../multi_view_desktop.dart';
import 'drag_to_move_area.dart';

/// Standard height of the custom window caption bar.
const double kWindowCaptionHeight = 32.0;

/// A custom title-bar replacement for frameless windows.
///
/// Renders a `DragToMoveArea` that lets the user move the window by dragging,
/// plus optional window control buttons (minimize / maximize / close).
///
/// Typical usage when the native title bar has been hidden:
///
/// ```dart
/// Column(
///   children: [
///     const WindowCaption(title: Text('My App')),
///     Expanded(child: MyContent()),
///   ],
/// )
/// ```
class WindowCaption extends StatefulWidget {
  const WindowCaption({
    super.key,
    this.title,
    this.backgroundColor,
    this.brightness,
  });

  /// Widget shown in the centre/left of the caption bar.
  final Widget? title;

  final Color? backgroundColor;

  /// Controls the foreground colour of title text and icons.
  /// Defaults to `Brightness.light` (dark icons).
  final Brightness? brightness;

  @override
  State<WindowCaption> createState() => _WindowCaptionState();
}

class _WindowCaptionState extends State<WindowCaption> {
  @override
  Widget build(BuildContext context) {
    final brightness = widget.brightness ?? Brightness.light;
    final foreground =
        brightness == Brightness.light ? Colors.black87 : Colors.white;

    return DragToMoveArea(
      child: Container(
        height: kWindowCaptionHeight,
        color: widget.backgroundColor ?? Colors.transparent,
        child: Row(
          children: [
            // On macOS the traffic-light buttons are in the top-left corner;
            // add padding so the title does not overlap them.
            if (Platform.isMacOS) const SizedBox(width: 72),
            Expanded(
              child: DefaultTextStyle(
                style: TextStyle(
                  color: foreground,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: widget.title ?? const SizedBox.shrink(),
                ),
              ),
            ),
            // On Windows / Linux render custom window buttons.
            if (!Platform.isMacOS) _WindowButtons(foreground: foreground),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _WindowButtons - minimize / maximize / close for Windows + Linux
// ---------------------------------------------------------------------------

class _WindowButtons extends StatelessWidget {
  const _WindowButtons({required this.foreground});

  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _CaptionButton(
          icon: Icons.remove,
          foreground: foreground,
          onPressed: () => MultiViewDesktop.of(context).minimize(),
        ),
        _CaptionButton(
          icon: Icons.crop_square,
          foreground: foreground,
          onPressed: () {
            final win = MultiViewDesktop.of(context);
            win.isMaximized().then((isMax) {
              if (!context.mounted) return;
              if (isMax) {
                win.unmaximize();
              } else {
                win.maximize();
              }
            });
          },
        ),
        _CaptionButton(
          icon: Icons.close,
          foreground: foreground,
          hoverColor: Colors.red,
          onPressed: () => MultiViewDesktop.of(context).closeWindow(),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.icon,
    required this.foreground,
    required this.onPressed,
    this.hoverColor,
  });

  final IconData icon;
  final Color foreground;
  final VoidCallback onPressed;
  final Color? hoverColor;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: 46,
          height: kWindowCaptionHeight,
          color: _hovered
              ? (widget.hoverColor ?? Colors.black12)
              : Colors.transparent,
          child: Icon(
            widget.icon,
            color: _hovered && widget.hoverColor != null
                ? Colors.white
                : widget.foreground,
            size: 16,
          ),
        ),
      ),
    );
  }
}

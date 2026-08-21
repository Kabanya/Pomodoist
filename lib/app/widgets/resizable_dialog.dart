import 'dart:math' as math;

import 'package:flutter/material.dart';

class ResizableDialog extends StatefulWidget {
  const ResizableDialog({
    required this.title,
    required this.content,
    required this.actions,
    required this.initialSize,
    required this.minSize,
    super.key,
  });

  static const containerKey = Key('resizable-dialog-container');
  static const resizeHandleKey = Key('resizable-dialog-resize-handle');

  final Widget title;
  final Widget content;
  final List<Widget> actions;
  final Size initialSize;
  final Size minSize;

  @override
  State<ResizableDialog> createState() => _ResizableDialogState();
}

class _ResizableDialogState extends State<ResizableDialog> {
  static const double _viewportMargin = 24;

  late Size _size;

  @override
  void initState() {
    super.initState();
    _size = widget.initialSize;
  }

  @override
  Widget build(BuildContext context) {
    final size = _resolvedSize(context);
    final theme = Theme.of(context);
    final dialogTheme = theme.dialogTheme;
    final shape =
        dialogTheme.shape ??
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(28));

    return Dialog(
      insetPadding: const EdgeInsets.all(_viewportMargin),
      clipBehavior: Clip.antiAlias,
      shape: shape,
      backgroundColor: dialogTheme.backgroundColor ?? theme.colorScheme.surface,
      surfaceTintColor: dialogTheme.surfaceTintColor ?? Colors.transparent,
      child: SizedBox(
        key: ResizableDialog.containerKey,
        width: size.width,
        height: size.height,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 10, right: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                    child: DefaultTextStyle(
                      style:
                          theme.textTheme.headlineSmall ??
                          const TextStyle(fontSize: 24),
                      child: widget.title,
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
                      child: SingleChildScrollView(child: widget.content),
                    ),
                  ),
                  if (widget.actions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 24, 20),
                      child: OverflowBar(
                        alignment: MainAxisAlignment.end,
                        overflowAlignment: OverflowBarAlignment.end,
                        spacing: 8,
                        overflowSpacing: 8,
                        children: widget.actions,
                      ),
                    ),
                ],
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeDownRight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: _resizeBy,
                  child: const SizedBox(
                    key: ResizableDialog.resizeHandleKey,
                    width: 32,
                    height: 32,
                    child: CustomPaint(painter: _ResizeHandlePainter()),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _resizeBy(DragUpdateDetails details) {
    final current = _resolvedSize(context);
    final maxSize = _maxSize(context);
    final minSize = _effectiveMinSize(maxSize);

    setState(() {
      _size = Size(
        (current.width + details.delta.dx)
            .clamp(minSize.width, maxSize.width)
            .toDouble(),
        (current.height + details.delta.dy)
            .clamp(minSize.height, maxSize.height)
            .toDouble(),
      );
    });
  }

  Size _resolvedSize(BuildContext context) {
    final maxSize = _maxSize(context);
    final minSize = _effectiveMinSize(maxSize);

    return Size(
      _size.width.clamp(minSize.width, maxSize.width).toDouble(),
      _size.height.clamp(minSize.height, maxSize.height).toDouble(),
    );
  }

  Size _maxSize(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final availableWidth =
        mediaQuery.size.width -
        mediaQuery.viewInsets.horizontal -
        (_viewportMargin * 2);
    final availableHeight =
        mediaQuery.size.height -
        mediaQuery.viewInsets.vertical -
        (_viewportMargin * 2);

    return Size(math.max(1, availableWidth), math.max(1, availableHeight));
  }

  Size _effectiveMinSize(Size maxSize) {
    return Size(
      math.min(widget.minSize.width, maxSize.width),
      math.min(widget.minSize.height, maxSize.height),
    );
  }
}

class _ResizeHandlePainter extends CustomPainter {
  const _ResizeHandlePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.26)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    for (var offset = 8.0; offset <= 18.0; offset += 5.0) {
      canvas.drawLine(
        Offset(size.width - offset, size.height - 4),
        Offset(size.width - 4, size.height - offset),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ResizeHandlePainter oldDelegate) => false;
}

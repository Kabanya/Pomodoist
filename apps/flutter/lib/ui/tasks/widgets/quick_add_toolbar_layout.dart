import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

bool quickAddToolbarUsesIcons(double availableWidth, double labeledWidth) =>
    labeledWidth > availableWidth;

/// Measures the same typography, icons, gaps and padding as the labeled buttons.
double quickAddLabeledButtonWidth(
  String label, {
  required ShadThemeData theme,
  required TextScaler textScaler,
  required TextDirection textDirection,
  bool primary = false,
  double trailingWidth = 0,
}) {
  final button = primary ? theme.primaryButtonTheme : theme.outlineButtonTheme;
  final size = primary
      ? button.size ?? ShadButtonSize.regular
      : ShadButtonSize.sm;
  final sizes = theme.buttonSizesTheme;
  final dimensions = switch (size) {
    ShadButtonSize.sm => button.sizesTheme?.sm ?? sizes.sm!,
    ShadButtonSize.lg => button.sizesTheme?.lg ?? sizes.lg!,
    ShadButtonSize.regular => button.sizesTheme?.regular ?? sizes.regular!,
  };
  final painter = TextPainter(
    text: TextSpan(
      text: label,
      style: button.textStyle ?? theme.textTheme.small,
    ),
    textDirection: textDirection,
    textScaler: textScaler,
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  final gap = button.gap ?? 8;
  final decoration = theme.decoration.merge(button.decoration);
  final border = primary
      ? decoration.border
      : (decoration.border ?? const ShadBorder()).merge(ShadBorder.all());
  final borderWidth =
      (border?.toBorder().dimensions.horizontal ?? 0) +
      (border?.padding?.resolve(textDirection).horizontal ?? 0) +
      (decoration.secondaryBorder?.padding?.resolve(textDirection).horizontal ??
          0);
  return math.max(
    button.width ?? dimensions.width ?? 0,
    width +
        dimensions.padding.resolve(textDirection).horizontal +
        borderWidth +
        (primary ? 24 : 18) +
        gap +
        (trailingWidth == 0 ? 0 : trailingWidth + gap),
  );
}

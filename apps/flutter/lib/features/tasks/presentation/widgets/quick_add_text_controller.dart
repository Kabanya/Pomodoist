import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../planning/domain/quick_add_parser.dart';

class QuickAddTextController extends TextEditingController {
  QuickAddTextController({
    super.text,
    QuickAddParser parser = const QuickAddParser(),
    DateTime Function()? now,
  }) : _parser = parser,
       _now = now ?? DateTime.now;

  final QuickAddParser _parser;
  final DateTime Function() _now;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final input = text;
    if (input.isEmpty) {
      return TextSpan(style: style, text: input);
    }
    final matches = _parser.analyze(input, now: _now()).matches;
    final composing = value.composing;
    final hasComposing =
        withComposing &&
        composing.isValid &&
        !composing.isCollapsed &&
        composing.end <= input.length;
    final boundaries = <int>{0, input.length};
    for (final match in matches) {
      if (match.start >= 0 &&
          match.end <= input.length &&
          match.start < match.end) {
        boundaries
          ..add(match.start)
          ..add(match.end);
      }
    }
    if (hasComposing) {
      boundaries
        ..add(composing.start)
        ..add(composing.end);
    }
    final offsets = boundaries.toList()..sort();
    final children = <InlineSpan>[];
    for (var index = 0; index < offsets.length - 1; index++) {
      final start = offsets[index];
      final end = offsets[index + 1];
      final match = matches.cast<QuickAddTokenMatch?>().firstWhere(
        (candidate) =>
            candidate != null &&
            candidate.start <= start &&
            candidate.end >= end,
        orElse: () => null,
      );
      var segmentStyle = match == null
          ? const TextStyle()
          : _tokenStyle(context, match.kind);
      if (hasComposing && start >= composing.start && end <= composing.end) {
        segmentStyle = segmentStyle.merge(
          const TextStyle(decoration: TextDecoration.underline),
        );
      }
      children.add(
        TextSpan(text: input.substring(start, end), style: segmentStyle),
      );
    }
    return TextSpan(style: style, children: children);
  }

  TextStyle _tokenStyle(BuildContext context, QuickAddTokenKind kind) {
    final colors = context.appColors;
    final color = switch (kind) {
      QuickAddTokenKind.project || QuickAddTokenKind.section => colors.info,
      QuickAddTokenKind.label => colors.warning,
      QuickAddTokenKind.date ||
      QuickAddTokenKind.time ||
      QuickAddTokenKind.duration => colors.accent,
      QuickAddTokenKind.priority ||
      QuickAddTokenKind.focusEstimate => Theme.of(context).colorScheme.tertiary,
    };
    return TextStyle(color: color, fontWeight: FontWeight.w600);
  }
}

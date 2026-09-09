import 'package:flutter/services.dart';

import '../../../planning/domain/quick_add_parser.dart';
import '../../domain/task_models.dart';

const quickAddSchedulingKinds = {
  QuickAddTokenKind.date,
  QuickAddTokenKind.time,
  QuickAddTokenKind.duration,
};

/// Rewrites only recognized source ranges, keeping unrelated text and selection.
TextEditingValue rewriteQuickAddMetadata(
  TextEditingValue value,
  QuickAddAnalysis analysis,
  Set<QuickAddTokenKind> kinds,
  String? token,
) {
  if (value.composing.isValid && !value.composing.isCollapsed) return value;
  final spans =
      analysis.matches.where((match) => kinds.contains(match.kind)).toList()
        ..sort((a, b) => a.start.compareTo(b.start));
  final ranges = <TextRange>[];
  for (final span in spans) {
    if (span.start < 0 ||
        span.end > value.text.length ||
        span.start >= span.end) {
      continue;
    }
    if (ranges.isNotEmpty &&
        span.start >= ranges.last.start &&
        (span.start <= ranges.last.end ||
            value.text.substring(ranges.last.end, span.start).trim().isEmpty)) {
      final previous = ranges.removeLast();
      ranges.add(
        TextRange(
          start: previous.start,
          end: span.end > previous.end ? span.end : previous.end,
        ),
      );
    } else {
      ranges.add(TextRange(start: span.start, end: span.end));
    }
  }
  final output = StringBuffer();
  var cursor = 0;
  for (var index = 0; index < ranges.length; index++) {
    final range = ranges[index];
    output.write(value.text.substring(cursor, range.start));
    if (index == 0) output.write(token ?? '');
    cursor = range.end;
  }
  output.write(value.text.substring(cursor));
  if (ranges.isEmpty && token != null && token.isNotEmpty) {
    if (value.text.isNotEmpty &&
        value.text[value.text.length - 1].trim().isNotEmpty) {
      output.write(' ');
    }
    output.write(token);
  }
  int mapOffset(int offset) {
    if (offset < 0) return offset;
    var delta = 0;
    for (var index = 0; index < ranges.length; index++) {
      final range = ranges[index];
      final inserted = index == 0 ? (token?.length ?? 0) : 0;
      if (offset < range.start) break;
      if (offset <= range.end) {
        final relative = offset == range.end
            ? inserted
            : (offset - range.start).clamp(0, inserted);
        return range.start + delta + relative;
      }
      delta += inserted - (range.end - range.start);
    }
    return (offset + delta).clamp(0, output.length);
  }

  return TextEditingValue(
    text: output.toString(),
    selection: value.selection.copyWith(
      baseOffset: mapOffset(value.selection.baseOffset),
      extentOffset: mapOffset(value.selection.extentOffset),
    ),
  );
}

String quickAddScheduleToken(TaskSchedule schedule) {
  final date = schedule.displayDate;
  String two(int value) => value.toString().padLeft(2, '0');
  final day =
      '${date.year.toString().padLeft(4, '0')}-${two(date.month)}-${two(date.day)}';
  if (schedule.isAllDay) return day;
  final start = schedule.start!.toLocal();
  return '$day ${two(start.hour)}:${two(start.minute)} ${schedule.duration!.inMinutes}m';
}

/// Null means the parser cannot represent the actual name without changing it.
String? quickAddProjectToken(
  String name,
  QuickAddParser parser, {
  required DateTime now,
}) {
  final token = '#${quickAddQuotedMetadataValue(name)}';
  final parsed = parser.parse(token, now: now);
  return parsed.project == name && parsed.content.isEmpty ? token : null;
}

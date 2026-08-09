import 'dart:core';

import '../../tasks/domain/task_models.dart';
import 'quick_add_date_time_normalizer.dart';

const _todayWords = {
  'today',
  'сегодня',
  'heute',
  'hoy',
  "aujourd'hui",
  'aujourd’hui',
  'aujourdhui',
  'اليوم',
  '今天',
};

const _tomorrowWords = {
  'tomorrow',
  'завтра',
  'morgen',
  'mañana',
  'demain',
  'غدا',
  'غداً',
  'غدًا',
  '明天',
};

class ParsedQuickAdd {
  const ParsedQuickAdd({
    required this.content,
    this.project,
    this.section,
    this.labels = const [],
    this.priority,
    this.dueDate,
    this.schedule,
    this.deadline,
    this.estimatedFocusIntervals,
  });

  final String content;
  final String? project;
  final String? section;
  final List<String> labels;
  final int? priority;
  final DateTime? dueDate;
  final TaskSchedule? schedule;
  final DateTime? deadline;
  final int? estimatedFocusIntervals;
}

enum QuickAddTokenKind {
  project,
  label,
  section,
  priority,
  date,
  time,
  duration,
  focusEstimate,
}

class QuickAddTokenMatch {
  const QuickAddTokenMatch({
    required this.kind,
    required this.start,
    required this.end,
  });

  final QuickAddTokenKind kind;
  final int start;
  final int end;
}

class QuickAddAnalysis {
  const QuickAddAnalysis({required this.parsed, required this.matches});

  final ParsedQuickAdd parsed;
  final List<QuickAddTokenMatch> matches;
}

class QuickAddParser {
  const QuickAddParser({
    this.defaultTimedBlockDuration = const Duration(minutes: 30),
  });

  final Duration defaultTimedBlockDuration;

  QuickAddAnalysis analyze(
    String input, {
    DateTime? now,
    DateTime? defaultDate,
  }) {
    final effectiveNow = now ?? DateTime.now();
    final parsed = parse(input, now: effectiveNow, defaultDate: defaultDate);
    return QuickAddAnalysis(
      parsed: parsed,
      matches: _sourceMatches(input, _dateOnly(effectiveNow)),
    );
  }

  ParsedQuickAdd parse(String input, {DateTime? now, DateTime? defaultDate}) {
    final today = _dateOnly(now ?? DateTime.now());
    final normalized = QuickAddDateTimeNormalizer(
      today,
    ).normalize(input.trim());
    final tokens = _quickAddTokens(normalized.text);
    final contentTokens = <String>[];
    final labels = <String>[];
    String? project;
    String? section;
    int? priority;
    DateTime? dueDate;
    int? estimate;
    int? startMinuteOfDay;
    int? endMinuteOfDay;
    Duration? blockDuration;

    for (final token in tokens) {
      final lower = token.toLowerCase();
      final projectName = _metadataValue(token, '#');
      if (projectName != null) {
        project = projectName;
        continue;
      }
      final labelName = _metadataValue(token, '@');
      if (labelName != null) {
        labels.add(labelName);
        continue;
      }
      if (token.startsWith('/') && token.length > 1) {
        section = token.substring(1);
        continue;
      }
      final priorityMatch = RegExp(
        r'^p([1-4])$',
        caseSensitive: false,
      ).firstMatch(token);
      if (priorityMatch != null) {
        priority = int.parse(priorityMatch.group(1)!);
        continue;
      }
      final estimateMatch = RegExp(
        r'^(\d+)(p|п)$',
        caseSensitive: false,
      ).firstMatch(token);
      if (estimateMatch != null) {
        estimate = int.parse(estimateMatch.group(1)!);
        continue;
      }
      final timeRangeMatch = RegExp(
        r'^(\d{1,2}):(\d{2})[-–](\d{1,2}):(\d{2})$',
      ).firstMatch(token);
      if (timeRangeMatch != null) {
        final startHour = int.parse(timeRangeMatch.group(1)!);
        final startMinute = int.parse(timeRangeMatch.group(2)!);
        final endHour = int.parse(timeRangeMatch.group(3)!);
        final endMinute = int.parse(timeRangeMatch.group(4)!);
        if (startHour >= 0 &&
            startHour <= 23 &&
            startMinute >= 0 &&
            startMinute <= 59 &&
            endHour >= 0 &&
            endHour <= 23 &&
            endMinute >= 0 &&
            endMinute <= 59) {
          startMinuteOfDay = startHour * 60 + startMinute;
          endMinuteOfDay = endHour * 60 + endMinute;
          continue;
        }
      }
      final timeMatch = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(token);
      if (timeMatch != null) {
        final hour = int.parse(timeMatch.group(1)!);
        final minute = int.parse(timeMatch.group(2)!);
        if (hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59) {
          startMinuteOfDay = hour * 60 + minute;
          continue;
        }
      }
      final durationMatch = RegExp(
        r'^(\d+)(m|min|мин|м)$',
        caseSensitive: false,
      ).firstMatch(lower);
      if (durationMatch != null) {
        final minutes = int.parse(durationMatch.group(1)!);
        if (minutes > 0) {
          blockDuration = Duration(minutes: minutes);
          continue;
        }
      }
      final hourDurationMatch = RegExp(
        r'^(\d+)(h|ч)$',
        caseSensitive: false,
      ).firstMatch(lower);
      if (hourDurationMatch != null) {
        final hours = int.parse(hourDurationMatch.group(1)!);
        if (hours > 0) {
          blockDuration = Duration(hours: hours);
          continue;
        }
      }
      final isoDate = _parseIsoDate(token);
      if (isoDate != null) {
        dueDate = isoDate;
        continue;
      }
      final due = _parseDueWord(lower, today);
      if (due != null) {
        dueDate = due;
        continue;
      }
      final numeric = int.tryParse(token);
      if (numeric != null && numeric > 0) {
        contentTokens.add(token);
        continue;
      }
      if (_isFocusWord(lower)) {
        final previous = contentTokens.isNotEmpty
            ? int.tryParse(contentTokens.last)
            : null;
        if (previous != null) {
          estimate = previous;
          contentTokens.removeLast();
          continue;
        }
      }
      contentTokens.add(token);
    }

    final effectiveDueDate = normalized.hasInvalidExplicitDate ? null : dueDate;
    final schedule = normalized.hasInvalidExplicitDate
        ? null
        : _scheduleFromParsed(
            dueDate: effectiveDueDate,
            defaultDate: defaultDate == null ? null : _dateOnly(defaultDate),
            today: today,
            startMinuteOfDay: startMinuteOfDay,
            endMinuteOfDay: endMinuteOfDay,
            blockDuration: blockDuration,
          );
    return ParsedQuickAdd(
      content: contentTokens.join(' ').trim(),
      project: project,
      section: section,
      labels: labels,
      priority: priority,
      dueDate: effectiveDueDate,
      schedule: schedule,
      estimatedFocusIntervals: estimate,
    );
  }

  List<QuickAddTokenMatch> _sourceMatches(String input, DateTime today) {
    final normalized = QuickAddDateTimeNormalizer(today).normalize(input);
    final suppressTemporal = normalized.hasInvalidExplicitDate;
    final tokens = _sourceTokens(input);
    final matches = <QuickAddTokenMatch>[];

    for (var index = 0; index < tokens.length; index++) {
      final token = tokens[index];
      final value = token.text;
      final lower = value.toLowerCase();
      QuickAddTokenKind? kind;
      if (_metadataValue(value, '#') != null) {
        kind = QuickAddTokenKind.project;
      } else if (_metadataValue(value, '@') != null) {
        kind = QuickAddTokenKind.label;
      } else if (value.startsWith('/') && value.length > 1) {
        kind = QuickAddTokenKind.section;
      } else if (RegExp(r'^p[1-4]$', caseSensitive: false).hasMatch(value)) {
        kind = QuickAddTokenKind.priority;
      } else if (RegExp(r'^\d+(p|п)$', caseSensitive: false).hasMatch(value)) {
        kind = QuickAddTokenKind.focusEstimate;
      } else {
        final duration = RegExp(
          r'^(\d+)(m|min|мин|м|h|ч)$',
          caseSensitive: false,
        ).firstMatch(lower);
        if (duration != null && int.parse(duration.group(1)!) > 0) {
          kind = QuickAddTokenKind.duration;
        }
      }
      if (kind != null) {
        matches.add(
          QuickAddTokenMatch(kind: kind, start: token.start, end: token.end),
        );
        continue;
      }

      if (index > 0 && _isFocusWord(lower)) {
        final previous = tokens[index - 1];
        if (int.tryParse(previous.text) != null &&
            !matches.any((match) => match.end > previous.start)) {
          matches.add(
            QuickAddTokenMatch(
              kind: QuickAddTokenKind.focusEstimate,
              start: previous.start,
              end: token.end,
            ),
          );
          continue;
        }
      }

      if (suppressTemporal) {
        continue;
      }
      final temporal = _longestTemporalMatch(input, tokens, index, today);
      if (temporal != null) {
        matches.add(temporal.match);
        index = temporal.lastTokenIndex;
      }
    }

    matches.sort((left, right) => left.start.compareTo(right.start));
    return List.unmodifiable(matches);
  }

  ({QuickAddTokenMatch match, int lastTokenIndex})? _longestTemporalMatch(
    String input,
    List<_QuickAddSourceToken> tokens,
    int startIndex,
    DateTime today,
  ) {
    final maxEnd = (startIndex + 8).clamp(0, tokens.length);
    for (var endIndex = maxEnd - 1; endIndex >= startIndex; endIndex--) {
      final source = input.substring(
        tokens[startIndex].start,
        tokens[endIndex].end,
      );
      final normalized = QuickAddDateTimeNormalizer(today).normalize(source);
      if (normalized.hasInvalidExplicitDate) {
        continue;
      }
      final kind = _normalizedTemporalKind(normalized.text, today);
      if (kind != null) {
        return (
          match: QuickAddTokenMatch(
            kind: kind,
            start: tokens[startIndex].start,
            end: tokens[endIndex].end,
          ),
          lastTokenIndex: endIndex,
        );
      }
    }
    return null;
  }

  QuickAddTokenKind? _normalizedTemporalKind(String value, DateTime today) {
    if (_parseIsoDate(value) != null ||
        _parseDueWord(value.toLowerCase(), today) != null) {
      return QuickAddTokenKind.date;
    }
    final range = RegExp(
      r'^(\d{1,2}):(\d{2})[-–](\d{1,2}):(\d{2})$',
    ).firstMatch(value);
    if (range != null &&
        _validTime(range.group(1)!, range.group(2)!) &&
        _validTime(range.group(3)!, range.group(4)!)) {
      return QuickAddTokenKind.time;
    }
    final time = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value);
    if (time != null && _validTime(time.group(1)!, time.group(2)!)) {
      return QuickAddTokenKind.time;
    }
    return null;
  }

  bool _validTime(String hour, String minute) {
    final parsedHour = int.parse(hour);
    final parsedMinute = int.parse(minute);
    return parsedHour >= 0 &&
        parsedHour <= 23 &&
        parsedMinute >= 0 &&
        parsedMinute <= 59;
  }

  List<_QuickAddSourceToken> _sourceTokens(String input) {
    final tokens = <_QuickAddSourceToken>[];
    var index = 0;
    while (index < input.length) {
      while (index < input.length && input[index].trim().isEmpty) {
        index++;
      }
      if (index >= input.length) {
        break;
      }
      final start = index;
      final quotedMetadata =
          (input[index] == '#' || input[index] == '@') &&
          index + 1 < input.length &&
          input[index + 1] == '"';
      if (quotedMetadata) {
        index += 2;
        while (index < input.length && input[index] != '"') {
          index++;
        }
        if (index < input.length) {
          index++;
        }
      } else {
        while (index < input.length && input[index].trim().isNotEmpty) {
          index++;
        }
      }
      tokens.add(
        _QuickAddSourceToken(
          text: input.substring(start, index),
          start: start,
          end: index,
        ),
      );
    }
    return tokens;
  }

  Iterable<String> _quickAddTokens(String input) sync* {
    var index = 0;
    while (index < input.length) {
      while (index < input.length && input[index].trim().isEmpty) {
        index++;
      }
      if (index >= input.length) {
        return;
      }

      final start = index;
      final quotedMetadata =
          (input[index] == '#' || input[index] == '@') &&
          index + 1 < input.length &&
          input[index + 1] == '"';
      if (quotedMetadata) {
        index += 2;
        while (index < input.length && input[index] != '"') {
          index++;
        }
        if (index < input.length) {
          index++;
        }
        yield input.substring(start, index);
        continue;
      }

      while (index < input.length && input[index].trim().isNotEmpty) {
        index++;
      }
      yield input.substring(start, index);
    }
  }

  String? _metadataValue(String token, String marker) {
    if (!token.startsWith(marker) || token.length <= 1) {
      return null;
    }
    var value = token.substring(1);
    if (value.startsWith('"')) {
      if (value.length <= 1 || !value.endsWith('"')) {
        return null;
      }
      value = value.substring(1, value.length - 1);
    }
    value = value.trim();
    return value.isEmpty ? null : value;
  }

  DateTime? _parseDueWord(String token, DateTime today) {
    if (_todayWords.contains(token)) {
      return today;
    }
    if (_tomorrowWords.contains(token)) {
      return today.add(const Duration(days: 1));
    }
    if (token == 'послезавтра') {
      return today.add(const Duration(days: 2));
    }
    return null;
  }

  bool _isFocusWord(String token) {
    return token == 'pomodoro' ||
        token == 'pomodoros' ||
        token == 'помидор' ||
        token == 'помидора' ||
        token == 'помидоров' ||
        token == 'фокус' ||
        token == 'фокуса' ||
        token == 'фокусов';
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  DateTime? _parseIsoDate(String token) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(token);
    if (match == null) {
      return null;
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }

  TaskSchedule? _scheduleFromParsed({
    required DateTime? dueDate,
    required DateTime? defaultDate,
    required DateTime today,
    required int? startMinuteOfDay,
    required int? endMinuteOfDay,
    required Duration? blockDuration,
  }) {
    if (startMinuteOfDay == null) {
      final date = dueDate ?? defaultDate;
      return date == null ? null : TaskSchedule.allDay(date);
    }
    final date = dueDate ?? defaultDate ?? today;
    final start = DateTime(
      date.year,
      date.month,
      date.day,
      startMinuteOfDay ~/ 60,
      startMinuteOfDay % 60,
    );
    if (endMinuteOfDay != null) {
      var end = DateTime(
        date.year,
        date.month,
        date.day,
        endMinuteOfDay ~/ 60,
        endMinuteOfDay % 60,
      );
      if (!end.isAfter(start)) {
        end = end.add(const Duration(days: 1));
      }
      return TaskSchedule.timed(start: start, end: end);
    }
    return TaskSchedule.timed(
      start: start,
      end: start.add(blockDuration ?? defaultTimedBlockDuration),
    );
  }
}

class _QuickAddSourceToken {
  const _QuickAddSourceToken({
    required this.text,
    required this.start,
    required this.end,
  });

  final String text;
  final int start;
  final int end;
}

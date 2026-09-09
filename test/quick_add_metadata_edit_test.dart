import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/features/planning/domain/quick_add_parser.dart';
import 'package:pomodoist/features/tasks/domain/task_models.dart';
import 'package:pomodoist/features/tasks/presentation/widgets/quick_add_metadata_edit.dart';

void main() {
  const parser = QuickAddParser();
  final now = DateTime(2026, 9, 9);
  test('source replacement removes duplicates and preserves other source', () {
    const text = 'Task завтра p1 #"Old name" @"My label" /Work 3p p2';
    final value = TextEditingValue(
      text: text,
      selection: const TextSelection(baseOffset: 0, extentOffset: 4),
    );
    final result = rewriteQuickAddMetadata(
      value,
      parser.analyze(text, now: now),
      {QuickAddTokenKind.priority},
      'p3',
    );
    final parsed = parser.parse(result.text, now: now);
    expect(parsed.priority, 3);
    expect(parsed.content, 'Task');
    expect(parsed.project, 'Old name');
    expect(parsed.labels, ['My label']);
    expect(parsed.section, 'Work');
    expect(parsed.estimatedFocusIntervals, 3);
    expect(result.text, contains('завтра'));
    expect(result.selection, value.selection);
    expect(
      parser
          .analyze(result.text, now: now)
          .matches
          .where((m) => m.kind == QuickAddTokenKind.priority),
      hasLength(1),
    );
  });
  test('repeated localized date edits and reset reveal inherited date', () {
    var value = const TextEditingValue(
      text: 'Task завтра today 23:30-01:00 30m',
    );
    final schedule = TaskSchedule.timed(
      start: DateTime(2026, 10, 4, 23, 45),
      end: DateTime(2026, 10, 5, 1, 15),
    );
    for (var i = 0; i < 3; i++) {
      value = rewriteQuickAddMetadata(
        value,
        parser.analyze(value.text, now: now),
        quickAddSchedulingKinds,
        quickAddScheduleToken(schedule),
      );
      final parsed = parser.parse(value.text, now: now);
      expect(parsed.content, 'Task');
      expect(parsed.schedule!.start, schedule.start);
      expect(parsed.schedule!.duration, const Duration(minutes: 90));
    }
    value = rewriteQuickAddMetadata(
      value,
      parser.analyze(value.text, now: now),
      quickAddSchedulingKinds,
      null,
    );
    expect(
      parser
          .parse(value.text, now: now, defaultDate: now)
          .schedule!
          .displayDate,
      now,
    );
  });
  test('all day removes time and duration and keeps date', () {
    const value = TextEditingValue(text: 'Task tomorrow 23:30 90m');
    final result = rewriteQuickAddMetadata(
      value,
      parser.analyze(value.text, now: now),
      quickAddSchedulingKinds,
      quickAddScheduleToken(TaskSchedule.allDay(now)),
    );
    expect(parser.parse(result.text, now: now).schedule!.isAllDay, isTrue);
    expect(parser.parse(result.text, now: now).dueDate, now);
  });
  test('selection offsets map through deleted spans; IME stays untouched', () {
    const value = TextEditingValue(
      text: 'p1 Task p2',
      selection: TextSelection(baseOffset: 3, extentOffset: 10),
    );
    final analysis = parser.analyze(value.text, now: now);
    final result = rewriteQuickAddMetadata(value, analysis, {
      QuickAddTokenKind.priority,
    }, null);
    expect(
      result.selection,
      const TextSelection(baseOffset: 1, extentOffset: 6),
    );
    final composing = value.copyWith(
      composing: const TextRange(start: 3, end: 7),
    );
    expect(
      rewriteQuickAddMetadata(composing, analysis, {
        QuickAddTokenKind.priority,
      }, 'p4'),
      composing,
    );
  });
  test('quoted project source ranges replace completely and reset', () {
    final name = r'Team "A" \next September 9';
    final token = quickAddProjectToken(name, parser, now: now)!;
    var value = TextEditingValue(text: 'Task $token #Old @"Label ١٢"');
    final replacement = quickAddProjectToken('New  team', parser, now: now)!;
    value = rewriteQuickAddMetadata(
      value,
      parser.analyze(value.text, now: now),
      {QuickAddTokenKind.project},
      replacement,
    );
    expect(parser.parse(value.text, now: now).project, 'New  team');
    expect(parser.parse(value.text, now: now).labels, ['Label ١٢']);
    expect(parser.parse(value.text, now: now).content, 'Task');
    value = rewriteQuickAddMetadata(
      value,
      parser.analyze(value.text, now: now),
      {QuickAddTokenKind.project},
      null,
    );
    expect(parser.parse(value.text, now: now).project, isNull);
    expect(parser.parse(value.text, now: now).content, 'Task');
  });
  test('identical scheduling edits are stable and map token end selection', () {
    const text = 'Task tomorrow 23:30 90m @home';
    var value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.indexOf(' @home')),
    );
    const token = '2026-10-04 23:45 90m';
    value = rewriteQuickAddMetadata(
      value,
      parser.analyze(value.text, now: now),
      quickAddSchedulingKinds,
      token,
    );
    expect(value.text, 'Task $token @home');
    expect(value.selection.baseOffset, 'Task $token'.length);
    final second = rewriteQuickAddMetadata(
      value,
      parser.analyze(value.text, now: now),
      quickAddSchedulingKinds,
      token,
    );
    expect(second, value);
  });
  test(
    'editing repairs invalid localized dates without consuming title words',
    () {
      for (final dateText in [
        '31/02/2027',
        'on 31 February 2027',
        'на 31 февраля 2027',
        'le 31 février 2027',
        '٣١/٠٢/٢٠٢٧',
      ]) {
        final original = TextEditingValue(
          text: 'Call client $dateText at 5 PM 90m @work',
        );
        final ordinary = parser.analyze(original.text, now: now);
        expect(ordinary.parsed.schedule, isNull);
        expect(
          ordinary.matches.where(
            (match) =>
                match.kind == QuickAddTokenKind.date ||
                match.kind == QuickAddTokenKind.time,
          ),
          isEmpty,
        );
        final editing = parser.analyze(
          original.text,
          now: now,
          includeInvalidScheduling: true,
        );
        expect(
          editing.matches
              .where((match) => match.kind == QuickAddTokenKind.date)
              .map((match) => original.text.substring(match.start, match.end)),
          [dateText],
        );
        expect(editing.parsed.schedule!.start!.toLocal().hour, 17);
        final corrected = editing.parsed.schedule!.moveToDate(
          DateTime(2027, 3, 1),
        );
        final token = quickAddScheduleToken(corrected);
        final value = rewriteQuickAddMetadata(
          original,
          editing,
          quickAddSchedulingKinds,
          token,
        );
        final parsed = parser.parse(value.text, now: now);
        expect(parsed.content, 'Call client');
        expect(parsed.labels, ['work']);
        expect(parsed.schedule!.displayDate, DateTime(2027, 3, 1));
        expect(parsed.schedule!.duration, const Duration(minutes: 90));
        expect(
          rewriteQuickAddMetadata(
            value,
            parser.analyze(
              value.text,
              now: now,
              includeInvalidScheduling: true,
            ),
            quickAddSchedulingKinds,
            token,
          ),
          value,
        );
        for (final input in [original, value]) {
          final reset = rewriteQuickAddMetadata(
            input,
            parser.analyze(
              input.text,
              now: now,
              includeInvalidScheduling: true,
            ),
            quickAddSchedulingKinds,
            null,
          );
          final inherited = parser.parse(
            reset.text,
            now: now,
            defaultDate: now,
          );
          expect(inherited.content, 'Call client');
          expect(inherited.schedule!.displayDate, now);
          expect(inherited.schedule!.isAllDay, isTrue);
        }
      }
    },
  );
  test('legacy backslash remains literal', () {
    expect(parser.parse(r'Task #"Team\next"', now: now).project, r'Team\next');
  });
  test('project names round trip exactly or are rejected', () {
    for (final name in [
      'Work',
      'My Project',
      'Работа сегодня',
      'Team @home',
      r'Team\Work',
      'Team "A"',
      'Team September 9',
      'Команда ١٢',
      'Team  two spaces',
      r'Team\next',
    ]) {
      final token = quickAddProjectToken(name, parser, now: now);
      expect(token, isNotNull);
      expect(parser.parse('Task $token', now: now).project, name);
    }
    for (final name in [' leading', '', 'trailing ']) {
      expect(quickAddProjectToken(name, parser, now: now), isNull);
    }
  });
}

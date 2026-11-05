import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/domain/models/planning/quick_add_parser.dart';
import 'package:pomodoist/ui/tasks/view_models/quick_add_metadata_edit.dart';

void main() {
  const parser = QuickAddParser();
  final now = DateTime(2026, 11, 6);
  const priorities = ['p', 'P', 'п', 'П', 'أ', '优', '優', '우', '!!'];
  const estimates = ['p', 'P', 'п', 'П', 'ب', '番', 'ポ', '뽀'];
  const digitSets = ['0123456789', '٠١٢٣٤٥٦٧٨٩', '۰۱۲۳۴۵۶۷۸۹', '０１２３４５６７８９'];
  String digits(int number, String alphabet) => number
      .toString()
      .split('')
      .map((digit) => alphabet[int.parse(digit)])
      .join();

  test('priority aliases parse and highlight every supported digit set', () {
    for (final prefix in priorities) {
      for (final alphabet in digitSets) {
        for (var number = 1; number <= 4; number++) {
          final token = '$prefix${digits(number, alphabet)}';
          final input = 'Task $token';
          final analysis = parser.analyze(input, now: now);
          expect(analysis.parsed.priority, number, reason: input);
          expect(analysis.parsed.content, 'Task');
          expect(analysis.matches.single.kind, QuickAddTokenKind.priority);
          final match = analysis.matches.single;
          expect(input.substring(match.start, match.end), token);
        }
      }
    }
  });

  test('estimate aliases parse and highlight supported digits and limits', () {
    for (final suffix in estimates) {
      for (final alphabet in digitSets) {
        for (final number in [1, 4, 12, 999]) {
          final token = '${digits(number, alphabet)}$suffix';
          final input = 'Task $token';
          final analysis = parser.analyze(input, now: now);
          expect(
            analysis.parsed.estimatedFocusIntervals,
            number,
            reason: input,
          );
          expect(analysis.parsed.content, 'Task');
          expect(analysis.matches.single.kind, QuickAddTokenKind.focusEstimate);
          final match = analysis.matches.single;
          expect(input.substring(match.start, match.end), token);
        }
      }
    }
  });

  test('date normalization cannot create command boundaries', () {
    for (final token in [
      'p2',
      'п2',
      'أ٢',
      '优2',
      '優２',
      '우2',
      '!!2',
      '4p',
      '4п',
      '٤ب',
      '4番',
      '４ポ',
      '4뽀',
    ]) {
      for (final input in ['Task $token明日', 'Task 3月4日$token']) {
        for (final editing in [false, true]) {
          final analysis = parser.analyze(
            input,
            now: now,
            includeInvalidScheduling: editing,
          );
          expect(analysis.parsed.priority, isNull, reason: input);
          expect(
            analysis.parsed.estimatedFocusIntervals,
            isNull,
            reason: input,
          );
          expect(analysis.parsed.content, startsWith('Task '));
          expect(analysis.parsed.content, isNot('Task'));
          expect(
            analysis.parsed.dueDate,
            isNotNull,
            reason: 'existing attached date recognition stays supported',
          );
          expect(
            analysis.matches.where(
              (match) =>
                  match.kind == QuickAddTokenKind.priority ||
                  match.kind == QuickAddTokenKind.focusEstimate,
            ),
            isEmpty,
            reason: input,
          );
        }
      }
    }
    final parsed = parser.parse('Task 優2明日 p3 4ポ明日 5p', now: now);
    expect(parsed.priority, 3);
    expect(parsed.estimatedFocusIntervals, 5);
    expect(parsed.content, 'Task 優2 4ポ');
  });

  test('invalid and attached commands remain text with no highlight', () {
    for (final token in [
      for (final prefix in priorities) ...[
        '${prefix}0',
        '${prefix}5',
        '${prefix}22',
        'word${prefix}2',
        '${prefix}2,',
      ],
      for (final suffix in estimates) ...[
        '0$suffix',
        '1000$suffix',
        '999999999999999999999999$suffix',
        'word4$suffix',
        '4${suffix}word',
      ],
      'з2',
      '2з',
      'п',
      'أ',
      '番',
    ]) {
      final input = 'Task $token';
      final analysis = parser.analyze(input, now: now);
      expect(analysis.parsed.content, input, reason: input);
      expect(analysis.parsed.priority, isNull, reason: input);
      expect(analysis.parsed.estimatedFocusIntervals, isNull, reason: input);
      expect(analysis.matches, isEmpty, reason: input);
    }
  });

  test('last valid command wins across scripts without changing metadata', () {
    const input = 'Task p1 п2 أ٣ 優４ 우2 !!3 1p 2п ٣ب ４番 5ポ 6뽀 #"أ٢" @"4番"';
    final parsed = parser.parse(input, now: now);
    expect(parsed.content, 'Task');
    expect(parsed.priority, 3);
    expect(parsed.estimatedFocusIntervals, 6);
    expect(parsed.project, 'أ٢');
    expect(parsed.labels, ['4番']);
  });

  test(
    'localized ranges can be replaced and cleared while keeping selection and IME',
    () {
      const input = 'Отчёт أ٢ 優３ ٤ب ５ポ #Work';
      const value = TextEditingValue(
        text: input,
        selection: TextSelection.collapsed(offset: input.length),
      );
      final priority = rewriteQuickAddMetadata(
        value,
        parser.analyze(input, now: now),
        {QuickAddTokenKind.priority},
        'p4',
      );
      expect(priority.text, 'Отчёт p4 ٤ب ５ポ #Work');
      expect(priority.selection.baseOffset, priority.text.length);
      final estimate = rewriteQuickAddMetadata(
        priority,
        parser.analyze(priority.text, now: now),
        {QuickAddTokenKind.focusEstimate},
        '7p',
      );
      expect(estimate.text, 'Отчёт p4 7p #Work');
      expect(parser.parse(estimate.text, now: now).estimatedFocusIntervals, 7);
      final cleared = rewriteQuickAddMetadata(
        estimate,
        parser.analyze(estimate.text, now: now),
        {QuickAddTokenKind.priority, QuickAddTokenKind.focusEstimate},
        null,
      );
      expect(parser.parse(cleared.text, now: now).content, 'Отчёт');
      expect(parser.parse(cleared.text, now: now).priority, isNull);
      expect(
        parser.parse(cleared.text, now: now).estimatedFocusIntervals,
        isNull,
      );
      expect(parser.parse(cleared.text, now: now).project, 'Work');
      final composing = value.copyWith(
        composing: const TextRange(start: 6, end: 8),
      );
      expect(
        rewriteQuickAddMetadata(composing, parser.analyze(input, now: now), {
          QuickAddTokenKind.priority,
        }, 'p1'),
        composing,
      );
    },
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/features/planning/domain/quick_add_parser.dart';

void main() {
  const parser = QuickAddParser();
  final now = DateTime(2026, 7, 10, 12);

  test('reports every recognized quick-add range in the original text', () {
    const input =
        'Plan @work #family /home p1 17:00-19:00 16:00 7 PM 8 march 45m 3p';

    final analysis = parser.analyze(input, now: now);

    expect(
      analysis.matches
          .map((match) => (match.kind, input.substring(match.start, match.end)))
          .toList(),
      [
        (QuickAddTokenKind.label, '@work'),
        (QuickAddTokenKind.project, '#family'),
        (QuickAddTokenKind.section, '/home'),
        (QuickAddTokenKind.priority, 'p1'),
        (QuickAddTokenKind.time, '17:00-19:00'),
        (QuickAddTokenKind.time, '16:00'),
        (QuickAddTokenKind.time, '7 PM'),
        (QuickAddTokenKind.date, '8 march'),
        (QuickAddTokenKind.duration, '45m'),
        (QuickAddTokenKind.focusEstimate, '3p'),
      ],
    );
    expect(analysis.parsed.content, 'Plan');
  });

  test('keeps localized source ranges across digit normalization', () {
    const input = 'اتصال ٤/٥/٢٠٢٧ الساعة ٥:٣٠ م';

    final analysis = parser.analyze(input, now: now);

    expect(
      analysis.matches
          .map((match) => (match.kind, input.substring(match.start, match.end)))
          .toList(),
      [
        (QuickAddTokenKind.date, '٤/٥/٢٠٢٧'),
        (QuickAddTokenKind.time, 'الساعة ٥:٣٠ م'),
      ],
    );
  });

  test('reports the full bang priority alias range', () {
    const input = 'Plan !!3';

    final analysis = parser.analyze(input, now: now);

    expect(analysis.matches, hasLength(1));
    expect(analysis.matches.single.kind, QuickAddTokenKind.priority);
    expect(
      input.substring(
        analysis.matches.single.start,
        analysis.matches.single.end,
      ),
      '!!3',
    );
    expect(analysis.parsed.content, 'Plan');
    expect(analysis.parsed.priority, 3);
  });

  test('reports localized date and time ranges for every app language', () {
    final cases = <({String input, List<String> expected})>[
      (input: 'Call 4 may 2027 at 5 PM', expected: ['4 may 2027', 'at 5 PM']),
      (
        input: 'Созвон 4 мая 2027 в 5 вечера',
        expected: ['4 мая 2027', 'в 5 вечера'],
      ),
      (
        input: 'Anruf am 4. Mai 2027 um 5 Uhr nachmittags',
        expected: ['am 4. Mai 2027', 'um 5 Uhr nachmittags'],
      ),
      (
        input: 'Llamada el 4 de mayo de 2027 a las 5 de la tarde',
        expected: ['el 4 de mayo de 2027', 'a las 5 de la tarde'],
      ),
      (
        input: 'Appel le 4 mai 2027 à 17h30',
        expected: ['le 4 mai 2027', 'à 17h30'],
      ),
      (
        input: 'اتصال ٤/٥/٢٠٢٧ الساعة ٥:٣٠ م',
        expected: ['٤/٥/٢٠٢٧', 'الساعة ٥:٣٠ م'],
      ),
      (input: '通话 2027年5月4日 下午5点半', expected: ['2027年5月4日', '下午5点半']),
    ];

    for (final item in cases) {
      final analysis = parser.analyze(item.input, now: now);
      expect(
        analysis.matches
            .map((match) => item.input.substring(match.start, match.end))
            .toList(),
        item.expected,
        reason: item.input,
      );
    }
  });

  test('does not report incomplete or invalid commands', () {
    const input = 'Call # @ / p5 31/02/2027 at 13 PM';

    final analysis = parser.analyze(input, now: now);

    expect(analysis.matches, isEmpty);
    expect(analysis.parsed.schedule, isNull);
  });

  test('does not accept an unfinished quoted metadata token', () {
    const input = 'Plan #"Product Launch';

    final analysis = parser.analyze(input, now: now);

    expect(analysis.matches, isEmpty);
    expect(analysis.parsed.project, isNull);
    expect(analysis.parsed.content, input);
  });

  test('does not highlight a zero duration that the parser keeps as text', () {
    const input = 'Plan 0m';

    final analysis = parser.analyze(input, now: now);

    expect(analysis.matches, isEmpty);
    expect(analysis.parsed.content, input);
  });

  test('reports a multi-word focus estimate as one range', () {
    const input = 'Написать статью 3 фокуса';

    final analysis = parser.analyze(input, now: now);

    expect(analysis.matches, hasLength(1));
    expect(analysis.matches.single.kind, QuickAddTokenKind.focusEstimate);
    expect(
      input.substring(
        analysis.matches.single.start,
        analysis.matches.single.end,
      ),
      '3 фокуса',
    );
  });
}

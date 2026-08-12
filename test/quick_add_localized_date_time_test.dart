import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/features/planning/domain/quick_add_parser.dart';

void main() {
  const parser = QuickAddParser();
  final now = DateTime(2026, 7, 10, 12);

  group('localized quick-add date and time parsing', () {
    test('parses English AM/PM without leaving syntax in the title', () {
      final parsed = parser.parse(
        'Call client 04/05/2027 at 5:30 p.M.',
        now: now,
      );

      expect(parsed.content, 'Call client');
      expect(parsed.schedule!.start!.toLocal(), DateTime(2027, 5, 4, 17, 30));
    });

    test('parses compact AM/PM ranges before numeric dates', () {
      final parsed = parser.parse('Workshop 04/05/2027 4-5 PM', now: now);

      expect(parsed.content, 'Workshop');
      expect(parsed.schedule!.start!.toLocal(), DateTime(2027, 5, 4, 16));
      expect(parsed.schedule!.end!.toLocal(), DateTime(2027, 5, 4, 17));
    });

    test('does not turn an ordinary hyphenated number into a date', () {
      final parsed = parser.parse('Review versions 4-5', now: now);

      expect(parsed.content, 'Review versions 4-5');
      expect(parsed.schedule, isNull);
    });

    test('uses the next year for a past numeric day/month date', () {
      final parsed = parser.parse('Plan review 04.05 9 AM', now: now);

      expect(parsed.content, 'Plan review');
      expect(parsed.schedule!.start!.toLocal(), DateTime(2027, 5, 4, 9));
    });

    test('parses culturally typical supported-language forms', () {
      final cases = <({String input, String content, DateTime expected})>[
        (
          input: 'Созвон 4.05.2027 в 5 вечера',
          content: 'Созвон',
          expected: DateTime(2027, 5, 4, 17),
        ),
        (
          input: 'Anruf am 4. Mai 2027 um 5 Uhr nachmittags',
          content: 'Anruf',
          expected: DateTime(2027, 5, 4, 17),
        ),
        (
          input: 'Llamada el 4 de mayo de 2027 a las 5:30 p. m.',
          content: 'Llamada',
          expected: DateTime(2027, 5, 4, 17, 30),
        ),
        (
          input: 'Appel le 1er mai 2027 à 17h30',
          content: 'Appel',
          expected: DateTime(2027, 5, 1, 17, 30),
        ),
        (
          input: 'اتصال ٤/٥/٢٠٢٧ الساعة ٥:٣٠ م',
          content: 'اتصال',
          expected: DateTime(2027, 5, 4, 17, 30),
        ),
        (
          input: '通话 2027年5月4日 下午5点半',
          content: '通话',
          expected: DateTime(2027, 5, 4, 17, 30),
        ),
      ];

      for (final item in cases) {
        final parsed = parser.parse(item.input, now: now);

        expect(parsed.content, item.content, reason: item.input);
        expect(parsed.schedule, isNotNull, reason: item.input);
        expect(
          parsed.schedule!.start!.toLocal(),
          item.expected,
          reason: item.input,
        );
      }
    });

    test(
      'does not schedule a valid time when its explicit date is invalid',
      () {
        final parsed = parser.parse('Call client 31/02/2027 at 5 PM', now: now);

        expect(parsed.schedule, isNull);
      },
    );
  });
}

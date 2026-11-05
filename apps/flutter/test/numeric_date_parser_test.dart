import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/domain/models/planning/numeric_date_parser.dart';
import 'package:pomodoist/domain/models/planning/quick_add_parser.dart';

void main() {
  final today = DateTime(2026, 11, 6);
  test('punctuation after a numeric date does not prevent scheduling', () {
    for (final suffix in ['.', ',', ';', '!', '?']) {
      final input = 'Task 25.11.27$suffix';
      final analysis = const QuickAddParser().analyze(input, now: today);
      expect(analysis.parsed.dueDate, DateTime(2027, 11, 25), reason: input);
      expect(analysis.parsed.content, 'Task');
      expect(analysis.matches.single.kind, QuickAddTokenKind.date);
    }
  });
  test('date components follow the selected order with every separator', () {
    for (final (order, text, expected) in [
      (NumericDateOrder.dayMonthYear, '25.11.27', DateTime(2027, 11, 25)),
      (NumericDateOrder.dayMonthYear, '4.5.2027', DateTime(2027, 5, 4)),
      (NumericDateOrder.monthDayYear, '11.25.27', DateTime(2027, 11, 25)),
      (NumericDateOrder.yearMonthDay, '25.11.27', DateTime(2025, 11, 27)),
      (NumericDateOrder.yearMonthDay, '2027.1.2', DateTime(2027, 1, 2)),
      (NumericDateOrder.dayMonthYear, '1.1.00', DateTime(2000)),
      (NumericDateOrder.monthDayYear, '12.31.99', DateTime(2099, 12, 31)),
    ]) {
      for (final separator in ['.', '/', '-']) {
        final token = text.replaceAll('.', separator);
        expect(
          parseNumericDate(token, order: order, today: today),
          expected,
          reason: token,
        );
        final parsed = QuickAddParser(
          dateOrder: order,
        ).parse('Task $token 09:30', now: today);
        expect(parsed.content, 'Task');
        expect(
          parsed.schedule!.start!.toLocal(),
          expected.add(const Duration(hours: 9, minutes: 30)),
        );
      }
    }
    for (final order in NumericDateOrder.values) {
      expect(
        parseNumericDate('2027-11-25', order: order, today: today),
        DateTime(2027, 11, 25),
      );
    }
  });

  test('yearless dates find the next valid calendar occurrence', () {
    for (final (input, reference, expected) in [
      ('06.11', today, DateTime(2026, 11, 6)),
      ('05.11', today, DateTime(2027, 11, 5)),
      ('29.02', today, DateTime(2028, 2, 29)),
      ('29.02', DateTime(2097), DateTime(2104, 2, 29)),
    ]) {
      expect(
        parseNumericDate(
          input,
          order: NumericDateOrder.dayMonthYear,
          today: reference,
        ),
        expected,
      );
      expect(
        const QuickAddParser().parse('Task $input', now: reference).dueDate,
        expected,
      );
    }
    expect(
      parseNumericDate(
        '02/29',
        order: NumericDateOrder.yearMonthDay,
        today: today,
      ),
      DateTime(2028, 2, 29),
    );
  });

  test(
    'invalid and incomplete numeric dates never roll over or parse a prefix',
    () {
      for (final input in [
        '25.11.2',
        '25.11.20277',
        '31.02.27',
        '29.02.27',
        '00.11.27',
        '25.00.27',
        '25.13.27',
        '25/11.27',
        '25.11.27.99',
        '25.11.27/',
        '25.11.0000',
        '0000-01-01',
      ]) {
        expect(
          parseNumericDate(
            input,
            order: NumericDateOrder.dayMonthYear,
            today: today,
          ),
          isNull,
          reason: input,
        );
        final analysis = const QuickAddParser().analyze(
          'Task $input 09:30',
          now: today,
        );
        expect(analysis.parsed.schedule, isNull, reason: input);
        expect(analysis.parsed.content, contains(input), reason: input);
        expect(analysis.matches, isEmpty, reason: input);
      }
      expect(
        parseNumericDate(
          '11/25/27',
          order: NumericDateOrder.dayMonthYear,
          today: today,
        ),
        isNull,
      );
      expect(
        parseNumericDate(
          '29.02.28',
          order: NumericDateOrder.dayMonthYear,
          today: today,
        ),
        DateTime(2028, 2, 29),
      );
    },
  );

  test('numeric normalization preserves metadata and ordinary numbers', () {
    const input = 'Task #25.11.27 @25.11.27 /25.11.27 4-5 25.11.27 23:30-01:00';
    final analysis = const QuickAddParser().analyze(input, now: today);
    final parsed = analysis.parsed;
    expect(parsed.content, 'Task 4-5');
    expect(parsed.project, '25.11.27');
    expect(parsed.labels, ['25.11.27']);
    expect(parsed.section, '25.11.27');
    expect(parsed.schedule!.start!.toLocal(), DateTime(2027, 11, 25, 23, 30));
    expect(parsed.schedule!.end!.toLocal(), DateTime(2027, 11, 26, 1));
    final date = analysis.matches.singleWhere(
      (m) => m.kind == QuickAddTokenKind.date,
    );
    expect(input.substring(date.start, date.end), '25.11.27');
    for (final text in ['٢٥.١١.٢٧', '۲۵.۱۱.۲۷', '２５.１１.２７']) {
      expect(
        parseNumericDate(
          text,
          order: NumericDateOrder.dayMonthYear,
          today: today,
        ),
        DateTime(2027, 11, 25),
      );
    }
  });
}

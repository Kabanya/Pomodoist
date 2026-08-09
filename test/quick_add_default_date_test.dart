import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/features/planning/domain/quick_add_parser.dart';

void main() {
  test('localized explicit date overrides a conflicting default date', () {
    final parsed = const QuickAddParser().parse(
      'Подготовить отчёт завтра 08:15',
      now: DateTime(2026, 5, 1, 12),
      defaultDate: DateTime(2026, 5, 9),
    );

    expect(parsed.dueDate, DateTime(2026, 5, 2));
    expect(parsed.schedule!.start!.toLocal(), DateTime(2026, 5, 2, 8, 15));
  });
}

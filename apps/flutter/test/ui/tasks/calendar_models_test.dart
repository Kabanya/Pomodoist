import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/domain/models/tasks/calendar_models.dart';

void main() {
  test('routine periods reject overlap and out-of-day bounds', () {
    expect(
      () => CalendarPeriod(name: 'bad', startMinutes: 100, endMinutes: 100),
      throwsArgumentError,
    );
    expect(
      () => CalendarPeriod(name: 'bad', startMinutes: -1, endMinutes: 60),
      throwsArgumentError,
    );
    expect(
      () => CalendarSettings(
        periods: [
          CalendarPeriod(name: 'A', startMinutes: 540, endMinutes: 720),
          CalendarPeriod(name: 'B', startMinutes: 700, endMinutes: 900),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('settings JSON round trips saved routine', () {
    final saved = CalendarSettings(
      mode: CalendarMode.routine,
      routineName: 'My day',
      periods: [
        CalendarPeriod(name: 'Focus', startMinutes: 600, endMinutes: 780),
      ],
    );
    final restored = CalendarSettings.fromJsonString(saved.toJsonString());
    expect(restored.mode, CalendarMode.routine);
    expect(restored.routineName, 'My day');
    expect(restored.periods.single.startMinutes, 600);
    expect(restored.periods.single.endMinutes, 780);
  });
}

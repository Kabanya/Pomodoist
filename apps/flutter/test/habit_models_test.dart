import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/domain/models/habits/habit_models.dart';
import 'package:pomodoist/domain/models/habits/habit_icons.dart';

void main() {
  test(
    'sign editing accepts catalog and whole emoji and rejects arbitrary text',
    () {
      for (final value in ['bookOpen', '👍🏽', '🇷🇺', '👨‍👩‍👧‍👦', '❤️']) {
        expect(normalizeHabitIcon(' $value '), value);
      }
      expect(normalizeHabitIcon(null), isNull);
      for (final value in ['', ' ', 'futureIcon', 'hello', '😀😀', '😀' * 33]) {
        expect(() => normalizeHabitIcon(value), throwsArgumentError);
      }
    },
  );
  test(
    'habit JSON preserves icons, complete emoji and unknown future signs',
    () {
      final base = Habit(
        id: 'h',
        userId: 'local-user',
        title: 'Read',
        scheduleHistory: [
          HabitSchedule(
            effectiveFrom: DateTime(2026, 10, 6),
            startDate: DateTime(2026, 10, 6),
            weekdays: [1, 2, 3, 4, 5, 6, 7],
            targetPerDay: 1,
          ),
        ],
        createdAt: DateTime.utc(2026, 10, 6),
        updatedAt: DateTime.utc(2026, 10, 6),
      ).toJson();
      for (final icon in [
        'bookOpen',
        '👍🏽',
        '🇷🇺',
        '👨‍👩‍👧‍👦',
        'futureIcon',
      ]) {
        expect(Habit.fromJson({...base, 'icon': icon}).toJson()['icon'], icon);
      }
      expect(
        Habit.fromJson({...base}..remove('icon')).toJson()['icon'],
        isNull,
      );
      expect(Habit.fromJson({...base, 'icon': null}).toJson()['icon'], isNull);
    },
  );
  test('calendar duration includes its first and last day across a year', () {
    expect(habitEndAfterDays(DateTime(2026, 12, 29), 7), DateTime(2027, 1, 4));
    expect(habitEndAfterDays(DateTime(2028, 2, 28), 7), DateTime(2028, 3, 5));
    for (final days in [7, 21, 30, 365]) {
      expect(
        habitEndAfterDays(
          DateTime(2026, 1, 1),
          days,
        ).difference(DateTime(2026, 1, 1)).inDays,
        days - 1,
      );
    }
  });
  test('weekdays and both bounds determine scheduled days', () {
    final schedule = HabitSchedule(
      effectiveFrom: DateTime(2026, 9, 28),
      startDate: DateTime(2026, 9, 28),
      endDate: DateTime(2026, 10, 2),
      weekdays: const [1, 3, 5],
      targetPerDay: 3,
    );
    expect(schedule.includes(DateTime(2026, 9, 27)), isFalse);
    expect(schedule.includes(DateTime(2026, 9, 28)), isTrue);
    expect(schedule.includes(DateTime(2026, 9, 29)), isFalse);
    expect(schedule.includes(DateTime(2026, 9, 30, 22)), isTrue);
    expect(schedule.includes(DateTime(2026, 10, 2)), isTrue);
    expect(schedule.includes(DateTime(2026, 10, 5)), isFalse);
  });
  test('schedule revisions preserve past goals and replace todays goal', () {
    final habit = Habit(
      id: 'h',
      userId: 'local-user',
      title: 'Read',
      scheduleHistory: [
        HabitSchedule(
          effectiveFrom: DateTime(2026, 9, 28),
          startDate: DateTime(2026, 9, 28),
          weekdays: const [1, 2, 3, 4, 5, 6, 7],
          targetPerDay: 1,
        ),
        HabitSchedule(
          effectiveFrom: DateTime(2026, 9, 30),
          startDate: DateTime(2026, 9, 28),
          weekdays: const [1, 2, 3, 4, 5, 6, 7],
          targetPerDay: 3,
        ),
      ],
      createdAt: DateTime.utc(2026, 9, 28),
      updatedAt: DateTime.utc(2026, 9, 30),
    );
    expect(habit.scheduleFor(DateTime(2026, 9, 29))!.targetPerDay, 1);
    expect(habit.scheduleFor(DateTime(2026, 9, 30))!.targetPerDay, 3);
    expect(
      Habit.fromJson(
        habit.toJson(),
      ).scheduleFor(DateTime(2026, 9, 29))!.targetPerDay,
      1,
    );
  });
  test(
    'date keys preserve local calendar fields and reject normalized dates',
    () {
      expect(habitDayKey(DateTime(2026, 3, 29, 23, 59)), '2026-03-29');
      expect(habitDateFromKey('2026-03-29'), DateTime(2026, 3, 29));
      expect(() => habitDateFromKey('2026-02-30'), throwsFormatException);
      expect(
        () => habitDateFromKey('2026-03-29T00:00:00Z'),
        throwsFormatException,
      );
    },
  );
  test('invalid goals, weekdays and reversed end cannot enter domain', () {
    HabitSchedule make({
      int target = 1,
      List<int> days = const [1],
      DateTime? end,
    }) => HabitSchedule(
      effectiveFrom: DateTime(2026, 9, 30),
      startDate: DateTime(2026, 9, 30),
      endDate: end,
      weekdays: days,
      targetPerDay: target,
    );
    expect(() => make(target: 0), throwsArgumentError);
    expect(() => make(target: 100), throwsArgumentError);
    expect(() => make(days: []), throwsArgumentError);
    expect(() => make(days: [0]), throwsArgumentError);
    expect(() => make(days: [1, 1]), throwsArgumentError);
    expect(() => make(end: DateTime(2026, 9, 29)), throwsArgumentError);
  });
}

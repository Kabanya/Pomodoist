import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/formatters.dart';
import 'package:pomodoist/app/task_time.dart';
import 'package:pomodoist/features/tasks/domain/task_models.dart';
import 'package:pomodoist/l10n/app_localizations.dart';

void main() {
  testWidgets('formatTaskListSchedule formats English relative dates', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 5, 12);

    expect(
      await _format(tester, const Locale('en'), _timed(2026, 7, 5), now),
      'Today 14:00',
    );
    expect(
      await _format(tester, const Locale('en'), _timed(2026, 7, 4), now),
      'Yesterday 14:00',
    );
    expect(
      await _format(tester, const Locale('en'), _timed(2026, 7, 6), now),
      'Tomorrow 14:00',
    );
    expect(
      await _format(tester, const Locale('en'), _timed(2026, 7, 9), now),
      'July 9 14:00',
    );
    expect(
      await _format(
        tester,
        const Locale('en'),
        TaskSchedule.allDay(
          DateTime(2026, 7, 5),
          recurrence: const TaskRecurrence(
            interval: 2,
            unit: TaskRecurrenceUnit.week,
            seriesId: 'series',
          ),
        ),
        now,
      ),
      'Today, every 2 weeks',
    );
    expect(
      await _format(
        tester,
        const Locale('en'),
        TaskSchedule.allDay(DateTime(2026, 7, 5), recurrenceSeriesId: 'series'),
        now,
      ),
      'Today',
    );
  });

  testWidgets('formatTaskListSchedule formats Russian relative dates', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 5, 12);

    expect(
      await _format(tester, const Locale('ru'), _timed(2026, 7, 5), now),
      'Сегодня 14:00',
    );
    expect(
      await _format(tester, const Locale('ru'), _timed(2026, 7, 4), now),
      'Вчера 14:00',
    );
    expect(
      await _format(tester, const Locale('ru'), _timed(2026, 7, 6), now),
      'Завтра 14:00',
    );
    expect(
      await _format(tester, const Locale('ru'), _timed(2026, 7, 9), now),
      '9 июля 14:00',
    );
    expect(
      await _format(
        tester,
        const Locale('ru'),
        TaskSchedule.allDay(DateTime(2026, 7, 5)),
        now,
      ),
      'Сегодня',
    );
  });

  testWidgets('within-date schedule formats time without repeating date', (
    tester,
  ) async {
    expect(
      await _formatWithinDate(
        tester,
        const Locale('en'),
        _timed(2026, 7, 5),
        alwaysUse24HourFormat: true,
      ),
      '14:00',
    );
    expect(
      await _formatWithinDate(
        tester,
        const Locale('en'),
        _timed(
          2026,
          7,
          5,
          recurrence: const TaskRecurrence(
            interval: 2,
            unit: TaskRecurrenceUnit.week,
            seriesId: 'timed-series',
          ),
        ),
        alwaysUse24HourFormat: true,
      ),
      '14:00, every 2 weeks',
    );
  });

  testWidgets('within-date schedule omits plain all-day date', (tester) async {
    expect(
      await _formatWithinDate(
        tester,
        const Locale('en'),
        TaskSchedule.allDay(DateTime(2026, 7, 5)),
      ),
      isNull,
    );
  });

  testWidgets('within-date schedule keeps all-day recurrence', (tester) async {
    expect(
      await _formatWithinDate(
        tester,
        const Locale('en'),
        TaskSchedule.allDay(
          DateTime(2026, 7, 5),
          recurrence: const TaskRecurrence(
            interval: 2,
            unit: TaskRecurrenceUnit.week,
            seriesId: 'all-day-series',
          ),
        ),
      ),
      'every 2 weeks',
    );
  });

  testWidgets('within-date schedule respects 12 and 24 hour preferences', (
    tester,
  ) async {
    expect(
      await _formatWithinDate(
        tester,
        const Locale('en'),
        _timed(2026, 7, 5),
        alwaysUse24HourFormat: false,
      ),
      '2:00 PM',
    );
    expect(
      await _formatWithinDate(
        tester,
        const Locale('en'),
        _timed(2026, 7, 5),
        alwaysUse24HourFormat: true,
      ),
      '14:00',
    );
  });

  testWidgets('task schedules honor smart, range, and start-only modes', (
    tester,
  ) async {
    final standardBlock = _timed(2026, 7, 5);
    final customBlock = _timed(2026, 7, 5, endMinute: 45);

    expect(
      await _formatWithMode(tester, standardBlock, TaskTimeDisplayMode.smart),
      'Today 14:00',
    );
    expect(
      await _formatWithMode(tester, customBlock, TaskTimeDisplayMode.smart),
      'Today 14:00-14:45',
    );
    expect(
      await _formatWithMode(tester, standardBlock, TaskTimeDisplayMode.range),
      'Today 14:00-14:30',
    );
    expect(
      await _formatWithMode(tester, customBlock, TaskTimeDisplayMode.startOnly),
      'Today 14:00',
    );
  });

  testWidgets(
    'range mode preserves cross-day dates, recurrence, and 12-hour time',
    (tester) async {
      final schedule = TaskSchedule.timed(
        start: DateTime(2026, 7, 5, 23, 30),
        end: DateTime(2026, 7, 6, 0, 15),
        recurrence: const TaskRecurrence(
          interval: 2,
          unit: TaskRecurrenceUnit.week,
          seriesId: 'series',
        ),
      );

      expect(
        await _formatWithinDateWithMode(
          tester,
          schedule,
          TaskTimeDisplayMode.range,
          alwaysUse24HourFormat: false,
        ),
        '11:30 PM-Mon, Jul 6 12:15 AM, every 2 weeks',
      );
    },
  );
}

TaskSchedule _timed(
  int year,
  int month,
  int day, {
  TaskRecurrence? recurrence,
  int endMinute = 30,
}) {
  return TaskSchedule.timed(
    start: DateTime(year, month, day, 14),
    end: DateTime(year, month, day, 14, endMinute),
    recurrence: recurrence,
  );
}

Future<String> _formatWithMode(
  WidgetTester tester,
  TaskSchedule schedule,
  TaskTimeDisplayMode displayMode,
) async {
  var value = '';
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(alwaysUse24HourFormat: true),
        child: Builder(
          builder: (context) {
            value = formatTaskListSchedule(
              context,
              schedule,
              now: DateTime(2026, 7, 5, 12),
              displayMode: displayMode,
              defaultTimedBlockMinutes: 30,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return value;
}

Future<String?> _formatWithinDateWithMode(
  WidgetTester tester,
  TaskSchedule schedule,
  TaskTimeDisplayMode displayMode, {
  required bool alwaysUse24HourFormat,
}) async {
  String? value;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(alwaysUse24HourFormat: alwaysUse24HourFormat),
        child: Builder(
          builder: (context) {
            value = formatTaskListScheduleWithinDate(
              context,
              schedule,
              displayMode: displayMode,
              defaultTimedBlockMinutes: 30,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return value;
}

Future<String> _format(
  WidgetTester tester,
  Locale locale,
  TaskSchedule schedule,
  DateTime now,
) async {
  var value = '';
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(alwaysUse24HourFormat: true),
        child: Builder(
          builder: (context) {
            value = formatTaskListSchedule(context, schedule, now: now);
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return value;
}

Future<String?> _formatWithinDate(
  WidgetTester tester,
  Locale locale,
  TaskSchedule schedule, {
  bool alwaysUse24HourFormat = true,
}) async {
  String? value;
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(alwaysUse24HourFormat: alwaysUse24HourFormat),
        child: Builder(
          builder: (context) {
            value = formatTaskListScheduleWithinDate(context, schedule);
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return value;
}

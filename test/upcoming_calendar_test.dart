import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/theme/app_theme.dart';
import 'package:pomodoist/features/tasks/presentation/widgets/upcoming_calendar.dart';
import 'package:pomodoist/l10n/app_localizations.dart';

void main() {
  final today = DateTime(2026, 12, 30);

  group('UpcomingCalendar layout and paging', () {
    testWidgets('shows 7 days at 759 and 14 days at 760', (tester) async {
      await _pumpCalendar(tester, width: 759, today: today);

      expect(_visibleDayCells(), findsNWidgets(7));

      await _pumpCalendar(tester, width: 760, today: today);

      expect(_visibleDayCells(), findsNWidgets(14));
    });

    testWidgets('uses the locale first day of week', (tester) async {
      await _pumpCalendar(
        tester,
        width: 390,
        today: today,
        locale: const Locale('de'),
      );

      expect(
        find.byKey(const ValueKey('upcoming-calendar-day-2026-12-28')),
        findsOneWidget,
      );
      expect(_visibleDayCells(), findsNWidgets(7));
    });

    testWidgets('keeps calendar dates normalized across a DST transition', (
      tester,
    ) async {
      final dstDay = DateTime(2026, 3, 8);
      final nextDay = DateTime(2026, 3, 9);
      await _pumpCalendar(
        tester,
        width: 390,
        today: dstDay,
        scheduledCounts: {nextDay: 1},
      );

      expect(_dayFinder(nextDay), findsOneWidget);
      expect(_dotsFor(nextDay), findsOneWidget);
    });

    testWidgets('narrow arrows move 7 days across a year boundary', (
      tester,
    ) async {
      await _pumpCalendar(tester, width: 759, today: today);

      expect(
        find.byKey(const ValueKey('upcoming-calendar-day-2026-12-27')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('upcoming-calendar-next')));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('upcoming-calendar-day-2027-01-03')),
        findsOneWidget,
      );
      expect(_visibleDayCells(), findsNWidgets(7));

      await tester.tap(
        find.byKey(const ValueKey('upcoming-calendar-previous')),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('upcoming-calendar-day-2026-12-27')),
        findsOneWidget,
      );
    });

    testWidgets('wide arrows move 14 days across a year boundary', (
      tester,
    ) async {
      await _pumpCalendar(tester, width: 760, today: today);

      await tester.tap(find.byKey(const ValueKey('upcoming-calendar-next')));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('upcoming-calendar-day-2027-01-10')),
        findsOneWidget,
      );
      expect(_visibleDayCells(), findsNWidgets(14));
    });

    testWidgets('narrow horizontal swipe moves 7 days', (tester) async {
      await _pumpCalendar(tester, width: 759, today: today);

      await tester.drag(
        find.byKey(const ValueKey('upcoming-calendar-days')),
        const Offset(-500, 0),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('upcoming-calendar-day-2027-01-03')),
        findsOneWidget,
      );
      expect(_visibleDayCells(), findsNWidgets(7));
    });

    testWidgets('wide month control opens an anchored popover', (tester) async {
      await _pumpCalendar(tester, width: 760, today: today);

      await tester.tap(find.byKey(const ValueKey('upcoming-calendar-month')));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.byKey(const ValueKey('upcoming-calendar-month-popover')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('upcoming-calendar-month-sheet')),
        findsNothing,
      );
      expect(find.byType(CalendarDatePicker), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('narrow month control opens a safe-area bottom sheet', (
      tester,
    ) async {
      await _pumpCalendar(tester, width: 759, today: today);

      await tester.tap(find.byKey(const ValueKey('upcoming-calendar-month')));
      await tester.pump(const Duration(milliseconds: 300));

      final sheet = find.byKey(const ValueKey('upcoming-calendar-month-sheet'));
      expect(sheet, findsOneWidget);
      expect(
        find.byKey(const ValueKey('upcoming-calendar-month-popover')),
        findsNothing,
      );
      expect(find.byType(CalendarDatePicker), findsOneWidget);
      expect(
        find.ancestor(of: sheet, matching: find.byType(SafeArea)),
        findsOneWidget,
      );

      Navigator.of(tester.element(sheet)).pop();
      await tester.pump(const Duration(milliseconds: 300));
    });
  });

  group('UpcomingCalendar anchoring and activation', () {
    testWidgets('initially anchors to the selected date week', (tester) async {
      await _pumpCalendar(
        tester,
        width: 759,
        today: today,
        selectedDate: DateTime(2027, 2, 17, 18, 30),
      );

      expect(
        find.byKey(const ValueKey('upcoming-calendar-day-2027-02-14')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('upcoming-calendar-day-2026-12-27')),
        findsNothing,
      );
    });

    testWidgets('new selection re-anchors and clearing returns to today', (
      tester,
    ) async {
      await _pumpCalendar(
        tester,
        width: 759,
        today: today,
        selectedDate: DateTime(2027, 2, 17),
      );

      await _pumpCalendar(
        tester,
        width: 759,
        today: today,
        selectedDate: DateTime(2027, 3, 20),
      );

      expect(
        find.byKey(const ValueKey('upcoming-calendar-day-2027-03-14')),
        findsOneWidget,
      );

      await _pumpCalendar(tester, width: 759, today: today);

      expect(
        find.byKey(const ValueKey('upcoming-calendar-day-2026-12-27')),
        findsOneWidget,
      );
    });

    testWidgets('today action selects today and repeated today cell clears', (
      tester,
    ) async {
      var clearCalls = 0;
      var todaySelections = 0;
      await _pumpCalendar(
        tester,
        width: 759,
        today: today,
        onClearSelection: () => clearCalls += 1,
        onTodaySelected: () => todaySelections += 1,
      );

      await tester.tap(find.byKey(const ValueKey('upcoming-calendar-next')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('upcoming-calendar-today')));
      await tester.pump();

      expect(todaySelections, 1);
      expect(clearCalls, 0);
      expect(
        find.byKey(const ValueKey('upcoming-calendar-day-2026-12-27')),
        findsOneWidget,
      );

      await _pumpCalendar(
        tester,
        width: 759,
        today: today,
        selectedDate: today,
        onClearSelection: () => clearCalls += 1,
        onTodaySelected: () => todaySelections += 1,
      );
      await tester.tap(
        find.byKey(const ValueKey('upcoming-calendar-day-2026-12-30')),
      );
      await tester.pump();

      expect(clearCalls, 1);
      expect(todaySelections, 1);
    });

    testWidgets('past dates are muted but selectable', (tester) async {
      final semantics = tester.ensureSemantics();
      final selected = <DateTime>[];
      await _pumpCalendar(
        tester,
        width: 759,
        today: today,
        scheduledCounts: {DateTime(2026, 12, 29): 1},
        onDateSelected: selected.add,
      );

      final past = find.byKey(
        const ValueKey('upcoming-calendar-day-2026-12-29'),
      );
      final future = find.byKey(
        const ValueKey('upcoming-calendar-day-2026-12-31'),
      );

      await tester.tap(past);
      await tester.tap(future);
      await tester.pump();

      expect(selected, [DateTime(2026, 12, 29), DateTime(2026, 12, 31)]);
      expect(
        tester.getSemantics(past).flagsCollection.isEnabled,
        Tristate.isTrue,
      );
      expect(
        tester.getSemantics(future).flagsCollection.isEnabled,
        Tristate.isTrue,
      );
      final pastDayText = tester.widget<Text>(
        find.descendant(of: past, matching: find.text('29')),
      );
      expect(
        pastDayText.style?.color,
        tester.element(past).appColors.mutedText,
      );
      final pastDot = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('upcoming-calendar-dot-2026-12-29-0')),
      );
      expect(
        (pastDot.decoration as BoxDecoration).color,
        tester.element(past).appColors.mutedText,
      );

      await _pumpCalendar(
        tester,
        width: 759,
        today: today,
        selectedDate: DateTime(2026, 12, 29),
        scheduledCounts: {DateTime(2026, 12, 29): 1},
      );

      expect(
        find.byKey(
          const ValueKey('upcoming-calendar-selected-marker-2026-12-29'),
        ),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(past).flagsCollection.isSelected,
        Tristate.isTrue,
      );
      final selectedPastDayText = tester.widget<Text>(
        find.descendant(of: past, matching: find.text('29')),
      );
      expect(
        selectedPastDayText.style?.color,
        tester.element(past).appColors.mutedText,
      );
      semantics.dispose();
    });

    testWidgets('picker selection uses the same past-date callback', (
      tester,
    ) async {
      final selected = <DateTime>[];
      await _pumpCalendar(
        tester,
        width: 759,
        today: today,
        onDateSelected: selected.add,
      );

      await tester.tap(find.byKey(const ValueKey('upcoming-calendar-month')));
      await tester.pump(const Duration(milliseconds: 300));
      final picker = tester.widget<CalendarDatePicker>(
        find.byType(CalendarDatePicker),
      );
      expect(picker.firstDate, DateTime(1926, 1, 1));
      picker.onDateChanged(DateTime(2026, 12, 29));
      await tester.pump(const Duration(milliseconds: 300));

      expect(selected, [DateTime(2026, 12, 29)]);
      expect(
        find.byKey(const ValueKey('upcoming-calendar-month-sheet')),
        findsNothing,
      );
    });
  });

  group('UpcomingCalendar load and visual semantics', () {
    testWidgets('uses 0, 1, 2, or 3 dots and exposes the uncapped count', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final zero = DateTime(2026, 12, 29, 12);
      final one = DateTime(2026, 12, 30, 12);
      final two = DateTime(2026, 12, 31, 12);
      final many = DateTime(2027, 1, 1, 12);
      await _pumpCalendar(
        tester,
        width: 759,
        today: today,
        scheduledCounts: {zero: 0, one: 1, two: 2, many: 12},
      );

      expect(_dotsFor(zero), findsNothing);
      expect(_dotsFor(one), findsOneWidget);
      expect(_dotsFor(two), findsNWidgets(2));
      expect(_dotsFor(many), findsNWidgets(3));
      expect(tester.getSemantics(_dayFinder(zero)).label, contains('0'));
      expect(tester.getSemantics(_dayFinder(many)).label, contains('12'));
      semantics.dispose();
    });

    testWidgets('today and selected dates have distinct non-color markers', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pumpCalendar(
        tester,
        width: 759,
        today: today,
        selectedDate: DateTime(2026, 12, 31),
      );

      final todayCell = _dayFinder(today);
      final selectedCell = _dayFinder(DateTime(2026, 12, 31));
      expect(tester.getSemantics(todayCell).label, contains('Today'));
      expect(
        tester.getSemantics(selectedCell).flagsCollection.isSelected,
        Tristate.isTrue,
      );
      expect(
        find.byKey(const ValueKey('upcoming-calendar-today-marker-2026-12-30')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('upcoming-calendar-selected-marker-2026-12-31'),
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });

  group('UpcomingCalendar keyboard and focus', () {
    testWidgets('right arrow and enter select tomorrow in LTR', (tester) async {
      final selected = <DateTime>[];
      await _pumpCalendar(
        tester,
        width: 759,
        today: today,
        onDateSelected: selected.add,
      );
      await _focusRail(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(selected, [DateTime(2026, 12, 31)]);
    });

    testWidgets('left arrow moves forward visually in RTL', (tester) async {
      final selected = <DateTime>[];
      await _pumpCalendar(
        tester,
        width: 759,
        today: today,
        locale: const Locale('ar'),
        onDateSelected: selected.add,
      );
      await _focusRail(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(selected, [DateTime(2026, 12, 31)]);
    });

    testWidgets('home end page up and page down move the roving date', (
      tester,
    ) async {
      final cases = <(LogicalKeyboardKey, LogicalKeyboardKey, DateTime)>[
        (
          LogicalKeyboardKey.home,
          LogicalKeyboardKey.enter,
          DateTime(2027, 1, 17),
        ),
        (
          LogicalKeyboardKey.end,
          LogicalKeyboardKey.space,
          DateTime(2027, 1, 23),
        ),
        (
          LogicalKeyboardKey.pageUp,
          LogicalKeyboardKey.enter,
          DateTime(2027, 1, 13),
        ),
        (
          LogicalKeyboardKey.pageDown,
          LogicalKeyboardKey.enter,
          DateTime(2027, 1, 27),
        ),
        (
          LogicalKeyboardKey.arrowUp,
          LogicalKeyboardKey.enter,
          DateTime(2027, 1, 13),
        ),
        (
          LogicalKeyboardKey.arrowDown,
          LogicalKeyboardKey.enter,
          DateTime(2027, 1, 27),
        ),
      ];

      for (final (movement, activation, expected) in cases) {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        final selected = <DateTime>[];
        await _pumpCalendar(
          tester,
          width: 759,
          today: today,
          selectedDate: DateTime(2027, 1, 20),
          onDateSelected: selected.add,
        );
        await _focusRail(tester);

        await tester.sendKeyEvent(movement);
        await tester.pump();
        await tester.sendKeyEvent(activation);
        await tester.pump();

        expect(selected, [expected], reason: movement.debugName);
      }
    });

    testWidgets('keyboard selects a past date', (tester) async {
      final selected = <DateTime>[];
      await _pumpCalendar(
        tester,
        width: 759,
        today: today,
        onDateSelected: selected.add,
      );
      await _focusRail(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(selected, [DateTime(2026, 12, 29)]);
    });

    testWidgets('wide to narrow resize keeps the roving date visible', (
      tester,
    ) async {
      final selected = <DateTime>[];
      await _pumpCalendar(
        tester,
        width: 760,
        today: today,
        onDateSelected: selected.add,
      );
      await _focusRail(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();

      await _pumpCalendar(
        tester,
        width: 759,
        today: today,
        onDateSelected: selected.add,
      );

      expect(
        find.byKey(const ValueKey('upcoming-calendar-day-2027-01-03')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('upcoming-calendar-day-2027-01-09')),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(selected, [DateTime(2027, 1, 9)]);
    });

    testWidgets(
      'focus returns to the month opener after either picker closes',
      (tester) async {
        for (final width in <double>[760, 759]) {
          await _pumpCalendar(tester, width: width, today: today);
          await tester.tap(
            find.byKey(const ValueKey('upcoming-calendar-month')),
          );
          await tester.pump(const Duration(milliseconds: 300));

          if (width >= 760) {
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          } else {
            final sheet = find.byKey(
              const ValueKey('upcoming-calendar-month-sheet'),
            );
            Navigator.of(tester.element(sheet)).pop();
          }
          await tester.pump(const Duration(milliseconds: 300));

          final opener = tester.widget<TextButton>(
            find.byKey(const ValueKey('upcoming-calendar-month')),
          );
          expect(opener.focusNode?.hasFocus, isTrue, reason: 'width $width');
        }
      },
    );
  });

  group('UpcomingCalendar resilient rendering', () {
    testWidgets('loading keeps day layout stable and uses a small indicator', (
      tester,
    ) async {
      await _pumpCalendar(tester, width: 759, today: today);
      final before = tester.getRect(_dayFinder(today));

      await _pumpCalendar(tester, width: 759, today: today, loading: true);
      final after = tester.getRect(_dayFinder(today));
      final indicator = find.byKey(const ValueKey('upcoming-calendar-loading'));

      expect(after.size, before.size);
      expect(indicator, findsOneWidget);
      expect(tester.getSize(indicator).longestSide, lessThanOrEqualTo(18));
    });

    testWidgets('dark theme and 2x text render without overflow', (
      tester,
    ) async {
      await _pumpCalendar(
        tester,
        width: 320,
        today: today,
        selectedDate: DateTime(2026, 12, 31),
        scheduledCounts: {DateTime(2026, 12, 31): 4},
        loading: true,
        theme: AppTheme.dark(),
        textScaler: const TextScaler.linear(2),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(_visibleDayCells(), findsNWidgets(7));
    });

    testWidgets('controls and day cells meet the 48dp target minimum', (
      tester,
    ) async {
      await _pumpCalendar(tester, width: 320, today: today);

      for (final key in const [
        'upcoming-calendar-previous',
        'upcoming-calendar-next',
        'upcoming-calendar-month',
        'upcoming-calendar-today',
      ]) {
        final size = tester.getSize(find.byKey(ValueKey(key)));
        expect(size.width, greaterThanOrEqualTo(48), reason: key);
        expect(size.height, greaterThanOrEqualTo(48), reason: key);
      }

      final daySize = tester.getSize(_dayFinder(today));
      expect(daySize.width, greaterThanOrEqualTo(48));
      expect(daySize.height, greaterThanOrEqualTo(48));
    });
  });
}

Finder _visibleDayCells() {
  return find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> &&
        key.value.startsWith('upcoming-calendar-day-');
  });
}

Finder _dayFinder(DateTime date) {
  return find.byKey(ValueKey('upcoming-calendar-day-${_dateKey(date)}'));
}

Finder _dotsFor(DateTime date) {
  return find.descendant(
    of: _dayFinder(date),
    matching: find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('upcoming-calendar-dot-${_dateKey(date)}-');
    }),
  );
}

String _dateKey(DateTime date) {
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${twoDigits(date.month)}-${twoDigits(date.day)}';
}

Future<void> _focusRail(WidgetTester tester) async {
  final focus = tester.widget<Focus>(
    find.byKey(const ValueKey('upcoming-calendar-focus')),
  );
  focus.focusNode!.requestFocus();
  await tester.pump();
}

Future<void> _pumpCalendar(
  WidgetTester tester, {
  required double width,
  required DateTime today,
  DateTime? selectedDate,
  Map<DateTime, int> scheduledCounts = const {},
  bool loading = false,
  ValueChanged<DateTime>? onDateSelected,
  VoidCallback? onClearSelection,
  VoidCallback? onTodaySelected,
  Locale locale = const Locale('en', 'US'),
  ThemeData? theme,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: theme ?? AppTheme.light(),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        );
      },
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: UpcomingCalendar(
              today: today,
              selectedDate: selectedDate,
              scheduledCounts: scheduledCounts,
              loading: loading,
              onDateSelected: onDateSelected ?? (_) {},
              onClearSelection: onClearSelection ?? () {},
              onTodaySelected: onTodaySelected ?? () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

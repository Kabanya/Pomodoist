import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/ui/core/widgets/app_zoom.dart';
import 'package:pomodoist/ui/core/view_models/app_zoom_view_model.dart';
import 'package:pomodoist/domain/models/settings/app_date_format.dart';
import 'package:pomodoist/ui/core/localization/app_date_formatter.dart';
import 'support/test_app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/ui/core/localization/app_localizations.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/widgets/app_date_time_picker.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Future<void> openPicker(
  WidgetTester tester,
  Future<void> Function(AppDateTimePickerState) open, {
  bool dark = false,
  Locale locale = const Locale('en'),
  AppDateFormat format = AppDateFormat.automatic,
  double textScale = 1,
  int zoom = 100,
}) async {
  final theme = dark ? AppTheme.dark() : AppTheme.light();
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.binding.setSurfaceSize(const Size(1000, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ShadApp.custom(
      theme: AppTheme.shadFromMaterial(theme),
      appBuilder: (_) => MaterialApp(
        theme: theme,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => AppDateFormatScope(
          format: format,
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: zoom == 100
                ? testAppBuilder(context, child)
                : ProviderScope(
                    overrides: [
                      appZoomProvider.overrideWith(() => _PickerZoom(zoom)),
                    ],
                    child: AppZoom(child: testAppBuilder(context, child)),
                  ),
          ),
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: AppDateTimePicker(
              builder: (context, picker) => TextButton(
                focusNode: picker.focusNode,
                onPressed: () => open(picker),
                child: const Text('Open picker'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open picker'));
  await tester.pumpAndSettle();
}

class _PickerZoom extends AppZoomController {
  _PickerZoom(this.zoom);
  final int zoom;
  @override
  int build() => zoom;
}

void main() {
  setUpAll(loadTestAppResources);
  testWidgets('time adjustments wrap midnight and invalid fields cannot save', (
    tester,
  ) async {
    TimeOfDay? result;
    await openPicker(tester, (picker) async {
      result = await picker.pickTime(
        initialTime: const TimeOfDay(hour: 23, minute: 55),
      );
    });
    await tester.tap(find.byKey(const Key('picker-offset-15')));
    await tester.pumpAndSettle();
    expect(result, isNull);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result, const TimeOfDay(hour: 0, minute: 10));

    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('picker-hour')),
        matching: find.byType(EditableText),
      ),
      '',
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ShadButton>(find.widgetWithText(ShadButton, 'Save'))
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<ShadButton>(find.byKey(const Key('picker-offset-15')))
          .enabled,
      isFalse,
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('picker-hour')),
        matching: find.byType(EditableText),
      ),
      '99',
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ShadButton>(find.widgetWithText(ShadButton, 'Save'))
          .enabled,
      isFalse,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsNothing);
    expect(result, isNull);
  });

  testWidgets('schedule keeps the date and time draft until one confirmation', (
    tester,
  ) async {
    ({DateTime date, TimeOfDay? time})? result;
    await openPicker(tester, (picker) async {
      result = await picker.pickSchedule(
        initialDate: DateTime(2026, 11, 2),
        initialTime: const TimeOfDay(hour: 15, minute: 30),
        initialAllDay: false,
        firstDate: DateTime(2026),
        lastDate: DateTime(2027),
      );
    }, dark: true);
    await tester.tap(find.byKey(const Key('picker-all-day')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('picker-all-day')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('picker-time-input-toggle')));
    await tester.pumpAndSettle();
    expect(result, isNull);
    await tester.enterText(
      find.byKey(const Key('picker-date-input')),
      '11/03/2026',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result, (
      date: DateTime(2026, 11, 3),
      time: const TimeOfDay(hour: 15, minute: 30),
    ));
  });

  testWidgets(
    'narrow schedule preserves its draft and leaves actions above the keyboard',
    (tester) async {
      ({DateTime date, TimeOfDay? time})? result;
      await openPicker(tester, (picker) async {
        result = await picker.pickSchedule(
          initialDate: DateTime(2026, 11, 2),
          initialTime: const TimeOfDay(hour: 15, minute: 30),
          initialAllDay: false,
          firstDate: DateTime(2026),
          lastDate: DateTime(2027),
        );
      });
      await tester.tap(find.byKey(const Key('picker-time-input-toggle')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('picker-minute')),
          matching: find.byType(EditableText),
        ),
        '42',
      );
      await tester.binding.setSurfaceSize(const Size(390, 844));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final save = find.widgetWithText(ShadButton, 'Save');
      expect(tester.getRect(save).bottom, lessThanOrEqualTo(544));
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(result, (
        date: DateTime(2026, 11, 2),
        time: const TimeOfDay(hour: 15, minute: 42),
      ));
    },
  );

  testWidgets('AM/PM and cancelling a schedule preserve caller state', (
    tester,
  ) async {
    var calls = 0;
    TimeOfDay? result;
    await openPicker(tester, (picker) async {
      result = await picker.pickTime(
        initialTime: const TimeOfDay(hour: 11, minute: 59),
      );
      calls++;
    });
    await tester.tap(find.byKey(const Key('picker-offset-5')));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result, const TimeOfDay(hour: 12, minute: 4));
    expect(calls, 1);
    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(calls, 2);
  });
  testWidgets(
    'presets, wheel scrolling and manual input share the same draft',
    (tester) async {
      ({DateTime date, TimeOfDay? time})? result;
      final today = DateUtils.dateOnly(DateTime.now());
      await openPicker(tester, (picker) async {
        result = await picker.pickSchedule(
          initialDate: today,
          initialTime: const TimeOfDay(hour: 15, minute: 30),
          initialAllDay: false,
          firstDate: DateTime(today.year),
          lastDate: DateTime(today.year + 1),
        );
      }, locale: const Locale('ru'));
      await tester.tap(find.byKey(const Key('picker-preset-7')));
      await tester.pumpAndSettle();
      final wheel = find.byType(ListWheelScrollView).last;
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(wheel),
          scrollDelta: const Offset(0, 44),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getCenter(wheel));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('picker-time-input-toggle')));
      await tester.pumpAndSettle();
      final minute = find.descendant(
        of: find.byKey(const Key('picker-minute')),
        matching: find.byType(EditableText),
      );
      expect(tester.widget<EditableText>(minute).controller.text, '32');
      await tester.enterText(minute, '59');
      await tester.tap(find.byKey(const Key('picker-time-input-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('picker-time-input-toggle')));
      await tester.pumpAndSettle();
      expect(tester.widget<EditableText>(minute).controller.text, '59');
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(result, (
        date: DateTime(today.year, today.month, today.day + 7),
        time: const TimeOfDay(hour: 15, minute: 59),
      ));
    },
  );

  testWidgets('date-only picker enforces bounds and the custom date order', (
    tester,
  ) async {
    DateTime? result;
    await openPicker(tester, (picker) async {
      result = await picker.pickDate(
        initialDate: DateTime(2026, 11, 2),
        firstDate: DateTime(2026, 11, 1),
        lastDate: DateTime(2026, 11, 3),
      );
    }, format: AppDateFormat.yearMonthDay);
    expect(find.byType(ListWheelScrollView), findsNothing);
    await tester.enterText(
      find.byKey(const Key('picker-date-input')),
      '2026-11-04',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.byKey(const Key('picker-date-input')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('picker-date-input')),
      '2026-11-03',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result, DateTime(2026, 11, 3));
  });

  for (final dark in [false, true]) {
    testWidgets(
      'large text keeps schedule actions usable in ${dark ? "dark" : "light"} theme',
      (tester) async {
        await openPicker(
          tester,
          (picker) async {
            await picker.pickSchedule(
              initialDate: DateTime(2026, 11, 2),
              initialTime: const TimeOfDay(hour: 15, minute: 30),
              initialAllDay: true,
              firstDate: DateTime(2026),
              lastDate: DateTime(2027),
            );
          },
          dark: dark,
          locale: const Locale('ru'),
          textScale: 2,
        );
        await tester.binding.setSurfaceSize(const Size(390, 844));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Сохранить'));
        await tester.pumpAndSettle();
        expect(find.text('Сохранить'), findsNothing);
      },
    );
  }
  testWidgets('200% app zoom keeps a schedule inside overlay coordinates', (
    tester,
  ) async {
    ({DateTime date, TimeOfDay? time})? result;
    await openPicker(tester, (picker) async {
      result = await picker.pickSchedule(
        initialDate: DateTime(2026, 11, 2),
        initialTime: const TimeOfDay(hour: 15, minute: 30),
        initialAllDay: true,
        firstDate: DateTime(2026),
        lastDate: DateTime(2027),
      );
    }, zoom: 200);
    final save = find.widgetWithText(ShadButton, 'Save');
    final rect = tester.getRect(save);
    expect(rect.bottom, lessThanOrEqualTo(900));
    expect(rect.right, lessThanOrEqualTo(1000));
    expect(tester.takeException(), isNull);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(result, (date: DateTime(2026, 11, 2), time: null));
  });
  testWidgets(
    'minute arrows carry through midnight and negative offsets wrap',
    (tester) async {
      TimeOfDay? result;
      await openPicker(tester, (picker) async {
        result = await picker.pickTime(
          initialTime: const TimeOfDay(hour: 23, minute: 59),
        );
      }, locale: const Locale('ru'));
      await tester.tap(find.byKey(const Key('picker-minute-increase')));
      await tester.pumpAndSettle();
      final hour = find.descendant(
        of: find.byKey(const Key('picker-hour')),
        matching: find.byType(EditableText),
      );
      expect(tester.widget<EditableText>(hour).controller.text, '00');
      await tester.tap(find.byKey(const Key('picker-offset--5')));
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(result, const TimeOfDay(hour: 23, minute: 55));
    },
  );
}

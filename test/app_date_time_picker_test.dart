import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/widgets/app_date_time_picker.dart';

void main() {
  test('picker uses the roomier side within the visible overlay', () {
    const viewport = Size(800, 600);
    final nearTop = pickerAvailableSpace(
      const Rect.fromLTWH(40, 30, 100, 40),
      viewport,
    );
    expect(nearTop, const Rect.fromLTRB(12, 78, 788, 588));
    final nearBottom = pickerAvailableSpace(
      const Rect.fromLTWH(700, 530, 80, 40),
      viewport,
    );
    expect(nearBottom, const Rect.fromLTRB(12, 12, 788, 522));
    final keyboard = pickerAvailableSpace(
      const Rect.fromLTWH(100, 400, 100, 40),
      viewport,
      viewPadding: const EdgeInsets.only(top: 24),
      viewInsets: const EdgeInsets.only(bottom: 300),
    );
    expect(keyboard, const Rect.fromLTRB(12, 36, 788, 288));
    // Zoomed and narrow overlays use their own logical coordinates.
    final narrow = pickerAvailableSpace(
      const Rect.fromLTWH(10, 110, 100, 40),
      const Size(240, 300),
    );
    expect(narrow, const Rect.fromLTRB(12, 158, 228, 288));
    final tiny = pickerAvailableSpace(
      const Rect.fromLTWH(10, 25, 100, 40),
      const Size(240, 90),
    );
    expect(tiny, const Rect.fromLTRB(12, 12, 228, 78));
    expect(pickerAvailableSpace(Rect.zero, Size.zero), Rect.zero);
  });

  test(
    'locale controls clock format and maps the first weekday to DateTime',
    () async {
      final english = await GlobalMaterialLocalizations.delegate.load(
        const Locale('en'),
      );
      final russian = await GlobalMaterialLocalizations.delegate.load(
        const Locale('ru'),
      );
      expect(pickerUses24Hours(english, alwaysUse24HourFormat: false), isFalse);
      expect(pickerUses24Hours(russian, alwaysUse24HourFormat: false), isTrue);
      expect(pickerUses24Hours(english, alwaysUse24HourFormat: true), isTrue);
      expect(pickerWeekStartsOn(english), DateTime.sunday);
      expect(pickerWeekStartsOn(russian), DateTime.monday);
    },
  );
  test(
    'localized date input rejects invalid dates and enforces day bounds',
    () async {
      final first = DateTime(2024, 2, 1, 12);
      final last = DateTime(2024, 2, 29, 12);
      for (final locale in [const Locale('en'), const Locale('ru')]) {
        final material = await GlobalMaterialLocalizations.delegate.load(
          locale,
        );
        DateTime? parse(String text) =>
            parsePickerDate(text, material, firstDate: first, lastDate: last);
        expect(
          parse(material.formatCompactDate(DateTime(2024, 2, 29))),
          DateTime(2024, 2, 29),
        );
        expect(parse(material.formatCompactDate(first)), DateTime(2024, 2, 1));
        expect(parse(material.formatCompactDate(DateTime(2024, 3, 1))), isNull);
        expect(
          parse(material.formatCompactDate(DateTime(2024, 1, 31))),
          isNull,
        );
        expect(
          parse(locale.languageCode == 'ru' ? '30.02.2024' : '02/30/2024'),
          isNull,
        );
        expect(parse(''), isNull);
        expect(parse('unfinished'), isNull);
      }
    },
  );

  test(
    '24-hour input preserves midnight and rejects incomplete or invalid time',
    () {
      TimeOfDay? parse(String hour, String minute) =>
          parsePickerTime(hour, minute, use24Hours: true, period: DayPeriod.am);
      expect(parse('00', '00'), const TimeOfDay(hour: 0, minute: 0));
      expect(parse('23', '59'), const TimeOfDay(hour: 23, minute: 59));
      for (final fields in [
        ('', '30'),
        ('10', ''),
        ('24', '00'),
        ('10', '60'),
        ('-1', '00'),
        ('bad', '15'),
      ]) {
        expect(parse(fields.$1, fields.$2), isNull);
      }
    },
  );

  test('12-hour input distinguishes noon, midnight, and evening', () {
    TimeOfDay? parse(String hour, DayPeriod period) =>
        parsePickerTime(hour, '15', use24Hours: false, period: period);
    expect(parse('12', DayPeriod.am), const TimeOfDay(hour: 0, minute: 15));
    expect(parse('12', DayPeriod.pm), const TimeOfDay(hour: 12, minute: 15));
    expect(parse('1', DayPeriod.pm), const TimeOfDay(hour: 13, minute: 15));
    expect(parse('11', DayPeriod.pm), const TimeOfDay(hour: 23, minute: 15));
    expect(parse('00', DayPeriod.am), isNull);
    expect(parse('13', DayPeriod.pm), isNull);
  });
}

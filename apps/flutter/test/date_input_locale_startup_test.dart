import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/domain/models/planning/numeric_date_parser.dart';
import 'package:pomodoist/domain/models/settings/app_date_format.dart';
import 'package:pomodoist/ui/core/localization/app_date_formatter.dart';

void main() {
  test(
    'background quick-add can resolve locale before Material initializes intl',
    () {
      for (final (locale, expected) in [
        ('ru', NumericDateOrder.dayMonthYear),
        ('en', NumericDateOrder.monthDayYear),
        ('en_GB', NumericDateOrder.dayMonthYear),
        ('de', NumericDateOrder.dayMonthYear),
        ('es', NumericDateOrder.dayMonthYear),
        ('fr', NumericDateOrder.dayMonthYear),
        ('ar', NumericDateOrder.dayMonthYear),
        ('pt_BR', NumericDateOrder.dayMonthYear),
        ('zh', NumericDateOrder.yearMonthDay),
        ('ja', NumericDateOrder.yearMonthDay),
        ('ko', NumericDateOrder.yearMonthDay),
      ]) {
        for (final mode in [AppDateFormat.automatic, AppDateFormat.longDate]) {
          expect(
            AppDateFormatter.inputOrderFor(mode, locale),
            expected,
            reason: locale,
          );
        }
      }
    },
  );
}

const appDateFormatPreferenceKey = 'app.dateFormat';

enum AppDateFormat {
  automatic,
  dayMonthYear,
  monthDayYear,
  yearMonthDay,
  longDate;

  static AppDateFormat fromStorageValue(Object? value) => values.firstWhere(
    (format) => format.name == value,
    orElse: () => automatic,
  );
}

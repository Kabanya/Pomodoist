enum NumericDateOrder { dayMonthYear, monthDayYear, yearMonthDay }

String normalizeDateDigits(String value) => String.fromCharCodes(
  value.runes.map((rune) {
    for (final zero in [0x0660, 0x06f0, 0xff10]) {
      if (rune >= zero && rune <= zero + 9) return 0x30 + rune - zero;
    }
    return rune;
  }),
);

/// Rejects calendar overflow and finds the next occurrence when year is omitted.
DateTime? resolveCalendarDate({
  required int day,
  required int month,
  required DateTime today,
  int? year,
}) {
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final firstYear = year ?? today.year;
  // Eight years covers the leap-day gap across a non-leap century.
  final lastYear = year ?? firstYear + 8;
  final currentDay = DateTime(today.year, today.month, today.day);
  for (
    var candidateYear = firstYear;
    candidateYear <= lastYear;
    candidateYear++
  ) {
    if (candidateYear < 1 || candidateYear > 9999) return null;
    final date = DateTime(candidateYear, month, day);
    if (date.month == month &&
        date.day == day &&
        (year != null || !date.isBefore(currentDay))) {
      return date;
    }
  }
  return null;
}

DateTime? parseNumericDate(
  String input, {
  required NumericDateOrder order,
  required DateTime today,
}) {
  final text = normalizeDateDigits(input.trim());
  final match = RegExp(
    r'^(\d{1,4})([./-])(\d{1,2})(?:\2(\d{1,4}))?$',
  ).firstMatch(text);
  if (match == null) return null;
  final first = match[1]!;
  final second = match[3]!;
  final third = match[4];
  // Canonical ISO dates are also emitted by the named-date normalizer.
  final iso = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text);
  final effectiveOrder = iso ? NumericDateOrder.yearMonthDay : order;
  final (day, month, yearText) = switch (effectiveOrder) {
    NumericDateOrder.dayMonthYear => (first, second, third),
    NumericDateOrder.monthDayYear => (second, first, third),
    NumericDateOrder.yearMonthDay =>
      third == null ? (second, first, null) : (third, second, first),
  };
  if (day.length > 2 ||
      month.length > 2 ||
      (yearText != null && yearText.length != 2 && yearText.length != 4)) {
    return null;
  }
  final year = yearText == null
      ? null
      : int.parse(yearText) + (yearText.length == 2 ? 2000 : 0);
  return resolveCalendarDate(
    day: int.parse(day),
    month: int.parse(month),
    year: year,
    today: today,
  );
}

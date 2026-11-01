import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:pomodoist/domain/models/settings/app_date_format.dart';
import 'package:pomodoist/ui/core/localization/app_localizations.dart';

class AppDateFormatScope extends InheritedWidget {
  const AppDateFormatScope({
    required this.format,
    required super.child,
    super.key,
  });

  final AppDateFormat format;

  @override
  bool updateShouldNotify(AppDateFormatScope oldWidget) =>
      format != oldWidget.format;
}

/// Keeps automatic formatting at the call site so existing labels stay intact.
class AppDateFormatter {
  const AppDateFormatter(this.mode, this.material, this.locale);

  factory AppDateFormatter.of(BuildContext context) => AppDateFormatter(
    context.dependOnInheritedWidgetOfExactType<AppDateFormatScope>()?.format ??
        AppDateFormat.automatic,
    MaterialLocalizations.of(context),
    Localizations.localeOf(context).toString(),
  );

  final AppDateFormat mode;
  final MaterialLocalizations material;
  final String locale;

  intl.DateFormat get _explicit => switch (mode) {
    AppDateFormat.dayMonthYear => intl.DateFormat('dd.MM.yyyy', locale),
    AppDateFormat.monthDayYear => intl.DateFormat('MM/dd/yyyy', locale),
    AppDateFormat.yearMonthDay => intl.DateFormat('yyyy-MM-dd', locale),
    AppDateFormat.longDate => intl.DateFormat.yMMMMd(locale),
    AppDateFormat.automatic => throw StateError(
      'Automatic uses Material localizations',
    ),
  };

  String format(DateTime date, {String Function()? automatic}) =>
      mode == AppDateFormat.automatic
      ? automatic?.call() ?? material.formatCompactDate(date)
      : _explicit.format(date);

  String formatTaskListDate(
    DateTime date,
    AppLocalizations l10n, {
    required DateTime now,
  }) {
    final localToday = now.toLocal();
    final localDay = date.toLocal();
    final today = DateTime(localToday.year, localToday.month, localToday.day);
    final day = DateTime(localDay.year, localDay.month, localDay.day);
    final offset = day.difference(today).inDays;
    return switch (offset) {
      -1 => l10n.yesterday,
      0 => l10n.today,
      1 => l10n.tomorrow,
      _ => format(
        day,
        automatic: () => intl.DateFormat.MMMMd(l10n.localeName).format(day),
      ),
    };
  }

  String get inputHint => mode == AppDateFormat.automatic
      ? material.dateHelpText
      : format(DateTime(2026, 11, 2));

  String formatWithTime(
    DateTime date, {
    required String Function() automatic,
  }) => mode == AppDateFormat.automatic
      ? automatic()
      : '${format(date)} ${intl.DateFormat.jm(locale).format(date)}';

  DateTime? parse(String text) {
    if (mode == AppDateFormat.automatic) {
      return material.parseCompactDate(text.trim());
    }
    try {
      final date = _explicit.parseStrict(text.trim());
      return date.year >= 1 && date.year <= 9999 ? date : null;
    } on FormatException {
      return null;
    }
  }
}

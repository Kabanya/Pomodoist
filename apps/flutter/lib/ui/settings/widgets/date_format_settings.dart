import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadSelect, ShadOption;
import 'package:pomodoist/domain/models/settings/app_date_format.dart';
import 'package:pomodoist/ui/core/localization/app_date_formatter.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/view_models/app_date_format_view_model.dart';
import 'package:pomodoist/ui/settings/widgets/settings_components.dart';

class DateFormatSettings extends ConsumerStatefulWidget {
  const DateFormatSettings({super.key});

  @override
  ConsumerState<DateFormatSettings> createState() => _DateFormatSettingsState();
}

class _DateFormatSettingsState extends ConsumerState<DateFormatSettings> {
  int _saveRevision = 0;

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(appDateFormatProvider);
    final l10n = context.l10n;
    final material = MaterialLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    String label(AppDateFormat format) => switch (format) {
      AppDateFormat.automatic => l10n.settingsDateFormatAutomatic,
      AppDateFormat.dayMonthYear => l10n.settingsDateFormatDayMonthYear,
      AppDateFormat.monthDayYear => l10n.settingsDateFormatMonthDayYear,
      AppDateFormat.yearMonthDay => l10n.settingsDateFormatYearMonthDay,
      AppDateFormat.longDate => l10n.settingsDateFormatLong,
    };
    String example(AppDateFormat format) => AppDateFormatter(
      format,
      material,
      locale,
    ).format(DateTime(2026, 11, 2));

    return SettingsRow(
      title: l10n.settingsDateFormatTitle,
      subtitle: l10n.settingsDateFormatSubtitle,
      control: ShadSelect<AppDateFormat>(
        key: ValueKey((selected, locale, _saveRevision)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        initialValue: selected,
        options: [
          for (final format in AppDateFormat.values)
            ShadOption(
              value: format,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      example(format),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    Text(
                      label(format),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
        ],
        selectedOptionBuilder: (context, format) => Text(
          format == AppDateFormat.automatic
              ? '${label(format)} · ${example(format)}'
              : example(format),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onChanged: (format) {
          if (format != null) {
            saveSetting(
              context,
              ref
                  .read(appDateFormatProvider.notifier)
                  .setFormat(format)
                  .whenComplete(() {
                    // Reset the select's internal choice after a failed write too.
                    if (mounted) setState(() => _saveRevision++);
                  }),
            );
          }
        },
      ),
    );
  }
}

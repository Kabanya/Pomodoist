import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';

class TodayDateButton extends StatelessWidget {
  const TodayDateButton({
    required this.today,
    required this.onPressed,
    super.key,
  });

  final DateTime today;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n, colors = context.appColors;
    return IconButton(
      tooltip:
          '${l.today}, ${DateFormat.yMMMMEEEEd(l.localeName).format(today)}',
      onPressed: onPressed,
      style: IconButton.styleFrom(
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.all(6),
      ),
      icon: Container(
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: colors.accentTint,
          borderRadius: BorderRadius.circular(8),
        ),
        child: ExcludeSemantics(
          child: Text(
            DateFormat.d(l.localeName).format(today),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium
                ?.merge(AppTheme.monoTextStyle)
                .copyWith(color: colors.accent, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

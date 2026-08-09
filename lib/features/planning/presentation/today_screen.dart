import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/formatters.dart';
import '../../../app/app_l10n.dart';
import '../../../app/providers.dart';
import '../../tasks/domain/task_models.dart';
import '../../tasks/presentation/widgets/task_list_view.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final l10n = context.l10n;
    final summary = ref.watch(productivitySummaryProvider).value;
    final subtitle = summary == null
        ? null
        : l10n.screenTodayFocusSummary(
            summary.plannedFocusIntervals,
            summary.completedFocusIntervals,
            formatFocusTime(context, summary.totalFocusSeconds),
          );
    return TaskListView(
      title: l10n.navToday,
      subtitle: subtitle,
      query: TaskQuery(kind: TaskQueryKind.today, now: today),
    );
  }
}

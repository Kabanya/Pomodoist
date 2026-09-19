import 'package:flutter/material.dart';

import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/tasks/widgets/task_list_view.dart';

class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TaskListView(
      title: l10n.navInbox,
      subtitle: l10n.screenInboxSubtitle,
      query: const TaskQuery.inbox(),
    );
  }
}

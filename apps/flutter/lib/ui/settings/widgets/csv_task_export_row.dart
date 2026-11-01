import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons, ShadButton;

import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/settings/view_models/csv_task_export_view_model.dart';
import 'package:pomodoist/ui/settings/widgets/settings_components.dart';
import 'package:pomodoist/utils/result.dart';

class CsvTaskExportRow extends ConsumerWidget {
  const CsvTaskExportRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(csvTaskExportViewModelProvider);
    final l10n = context.l10n;
    return SettingsRow(
      key: const Key('csv-export-row'),
      title: l10n.csvExportTitle,
      subtitle: l10n.csvExportSubtitle,
      control: ShadButton(
        key: const Key('csv-export-save'),
        height: 48,
        enabled: !busy,
        leading: busy
            ? SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Theme.of(context).colorScheme.onPrimary,
                  semanticsLabel: l10n.csvExportButton,
                ),
              )
            : const Icon(LucideIcons.fileDown),
        onPressed: busy
            ? null
            : () async {
                final result = await ref
                    .read(csvTaskExportViewModelProvider.notifier)
                    .exportAllTasks();
                if (!context.mounted) return;
                final message = switch (result) {
                  Success(value: true) => context.l10n.csvExportSuccess,
                  Success() => null,
                  Failure() => context.l10n.csvExportError,
                };
                if (message != null) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(message)));
                }
              },
        child: Text(l10n.csvExportButton),
      ),
    );
  }
}

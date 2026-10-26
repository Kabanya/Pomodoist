import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadButton;
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/settings/view_models/ai_quota_view_model.dart';
import 'package:pomodoist/ui/settings/widgets/settings_components.dart';

class SettingsAiQuota extends ConsumerWidget {
  const SettingsAiQuota({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(aiQuotaViewModelProvider);
    final l10n = context.l10n;
    return state.when(
      loading: () => const LinearProgressIndicator(minHeight: 2),
      error: (error, stack) => SettingsRow(
        title: l10n.aiQuotaTitle,
        subtitle: l10n.aiQuotaUnavailable,
        control: ShadButton.outline(
          height: 48,
          onPressed: () => ref.invalidate(aiQuotaViewModelProvider),
          child: Text(l10n.commonRetry),
        ),
      ),
      data: (quota) => quota == null
          ? const SizedBox.shrink()
          : SettingsRow(
              title: l10n.aiQuotaTitle,
              subtitle:
                  '${l10n.aiQuotaUsage(quota.used, quota.limit, quota.remaining)}\n${l10n.aiQuotaReset(DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag()).format(quota.resetsAt.toLocal()))}\n${l10n.aiQuotaExplanation}',
              control: ShadButton.outline(
                height: 48,
                onPressed: () => ref.invalidate(aiQuotaViewModelProvider),
                child: Text(l10n.settingsRefreshAccount),
              ),
            ),
    );
  }
}

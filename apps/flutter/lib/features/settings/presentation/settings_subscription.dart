import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadButton, LucideIcons;

import '../../../app/app_l10n.dart';
import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_theme.dart';
import '../../billing/billing.dart';
import '../../onboarding/onboarding_gate.dart';
import 'settings_components.dart';

/// A failed or unfinished lookup is not evidence of a Free subscription.
BillingAccessTier? settingsSubscriptionTier(BillingState state) {
  if (!state.hasActiveEntitlement && (state.loading || state.error != null)) {
    return null;
  }
  return billingAccessTier(state);
}

class SettingsSubscription extends ConsumerWidget {
  const SettingsSubscription({super.key});

  Future<void> _open(BuildContext context) => showDialog<void>(
    context: context,
    animationStyle: AnimationStyle(
      duration: AppMotion.duration(context, AppMotion.popup),
      reverseDuration: AppMotion.duration(context, AppMotion.popup),
      curve: AppMotion.curve,
    ),
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: LaunchOfferPaywall(
            compact: true,
            showPlansWhenActive: true,
            onClose: () => Navigator.pop(context),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(billingControllerProvider);
    final l10n = context.l10n;
    final plan = switch (settingsSubscriptionTier(state)) {
      null => '—',
      BillingAccessTier.free => l10n.settingsPlanFree,
      BillingAccessTier.monthly => l10n.billingMonthlyTitle,
      BillingAccessTier.annual => l10n.billingAnnualTitle,
      BillingAccessTier.lifetime => l10n.billingLifetimeTitle,
      BillingAccessTier.pro => l10n.settingsPlanPro,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsRow(
          title: l10n.billingTitle,
          subtitle: '${l10n.settingsPlanLabel}: $plan',
          control: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: ShadButton.outline(
              height: 48,
              onPressed: () => _open(context),
              trailing: const Icon(LucideIcons.chevronRight, size: 16),
              child: Text(l10n.settingsSubscriptionActions),
            ),
          ),
        ),
        if (state.loading) const LinearProgressIndicator(minHeight: 2),
        if (state.error != null) ...[
          Text(
            l10n.settingsSubscriptionError,
            style: TextStyle(color: context.appColors.error),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: ShadButton.ghost(
              height: 48,
              enabled: !state.loading,
              onPressed: () =>
                  ref.read(billingControllerProvider.notifier).reload(),
              child: Text(l10n.commonRetry),
            ),
          ),
        ],
      ],
    );
  }
}

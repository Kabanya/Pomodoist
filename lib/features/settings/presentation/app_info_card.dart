import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;

import '../../../app/app_l10n.dart';
import '../../../app/legal_urls.dart';
import '../../billing/billing.dart';
import '../../updates/update_widgets.dart';

final appVersionProvider = FutureProvider<String>((ref) async {
  final packageInfo = await PackageInfo.fromPlatform();
  return formatAppVersion(packageInfo.version, packageInfo.buildNumber);
});

String formatAppVersion(String version, String buildNumber) {
  if (buildNumber.isEmpty) {
    return version;
  }
  return '$version ($buildNumber)';
}

class SettingsAppInfoCard extends ConsumerWidget {
  const SettingsAppInfoCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final version = ref
        .watch(appVersionProvider)
        .when(data: (value) => value, error: (_, _) => '—', loading: () => '—');
    final tier = billingAccessTier(ref.watch(billingControllerProvider));
    final plan = switch (tier) {
      BillingAccessTier.free => l10n.settingsPlanFree,
      BillingAccessTier.monthly => l10n.billingMonthlyTitle,
      BillingAccessTier.annual => l10n.billingAnnualTitle,
      BillingAccessTier.lifetime => l10n.billingLifetimeTitle,
      BillingAccessTier.pro => l10n.settingsPlanPro,
    };

    return Card(
      key: const Key('settings-app-info-card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.settingsAboutTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            ListTile(
              contentPadding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              leading: const Icon(LucideIcons.info),
              title: Text(l10n.settingsVersionLabel),
              trailing: Text(
                version,
                key: const Key('settings-app-version-value'),
                textAlign: TextAlign.end,
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              leading: const Icon(LucideIcons.award),
              title: Text(l10n.settingsPlanLabel),
              trailing: Text(
                plan,
                key: const Key('settings-app-plan-value'),
                textAlign: TextAlign.end,
              ),
            ),
            ListTile(
              key: const Key('settings-privacy-policy-link'),
              contentPadding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              leading: const Icon(LucideIcons.shield),
              title: Text(l10n.privacyPolicy),
              trailing: const Icon(LucideIcons.externalLink),
              onTap: () => unawaited(
                launchPomodoistExternalUrl(pomodoistPrivacyPolicyUrl),
              ),
            ),
            ListTile(
              key: const Key('settings-terms-of-use-link'),
              contentPadding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              leading: const Icon(LucideIcons.fileText),
              title: Text(l10n.termsOfUse),
              trailing: const Icon(LucideIcons.externalLink),
              onTap: () =>
                  unawaited(launchPomodoistExternalUrl(pomodoistTermsOfUseUrl)),
            ),
            ListTile(
              key: const Key('settings-support-link'),
              contentPadding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              leading: const Icon(LucideIcons.headset),
              title: Text(l10n.support),
              trailing: const Icon(LucideIcons.externalLink),
              onTap: () =>
                  unawaited(launchPomodoistExternalUrl(pomodoistSupportUrl)),
            ),
            const DesktopUpdateSettings(),
          ],
        ),
      ),
    );
  }
}

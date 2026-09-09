import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons, ShadButton;

import '../../../app/app_l10n.dart';
import '../../../app/legal_urls.dart';
import 'settings_components.dart';
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
    final version = ref.watch(appVersionProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      key: const Key('settings-app-info-card'),
      children: [
        SettingsGroup(
          children: [
            SettingsRow(
              title: l10n.settingsVersionLabel,
              controlWidth: 160,
              control: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (version.hasValue)
                    Text(
                      version.value!,
                      key: const Key('settings-app-version-value'),
                    ),
                  if (version.isLoading)
                    const LinearProgressIndicator(minHeight: 2),
                  if (version.hasError) ...[
                    Text(l10n.settingsVersionError),
                    ShadButton.ghost(
                      height: 48,
                      onPressed: () => ref.invalidate(appVersionProvider),
                      child: Text(l10n.commonRetry),
                    ),
                  ],
                ],
              ),
            ),
            ListTile(
              key: const Key('settings-privacy-policy-link'),
              contentPadding: EdgeInsets.zero,
              minTileHeight: 48,
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
              minTileHeight: 48,
              leading: const Icon(LucideIcons.fileText),
              title: Text(l10n.termsOfUse),
              trailing: const Icon(LucideIcons.externalLink),
              onTap: () =>
                  unawaited(launchPomodoistExternalUrl(pomodoistTermsOfUseUrl)),
            ),
            ListTile(
              key: const Key('settings-support-link'),
              contentPadding: EdgeInsets.zero,
              minTileHeight: 48,
              leading: const Icon(LucideIcons.headset),
              title: Text(l10n.support),
              trailing: const Icon(LucideIcons.externalLink),
              onTap: () =>
                  unawaited(launchPomodoistExternalUrl(pomodoistSupportUrl)),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const DesktopUpdateSettings(),
      ],
    );
  }
}

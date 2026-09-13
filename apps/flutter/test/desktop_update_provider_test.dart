import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/runtime_public_config.dart';
import 'package:pomodoist/features/updates/update_providers.dart';
import 'package:pomodoist/features/updates/update_release.dart';

import 'desktop_update_controller_test.dart' as support;

void main() {
  for (final (environment, webUrl, apiUrl, allowed) in [
    ('local', 'http://127.0.0.1:7358', '', false),
    (
      'selfhosted',
      'https://tasks.example.com',
      'https://api.example.com',
      false,
    ),
    (
      'staging',
      'https://app-test.pomodoist.com',
      'https://supabase-test.pomodoist.com',
      false,
    ),
    (
      'production',
      'https://app.pomodoist.com',
      'https://ewauihswbwduvklrozke.supabase.co',
      true,
    ),
  ]) {
    test('$environment gates official checks and installation', () async {
      final config = RuntimePublicConfig.fromBuildTimeValues(
        environment: environment,
        release: '0123456789abcdef0123456789abcdef01234567',
        webAppUrl: webUrl,
        supabaseUrl: apiUrl,
        supabaseAnonKey: apiUrl.isEmpty ? '' : 'public-test-key',
        turnstileSiteKey: 'public-test-site-key',
        sentryDsn: '',
      );
      final container = ProviderContainer(
        overrides: [runtimePublicConfigProvider.overrideWithValue(config)],
      );
      addTearDown(container.dispose);
      final configured = container.read(desktopUpdateControllerProvider);
      final source = support.FakeUpdateSource();
      final installer = support.FakeUpdateInstaller();
      final preferences = support.MemoryUpdatePreferences();
      // Keep the provider's environment decision, replacing OS/network effects.
      final controller = support.testController(
        source: source,
        installer: installer,
        preferences: preferences,
        officialUpdatesAllowed: configured.officialUpdatesAllowed,
      );
      addTearDown(controller.dispose);
      await controller.start();
      await controller.check();
      await controller.check(manual: true);
      await controller.setChannel(UpdateChannel.rc);
      controller.offer = support.testOffer();
      await controller.update();
      expect(controller.enabled, allowed);
      expect(installer.acknowledgements, 1);
      expect(source.calls, allowed ? 3 : 0);
      expect(installer.installs, allowed ? 1 : 0);
      expect(
        preferences.channel,
        allowed ? UpdateChannel.rc : UpdateChannel.stable,
      );
      expect(controller.popupVisible, allowed);
    });
  }
}

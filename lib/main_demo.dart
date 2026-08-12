import 'package:app_account/app_account.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'app/account_providers.dart';
import 'app/app.dart';
import 'app/providers.dart';
import 'app/runtime_public_config.dart';
import 'app/runtime_public_config_loader.dart';
import 'app/web_bootstrap_loader.dart';
import 'demo/demo_seed_data.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  final runtimeConfig = await loadRuntimePublicConfig();
  runApp(
    ProviderScope(
      overrides: [
        runtimePublicConfigProvider.overrideWithValue(runtimeConfig),
        accountAuthStateProvider.overrideWith(
          (ref) => Stream.value(const AccountAuthState(signedIn: true)),
        ),
        appStartupProvider.overrideWith((ref) async {
          final db = ref.watch(appDatabaseProvider);
          await db.ensureDemoSeedData();
          await ref.watch(notificationSchedulerProvider).initialize();
        }),
      ],
      child: const PomodoistApp(),
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) {
    hideWebBootstrapLoader();
  });
}

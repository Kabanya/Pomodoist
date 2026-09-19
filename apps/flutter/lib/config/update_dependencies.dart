import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:pomodoist/config/runtime_public_config.dart';
import 'package:pomodoist/data/services/updates/github_update_source.dart';
import 'package:pomodoist/data/repositories/updates/update_controller.dart';
import 'package:pomodoist/data/services/updates/update_installer.dart';

final desktopUpdateControllerProvider = Provider<DesktopUpdateController>((
  ref,
) {
  final controller = DesktopUpdateController(
    source: GitHubUpdateSource(),
    installer: createUpdateInstaller(),
    preferences: SharedUpdatePreferences(),
    installedVersion: () async => (await PackageInfo.fromPlatform()).version,
    officialUpdatesAllowed:
        ref.watch(runtimePublicConfigProvider).environment ==
        RuntimeEnvironment.production,
    // Development/test runs never contact GitHub automatically. A real release
    // checks after startup and on a six-hour cadence; manual checks remain usable.
    automaticChecks: kReleaseMode,
  );
  ref.onDispose(controller.dispose);
  return controller;
});

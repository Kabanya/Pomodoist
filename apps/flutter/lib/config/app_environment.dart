import 'package:flutter/foundation.dart';

import 'package:pomodoist/config/runtime_public_config.dart';
import 'package:pomodoist/domain/models/app_flavor.dart';

/// The environment an entry point declares it is built for.
///
/// Each entry point names exactly one value and the runtime configuration must
/// agree with it, so a build wired to the wrong backend fails at startup
/// instead of silently talking to the wrong server.
enum AppEnvironment {
  development,
  staging,
  production;

  /// The build flavor that ships this environment.
  ///
  /// Written as an explicit switch rather than a name lookup so that adding a
  /// value to either enum is a compile error here until the mapping is
  /// considered, even if the two enums stop lining up one to one.
  AppFlavor get flavor => switch (this) {
    AppEnvironment.development => AppFlavor.development,
    AppEnvironment.staging => AppFlavor.staging,
    AppEnvironment.production => AppFlavor.production,
  };
}

/// Throws unless [config] carries an environment [appEnvironment] accepts and
/// the build was compiled with the matching flavor.
///
/// [RuntimeEnvironment.selfhosted] is accepted by [AppEnvironment.production]
/// because both are served by the same shipped application. Web additionally
/// accepts [RuntimeEnvironment.staging]: the web image is built once and the
/// environment is chosen when the container starts, so the staging and
/// production sites run the same entry point. Which domains belong to which
/// environment is still enforced by `RuntimePublicConfig`, which rejects a
/// staging config that does not use the staging domains.
///
/// Off the web the build is also checked against the compile-time
/// `--flavor` define: when [buildFlavor] (by default [buildTimeAppFlavor])
/// names a flavor other than [AppEnvironment.flavor], the entry point and the
/// flavor disagree and the build is rejected before any repository is
/// constructed. A build with no flavor at all — a bare `flutter run`, or a
/// unit test — is not rejected here, because nothing was declared to disagree
/// with; the runtime-config check above still catches a build pointed at the
/// wrong backend.
///
/// On the web the flavor check is skipped entirely: web builds carry no
/// compile-time flavor and resolve theirs from `config.js` at runtime, and the
/// web environment acceptance rules above already cover that case.
void validateEnvironment({
  required AppEnvironment appEnvironment,
  required RuntimePublicConfig config,
  bool isWeb = kIsWeb,
  AppFlavor? buildFlavor,
}) {
  final builtAs = buildFlavor ?? buildTimeAppFlavor;
  if (!isWeb && builtAs != null && builtAs != appEnvironment.flavor) {
    throw StateError(
      'Entrypoint/flavor mismatch: ${appEnvironment.name} entrypoint '
      '(${appEnvironment.flavor.entrypoint}) was built with --flavor '
      '${builtAs.name}. Pass --flavor ${appEnvironment.flavor.name}.',
    );
  }
  final accepted = switch (appEnvironment) {
    AppEnvironment.development => const {RuntimeEnvironment.local},
    AppEnvironment.staging => const {RuntimeEnvironment.staging},
    AppEnvironment.production =>
      isWeb
          ? const {
              RuntimeEnvironment.production,
              RuntimeEnvironment.selfhosted,
              RuntimeEnvironment.staging,
            }
          : const {
              RuntimeEnvironment.production,
              RuntimeEnvironment.selfhosted,
            },
  };
  if (!accepted.contains(config.environment)) {
    throw StateError(
      'Entrypoint/config mismatch: '
      '${appEnvironment.name} / ${config.environment.name}',
    );
  }
}

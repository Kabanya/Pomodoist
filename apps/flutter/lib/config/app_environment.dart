import 'package:flutter/foundation.dart';

import 'package:pomodoist/config/runtime_public_config.dart';

/// The environment an entry point declares it is built for.
///
/// Each entry point names exactly one value and the runtime configuration must
/// agree with it, so a build wired to the wrong backend fails at startup
/// instead of silently talking to the wrong server.
enum AppEnvironment { development, staging, production }

/// Throws unless [config] carries an environment [appEnvironment] accepts.
///
/// [RuntimeEnvironment.selfhosted] is accepted by [AppEnvironment.production]
/// because both are served by the same shipped application. Web additionally
/// accepts [RuntimeEnvironment.staging]: the web image is built once and the
/// environment is chosen when the container starts, so the staging and
/// production sites run the same entry point. Which domains belong to which
/// environment is still enforced by `RuntimePublicConfig`, which rejects a
/// staging config that does not use the staging domains.
void validateEnvironment({
  required AppEnvironment appEnvironment,
  required RuntimePublicConfig config,
  bool isWeb = kIsWeb,
}) {
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

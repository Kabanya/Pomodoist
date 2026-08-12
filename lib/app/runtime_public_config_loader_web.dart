import 'dart:js_interop';

import 'runtime_public_config.dart';
import 'runtime_public_config_loader_core.dart';
import 'sentry_observability.dart';

@JS('window.pomodoistRuntimeConfig')
external JSAny? get _preloadedRuntimeConfig;

Future<SentryRuntimePolicy> loadSentryRuntimePolicy() async {
  final preloaded = _preloadedRuntimeConfig;
  if (preloaded != null) {
    return parsePreloadedSentryRuntimePolicy(preloaded.dartify());
  }
  return SentryRuntimePolicy.fromValues(
    environment: const String.fromEnvironment(
      'POMODOIST_ENVIRONMENT',
      defaultValue: 'local',
    ),
    release: const String.fromEnvironment(
      'POMODOIST_RELEASE',
      defaultValue: 'development',
    ),
    sentryDsn: const String.fromEnvironment('SENTRY_DSN'),
  );
}

Future<RuntimePublicConfig> loadRuntimePublicConfig() async {
  final preloaded = _preloadedRuntimeConfig;
  if (preloaded != null) {
    return parsePreloadedRuntimePublicConfig(preloaded.dartify());
  }
  final buildTime = RuntimePublicConfig.fromBuildTime();
  if (buildTime.environment == RuntimeEnvironment.local) return buildTime;
  throw const FormatException(
    'window.pomodoistRuntimeConfig is required outside local development',
  );
}

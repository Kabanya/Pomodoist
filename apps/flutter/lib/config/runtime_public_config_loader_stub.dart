import 'package:pomodoist/config/runtime_public_config.dart';
import 'package:pomodoist/config/sentry_observability.dart';

Future<SentryRuntimePolicy> loadSentryRuntimePolicy() async {
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
  return RuntimePublicConfig.fromBuildTime();
}

import 'package:pomodoist/config/runtime_public_config.dart';
import 'package:pomodoist/config/sentry_observability.dart';
import 'package:pomodoist/domain/models/app_flavor.dart';

/// Flavor a deployment serves, derived from its runtime environment.
///
/// A web image is built once and deployed to every environment, so the flavor
/// cannot come from the compile-time `FLUTTER_APP_FLAVOR` define there. It is
/// read from the runtime configuration instead.
///
/// Self-hosted deployments run the shipped application, so they serve the
/// production flavor.
AppFlavor appFlavorForRuntimeEnvironment(RuntimeEnvironment environment) =>
    switch (environment) {
      RuntimeEnvironment.local => AppFlavor.development,
      RuntimeEnvironment.staging => AppFlavor.staging,
      RuntimeEnvironment.production => AppFlavor.production,
      RuntimeEnvironment.selfhosted => AppFlavor.production,
    };

RuntimePublicConfig parsePreloadedRuntimePublicConfig(Object? value) {
  if (value is! Map<Object?, Object?> ||
      value.keys.any((key) => key is! String)) {
    throw const FormatException(
      'window.pomodoistRuntimeConfig must be a JSON object',
    );
  }
  return RuntimePublicConfig.fromRuntimeJson(value.cast<String, Object?>());
}

SentryRuntimePolicy parsePreloadedSentryRuntimePolicy(Object? value) {
  if (value is! Map<Object?, Object?> ||
      value.keys.any((key) => key is! String)) {
    throw const FormatException(
      'window.pomodoistRuntimeConfig must be a JSON object',
    );
  }
  final json = value.cast<String, Object?>();
  return SentryRuntimePolicy.fromValues(
    environment: _monitoringString(json, 'environment'),
    release: _monitoringString(json, 'release'),
    sentryDsn: _monitoringString(json, 'sentryDsn'),
  );
}

String _monitoringString(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is! String) throw FormatException('$field must be a string');
  return value;
}

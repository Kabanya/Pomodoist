import 'runtime_public_config.dart';
import 'sentry_observability.dart';

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

import 'package:flutter_riverpod/flutter_riverpod.dart';

enum RuntimeEnvironment { local, staging, production }

class RuntimePublicConfig {
  const RuntimePublicConfig._({
    required this.environment,
    required this.release,
    required this.webAppUrl,
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    required this.googleWebClientId,
    required this.turnstileSiteKey,
    required this.sentryDsn,
  });

  static const fieldNames = {
    'environment',
    'release',
    'webAppUrl',
    'supabaseUrl',
    'supabaseAnonKey',
    'googleWebClientId',
    'turnstileSiteKey',
    'sentryDsn',
  };

  final RuntimeEnvironment environment;
  final String release;
  final Uri webAppUrl;
  final Uri? supabaseUrl;
  final String supabaseAnonKey;
  final String googleWebClientId;
  final String turnstileSiteKey;
  final Uri? sentryDsn;

  factory RuntimePublicConfig.fromRuntimeJson(Map<String, Object?> json) {
    final actualFields = json.keys.toSet();
    if (actualFields.length != fieldNames.length ||
        !actualFields.containsAll(fieldNames)) {
      final unexpected = actualFields.difference(fieldNames).toList()..sort();
      final missing = fieldNames.difference(actualFields).toList()..sort();
      throw FormatException(
        'Runtime config must contain exactly the public allowlist; '
        'missing=${missing.join(',')}, unexpected=${unexpected.join(',')}',
      );
    }
    return RuntimePublicConfig._validated(
      environment: _requiredString(json, 'environment'),
      release: _requiredString(json, 'release'),
      webAppUrl: _requiredString(json, 'webAppUrl'),
      supabaseUrl: _requiredString(json, 'supabaseUrl'),
      supabaseAnonKey: _requiredString(json, 'supabaseAnonKey'),
      googleWebClientId: _string(json, 'googleWebClientId'),
      turnstileSiteKey: _string(json, 'turnstileSiteKey'),
      sentryDsn: _string(json, 'sentryDsn'),
      allowLocal: false,
    );
  }

  factory RuntimePublicConfig.fromBuildTime() {
    return RuntimePublicConfig.fromBuildTimeValues(
      environment: const String.fromEnvironment(
        'POMODOIST_ENVIRONMENT',
        defaultValue: 'local',
      ),
      release: const String.fromEnvironment(
        'POMODOIST_RELEASE',
        defaultValue: 'development',
      ),
      webAppUrl: const String.fromEnvironment(
        'WEB_APP_URL',
        defaultValue: 'http://127.0.0.1:7358',
      ),
      supabaseUrl: const String.fromEnvironment('SUPABASE_URL'),
      supabaseAnonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
      googleWebClientId: const String.fromEnvironment('GOOGLE_WEB_CLIENT_ID'),
      turnstileSiteKey: const String.fromEnvironment('TURNSTILE_SITE_KEY'),
      sentryDsn: const String.fromEnvironment('SENTRY_DSN'),
    );
  }

  factory RuntimePublicConfig.fromBuildTimeValues({
    required String environment,
    required String release,
    required String webAppUrl,
    required String supabaseUrl,
    required String supabaseAnonKey,
    required String googleWebClientId,
    required String turnstileSiteKey,
    required String sentryDsn,
  }) {
    return RuntimePublicConfig._validated(
      environment: environment,
      release: release,
      webAppUrl: webAppUrl,
      supabaseUrl: supabaseUrl,
      supabaseAnonKey: supabaseAnonKey,
      googleWebClientId: googleWebClientId,
      turnstileSiteKey: turnstileSiteKey,
      sentryDsn: sentryDsn,
      allowLocal: true,
    );
  }

  factory RuntimePublicConfig._validated({
    required String environment,
    required String release,
    required String webAppUrl,
    required String supabaseUrl,
    required String supabaseAnonKey,
    required String googleWebClientId,
    required String turnstileSiteKey,
    required String sentryDsn,
    required bool allowLocal,
  }) {
    final parsedEnvironment = switch (environment) {
      'local' when allowLocal => RuntimeEnvironment.local,
      'staging' => RuntimeEnvironment.staging,
      'production' => RuntimeEnvironment.production,
      _ => throw FormatException('Unexpected environment: $environment'),
    };
    final remote = parsedEnvironment != RuntimeEnvironment.local;
    if (remote && !RegExp(r'^[0-9a-f]{40}$').hasMatch(release)) {
      throw const FormatException('release must be a full Git commit SHA');
    }
    if (!remote && release.isEmpty) {
      throw const FormatException('release is required');
    }

    final parsedWebAppUrl = _uri(
      webAppUrl,
      field: 'webAppUrl',
      httpsRequired: remote,
      required: true,
    )!;
    final parsedSupabaseUrl = _uri(
      supabaseUrl,
      field: 'supabaseUrl',
      httpsRequired: remote,
      required: remote,
    );
    if (remote && supabaseAnonKey.isEmpty) {
      throw const FormatException('supabaseAnonKey is required');
    }
    if (remote && turnstileSiteKey.isEmpty) {
      throw const FormatException('turnstileSiteKey is required');
    }
    if (!remote && (parsedSupabaseUrl == null) != supabaseAnonKey.isEmpty) {
      throw const FormatException(
        'Local supabaseUrl and supabaseAnonKey must be configured together',
      );
    }
    final parsedSentryDsn = _sentryDsn(sentryDsn);

    _validateEnvironmentDomains(
      environment: parsedEnvironment,
      webAppUrl: parsedWebAppUrl,
      supabaseUrl: parsedSupabaseUrl,
    );

    return RuntimePublicConfig._(
      environment: parsedEnvironment,
      release: release,
      webAppUrl: parsedWebAppUrl,
      supabaseUrl: parsedSupabaseUrl,
      supabaseAnonKey: supabaseAnonKey,
      googleWebClientId: googleWebClientId,
      turnstileSiteKey: turnstileSiteKey,
      sentryDsn: parsedSentryDsn,
    );
  }

  Map<String, String> toJson() => {
    'environment': environment.name,
    'release': release,
    'webAppUrl': webAppUrl.toString(),
    'supabaseUrl': supabaseUrl?.toString() ?? '',
    'supabaseAnonKey': supabaseAnonKey,
    'googleWebClientId': googleWebClientId,
    'turnstileSiteKey': turnstileSiteKey,
    'sentryDsn': sentryDsn?.toString() ?? '',
  };
}

final runtimePublicConfigProvider = Provider<RuntimePublicConfig>(
  (ref) => RuntimePublicConfig.fromBuildTime(),
);

String _requiredString(Map<String, Object?> json, String field) {
  final value = _string(json, field);
  if (value.isEmpty) throw FormatException('$field is required');
  return value;
}

String _string(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is! String) throw FormatException('$field must be a string');
  return value;
}

Uri? _uri(
  String value, {
  required String field,
  required bool httpsRequired,
  required bool required,
}) {
  if (value.isEmpty) {
    if (required) throw FormatException('$field is required');
    return null;
  }
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    throw FormatException('$field must be an absolute URL');
  }
  if (httpsRequired && uri.scheme != 'https') {
    throw FormatException('$field must use HTTPS');
  }
  if (!httpsRequired && uri.scheme != 'https' && uri.scheme != 'http') {
    throw FormatException('$field must use HTTP or HTTPS');
  }
  return uri;
}

Uri? _sentryDsn(String value) {
  if (value.isEmpty) return null;
  final uri = Uri.tryParse(value);
  final publicKey = uri?.userInfo ?? '';
  final projectSegments = uri?.pathSegments ?? const <String>[];
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.hasPort ||
      !RegExp(r'^[A-Za-z0-9]+$').hasMatch(publicKey) ||
      !RegExp(r'^o[0-9]+\.ingest\.sentry\.io$').hasMatch(uri.host) ||
      projectSegments.length != 1 ||
      !RegExp(r'^[0-9]+$').hasMatch(projectSegments.single) ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw const FormatException('sentryDsn must be a public Sentry Cloud DSN');
  }
  return uri;
}

void _validateEnvironmentDomains({
  required RuntimeEnvironment environment,
  required Uri webAppUrl,
  required Uri? supabaseUrl,
}) {
  switch (environment) {
    case RuntimeEnvironment.local:
      return;
    case RuntimeEnvironment.staging:
      if (!const {'app-test.pomodoist.com'}.contains(webAppUrl.host) ||
          !const {'supabase-test.pomodoist.com'}.contains(supabaseUrl?.host)) {
        throw const FormatException(
          'staging config must use the Pomodoist staging domains',
        );
      }
      return;
    case RuntimeEnvironment.production:
      if (webAppUrl.host != 'app.pomodoist.com' ||
          supabaseUrl?.host != 'ewauihswbwduvklrozke.supabase.co') {
        throw const FormatException(
          'production config must use production domains',
        );
      }
      return;
  }
}

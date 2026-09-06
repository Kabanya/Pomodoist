import 'dart:convert';
import 'dart:io';

const _productionWebUrl = 'https://app.pomodoist.com';
const _productionCaptchaUrl = 'https://app.pomodoist.com/auth/challenge';
const _productionSupabaseUrl = 'https://ewauihswbwduvklrozke.supabase.co';
const _forbiddenSupabaseKeys = {
  'SERVICE_ROLE_KEY',
  'SUPABASE_SECRET_KEY',
  'SUPABASE_SERVICE_ROLE_KEY',
};

void validateDesktopReleaseConfig(Map<String, Object?> config) {
  for (final entry in config.entries) {
    final value = entry.value;
    if (_forbiddenSupabaseKeys.contains(entry.key.toUpperCase()) ||
        value is String && value.startsWith('sb_secret_')) {
      throw const FormatException(
        'Desktop configuration must not contain privileged Supabase keys.',
      );
    }
  }

  final environment = _requiredString(config, 'POMODOIST_ENVIRONMENT');
  if (environment != 'production' && environment != 'selfhosted') {
    throw const FormatException(
      'POMODOIST_ENVIRONMENT must select production or selfhosted.',
    );
  }

  if (environment == 'selfhosted') {
    _validateSelfHostedConfig(config);
    return;
  }

  if (_requiredString(config, 'WEB_APP_URL') != _productionWebUrl) {
    throw const FormatException('WEB_APP_URL must use the production host.');
  }
  if (_requiredString(config, 'POMODOIST_REGISTRATION_URL') !=
      _productionCaptchaUrl) {
    throw const FormatException(
      'POMODOIST_REGISTRATION_URL must use the production challenge.',
    );
  }

  final turnstile = _requiredString(config, 'TURNSTILE_SITE_KEY');
  if (turnstile.toLowerCase().contains('replace-with') ||
      turnstile.contains('00000000000000000000')) {
    throw const FormatException(
      'TURNSTILE_SITE_KEY must be a production site key.',
    );
  }

  _optionalString(config, 'SENTRY_DSN');

  final supabaseUrl = _nonEmptyOptionalString(config, 'SUPABASE_URL');
  final supabaseKey = _nonEmptyOptionalString(config, 'SUPABASE_ANON_KEY');
  if ((supabaseUrl == null) != (supabaseKey == null)) {
    throw const FormatException(
      'SUPABASE_URL and SUPABASE_ANON_KEY must be supplied together.',
    );
  }
  if (supabaseUrl != null && supabaseUrl != _productionSupabaseUrl) {
    throw const FormatException(
      'SUPABASE_URL must use the production project.',
    );
  }
}

void _validateSelfHostedConfig(Map<String, Object?> config) {
  final webAppUrl = _selfHostedUrl(
    _requiredString(config, 'WEB_APP_URL'),
    'WEB_APP_URL',
  );
  _selfHostedUrl(_requiredString(config, 'SUPABASE_URL'), 'SUPABASE_URL');
  _requiredString(config, 'SUPABASE_ANON_KEY');

  final turnstile = _nonEmptyOptionalString(config, 'TURNSTILE_SITE_KEY');
  final registration = _nonEmptyOptionalString(
    config,
    'POMODOIST_REGISTRATION_URL',
  );
  if (turnstile != null && registration == null) {
    throw const FormatException(
      'POMODOIST_REGISTRATION_URL is required when Turnstile is enabled.',
    );
  }
  if (registration != null) {
    final registrationUrl = _selfHostedUrl(
      registration,
      'POMODOIST_REGISTRATION_URL',
    );
    if (registrationUrl.path != '/auth/challenge' ||
        registrationUrl.origin != webAppUrl.origin) {
      throw const FormatException(
        'POMODOIST_REGISTRATION_URL must use the selfhosted web origin.',
      );
    }
  }

  final sentry = _nonEmptyOptionalString(config, 'SENTRY_DSN');
  if (sentry != null) {
    final uri = _selfHostedUrl(sentry, 'SENTRY_DSN');
    if (!RegExp(r'^[A-Za-z0-9]+$').hasMatch(uri.userInfo) ||
        uri.pathSegments.isEmpty ||
        !RegExp(r'^[0-9]+$').hasMatch(uri.pathSegments.last)) {
      throw const FormatException('SENTRY_DSN must be a public Sentry DSN.');
    }
  }
}

Uri _selfHostedUrl(String value, String field) {
  final uri = Uri.tryParse(value);
  final loopback =
      uri != null && const {'localhost', '127.0.0.1', '::1'}.contains(uri.host);
  if (uri == null ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty && field != 'SENTRY_DSN' ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.scheme != 'https' && !(uri.scheme == 'http' && loopback)) {
    throw FormatException('$field must use HTTPS or loopback HTTP.');
  }
  return uri;
}

String _requiredString(Map<String, Object?> config, String field) {
  final value = config[field];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$field is required.');
  }
  return value.trim();
}

void _optionalString(Map<String, Object?> config, String field) {
  final value = config[field];
  if (value != null && value is! String) {
    throw FormatException('$field must be a string.');
  }
}

String? _nonEmptyOptionalString(Map<String, Object?> config, String field) {
  final value = config[field];
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('$field must be a string.');
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

Future<void> main(List<String> arguments) async {
  try {
    if (arguments.length != 2 || arguments.first != '--config') {
      throw const FormatException('Expected --config <path>.');
    }
    final file = File(arguments[1]);
    final contents = await file.readAsString();
    final Object? decoded = file.path.toLowerCase().endsWith('.json')
        ? _decodeJson(contents)
        : _decodeDotEnv(contents);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException(
        'Desktop configuration must be a JSON object.',
      );
    }
    validateDesktopReleaseConfig(decoded);
    stdout.writeln('Desktop production configuration is valid.');
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
  } on FileSystemException {
    stderr.writeln('Desktop production configuration could not be read.');
    exitCode = 66;
  }
}

Object? _decodeJson(String contents) {
  try {
    return jsonDecode(contents);
  } on FormatException {
    throw const FormatException('Desktop configuration must be valid JSON.');
  }
}

Map<String, Object?> _decodeDotEnv(String contents) {
  final values = <String, Object?>{};
  final lines = const LineSplitter().convert(contents);
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final separator = line.indexOf('=');
    if (separator < 1) {
      throw FormatException(
        'Desktop configuration has an invalid assignment at line ${index + 1}.',
      );
    }
    final name = line.substring(0, separator).trim();
    if (!RegExp(r'^[A-Z][A-Z0-9_]*$').hasMatch(name)) {
      throw FormatException(
        'Desktop configuration has an invalid key at line ${index + 1}.',
      );
    }
    if (values.containsKey(name)) {
      throw FormatException('Desktop configuration contains duplicate $name.');
    }
    values[name] = line.substring(separator + 1);
  }
  return values;
}

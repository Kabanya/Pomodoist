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

  if (_requiredString(config, 'POMODOIST_ENVIRONMENT') != 'production') {
    throw const FormatException(
      'POMODOIST_ENVIRONMENT must select production.',
    );
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

  final googleClientId = _requiredString(config, 'GOOGLE_DESKTOP_CLIENT_ID');
  if (googleClientId.toLowerCase().startsWith('replace-with') ||
      !RegExp(
        r'^[A-Za-z0-9-]+\.apps\.googleusercontent\.com$',
      ).hasMatch(googleClientId)) {
    throw const FormatException(
      'GOOGLE_DESKTOP_CLIENT_ID must be a desktop OAuth client ID.',
    );
  }

  _optionalString(config, 'SENTRY_DSN');
  _optionalString(config, 'GOOGLE_DESKTOP_CLIENT_SECRET');

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
    final Object? decoded;
    try {
      decoded = jsonDecode(await file.readAsString());
    } on FormatException {
      throw const FormatException('Desktop configuration must be valid JSON.');
    }
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

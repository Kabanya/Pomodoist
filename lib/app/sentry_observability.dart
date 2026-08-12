import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'runtime_public_config.dart';

class SentryRuntimePolicy {
  const SentryRuntimePolicy._({
    required this.enabled,
    required this.dsn,
    required this.environment,
    required this.dist,
    required this.release,
    required this.errorSampleRate,
    required this.tracesSampleRate,
    required this.sendDefaultPii,
  });

  factory SentryRuntimePolicy.fromConfig(RuntimePublicConfig config) {
    return SentryRuntimePolicy.fromValues(
      environment: config.environment.name,
      release: config.release,
      sentryDsn: config.sentryDsn?.toString() ?? '',
    );
  }

  factory SentryRuntimePolicy.fromValues({
    required String environment,
    required String release,
    required String sentryDsn,
  }) {
    final parsedEnvironment = switch (environment) {
      'local' => RuntimeEnvironment.local,
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
    if (sentryDsn.isNotEmpty) {
      _validatePublicSentryDsn(sentryDsn);
    }

    final enabled = remote && sentryDsn.isNotEmpty;
    return SentryRuntimePolicy._(
      enabled: enabled,
      dsn: enabled ? sentryDsn : '',
      environment: parsedEnvironment.name,
      dist: parsedEnvironment.name,
      release: release,
      errorSampleRate: enabled ? 1 : 0,
      tracesSampleRate: enabled
          ? parsedEnvironment == RuntimeEnvironment.staging
                ? 0.10
                : 0.05
          : 0,
      sendDefaultPii: false,
    );
  }

  final bool enabled;
  final String dsn;
  final String environment;
  final String dist;
  final String release;
  final double errorSampleRate;
  final double tracesSampleRate;
  final bool sendDefaultPii;

  Map<String, String> get publicMetadata => {
    'environment': environment,
    'release': release,
  };
}

abstract interface class StartupMonitor {
  Future<void> run(
    SentryRuntimePolicy policy,
    Future<void> Function() appRunner,
  );
}

class SentryStartupMonitor implements StartupMonitor {
  const SentryStartupMonitor()
    : _transport = null,
      _restoreTestGlobals = false;

  @visibleForTesting
  const SentryStartupMonitor.testing({required Transport transport})
    : _transport = transport,
      _restoreTestGlobals = true;

  final Transport? _transport;
  final bool _restoreTestGlobals;

  @override
  Future<void> run(
    SentryRuntimePolicy policy,
    Future<void> Function() appRunner,
  ) async {
    Object? startupError;
    StackTrace? startupStackTrace;

    void configure(SentryOptions options) {
      final configuredTransport = _transport;
      options
        ..dsn = policy.dsn
        ..environment = policy.environment
        ..release = policy.release
        ..dist = policy.dist
        ..sampleRate = policy.errorSampleRate
        ..tracesSampleRate = policy.tracesSampleRate
        ..sendDefaultPii = policy.sendDefaultPii;
      if (configuredTransport != null) {
        options.transport = configuredTransport;
      }
      options.beforeSend = filterCaptchaChallengeEvent;
      options.beforeSendTransaction = filterCaptchaChallengeTransaction;
      options.beforeBreadcrumb = filterCaptchaChallengeBreadcrumb;
    }

    Future<void> guardedAppRunner() async {
      try {
        await appRunner();
      } catch (error, stackTrace) {
        // Keep bootstrap failures inside the initialized SDK, then rethrow
        // outside Sentry's guarded zone so callers still receive the error.
        await Sentry.captureException(error, stackTrace: stackTrace);
        startupError = error;
        startupStackTrace = stackTrace;
      }
    }

    final originalFlutterError = FlutterError.onError;
    final originalPlatformError = PlatformDispatcher.instance.onError;
    try {
      await SentryFlutter.init(configure, appRunner: guardedAppRunner);
    } finally {
      if (_restoreTestGlobals) {
        await Sentry.close();
        FlutterError.onError = originalFlutterError;
        PlatformDispatcher.instance.onError = originalPlatformError;
      }
    }

    if (startupError != null) {
      Error.throwWithStackTrace(startupError!, startupStackTrace!);
    }
  }
}

bool containsCaptchaChallengeMetadata(Object? value) {
  if (value is String) {
    return value.contains('/auth/challenge') ||
        RegExp(r'pomodoist://captcha-callback(?:[?#]|$)').hasMatch(value);
  }
  if (value is Map) {
    return value.entries.any(
      (entry) =>
          containsCaptchaChallengeMetadata(entry.key) ||
          containsCaptchaChallengeMetadata(entry.value),
    );
  }
  if (value is Iterable) {
    return value.any(containsCaptchaChallengeMetadata);
  }
  return false;
}

SentryEvent? filterCaptchaChallengeEvent(SentryEvent event, Hint hint) {
  return containsCaptchaChallengeMetadata(event.toJson()) ? null : event;
}

SentryTransaction? filterCaptchaChallengeTransaction(
  SentryTransaction transaction,
  Hint hint,
) {
  return containsCaptchaChallengeMetadata(transaction.toJson())
      ? null
      : transaction;
}

Breadcrumb? filterCaptchaChallengeBreadcrumb(
  Breadcrumb? breadcrumb,
  Hint hint,
) {
  if (breadcrumb == null) return null;
  return containsCaptchaChallengeMetadata(breadcrumb.toJson())
      ? null
      : breadcrumb;
}

Future<void> runPomodoistStartup({
  required Future<SentryRuntimePolicy> Function() loadMonitoringPolicy,
  required Future<RuntimePublicConfig> Function() loadRuntimeConfig,
  required Future<void> Function(RuntimePublicConfig config) startApplication,
  required StartupMonitor monitor,
  void Function()? onStartupFailure,
}) async {
  late final SentryRuntimePolicy policy;
  try {
    policy = await loadMonitoringPolicy();
  } catch (_) {
    _notifyStartupFailure(onStartupFailure);
    rethrow;
  }

  Future<void> appRunner() async {
    try {
      final config = await loadRuntimeConfig();
      await startApplication(config);
    } catch (_) {
      _notifyStartupFailure(onStartupFailure);
      rethrow;
    }
  }

  if (!policy.enabled) {
    await appRunner();
    return;
  }
  await monitor.run(policy, appRunner);
}

void _notifyStartupFailure(void Function()? callback) {
  try {
    callback?.call();
  } catch (_) {
    // Diagnostics must preserve the original startup failure.
  }
}

void _validatePublicSentryDsn(String value) {
  final uri = Uri.tryParse(value);
  final publicKey = uri?.userInfo ?? '';
  final segments = uri?.pathSegments ?? const <String>[];
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.hasPort ||
      !RegExp(r'^[A-Za-z0-9]+$').hasMatch(publicKey) ||
      !RegExp(r'^o[0-9]+\.ingest\.sentry\.io$').hasMatch(uri.host) ||
      segments.length != 1 ||
      !RegExp(r'^[0-9]+$').hasMatch(segments.single) ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw const FormatException('sentryDsn must be a public Sentry Cloud DSN');
  }
}

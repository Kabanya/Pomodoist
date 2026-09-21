import 'package:pomodoist/config/sentry_observability.dart';

import 'strict_fake.dart';

/// In-memory [StartupMonitor] double.
///
/// [run] records its policy, runs the application callback, and captures any
/// failure in [capturedErrors] before rethrowing it.
class FakeStartupMonitor extends StrictFake implements StartupMonitor {
  /// Policies passed to [run].
  final runCalls = <SentryRuntimePolicy>[];

  /// Errors the application callback threw, in call order.
  final capturedErrors = <Object>[];

  @override
  Future<void> run(
    SentryRuntimePolicy policy,
    Future<void> Function() appRunner,
  ) async {
    runCalls.add(policy);
    try {
      await appRunner();
    } catch (error) {
      capturedErrors.add(error);
      rethrow;
    }
  }
}

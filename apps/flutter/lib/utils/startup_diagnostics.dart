import 'dart:developer' as developer;

final _elapsed = Stopwatch()..start();
final _stages = <String>{};

/// Startup milestones contain timings only, never account or task content.
void traceStartupStage(String stage) {
  if (!_stages.add(stage)) return;
  final milliseconds = _elapsed.elapsedMilliseconds;
  developer.Timeline.instantSync(
    'Pomodoist.startup.$stage',
    arguments: {'elapsedMs': milliseconds},
  );
  developer.log('$stage elapsedMs=$milliseconds', name: 'pomodoist.startup');
  if (!const bool.fromEnvironment('dart.vm.product')) {
    // ignore: avoid_print
    print('pomodoist.startup $stage elapsedMs=$milliseconds');
  }
}

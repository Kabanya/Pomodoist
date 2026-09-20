import 'package:pomodoist/data/repositories/focus/focus_repository.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'package:pomodoist/utils/timer_engine.dart';

/// Completes a running interval once, after its computed duration expires.
final class CompleteExpiredFocusIntervalUseCase {
  CompleteExpiredFocusIntervalUseCase(this._focus);

  final FocusRepository _focus;
  String? _completingIntervalId;

  Future<void> call(FocusIntervalItem? interval, DateTime now) async {
    if (interval == null ||
        interval.status != 'running' ||
        _completingIntervalId == interval.id ||
        calculateRemaining(
              now: now,
              startedAt: interval.startedAt,
              plannedSeconds: interval.plannedSeconds,
              pausedTotalSeconds: interval.pausedTotalSeconds,
              pausedAt: interval.pausedAt,
            ) !=
            Duration.zero) {
      return;
    }
    _completingIntervalId = interval.id;
    try {
      (await _focus.completeActiveInterval(now: now)).getOrThrow();
    } finally {
      if (_completingIntervalId == interval.id) {
        _completingIntervalId = null;
      }
    }
  }
}

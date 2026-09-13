Duration calculateRemaining({
  required DateTime now,
  required DateTime startedAt,
  required int plannedSeconds,
  required int pausedTotalSeconds,
  DateTime? pausedAt,
}) {
  final effectiveNow = pausedAt ?? now;
  final elapsedSeconds =
      effectiveNow.difference(startedAt).inSeconds - pausedTotalSeconds;
  final remainingSeconds = plannedSeconds - elapsedSeconds;
  return Duration(seconds: remainingSeconds.clamp(0, plannedSeconds));
}

DateTime calculateExpectedEndAt({
  required DateTime startedAt,
  required int plannedSeconds,
  required int pausedTotalSeconds,
}) {
  return startedAt.add(Duration(seconds: plannedSeconds + pausedTotalSeconds));
}

bool isIntervalExpired({
  required DateTime now,
  required DateTime startedAt,
  required int plannedSeconds,
  required int pausedTotalSeconds,
  DateTime? pausedAt,
}) {
  return calculateRemaining(
        now: now,
        startedAt: startedAt,
        plannedSeconds: plannedSeconds,
        pausedTotalSeconds: pausedTotalSeconds,
        pausedAt: pausedAt,
      ) ==
      Duration.zero;
}

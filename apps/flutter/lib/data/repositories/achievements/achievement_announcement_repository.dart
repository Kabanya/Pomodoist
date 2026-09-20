import 'package:pomodoist/domain/models/productivity/achievement_models.dart';

class AchievementAnnouncementState {
  const AchievementAnnouncementState({
    required this.queue,
    required this.current,
  });

  const AchievementAnnouncementState.empty() : queue = const [], current = null;

  final List<AchievementItem> queue;
  final AchievementItem? current;
}

/// Application-session owner of the achievement announcement queue.
///
/// Deduplicates queued items so each achievement is announced once, and keeps
/// the queue available while individual screens mount and unmount. [state] is
/// the current snapshot; [watch] delivers later updates.
abstract interface class AchievementAnnouncementRepository {
  AchievementAnnouncementState get state;

  Stream<AchievementAnnouncementState> watch();

  void enqueue(List<AchievementItem> items);

  void dismissCurrent();

  void dispose();
}

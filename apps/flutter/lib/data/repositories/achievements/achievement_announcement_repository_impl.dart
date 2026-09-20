import 'dart:async';

import 'package:pomodoist/data/repositories/achievements/achievement_announcement_repository.dart';
import 'package:pomodoist/domain/models/productivity/achievement_models.dart';

final class DefaultAchievementAnnouncementRepository
    implements AchievementAnnouncementRepository {
  AchievementAnnouncementState _state =
      const AchievementAnnouncementState.empty();
  final _states = StreamController<AchievementAnnouncementState>.broadcast(
    sync: true,
  );
  @override
  AchievementAnnouncementState get state => _state;
  @override
  Stream<AchievementAnnouncementState> watch() => _states.stream;

  void _publish(AchievementAnnouncementState value) {
    _state = value;
    _states.add(value);
  }

  @override
  void enqueue(List<AchievementItem> items) {
    if (items.isEmpty) {
      return;
    }

    final existingIds = {
      if (state.current != null) state.current!.id,
      ...state.queue.map((item) => item.id),
    };
    final nextItems = [
      for (final item in items)
        if (!existingIds.contains(item.id)) item,
    ];
    if (nextItems.isEmpty) {
      return;
    }

    if (state.current == null) {
      _publish(
        AchievementAnnouncementState(
          current: nextItems.first,
          queue: List.unmodifiable(nextItems.skip(1)),
        ),
      );
      return;
    }

    _publish(
      AchievementAnnouncementState(
        current: state.current,
        queue: List.unmodifiable([...state.queue, ...nextItems]),
      ),
    );
  }

  @override
  void dismissCurrent() {
    if (state.queue.isEmpty) {
      _publish(const AchievementAnnouncementState.empty());
      return;
    }

    _publish(
      AchievementAnnouncementState(
        current: state.queue.first,
        queue: List.unmodifiable(state.queue.skip(1)),
      ),
    );
  }

  @override
  void dispose() {
    _states.close();
  }
}

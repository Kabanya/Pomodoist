import 'package:flutter/foundation.dart';

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

class AchievementAnnouncementRepository extends ChangeNotifier {
  AchievementAnnouncementState _state =
      const AchievementAnnouncementState.empty();
  AchievementAnnouncementState get state => _state;
  set state(AchievementAnnouncementState value) {
    _state = value;
    notifyListeners();
  }

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
      state = AchievementAnnouncementState(
        current: nextItems.first,
        queue: List.unmodifiable(nextItems.skip(1)),
      );
      return;
    }

    state = AchievementAnnouncementState(
      current: state.current,
      queue: List.unmodifiable([...state.queue, ...nextItems]),
    );
  }

  void dismissCurrent() {
    if (state.queue.isEmpty) {
      state = const AchievementAnnouncementState.empty();
      return;
    }

    state = AchievementAnnouncementState(
      current: state.queue.first,
      queue: List.unmodifiable(state.queue.skip(1)),
    );
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/achievement_models.dart';

class AchievementAnnouncementState {
  const AchievementAnnouncementState({
    required this.queue,
    required this.current,
  });

  const AchievementAnnouncementState.empty() : queue = const [], current = null;

  final List<AchievementItem> queue;
  final AchievementItem? current;
}

class AchievementAnnouncementController
    extends Notifier<AchievementAnnouncementState> {
  @override
  AchievementAnnouncementState build() {
    return const AchievementAnnouncementState.empty();
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
        queue: nextItems.skip(1).toList(),
      );
      return;
    }

    state = AchievementAnnouncementState(
      current: state.current,
      queue: [...state.queue, ...nextItems],
    );
  }

  void dismissCurrent() {
    if (state.queue.isEmpty) {
      state = const AchievementAnnouncementState.empty();
      return;
    }

    state = AchievementAnnouncementState(
      current: state.queue.first,
      queue: state.queue.skip(1).toList(),
    );
  }
}

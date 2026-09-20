import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/data/repositories/achievements/achievement_announcement_repository.dart';
import 'package:pomodoist/data/repositories/achievements/achievement_announcement_repository_impl.dart';

final achievementAnnouncementRepositoryProvider =
    Provider<AchievementAnnouncementRepository>((ref) {
      final repository = DefaultAchievementAnnouncementRepository();
      ref.onDispose(repository.dispose);
      return repository;
    });

final achievementAnnouncementStateProvider =
    Provider<AchievementAnnouncementState>((ref) {
      final repository = ref.watch(achievementAnnouncementRepositoryProvider);
      final subscription = repository.watch().listen(
        (_) => ref.invalidateSelf(),
      );
      ref.onDispose(subscription.cancel);
      return repository.state;
    });

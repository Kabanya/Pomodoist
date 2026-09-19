import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/data/repositories/achievements/achievement_announcement_repository.dart';

final achievementAnnouncementRepositoryProvider =
    Provider<AchievementAnnouncementRepository>((ref) {
      final repository = AchievementAnnouncementRepository();
      ref.onDispose(repository.dispose);
      return repository;
    });

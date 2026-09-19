import 'package:pomodoist/utils/result.dart';

import 'package:pomodoist/domain/models/productivity/achievement_models.dart';

abstract interface class AchievementRepository {
  Stream<List<AchievementItem>> watchAchievements();

  Future<Result<List<AchievementItem>>> takePendingAnnouncements(
    List<AchievementItem> items,
  );
}

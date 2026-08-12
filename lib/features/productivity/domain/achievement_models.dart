enum AchievementGroup { focus, task, combo }

enum AchievementPresentation { globalBanner, bottomPlaque }

class AchievementItem {
  const AchievementItem({
    required this.id,
    required this.group,
    required this.presentation,
    required this.titleRu,
    required this.titleEn,
    required this.subtitleRu,
    required this.subtitleEn,
    required this.progress,
    required this.target,
  });

  final String id;
  final AchievementGroup group;
  final AchievementPresentation presentation;
  final String titleRu;
  final String titleEn;
  final String subtitleRu;
  final String subtitleEn;
  final int progress;
  final int target;

  bool get unlocked => progress >= target;

  double get progressRatio {
    if (target <= 0) {
      return unlocked ? 1 : 0;
    }
    return (progress / target).clamp(0, 1).toDouble();
  }

  String titleFor(String localeName) =>
      _isRussian(localeName) ? titleRu : titleEn;

  String subtitleFor(String localeName) =>
      _isRussian(localeName) ? subtitleRu : subtitleEn;

  static bool _isRussian(String localeName) {
    return localeName.toLowerCase().startsWith('ru');
  }
}

abstract interface class AchievementRepository {
  Stream<List<AchievementItem>> watchAchievements();

  Future<List<AchievementItem>> takePendingAnnouncements(
    List<AchievementItem> items,
  );
}

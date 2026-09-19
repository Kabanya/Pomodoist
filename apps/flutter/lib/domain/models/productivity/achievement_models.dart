enum AchievementGroup { focus, task, combo }

enum AchievementPresentation { globalBanner, bottomPlaque }

class AchievementItem {
  const AchievementItem({
    required this.id,
    required this.group,
    required this.presentation,
    required this.progress,
    required this.target,
  });

  final String id;
  final AchievementGroup group;
  final AchievementPresentation presentation;
  final int progress;
  final int target;

  bool get unlocked => progress >= target;

  double get progressRatio {
    if (target <= 0) {
      return unlocked ? 1 : 0;
    }
    return (progress / target).clamp(0, 1).toDouble();
  }
}

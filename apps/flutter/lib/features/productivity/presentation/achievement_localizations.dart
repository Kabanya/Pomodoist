import '../../../l10n/app_localizations.dart';
import '../domain/achievement_models.dart';

extension AchievementLocalizations on AchievementItem {
  String titleFor(AppLocalizations l10n) => l10n.achievementTitle(id);

  String subtitleFor(AppLocalizations l10n) => switch (id) {
    'combo_day_not_wasted' => l10n.achievementDayNotWastedSubtitle,
    'combo_focus_plus_check' => l10n.achievementFocusPlusCheckSubtitle,
    'combo_no_fuss' => l10n.achievementNoFussSubtitle,
    'combo_clean_entry' => l10n.achievementCleanEntrySubtitle,
    'combo_tomato_closed_question' => l10n.achievementTomatoClosedSubtitle,
    _ => switch (group) {
      AchievementGroup.focus => l10n.achievementFocusSubtitle(target),
      AchievementGroup.task => l10n.achievementTaskSubtitle(target),
      AchievementGroup.combo => l10n.comboAchievements,
    },
  };
}

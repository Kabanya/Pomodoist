import 'package:pomodoist/ui/core/localization/app_localizations.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';

extension FocusPresetLocalizations on FocusPresetItem {
  String displayName(AppLocalizations l10n) => switch ((id, name)) {
    (defaultPresetId, 'Classic') => l10n.themeClassic,
    (deepWorkPresetId, 'Deep Work') => l10n.focusPresetDeepWork,
    (shortSprintPresetId, 'Short Sprint') => l10n.focusPresetShortSprint,
    _ => name,
  };
}

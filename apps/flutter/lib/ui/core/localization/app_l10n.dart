import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:pomodoist/domain/models/settings/custom_model_config.dart';
import 'package:flutter/widgets.dart';
import 'package:pomodoist/ui/core/localization/app_localizations.dart';
import 'package:pomodoist/ui/core/localization/app_localizations_en.dart';

import 'package:pomodoist/domain/models/settings/app_shortcut.dart';

extension AppL10nContext on BuildContext {
  AppLocalizations get l10n =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ??
      AppLocalizationsEn();
}

String appShortcutLabel(AppLocalizations l10n, AppShortcutCommand command) =>
    switch (command) {
      AppShortcutCommand.togglePomo => l10n.settingsShortcutsTogglePomo,
      AppShortcutCommand.toggleSidebar => l10n.settingsShortcutsToggleSidebar,
      AppShortcutCommand.toggleTaskDetails =>
        l10n.settingsShortcutsToggleTaskDetails,
      AppShortcutCommand.toggleTaskDetailsAlternate =>
        l10n.settingsShortcutsToggleTaskDetailsAlternate,
      AppShortcutCommand.quickAdd => l10n.addTask,
      AppShortcutCommand.browse => l10n.navBrowse,
      AppShortcutCommand.search => l10n.navSearch,
      AppShortcutCommand.today => l10n.navToday,
      AppShortcutCommand.upcoming => l10n.navUpcoming,
      AppShortcutCommand.focus => l10n.navFocus,
      AppShortcutCommand.focusAlternate => l10n.settingsShortcutsFocusAlternate,
      AppShortcutCommand.inbox => l10n.navInbox,
      AppShortcutCommand.priorityMatrix => l10n.navPriorityMatrix,
      AppShortcutCommand.calendar => l10n.navCalendar,
      AppShortcutCommand.timeline => l10n.navTimeline,
      AppShortcutCommand.kanban => l10n.navKanban,
      AppShortcutCommand.reports => l10n.navReports,
      AppShortcutCommand.settings => l10n.navSettings,
    };

String modelCheckLabel(AppLocalizations l, ModelCheck check) => switch (check) {
  ModelCheck.success => l.customTestOk,
  ModelCheck.configuration => l.customInvalidUrl,
  ModelCheck.unauthorized => l.customDenied,
  ModelCheck.rateLimited => l.customRateLimit,
  ModelCheck.provider => l.customProviderError,
  ModelCheck.network => kIsWeb ? l.customBrowserNetwork : l.customNetwork,
  ModelCheck.timeout => l.customTimeout,
  ModelCheck.invalidResponse => l.customInvalidResponse,
};

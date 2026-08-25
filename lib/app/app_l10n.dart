import 'package:flutter/widgets.dart';
import 'package:pomodoist/l10n/app_localizations.dart';
import 'package:pomodoist/l10n/app_localizations_en.dart';

import 'keyboard_shortcuts.dart';

extension AppL10nContext on BuildContext {
  AppLocalizations get l10n =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ??
      AppLocalizationsEn();
}

String appShortcutLabel(AppLocalizations l10n, AppShortcutCommand command) =>
    switch (command) {
      AppShortcutCommand.toggleSidebar => l10n.settingsShortcutsToggleSidebar,
      AppShortcutCommand.quickAdd => l10n.addTask,
      AppShortcutCommand.browse => l10n.navBrowse,
      AppShortcutCommand.search => l10n.navSearch,
      AppShortcutCommand.today => l10n.navToday,
      AppShortcutCommand.upcoming => l10n.navUpcoming,
      AppShortcutCommand.focus => l10n.navFocus,
      AppShortcutCommand.inbox => l10n.navInbox,
      AppShortcutCommand.priorityMatrix => l10n.navPriorityMatrix,
      AppShortcutCommand.timeline => l10n.navTimeline,
      AppShortcutCommand.kanban => l10n.navKanban,
      AppShortcutCommand.reports => l10n.navReports,
      AppShortcutCommand.settings => l10n.navSettings,
    };

import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;
import 'package:pomodoist/domain/models/settings/bottom_navigation_preferences.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';

extension BottomNavigationPresentation on BottomNavigationDestination {
  String label(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      BottomNavigationDestination.today => l10n.navToday,
      BottomNavigationDestination.upcoming => l10n.navUpcoming,
      BottomNavigationDestination.focus => l10n.navFocus,
      BottomNavigationDestination.inbox => l10n.navInbox,
      BottomNavigationDestination.projects => l10n.navProjects,
      BottomNavigationDestination.browse => l10n.navBrowse,
      BottomNavigationDestination.search => l10n.navSearch,
      BottomNavigationDestination.calendar => l10n.navCalendar,
      BottomNavigationDestination.timeline => l10n.navTimeline,
      BottomNavigationDestination.kanban => l10n.navKanban,
      BottomNavigationDestination.priorityMatrix => l10n.navPriorityMatrix,
      BottomNavigationDestination.reports => l10n.navReports,
      BottomNavigationDestination.settings => l10n.navSettings,
    };
  }

  IconData get icon => switch (this) {
    BottomNavigationDestination.today => LucideIcons.calendarCheck,
    BottomNavigationDestination.upcoming => LucideIcons.calendarDays,
    BottomNavigationDestination.focus => LucideIcons.timer,
    BottomNavigationDestination.inbox => LucideIcons.inbox,
    BottomNavigationDestination.projects => LucideIcons.folder,
    BottomNavigationDestination.browse => LucideIcons.layoutGrid,
    BottomNavigationDestination.search => LucideIcons.search,
    BottomNavigationDestination.calendar => LucideIcons.calendarRange,
    BottomNavigationDestination.timeline => LucideIcons.chartNoAxesGantt,
    BottomNavigationDestination.kanban => LucideIcons.columns3,
    BottomNavigationDestination.priorityMatrix => LucideIcons.grid2x2,
    BottomNavigationDestination.reports =>
      LucideIcons.chartNoAxesColumnIncreasing,
    BottomNavigationDestination.settings => LucideIcons.settings2,
  };
}

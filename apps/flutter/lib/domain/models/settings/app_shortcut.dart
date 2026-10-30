enum AppShortcutCommand {
  toggleSidebar,
  togglePomo,
  toggleTaskDetails,
  toggleTaskDetailsAlternate,
  quickAdd,
  browse,
  search,
  today,
  upcoming,
  focus,
  focusAlternate,
  inbox,
  priorityMatrix,
  calendar,
  timeline,
  kanban,
  reports,
  settings;

  String get storageKey => name;
}

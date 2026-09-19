enum AppShortcutCommand {
  toggleSidebar,
  quickAdd,
  browse,
  search,
  today,
  upcoming,
  focus,
  inbox,
  priorityMatrix,
  timeline,
  kanban,
  reports,
  settings;

  String get storageKey => name;
}

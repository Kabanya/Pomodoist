// ignore_for_file: deprecated_member_use

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/keyboard_shortcuts.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/ui/core/platform/macos_app_menu.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/domain/use_cases/tasks/project_list_data.dart';

final class ShellKeyboardState {
  const ShellKeyboardState({required this.platform, required this.shortcuts});

  final TargetPlatform platform;
  final Map<AppShortcutCommand, AppShortcutBinding> shortcuts;

  bool matchesZoom(KeyEvent event, HardwareKeyboard keyboard) =>
      appZoomBindings(
        platform,
      ).keys.any((binding) => binding.matches(event, keyboard));

  bool matchesZoomRaw(RawKeyEvent event) => appZoomBindings(
    platform,
  ).keys.any((binding) => binding.matchesRawEvent(event));
}

final shellKeyboardViewModelProvider = Provider<ShellKeyboardState>((ref) {
  ref.watch(keyboardShortcutsLoadedProvider);
  return ShellKeyboardState(
    platform: ref.watch(shortcutTargetPlatformProvider),
    shortcuts: ref.watch(keyboardShortcutsProvider),
  );
});

final shellTodayFocusStripVisibleProvider = Provider<bool>(
  (ref) => ref.watch(todayFocusStripVisibleProvider),
);

final class ShellSidebarState {
  const ShellSidebarState({
    required this.displayName,
    required this.inboxCount,
    required this.todayCount,
    required this.upcomingCount,
    required this.projects,
    required this.projectTaskCounts,
  });

  final String? displayName;
  final int inboxCount;
  final int todayCount;
  final int upcomingCount;
  final AsyncValue<List<ProjectItem>> projects;
  final Map<String, int> projectTaskCounts;
}

final shellSidebarViewModelProvider = Provider<ShellSidebarState>((ref) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final profile = ref.watch(accountProfileProvider);
  final inbox = ref.watch(tasksByQueryProvider(const TaskQuery.inbox()));
  final todayTasks = ref.watch(
    tasksByQueryProvider(TaskQuery(kind: TaskQueryKind.today, now: today)),
  );
  final upcoming = ref.watch(
    tasksByQueryProvider(TaskQuery(kind: TaskQueryKind.upcoming, now: today)),
  );
  final all = ref.watch(tasksByQueryProvider(const TaskQuery.all()));
  return ShellSidebarState(
    displayName: profile?.displayName ?? profile?.email,
    inboxCount: _openTaskCount(inbox),
    todayCount: _openTaskCount(todayTasks),
    upcomingCount: _openTaskCount(upcoming),
    projects: ref.watch(projectsProvider),
    projectTaskCounts: countOpenTasksByProject(all.value ?? const []),
  );
});

int _openTaskCount(AsyncValue<List<TaskItem>> value) =>
    value.value?.where((task) => !task.isCompleted && !task.isDeleted).length ??
    0;

abstract interface class ShellAppMenu {
  Future<void> sync({
    required String locale,
    required Map<AppShortcutCommand, String> labels,
    required ShellKeyboardState keyboard,
  });
  void dispose();
}

ShellAppMenu? createShellAppMenu({
  required ShellKeyboardState keyboard,
  required ValueChanged<String> onSelected,
}) => keyboard.platform == TargetPlatform.macOS
    ? _ShellAppMenu(
        MacOSAppMenuController(
          platform: keyboard.platform,
          onSelected: onSelected,
          allowedCommandIds: {
            for (final command in AppShortcutCommand.values) command.name,
          },
        ),
      )
    : null;

final class _ShellAppMenu implements ShellAppMenu {
  const _ShellAppMenu(this._controller);
  final MacOSAppMenuController _controller;

  @override
  Future<void> sync({
    required String locale,
    required Map<AppShortcutCommand, String> labels,
    required ShellKeyboardState keyboard,
  }) => _controller.sync(
    locale: locale,
    commands: [
      for (final command in AppShortcutCommand.values)
        MacOSMenuCommand(
          id: command.name,
          label: labels[command]!,
          keyLabel: keyboard.shortcuts[command]!.keyLabel,
          meta: keyboard.shortcuts[command]!.meta,
          control: keyboard.shortcuts[command]!.control,
          alt: keyboard.shortcuts[command]!.alt,
          shift: keyboard.shortcuts[command]!.shift,
        ),
    ],
  );

  @override
  void dispose() => _controller.dispose();
}

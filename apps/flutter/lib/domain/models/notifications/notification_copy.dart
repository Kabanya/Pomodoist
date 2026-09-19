final class NotificationCopy {
  const NotificationCopy({
    required this.focusCompleted,
    required this.longBreakCompleted,
    required this.breakCompleted,
    required this.focusChannel,
    required this.focusDescription,
    required this.taskChannel,
    required this.taskDescription,
    required this.returnChannel,
    required this.returnDescription,
    required this.openApp,
  });

  const NotificationCopy.english()
    : focusCompleted = 'Focus interval completed',
      longBreakCompleted = 'Long break completed',
      breakCompleted = 'Break completed',
      focusChannel = 'Focus',
      focusDescription = 'Focus interval completion notifications',
      taskChannel = 'Task start',
      taskDescription = 'Task start notifications',
      returnChannel = 'Return reminders',
      returnDescription = 'Gentle reminders to return to Pomodoist',
      openApp = 'Open Pomodoist';

  final String focusCompleted;
  final String longBreakCompleted;
  final String breakCompleted;
  final String focusChannel;
  final String focusDescription;
  final String taskChannel;
  final String taskDescription;
  final String returnChannel;
  final String returnDescription;
  final String openApp;
}

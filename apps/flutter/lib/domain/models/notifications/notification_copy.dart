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
    required this.taskStarting,
    required this.returnMessages,
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
      openApp = 'Open Pomodoist',
      taskStarting = 'Task starting',
      returnMessages = const [
        (
          title: 'Pomo misses you',
          body: 'If you have the energy, finish one small task.',
        ),
        (
          title: 'Pomo checking in',
          body: 'Choose the easiest item on your list — one is enough.',
        ),
        (
          title: 'Pomo is here',
          body: 'You can start with a task you can finish today.',
        ),
        (
          title: 'An evening with Pomo',
          body: 'One finished task is already a good step.',
        ),
        (
          title: 'A reminder from Pomo',
          body: 'Check your list and pick one manageable thing for tonight.',
        ),
      ];

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
  final String taskStarting;
  final List<({String title, String body})> returnMessages;

  ({String title, String body}) returnMessageFor(DateTime date) {
    final day = DateTime.utc(date.year, date.month, date.day);
    final index =
        day.difference(DateTime.utc(2026)).inDays % returnMessages.length;
    return returnMessages[index];
  }
}

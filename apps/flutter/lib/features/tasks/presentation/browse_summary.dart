import '../../productivity/domain/productivity_models.dart';

enum BrowsePeriod { today, sevenDays }

({int completedTasks, int focusIntervals, int focusSeconds, int openTasks})
browseSummary(ProductivitySummary summary, BrowsePeriod period) {
  var completedTasks = summary.completedTasks;
  var focusIntervals = summary.completedFocusIntervals;
  var focusSeconds = summary.totalFocusSeconds;
  if (period == BrowsePeriod.sevenDays) {
    completedTasks = 0;
    focusIntervals = 0;
    focusSeconds = 0;
    for (final day in summary.lastSevenDays) {
      completedTasks += day.completedTasks;
      focusIntervals += day.completedFocusIntervals;
      focusSeconds += day.totalFocusSeconds;
    }
  }
  return (
    completedTasks: completedTasks,
    focusIntervals: focusIntervals,
    focusSeconds: focusSeconds,
    openTasks: summary.openTasks,
  );
}

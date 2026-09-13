class ProductivitySummary {
  const ProductivitySummary({
    required this.completedTasks,
    required this.completedFocusIntervals,
    required this.totalFocusSeconds,
    required this.plannedFocusIntervals,
    required this.openTasks,
    required this.allTimeCompletedTasks,
    required this.allTimeCompletedFocusIntervals,
    this.lastSevenDays = const [],
  });

  final int completedTasks;
  final int completedFocusIntervals;
  final int totalFocusSeconds;
  final int plannedFocusIntervals;
  final int openTasks;
  final int allTimeCompletedTasks;
  final int allTimeCompletedFocusIntervals;
  final List<ProductivityDaySummary> lastSevenDays;
}

class ProductivityDaySummary {
  const ProductivityDaySummary({
    required this.localDate,
    required this.completedTasks,
    required this.completedFocusIntervals,
    required this.totalFocusSeconds,
  });

  final DateTime localDate;
  final int completedTasks;
  final int completedFocusIntervals;
  final int totalFocusSeconds;
}

abstract interface class ProductivityRepository {
  Stream<ProductivitySummary> watchTodaySummary();
  Future<void> recalculateDailyStats(DateTime localDate);
}

import 'package:pomodoist/utils/result.dart';

import 'package:pomodoist/domain/models/productivity/productivity_models.dart';

abstract interface class ProductivityRepository {
  Stream<ProductivitySummary> watchTodaySummary();
  Future<Result<void>> recalculateDailyStats(DateTime localDate);
}

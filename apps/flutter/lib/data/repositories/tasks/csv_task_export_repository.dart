import 'package:pomodoist/utils/result.dart';

abstract interface class CsvTaskExportRepository {
  /// False means the save was cancelled or the account changed.
  Future<Result<bool>> exportAllTasks();
}

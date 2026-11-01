import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/csv_task_export_dependencies.dart';
import 'package:pomodoist/data/repositories/tasks/csv_task_export_repository.dart';
import 'package:pomodoist/utils/result.dart';

final csvTaskExportViewModelProvider =
    NotifierProvider.autoDispose<CsvTaskExportViewModel, bool>(
      CsvTaskExportViewModel.new,
    );

class CsvTaskExportViewModel extends Notifier<bool> {
  late CsvTaskExportRepository _exporter;

  @override
  bool build() {
    _exporter = ref.watch(csvTaskExportRepositoryProvider);
    return false;
  }

  Future<Result<bool>> exportAllTasks() async {
    if (state) return const Success(false);
    state = true;
    try {
      return await _exporter.exportAllTasks();
    } finally {
      if (ref.mounted) state = false;
    }
  }
}

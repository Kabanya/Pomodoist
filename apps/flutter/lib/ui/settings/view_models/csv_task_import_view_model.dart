import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/domain/use_cases/tasks/csv_task_import_use_case.dart';
import 'package:pomodoist/domain/models/tasks/csv_task_import.dart';
import 'package:pomodoist/utils/result.dart';

final class CsvTaskImportState {
  const CsvTaskImportState({this.busy = false, this.preview});
  final bool busy;
  final CsvTaskImportPreview? preview;
}

final csvTaskImportViewModelProvider =
    NotifierProvider.autoDispose<CsvTaskImportViewModel, CsvTaskImportState>(
      CsvTaskImportViewModel.new,
    );

class CsvTaskImportViewModel extends Notifier<CsvTaskImportState> {
  late CsvTaskImportUseCase _importer;
  @override
  CsvTaskImportState build() {
    _importer = ref.watch(csvTaskImporterProvider);
    return const CsvTaskImportState();
  }

  bool beginSelection() {
    if (state.busy) return false;
    state = const CsvTaskImportState(busy: true);
    return true;
  }

  Future<Result<CsvTaskImportPreview>> prepare(List<int> bytes) async {
    final result = await _importer.prepare(bytes);
    if (ref.mounted) {
      switch (result) {
        case Success(value: final preview):
          state = CsvTaskImportState(busy: true, preview: preview);
        case Failure():
          break;
      }
    }
    return result;
  }

  Future<Result<CsvTaskImportResult>> commit() {
    final preview = state.preview;
    if (preview == null) {
      return Future.value(
        Failure(StateError('Import preview is required.'), StackTrace.current),
      );
    }
    return _importer.commit(preview);
  }

  void finish() {
    state = const CsvTaskImportState();
  }
}

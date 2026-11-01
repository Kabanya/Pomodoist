import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/csv_task_export_dependencies.dart';
import 'package:pomodoist/data/repositories/tasks/csv_task_export_repository.dart';
import 'package:pomodoist/ui/settings/view_models/csv_task_export_view_model.dart';
import 'package:pomodoist/utils/result.dart';

void main() {
  test(
    'blocks concurrent exports and allows retry after failure or cancel',
    () async {
      final repository = _Exporter();
      final container = ProviderContainer(
        overrides: [
          csvTaskExportRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        csvTaskExportViewModelProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      final viewModel = container.read(csvTaskExportViewModelProvider.notifier);

      final first = viewModel.exportAllTasks();
      expect(container.read(csvTaskExportViewModelProvider), isTrue);
      expect((await viewModel.exportAllTasks()).getOrThrow(), isFalse);
      expect(repository.calls, 1);
      repository.pending.complete(
        Failure(StateError('disk full'), StackTrace.current),
      );
      expect(await first, isA<Failure<bool>>());
      expect(container.read(csvTaskExportViewModelProvider), isFalse);

      repository.pending = Completer<Result<bool>>();
      final retry = viewModel.exportAllTasks();
      repository.pending.complete(const Success(false));
      expect((await retry).getOrThrow(), isFalse);
      expect(container.read(csvTaskExportViewModelProvider), isFalse);
      expect(repository.calls, 2);
    },
  );
}

class _Exporter implements CsvTaskExportRepository {
  var calls = 0;
  var pending = Completer<Result<bool>>();
  @override
  Future<Result<bool>> exportAllTasks() {
    calls++;
    return pending.future;
  }
}

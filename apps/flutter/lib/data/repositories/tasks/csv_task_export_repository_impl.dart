import 'package:pomodoist/data/repositories/tasks/csv_task_export_repository.dart';
import 'package:pomodoist/data/services/files/csv_task_export_service.dart';
import 'package:pomodoist/domain/models/account/account_session.dart';
import 'package:pomodoist/utils/result.dart';

final class DriftCsvTaskExportRepository implements CsvTaskExportRepository {
  DriftCsvTaskExportRepository(
    this._service, {
    required AccountSession Function() currentSession,
    DateTime Function()? now,
  }) : _currentSession = currentSession,
       _now = now ?? DateTime.now;

  final CsvTaskExportService _service;
  final AccountSession Function() _currentSession;
  final DateTime Function() _now;

  @override
  Future<Result<bool>> exportAllTasks() => Result.capture(() async {
    final session = _currentSession();
    final snapshot = await _service.snapshot();
    final owner = snapshot.owner;
    final expectedOwner = session.userId ?? 'guest';
    bool current() => _currentSession() == session;
    if (!current() || (owner.userId ?? 'guest') != expectedOwner) {
      return false;
    }
    final date = _now().toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    final name =
        'pomodoist-tasks-${date.year.toString().padLeft(4, '0')}-'
        '${two(date.month)}-${two(date.day)}-'
        '${two(date.hour)}${two(date.minute)}${two(date.second)}.csv';
    final path = await _service.selectPath(name);
    if (path == null || !current()) return false;
    final ownerNow = await _service.owner();
    if (!current() || ownerNow != owner) return false;
    await _service.writeFile(snapshot.bytes, name, path);
    return true;
  });
}

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/repositories/pomo/pomo_activity_repository_impl.dart';
import 'package:pomodoist/domain/models/pomo/pomo_focus.dart';

void main() {
  test(
    'fatigue survives run changes and resets only at a completed break',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final start = DateTime.utc(2026, 10, 18);
      Future<void> add(
        String id,
        String run,
        int minute, {
        String type = 'work',
        String status = 'stopped',
      }) => db
          .into(db.focusIntervals)
          .insert(
            FocusIntervalsCompanion.insert(
              id: id,
              runId: run,
              type: type,
              status: status,
              plannedSeconds: 1800,
              startedAt: start.add(Duration(minutes: minute)),
              pausedTotalSeconds: const Value(0),
              stoppedAt: Value(start.add(Duration(minutes: minute + 30))),
              completedAt: Value(
                status == 'completed'
                    ? start.add(Duration(minutes: minute + 30))
                    : null,
              ),
              sequenceNumber: 1,
              createdAt: start,
              updatedAt: start,
            ),
          )
          .then((_) {});
      await add('a', 'run-a', 0);
      await add('b', 'run-b', 30);
      final repo = LocalPomoActivityRepository(db);
      expect(
        pomoWorkSinceBreak(
          await repo.watchSinceBreak().first,
          start.add(const Duration(hours: 2)),
        ),
        const Duration(hours: 1),
      );
      await add('break', 'run-b', 60, type: 'shortBreak', status: 'completed');
      expect(await repo.watchSinceBreak().first, isEmpty);
      await add('c', 'run-c', 90);
      expect(
        pomoWorkSinceBreak(
          await repo.watchSinceBreak().first,
          start.add(const Duration(hours: 3)),
        ),
        const Duration(minutes: 30),
      );
    },
  );
}

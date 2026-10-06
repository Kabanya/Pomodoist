import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:pomodoist/data/repositories/habits/habit_repository.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/habit_row_mapping.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/domain/models/habits/habit_models.dart';
import 'package:pomodoist/domain/models/habits/habit_icons.dart';
import 'package:pomodoist/utils/result.dart';

class DriftHabitRepository implements HabitRepository {
  DriftHabitRepository(this._db, this._outbox, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();
  final AppDatabase _db;
  final OutboxService _outbox;
  final Uuid _uuid;
  @override
  Stream<List<Habit>> watchHabits() =>
      (_db.select(_db.habits)
            ..where((h) => h.isDeleted.not())
            ..orderBy([
              (h) => OrderingTerm.asc(h.createdAt),
              (h) => OrderingTerm.asc(h.id),
            ]))
          .watch()
          .map((rows) => List.unmodifiable(rows.map(habitFromRow)));
  @override
  Stream<List<HabitCheckIn>> watchCheckIns() =>
      (_db.select(_db.habitCheckIns)..where((c) => c.isDeleted.not()))
          .watch()
          .map((rows) => List.unmodifiable(rows.map(habitCheckInFromRow)));

  Future<void> _validateProject(String? id) async {
    if (id == null) return;
    final project = await (_db.select(
      _db.projects,
    )..where((p) => p.id.equals(id))).getSingleOrNull();
    if (project == null ||
        project.scopeId != null ||
        project.isArchived ||
        project.isDeleted) {
      throw ArgumentError('Select an active personal project');
    }
  }

  Future<Habit> _find(String id) async {
    final row = await (_db.select(
      _db.habits,
    )..where((h) => h.id.equals(id))).getSingleOrNull();
    if (row == null || row.isDeleted) throw StateError('Habit unavailable');
    return habitFromRow(row);
  }

  Future<void> _save(Habit habit, String type) async {
    await _db.into(_db.habits).insertOnConflictUpdate(habitToRow(habit));
    await _outbox.enqueueBatch([
      SyncQueueCommand(type: type, clientId: habit.id, payload: habit.toJson()),
    ], occurredAt: habit.updatedAt);
  }

  @override
  Future<Result<String>> createHabit(
    HabitDraft draft, {
    required DateTime now,
  }) => Result.capture(
    () => _db.transaction(() async {
      await _validateProject(draft.projectId);
      final habit = Habit(
        id: _uuid.v4(),
        userId: localUserId,
        title: draft.title,
        icon: normalizeHabitIcon(draft.icon),
        projectId: draft.projectId,
        reminderMinutes: draft.reminderMinutes,
        scheduleHistory: [draft.schedule(draft.startDate)],
        createdAt: now.toUtc(),
        updatedAt: now.toUtc(),
      );
      await _save(habit, 'habit.create');
      return habit.id;
    }),
  );
  @override
  Future<Result<void>> updateHabit(
    String id,
    HabitDraft draft, {
    required DateTime now,
  }) => Result.capture(
    () => _db.transaction(() async {
      final old = await _find(id);
      await _validateProject(draft.projectId);
      final today = habitDate(now.toLocal());
      final current = old.scheduleHistory.last;
      final candidate = draft.schedule(today);
      final same =
          current.startDate == candidate.startDate &&
          current.endDate == candidate.endDate &&
          current.targetPerDay == candidate.targetPerDay &&
          current.dayPeriod == candidate.dayPeriod &&
          current.periodTargets.length == candidate.periodTargets.length &&
          current.periodTargets.entries.every(
            (e) => candidate.periodTargets[e.key] == e.value,
          ) &&
          current.weekdays.toSet().containsAll(candidate.weekdays) &&
          current.weekdays.length == candidate.weekdays.length;
      final history = same
          ? old.scheduleHistory
          : [
              ...old.scheduleHistory.where(
                (s) => s.effectiveFrom.isBefore(today),
              ),
              candidate,
            ];
      await _save(
        Habit(
          id: id,
          userId: old.userId,
          title: draft.title,
          icon: draft.icon == old.icon
              ? old.icon
              : normalizeHabitIcon(draft.icon),
          projectId: draft.projectId,
          reminderMinutes: draft.reminderMinutes,
          scheduleHistory: history,
          createdAt: old.createdAt,
          updatedAt: now.toUtc(),
        ),
        'habit.update',
      );
    }),
  );
  @override
  Future<Result<void>> updateIcon(
    String id,
    String? icon, {
    required DateTime now,
  }) => Result.capture(
    () => _db.transaction(() async {
      final old = await _find(id);
      final normalized = normalizeHabitIcon(icon);
      if (old.icon == normalized) return;
      final stamp = now.toUtc();
      await (_db.update(_db.habits)..where((h) => h.id.equals(id))).write(
        HabitsCompanion(icon: Value(normalized), updatedAt: Value(stamp)),
      );
      await _outbox.enqueueBatch([
        SyncQueueCommand(
          type: 'habit.update',
          clientId: id,
          payload: {'icon': normalized, 'updatedAt': stamp.toIso8601String()},
        ),
      ], occurredAt: stamp);
    }),
  );
  @override
  Future<Result<void>> deleteHabit(String id, {required DateTime now}) =>
      Result.capture(
        () => _db.transaction(() async {
          final old = await _find(id);
          await _save(
            Habit(
              id: id,
              userId: old.userId,
              title: old.title,
              icon: old.icon,
              projectId: old.projectId,
              reminderMinutes: old.reminderMinutes,
              scheduleHistory: old.scheduleHistory,
              createdAt: old.createdAt,
              updatedAt: now.toUtc(),
              isDeleted: true,
            ),
            'habit.delete',
          );
        }),
      );
  @override
  Future<Result<void>> addCheckIn(
    String id,
    DateTime day, {
    required DateTime now,
    HabitDayPeriod? period,
  }) => Result.capture(
    () => _db.transaction(() async {
      final habit = await _find(id);
      final date = habitDate(day);
      if (date.isAfter(habitDate(now.toLocal())) ||
          !habit.isScheduledOn(date)) {
        throw ArgumentError('Day is not editable');
      }
      final existing =
          await (_db.select(_db.habitCheckIns)..where(
                (c) =>
                    c.habitId.equals(id) &
                    c.day.equals(habitDayKey(date)) &
                    c.isDeleted.not(),
              ))
              .get();
      final targets = habit
          .scheduleFor(date)!
          .targetsFor(habit.reminderMinutes);
      final selected =
          period ?? (targets.length == 1 ? targets.keys.single : null);
      if (selected == null || !targets.containsKey(selected)) {
        throw ArgumentError('Select a scheduled period');
      }
      final counts = habitPeriodCounts(
        habit,
        date,
        existing.map(habitCheckInFromRow),
      );
      if (counts[selected]! >= targets[selected]!) {
        throw StateError('Period goal already reached');
      }
      final checkIn = HabitCheckIn(
        id: _uuid.v4(),
        userId: localUserId,
        habitId: id,
        dayPeriod: selected,
        day: date,
        createdAt: now.toUtc(),
        updatedAt: now.toUtc(),
      );
      await _db.into(_db.habitCheckIns).insert(habitCheckInToRow(checkIn));
      await _outbox.enqueueBatch([
        SyncQueueCommand(
          type: 'habit_check_in.create',
          clientId: checkIn.id,
          payload: checkIn.toJson(),
        ),
      ], occurredAt: now);
    }),
  );
  @override
  Future<Result<void>> undoCheckIn(
    String id,
    DateTime day, {
    required DateTime now,
    HabitDayPeriod? period,
  }) => Result.capture(
    () => _db.transaction(() async {
      final habit = await _find(id);
      if (habitDate(day).isAfter(habitDate(now.toLocal()))) {
        throw ArgumentError('Day is not editable');
      }
      final rows =
          await (_db.select(_db.habitCheckIns)
                ..where(
                  (c) =>
                      c.habitId.equals(id) &
                      c.day.equals(habitDayKey(day)) &
                      c.isDeleted.not(),
                )
                ..orderBy([
                  (c) => OrderingTerm.desc(c.createdAt),
                  (c) => OrderingTerm.desc(c.id),
                ]))
              .get();
      final assigned = habitCheckInPeriods(
        habit,
        day,
        rows.map(habitCheckInFromRow),
      );
      final row = rows
          .where((r) => period == null || assigned[r.id] == period)
          .firstOrNull;
      if (row == null) return;
      final checkIn = HabitCheckIn(
        id: row.id,
        userId: row.userId,
        habitId: id,
        dayPeriod: habitCheckInFromRow(row).dayPeriod,
        day: day,
        createdAt: row.createdAt,
        updatedAt: now.toUtc(),
        isDeleted: true,
      );
      await _db
          .into(_db.habitCheckIns)
          .insertOnConflictUpdate(habitCheckInToRow(checkIn));
      await _outbox.enqueueBatch([
        SyncQueueCommand(
          type: 'habit_check_in.delete',
          clientId: row.id,
          payload: checkIn.toJson(),
        ),
      ], occurredAt: now);
    }),
  );
}

import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/data/repositories/habits/habit_repository_impl.dart';
import 'package:pomodoist/domain/models/habits/habit_models.dart';

void main() {
  final today = DateTime(2026, 9, 30, 12);
  late AppDatabase db;
  late DriftHabitRepository repo;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.ensureSeedData();
    repo = DriftHabitRepository(db, DriftOutboxService(db));
  });
  tearDown(() => db.close());
  HabitDraft draft({int target = 2}) => HabitDraft(
    title: 'Read',
    startDate: DateTime(2026, 9, 28),
    targetPerDay: target,
  );
  Future<String> create() async =>
      (await repo.createHabit(draft(), now: today)).getOrThrow();
  test(
    'icon-only writes preserve goals, reminders and check-ins and roll back on outbox failure',
    () async {
      final id = (await repo.createHabit(
        HabitDraft(
          title: 'Read',
          startDate: today,
          targetPerDay: 2,
          reminderMinutes: 480,
          icon: '📚',
        ),
        now: today,
      )).getOrThrow();
      (await repo.addCheckIn(id, today, now: today)).getOrThrow();
      final before = (await repo.watchHabits().first).single.toJson();
      final stamp = today.add(const Duration(minutes: 1));
      (await repo.updateIcon(id, 'bookOpen', now: stamp)).getOrThrow();
      final after = (await repo.watchHabits().first).single.toJson();
      expect(after, {
        ...before,
        'icon': 'bookOpen',
        'updatedAt': stamp.toUtc().toIso8601String(),
      });
      expect(await repo.watchCheckIns().first, hasLength(1));
      final commands = await db.select(db.syncCommands).get();
      expect(jsonDecode(commands.last.payloadJson), {
        'icon': 'bookOpen',
        'updatedAt': stamp.toUtc().toIso8601String(),
      });
      final failing = DriftHabitRepository(db, _FailingOutbox(db));
      expect(
        (await failing.updateIcon(id, '👍🏽', now: stamp)).getOrThrow,
        throwsStateError,
      );
      expect((await repo.watchHabits().first).single.icon, 'bookOpen');
      expect(await db.select(db.syncCommands).get(), hasLength(3));
      expect(
        (await repo.updateIcon(id, 'invalid', now: stamp)).getOrThrow,
        throwsArgumentError,
      );
      expect((await repo.watchHabits().first).single.icon, 'bookOpen');
      (await repo.updateHabit(
        id,
        HabitDraft(
          title: 'Read again',
          startDate: today,
          targetPerDay: 2,
          reminderMinutes: 480,
          icon: 'bookOpen',
        ),
        now: stamp,
      )).getOrThrow();
      expect((await repo.watchHabits().first).single.icon, 'bookOpen');
      (await repo.updateIcon(id, null, now: stamp)).getOrThrow();
      expect((await repo.watchHabits().first).single.icon, isNull);
      (await repo.deleteHabit(id, now: stamp)).getOrThrow();
      expect(
        (await repo.updateIcon(id, 'heart', now: stamp)).getOrThrow,
        throwsStateError,
      );
    },
  );
  test('editing a habit preserves an unchanged future sign', () async {
    final id = await create();
    await db.customStatement('UPDATE habits SET icon = ? WHERE id = ?', [
      'futureIcon',
      id,
    ]);
    (await repo.updateHabit(
      id,
      HabitDraft(
        title: 'Read again',
        startDate: DateTime(2026, 9, 28),
        targetPerDay: 2,
        icon: 'futureIcon',
      ),
      now: today,
    )).getOrThrow();
    expect((await repo.watchHabits().first).single.icon, 'futureIcon');
    final updates = await (db.select(
      db.syncCommands,
    )..where((c) => c.type.equals('habit.update'))).get();
    expect(jsonDecode(updates.single.payloadJson)['icon'], 'futureIcon');
  });
  test(
    'schema 10 migration preserves data and signs survive a restart',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'habit-icon-migration-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/habits.sqlite');
      var disk = AppDatabase(NativeDatabase(file));
      try {
        var saved = DriftHabitRepository(disk, DriftOutboxService(disk));
        final id = (await saved.createHabit(draft(), now: today)).getOrThrow();
        (await saved.addCheckIn(id, today, now: today)).getOrThrow();
        await disk.customStatement('ALTER TABLE habits DROP COLUMN icon');
        await disk.customStatement('PRAGMA user_version = 10');
        await disk.close();
        disk = AppDatabase(NativeDatabase(file));
        saved = DriftHabitRepository(disk, DriftOutboxService(disk));
        expect((await saved.watchHabits().first).single.icon, isNull);
        expect(await saved.watchCheckIns().first, hasLength(1));
        expect(await disk.select(disk.syncCommands).get(), hasLength(2));
        (await saved.updateIcon(id, '👨‍👩‍👧‍👦', now: today)).getOrThrow();
        await disk.close();
        disk = AppDatabase(NativeDatabase(file));
        saved = DriftHabitRepository(disk, DriftOutboxService(disk));
        expect((await saved.watchHabits().first).single.icon, '👨‍👩‍👧‍👦');
        expect(await saved.watchCheckIns().first, hasLength(1));
      } finally {
        await disk.close();
      }
    },
  );
  test(
    'period changes persist in existing JSON and preserve older schedules',
    () async {
      final id = await create();
      (await repo.addCheckIn(
        id,
        DateTime(2026, 9, 29),
        now: today,
      )).getOrThrow();
      (await repo.updateHabit(
        id,
        HabitDraft(
          title: 'Read',
          startDate: DateTime(2026, 9, 28),
          targetPerDay: 2,
          dayPeriod: HabitDayPeriod.morning,
        ),
        now: today,
      )).getOrThrow();
      final habit = (await repo.watchHabits().first).single;
      expect(
        habit.scheduleFor(DateTime(2026, 9, 29))!.dayPeriod,
        HabitDayPeriod.automatic,
      );
      expect(habit.scheduleFor(today)!.dayPeriod, HabitDayPeriod.morning);
      expect(await repo.watchCheckIns().first, hasLength(1));
      final commands = await db.select(db.syncCommands).get();
      final payload = jsonDecode(
        commands.singleWhere((c) => c.type == 'habit.update').payloadJson,
      );
      expect(payload['scheduleHistory'].last['dayPeriod'], 'morning');
      expect(db.schemaVersion, 11);
    },
  );
  test(
    'offline create stores domain data and captured outbox atomically',
    () async {
      final id = await create();
      final habits = await repo.watchHabits().first;
      expect(habits.single.id, id);
      expect(habits.single.scheduleFor(today)!.targetPerDay, 2);
      final command = await db.select(db.syncCommands).getSingle();
      expect(command.type, 'habit.create');
      expect(jsonDecode(command.payloadJson)['title'], 'Read');
    },
  );
  test('outbox failure rolls back habit write', () async {
    final failing = DriftHabitRepository(db, _FailingOutbox(db));
    expect(
      (await failing.createHabit(draft(), now: today)).getOrThrow,
      throwsStateError,
    );
    expect(await repo.watchHabits().first, isEmpty);
    expect(await db.select(db.syncCommands).get(), isEmpty);
  });
  test('check-ins are bounded and undo preserves a deleted record', () async {
    final id = await create();
    (await repo.addCheckIn(id, today, now: today)).getOrThrow();
    (await repo.addCheckIn(
      id,
      today,
      now: today.add(const Duration(seconds: 1)),
    )).getOrThrow();
    expect(
      (await repo.addCheckIn(id, today, now: today)).getOrThrow,
      throwsStateError,
    );
    expect(await repo.watchCheckIns().first, hasLength(2));
    (await repo.undoCheckIn(
      id,
      today,
      now: today.add(const Duration(minutes: 1)),
    )).getOrThrow();
    expect(await repo.watchCheckIns().first, hasLength(1));
    expect(
      (await db.select(db.habitCheckIns).get()).where((c) => c.isDeleted),
      hasLength(1),
    );
  });
  test(
    'past check-ins allowed but future and unscheduled days rejected',
    () async {
      final id = await create();
      (await repo.addCheckIn(
        id,
        DateTime(2026, 9, 29),
        now: today,
      )).getOrThrow();
      expect(
        (await repo.addCheckIn(
          id,
          DateTime(2026, 10, 1),
          now: today,
        )).getOrThrow,
        throwsArgumentError,
      );
      expect(
        (await repo.addCheckIn(
          id,
          DateTime(2026, 9, 27),
          now: today,
        )).getOrThrow,
        throwsArgumentError,
      );
    },
  );
  test(
    'edit preserves historical target and same-day edits replace version',
    () async {
      final id = await create();
      (await repo.updateHabit(id, draft(target: 3), now: today)).getOrThrow();
      (await repo.updateHabit(id, draft(target: 4), now: today)).getOrThrow();
      final habit = (await repo.watchHabits().first).single;
      expect(habit.scheduleHistory, hasLength(2));
      expect(habit.scheduleFor(DateTime(2026, 9, 29))!.targetPerDay, 2);
      expect(habit.scheduleFor(today)!.targetPerDay, 4);
    },
  );
  test('delete hides habit and forbids a late local check-in', () async {
    final id = await create();
    (await repo.deleteHabit(id, now: today)).getOrThrow();
    expect(await repo.watchHabits().first, isEmpty);
    expect(
      (await repo.addCheckIn(id, today, now: today)).getOrThrow,
      throwsStateError,
    );
    expect((await db.select(db.habits).getSingle()).isDeleted, isTrue);
  });
  test(
    'check-in and undo both roll back when their outbox write fails',
    () async {
      final id = await create();
      final failing = DriftHabitRepository(db, _FailingOutbox(db));
      expect(
        (await failing.addCheckIn(id, today, now: today)).getOrThrow,
        throwsStateError,
      );
      expect(await repo.watchCheckIns().first, isEmpty);
      expect(await db.select(db.syncCommands).get(), hasLength(1));
      (await repo.addCheckIn(id, today, now: today)).getOrThrow();
      expect(
        (await failing.undoCheckIn(id, today, now: today)).getOrThrow,
        throwsStateError,
      );
      expect(await repo.watchCheckIns().first, hasLength(1));
      expect(await db.select(db.syncCommands).get(), hasLength(2));
    },
  );
  for (final legacyVersion in [8, 9]) {
    test(
      'version $legacyVersion upgrade preserves legacy marks and stores period attribution',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'habit-period-migration-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final file = File('${directory.path}/habits.sqlite');
        var disk = AppDatabase(NativeDatabase(file));
        try {
          var saved = DriftHabitRepository(disk, DriftOutboxService(disk));
          final id = (await saved.createHabit(
            draft(),
            now: today,
          )).getOrThrow();
          (await saved.addCheckIn(id, today, now: today)).getOrThrow();
          final original = (await saved.watchCheckIns().first).single;
          await disk.customStatement(
            'ALTER TABLE habit_check_ins DROP COLUMN day_period',
          );
          await disk.customStatement('PRAGMA user_version = $legacyVersion');
          await disk.close();
          disk = AppDatabase(NativeDatabase(file));
          saved = DriftHabitRepository(disk, DriftOutboxService(disk));
          final legacy = (await saved.watchCheckIns().first).single;
          expect(legacy.id, original.id);
          expect(legacy.dayPeriod, isNull);
          expect(legacy.createdAt, original.createdAt);
          expect(await disk.select(disk.syncCommands).get(), hasLength(2));
          (await saved.updateHabit(
            id,
            HabitDraft(
              title: 'Read',
              startDate: DateTime(2026, 9, 28),
              periodTargets: {HabitDayPeriod.night: 2},
            ),
            now: today,
          )).getOrThrow();
          (await saved.addCheckIn(
            id,
            today,
            period: HabitDayPeriod.night,
            now: today,
          )).getOrThrow();
          await disk.close();
          disk = AppDatabase(NativeDatabase(file));
          saved = DriftHabitRepository(disk, DriftOutboxService(disk));
          final marks = await saved.watchCheckIns().first;
          expect(marks, hasLength(2));
          expect(
            marks.where((c) => c.dayPeriod == HabitDayPeriod.night),
            hasLength(1),
          );
          expect(
            (await saved.watchHabits().first)
                .single
                .scheduleHistory
                .last
                .periodTargets,
            {HabitDayPeriod.night: 2},
          );
        } finally {
          await disk.close();
        }
      },
    );
  }
  test(
    'version 8 upgrade preserves old data and new data survives restart',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'habit-migration-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/habits.sqlite');
      var disk = AppDatabase(NativeDatabase(file));
      try {
        await disk.ensureSeedData();
        final projects = await disk.select(disk.projects).get();
        await disk.customStatement('DROP TABLE habit_check_ins');
        await disk.customStatement('DROP TABLE habits');
        await disk.customStatement('PRAGMA user_version = 8');
        await disk.close();
        disk = AppDatabase(NativeDatabase(file));
        expect(await disk.select(disk.projects).get(), projects);
        expect(
          (await disk.customSelect('PRAGMA user_version').getSingle())
              .read<int>('user_version'),
          11,
        );
        expect(
          await disk
              .customSelect(
                "SELECT name FROM sqlite_master WHERE name='habit_check_ins_by_day'",
              )
              .get(),
          hasLength(1),
        );
        var saved = DriftHabitRepository(disk, DriftOutboxService(disk));
        final id = (await saved.createHabit(draft(), now: today)).getOrThrow();
        (await saved.addCheckIn(id, today, now: today)).getOrThrow();
        await disk.close();
        disk = AppDatabase(NativeDatabase(file));
        saved = DriftHabitRepository(disk, DriftOutboxService(disk));
        expect((await saved.watchHabits().first).single.id, id);
        expect(await saved.watchCheckIns().first, hasLength(1));
        expect(await disk.select(disk.syncCommands).get(), hasLength(2));
      } finally {
        await disk.close();
      }
    },
  );
  test('account reset clears habits and check-ins', () async {
    final id = await create();
    (await repo.addCheckIn(id, today, now: today)).getOrThrow();
    await db.resetAccountData();
    expect(await db.select(db.habits).get(), isEmpty);
    expect(await db.select(db.habitCheckIns).get(), isEmpty);
  });
  test('missing or shared projects cannot be selected', () async {
    expect(
      (await repo.createHabit(
        HabitDraft(title: 'Read', startDate: today, projectId: 'missing'),
        now: today,
      )).getOrThrow,
      throwsArgumentError,
    );
    await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            id: 'shared',
            userId: localUserId,
            name: 'Shared',
            scopeId: const Value('scope'),
            orderKey: '1',
            createdAt: today,
            updatedAt: today,
          ),
        );
    expect(
      (await repo.createHabit(
        HabitDraft(title: 'Read', startDate: today, projectId: 'shared'),
        now: today,
      )).getOrThrow,
      throwsArgumentError,
    );
  });
}

class _FailingOutbox extends DriftOutboxService {
  _FailingOutbox(super.db);
  @override
  Future<void> enqueueBatch(
    List<SyncQueueCommand> commands, {
    DateTime? occurredAt,
  }) async {
    await super.enqueueBatch(commands, occurredAt: occurredAt);
    throw StateError('outbox unavailable');
  }
}

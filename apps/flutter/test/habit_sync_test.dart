import 'package:app_account/app_account.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/data/repositories/habits/habit_repository_impl.dart';
import 'package:pomodoist/domain/models/habits/habit_models.dart';
import 'package:uuid/uuid.dart';
import 'support/account_sync_engine.dart';

void main() {
  final now = DateTime(2026, 9, 30, 12);
  late AppDatabase db;
  late DriftHabitRepository repo;
  late _Account account;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.ensureSeedData();
    repo = DriftHabitRepository(db, DriftOutboxService(db));
    account = _Account();
  });
  tearDown(() => db.close());
  test(
    'habit sign survives push, other-device pull, legacy updates and explicit reset',
    () async {
      final id = (await repo.createHabit(
        HabitDraft(title: 'Read', startDate: now, icon: '📚'),
        now: now,
      )).getOrThrow();
      final sender = testSyncEngine(
        db: db,
        account: account,
        uuid: const Uuid(),
      );
      await sender.pushPending();
      final payload = account.pushed
          .singleWhere((o) => o.entityType == 'habit')
          .payload;
      expect(payload['icon'], '📚');
      final remoteDb = AppDatabase(NativeDatabase.memory());
      addTearDown(remoteDb.close);
      final remote = _Account()
        ..changes = [
          AccountSyncEntity(
            entityType: 'habit',
            entityId: id,
            serverRevision: 1,
            data: payload,
          ),
        ];
      final receiver = testSyncEngine(
        db: remoteDb,
        account: remote,
        uuid: const Uuid(),
      );
      final received = DriftHabitRepository(
        remoteDb,
        DriftOutboxService(remoteDb),
      );
      await receiver.pullLatest();
      expect((await received.watchHabits().first).single.icon, '📚');
      final legacy = {...payload}..remove('icon');
      legacy['title'] = 'Read again';
      remote.changes = [
        AccountSyncEntity(
          entityType: 'habit',
          entityId: id,
          serverRevision: 2,
          data: legacy,
        ),
      ];
      await receiver.pullLatest();
      expect((await received.watchHabits().first).single.icon, '📚');
      expect((await received.watchHabits().first).single.title, 'Read again');
      (await repo.updateIcon(
        id,
        null,
        now: now.add(const Duration(minutes: 1)),
      )).getOrThrow();
      await sender.pushPending();
      final reset = account.pushed
          .lastWhere((o) => o.entityType == 'habit')
          .payload;
      expect(reset.containsKey('icon'), isTrue);
      expect(reset['icon'], isNull);
      remote.changes = [
        AccountSyncEntity(
          entityType: 'habit',
          entityId: id,
          serverRevision: 3,
          data: reset,
        ),
      ];
      await receiver.pullLatest();
      expect((await received.watchHabits().first).single.icon, isNull);
      expect((await received.watchHabits().first).single.title, 'Read again');
    },
  );
  test(
    'period quotas and night check-ins survive push, pull and snapshot',
    () async {
      final id = (await repo.createHabit(
        HabitDraft(
          title: 'Water',
          startDate: now,
          periodTargets: {HabitDayPeriod.morning: 2, HabitDayPeriod.night: 1},
        ),
        now: now,
      )).getOrThrow();
      (await repo.addCheckIn(
        id,
        now,
        period: HabitDayPeriod.night,
        now: now,
      )).getOrThrow();
      final engine = testSyncEngine(
        db: db,
        account: account,
        uuid: const Uuid(),
      );
      await engine.pushPending();
      final habit = account.pushed.singleWhere((o) => o.entityType == 'habit');
      final check = account.pushed.singleWhere(
        (o) => o.entityType == 'habit_check_in',
      );
      expect(
        (habit.payload['scheduleHistory'] as List).single['periodTargets'],
        {'morning': 2, 'night': 1},
      );
      expect(check.payload['dayPeriod'], 'night');
      final remoteDb = AppDatabase(NativeDatabase.memory());
      addTearDown(remoteDb.close);
      final remote = _Account()
        ..changes = [
          AccountSyncEntity(
            entityType: 'habit',
            entityId: id,
            serverRevision: 1,
            data: habit.payload,
          ),
          AccountSyncEntity(
            entityType: 'habit_check_in',
            entityId: check.entityId,
            serverRevision: 1,
            data: check.payload,
          ),
        ];
      final receiver = testSyncEngine(
        db: remoteDb,
        account: remote,
        uuid: const Uuid(),
      );
      await receiver.pullLatest();
      final received = DriftHabitRepository(
        remoteDb,
        DriftOutboxService(remoteDb),
      );
      expect(
        (await received.watchCheckIns().first).single.dayPeriod,
        HabitDayPeriod.night,
      );
      expect(
        (await received.watchHabits().first)
            .single
            .scheduleHistory
            .last
            .periodTargets,
        {HabitDayPeriod.morning: 2, HabitDayPeriod.night: 1},
      );
      await receiver.importLocalSnapshotIfNeeded();
      expect(
        remote.pushed
            .singleWhere((o) => o.entityType == 'habit_check_in')
            .payload['dayPeriod'],
        'night',
      );
    },
  );
  test('remote manual period survives pull, local edit and outbox', () async {
    final id = (await repo.createHabit(
      HabitDraft(title: 'Read', startDate: now),
      now: now,
    )).getOrThrow();
    final local = (await repo.watchHabits().first).single;
    final payload = local.toJson();
    (payload['scheduleHistory'] as List).single['dayPeriod'] = 'evening';
    account.changes = [
      AccountSyncEntity(
        entityType: 'habit',
        entityId: id,
        serverRevision: 5,
        data: payload,
      ),
    ];
    final engine = testSyncEngine(db: db, account: account, uuid: const Uuid());
    await engine.pullLatest();
    expect(
      (await repo.watchHabits().first).single.scheduleHistory.last.dayPeriod,
      HabitDayPeriod.evening,
    );
    (await repo.updateHabit(
      id,
      HabitDraft(
        title: 'Read edited',
        startDate: now,
        dayPeriod: HabitDayPeriod.evening,
      ),
      now: now.add(const Duration(minutes: 1)),
    )).getOrThrow();
    await engine.pushPending();
    final pushed = account.pushed
        .lastWhere((o) => o.entityType == 'habit')
        .payload;
    expect((pushed['scheduleHistory'] as List).last['dayPeriod'], 'evening');
  });
  test(
    'outbox and snapshot use public calendar format and import tombstones',
    () async {
      final id = (await repo.createHabit(
        HabitDraft(title: 'Read', startDate: now, targetPerDay: 2),
        now: now,
      )).getOrThrow();
      (await repo.addCheckIn(id, now, now: now)).getOrThrow();
      final engine = testSyncEngine(
        db: db,
        account: account,
        uuid: const Uuid(),
      );
      await engine.pushPending();
      final habits = account.pushed.where((o) => o.entityType == 'habit');
      expect(habits.single.payload['scheduleHistory'], isA<List>());
      expect(
        (habits.single.payload['scheduleHistory'] as List).single['startDate'],
        '2026-09-30',
      );
      expect(
        account.pushed
            .singleWhere((o) => o.entityType == 'habit_check_in')
            .payload['day'],
        '2026-09-30',
      );
      (await repo.deleteHabit(id, now: now)).getOrThrow();
      account.pushed.clear();
      await engine.importLocalSnapshotIfNeeded();
      expect(
        account.pushed.singleWhere((o) => o.entityType == 'habit').operation,
        'delete',
      );
    },
  );
  test(
    'initial import includes active habits before their independent check-ins',
    () async {
      final id = (await repo.createHabit(
        HabitDraft(title: 'Read', startDate: now),
        now: now,
      )).getOrThrow();
      (await repo.addCheckIn(id, now, now: now)).getOrThrow();
      final engine = testSyncEngine(
        db: db,
        account: account,
        uuid: const Uuid(),
      );
      await engine.importLocalSnapshotIfNeeded();
      final habitIndex = account.pushed.indexWhere(
        (o) => o.entityType == 'habit',
      );
      final checkIndex = account.pushed.indexWhere(
        (o) => o.entityType == 'habit_check_in',
      );
      expect(habitIndex, greaterThanOrEqualTo(0));
      expect(checkIndex, greaterThan(habitIndex));
      expect(account.pushed[checkIndex].payload['habitId'], id);
      expect(account.pushed[checkIndex].payload['day'], '2026-09-30');
      final imported = account.pushed.length;
      await engine.importLocalSnapshotIfNeeded();
      expect(account.pushed, hasLength(imported));
    },
  );
  test(
    'a full pull may deliver a check-in before its parent and retains offline edits',
    () async {
      final id = (await repo.createHabit(
        HabitDraft(title: 'Read', startDate: DateTime(2026, 9, 28)),
        now: DateTime(2026, 9, 28),
      )).getOrThrow();
      final original = (await repo.watchHabits().first).single;
      (await repo.updateHabit(
        id,
        HabitDraft(
          title: 'Read new',
          startDate: DateTime(2026, 9, 28),
          targetPerDay: 3,
        ),
        now: now,
      )).getOrThrow();
      account.changes = [
        AccountSyncEntity(
          entityType: 'habit_check_in',
          entityId: 'remote-check',
          serverRevision: 1,
          data: HabitCheckIn(
            id: 'remote-check',
            userId: localUserId,
            habitId: 'other',
            day: now,
            createdAt: now,
            updatedAt: now,
          ).toJson(),
        ),
        AccountSyncEntity(
          entityType: 'habit',
          entityId: 'other',
          serverRevision: 2,
          data: Habit(
            id: 'other',
            userId: localUserId,
            title: 'Other',
            scheduleHistory: original.scheduleHistory,
            createdAt: now,
            updatedAt: now,
          ).toJson(),
        ),
        AccountSyncEntity(
          entityType: 'habit',
          entityId: id,
          serverRevision: 3,
          data: original.toJson(),
        ),
      ];
      await testSyncEngine(
        db: db,
        account: account,
        uuid: const Uuid(),
      ).pullLatest();
      final habits = await repo.watchHabits().first;
      expect(habits, hasLength(2));
      final edited = habits.singleWhere((h) => h.id == id);
      expect(edited.title, 'Read new');
      expect(edited.scheduleFor(now)!.targetPerDay, 3);
      expect(
        habitCompletionCount('other', now, await repo.watchCheckIns().first),
        1,
      );
    },
  );
  test(
    'repeated pulls deduplicate check-ins from independent devices',
    () async {
      final habit = Habit(
        id: 'h',
        userId: localUserId,
        title: 'Read',
        scheduleHistory: [
          HabitDraft(
            title: 'Read',
            startDate: now,
            targetPerDay: 2,
          ).schedule(now),
        ],
        createdAt: now,
        updatedAt: now,
      );
      account.changes = [
        AccountSyncEntity(
          entityType: 'habit',
          entityId: 'h',
          serverRevision: 1,
          data: habit.toJson(),
        ),
        for (var i = 0; i < 2; i++)
          AccountSyncEntity(
            entityType: 'habit_check_in',
            entityId: 'c$i',
            serverRevision: 2 + i,
            data: HabitCheckIn(
              id: 'c$i',
              userId: localUserId,
              habitId: 'h',
              day: now,
              createdAt: now,
              updatedAt: now,
            ).toJson(),
          ),
      ];
      final engine = testSyncEngine(
        db: db,
        account: account,
        uuid: const Uuid(),
      );
      await engine.pullLatest();
      await engine.pullLatest();
      expect(await repo.watchHabits().first, hasLength(1));
      expect(await repo.watchCheckIns().first, hasLength(2));
      expect(
        habitCompletionCount('h', now, await repo.watchCheckIns().first),
        2,
      );
    },
  );
  test(
    'delete arriving before creation cannot resurrect a habit or check-in',
    () async {
      final habit = Habit(
        id: 'h',
        userId: localUserId,
        title: 'Read',
        scheduleHistory: [
          HabitDraft(title: 'Read', startDate: now).schedule(now),
        ],
        createdAt: now,
        updatedAt: now,
      );
      account.changes = [
        AccountSyncEntity(
          entityType: 'habit',
          entityId: 'h',
          serverRevision: 5,
          data: habit.toJson(),
          deletedAt: now,
        ),
        AccountSyncEntity(
          entityType: 'habit',
          entityId: 'h',
          serverRevision: 1,
          data: habit.toJson(),
        ),
        AccountSyncEntity(
          entityType: 'habit_check_in',
          entityId: 'c',
          serverRevision: 6,
          data: HabitCheckIn(
            id: 'c',
            userId: localUserId,
            habitId: 'h',
            day: now,
            createdAt: now,
            updatedAt: now,
          ).toJson(),
        ),
      ];
      await testSyncEngine(
        db: db,
        account: account,
        uuid: const Uuid(),
      ).pullLatest();
      expect(await repo.watchHabits().first, isEmpty);
      expect(await repo.watchCheckIns().first, isEmpty);
    },
  );
}

class _Account implements AccountClient {
  List<AccountSyncEntity> changes = [];
  final pushed = <AccountSyncOperation>[];
  @override
  Future<AccountSyncPullResult> pullChanges({
    required String appId,
    required String deviceId,
    required int sinceRevision,
    int limit = 500,
  }) async =>
      AccountSyncPullResult(nextCursor: 6, hasMore: false, changes: changes);
  @override
  Future<AccountSyncPushResult> pushChanges({
    required String appId,
    required String deviceId,
    required List<AccountSyncOperation> operations,
  }) async {
    pushed.addAll(operations);
    return AccountSyncPushResult(serverRevision: 6, applied: const []);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

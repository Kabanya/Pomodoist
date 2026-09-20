import 'package:app_account/app_account.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import '../support/account_sync_engine.dart';
import 'package:uuid/uuid.dart';

class SwitchingAccount extends Fake implements AccountClient {
  String userId = 'a';
  final pushedAs = <String>[];
  bool current = true;
  @override
  String? get currentUserId => userId;
  @override
  Future<AccountSyncPushResult> pushChanges({
    required String appId,
    required String deviceId,
    required List<AccountSyncOperation> operations,
  }) async {
    pushedAs.add(userId);
    current = false;
    userId = 'b';
    return const AccountSyncPushResult(serverRevision: 1, applied: []);
  }

  @override
  Future<void> broadcastSyncHint({
    required String appId,
    required String deviceId,
  }) async {}
}

void main() {
  test('sync does not upload remaining batches after account change', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureSeedData();
    final now = DateTime.utc(2026);
    for (var i = 0; i < 105; i++) {
      await db
          .into(db.tasks)
          .insert(
            TasksCompanion.insert(
              id: 't$i',
              userId: localUserId,
              content: 'private account A task',
              projectId: inboxProjectId,
              orderKey: '$i',
              createdAt: now,
              updatedAt: now,
            ),
          );
    }
    final account = SwitchingAccount();
    final engine = testSyncEngine(db: db, account: account, uuid: const Uuid());
    await engine.syncNow(isSessionCurrent: () => account.current);
    expect(account.pushedAs, everyElement('a'));
  });
}

import 'package:drift/drift.dart';
import 'dart:convert';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/domain/models/account/history_policy.dart';

/// Reads the persisted server history policy; retention decisions live above I/O.
final class AccountHistoryPolicyStore {
  AccountHistoryPolicyStore(this._db);
  final AppDatabase _db;
  Future<PomodoistHistoryPolicy> load() async {
    final row =
        await (_db.select(_db.sharedEntities)..where(
              (r) =>
                  r.scopeId.equals('_account') &
                  r.entityType.equals('history') &
                  r.entityId.equals('personal'),
            ))
            .getSingleOrNull();
    final data = row == null
        ? <String, dynamic>{}
        : jsonDecode(row.dataJson) as Map<String, dynamic>;
    return (
      historyUnlimited: data['historyUnlimited'] == true,
      graceEndsAt: DateTime.tryParse(data['graceEndsAt']?.toString() ?? ''),
    );
  }
}

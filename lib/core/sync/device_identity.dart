import 'package:uuid/uuid.dart';

import '../db/app_database.dart';

const pomodoistSyncStateId = 'pomodoist';

Future<String> pomodoistDeviceId(AppDatabase db, {Uuid? uuid}) async {
  final existing = await (db.select(
    db.syncState,
  )..where((row) => row.id.equals(pomodoistSyncStateId))).getSingleOrNull();
  if (existing != null) {
    return existing.deviceId;
  }
  final now = DateTime.now().toUtc();
  final deviceId = (uuid ?? const Uuid()).v4();
  await db
      .into(db.syncState)
      .insert(
        SyncStateCompanion.insert(
          id: pomodoistSyncStateId,
          deviceId: deviceId,
          createdAt: now,
          updatedAt: now,
        ),
      );
  return deviceId;
}

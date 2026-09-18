import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/sync/sync_queue_repository.dart';
import '../domain/task_models.dart';

class DriftLabelRepository implements LabelRepository {
  DriftLabelRepository(this._db, this._syncQueue, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final SyncQueueRepository _syncQueue;
  final Uuid _uuid;

  @override
  Stream<List<LabelItem>> watchLabels() {
    final statement = _db.select(_db.labels)
      ..where(
        (label) =>
            label.scopeId.isNull() &
            label.kind.equals(labelKindUser) &
            label.isDeleted.equals(false),
      )
      ..orderBy([(label) => OrderingTerm.asc(label.orderKey)]);
    return statement.watch().map((rows) => rows.map(_mapLabel).toList());
  }

  @override
  Future<LabelItem?> findByName(String name) async {
    final normalizedName = name.trim().toLowerCase();
    final row =
        (await (_db.select(_db.labels)..where(
                  (label) =>
                      label.scopeId.isNull() &
                      label.kind.equals(labelKindUser) &
                      label.isDeleted.equals(false),
                ))
                .get())
            .firstWhereOrNull(
              (label) => label.name.trim().toLowerCase() == normalizedName,
            );
    return row == null ? null : _mapLabel(row);
  }

  @override
  Future<String> createLabel(String name, {String? icon}) async {
    if (icon != null) _validateIcon(icon);
    final existing = await findByName(name);
    if (existing != null) {
      return existing.id;
    }
    final now = DateTime.now().toUtc();
    final id = _uuid.v4();
    await _db.transaction(() async {
      await _db
          .into(_db.labels)
          .insert(
            LabelsCompanion.insert(
              id: id,
              userId: localUserId,
              name: name.trim(),
              icon: Value(icon),
              kind: const Value(labelKindUser),
              orderKey: now.microsecondsSinceEpoch.toString().padLeft(20, '0'),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await _syncQueue.enqueue(
        type: 'label.create',
        clientId: id,
        payload: {'id': id, 'name': name.trim(), 'icon': ?icon},
      );
    });
    return id;
  }

  void _validateIcon(String icon) {
    if (!LabelIcon.values.any((value) => value.name == icon)) {
      throw ArgumentError.value(icon, 'icon', 'Unknown label icon');
    }
  }

  @override
  Future<void> updateLabelIcon(String id, String icon) async {
    _validateIcon(icon);
    await _db.transaction(() async {
      final changed =
          await (_db.update(_db.labels)..where(
                (row) =>
                    row.id.equals(id) &
                    row.kind.equals(labelKindUser) &
                    row.isDeleted.equals(false),
              ))
              .write(
                LabelsCompanion(
                  icon: Value(icon),
                  updatedAt: Value(DateTime.now().toUtc()),
                ),
              );
      if (changed == 0) throw StateError('Label no longer exists');
      await _syncQueue.enqueue(
        type: 'label.update',
        clientId: id,
        payload: {'id': id, 'icon': icon},
      );
    });
  }

  @override
  Future<void> deleteLabel(String id) async {
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      final label =
          await (_db.select(_db.labels)
                ..where(
                  (label) =>
                      label.id.equals(id) &
                      label.scopeId.isNull() &
                      label.kind.equals(labelKindUser) &
                      label.isDeleted.equals(false),
                )
                ..limit(1))
              .getSingleOrNull();
      if (label == null) {
        return;
      }
      await (_db.update(
        _db.labels,
      )..where((label) => label.id.equals(id))).write(
        LabelsCompanion(isDeleted: const Value(true), updatedAt: Value(now)),
      );
      await _syncQueue.enqueue(
        type: 'label.delete',
        clientId: id,
        payload: {'id': id},
      );
    });
  }

  LabelItem _mapLabel(LabelRow row) => LabelItem(
    id: row.id,
    userId: row.userId,
    name: row.name,
    color: row.color,
    icon: row.icon,
    orderKey: row.orderKey,
    isFavorite: row.isFavorite,
    isDeleted: row.isDeleted,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}

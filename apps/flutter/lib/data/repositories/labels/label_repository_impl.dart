import 'package:pomodoist/utils/result.dart';
import 'package:pomodoist/data/repositories/labels/label_repository.dart';
import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/label_local_service.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';

class DriftLabelRepository implements LabelRepository {
  DriftLabelRepository(AppDatabase db, this._syncQueue, {Uuid? uuid})
    : _db = db,
      _uuid = uuid ?? const Uuid(),
      _labels = LabelLocalService(db);

  final AppDatabase _db;
  final OutboxService _syncQueue;
  final Uuid _uuid;
  final LabelLocalService _labels;

  @override
  Stream<List<LabelItem>> watchLabels() {
    return _labels.watchActiveUserLabels().map(
      (rows) => rows.map(_mapLabel).toList(),
    );
  }

  @override
  Future<Result<LabelItem?>> findByName(String name) =>
      Result.capture<LabelItem?>(() async {
        final normalizedName = name.trim().toLowerCase();
        final row = (await _labels.activeUserLabels()).firstWhereOrNull(
          (label) => label.name.trim().toLowerCase() == normalizedName,
        );
        return row == null ? null : _mapLabel(row);
      });

  @override
  Future<Result<String>> createLabel(String name, {String? icon}) =>
      Result.capture<String>(() async {
        if (icon != null) _validateIcon(icon);
        final existing = await findByName(
          name,
        ).then((result) => result.getOrThrow());
        if (existing != null) {
          return existing.id;
        }
        final now = DateTime.now().toUtc();
        final id = _uuid.v4();
        await _db.transaction(() async {
          await _labels.insertLabel(
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
      });

  void _validateIcon(String icon) {
    if (!LabelIcon.values.any((value) => value.name == icon)) {
      throw ArgumentError.value(icon, 'icon', 'Unknown label icon');
    }
  }

  @override
  Future<Result<void>> updateLabelIcon(String id, String icon) =>
      Result.capture<void>(() async {
        _validateIcon(icon);
        await _db.transaction(() async {
          final changed = await _labels.updateIcon(
            id,
            icon,
            DateTime.now().toUtc(),
          );
          if (changed == 0) throw StateError('Label no longer exists');
          await _syncQueue.enqueue(
            type: 'label.update',
            clientId: id,
            payload: {'id': id, 'icon': icon},
          );
        });
      });

  @override
  Future<Result<void>> deleteLabel(String id) => Result.capture<void>(() async {
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      final label = await _labels.findActiveUserLabel(id);
      if (label == null) {
        return;
      }
      await _labels.markDeleted(id, now);
      await _syncQueue.enqueue(
        type: 'label.delete',
        clientId: id,
        payload: {'id': id},
      );
    });
  });

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

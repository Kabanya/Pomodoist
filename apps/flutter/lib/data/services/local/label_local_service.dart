import 'package:drift/drift.dart';

import 'package:pomodoist/data/services/local/database/app_database.dart';

class LabelLocalService {
  LabelLocalService(this._db);

  final AppDatabase _db;

  Stream<List<LabelRow>> watchActiveUserLabels() {
    final statement = _db.select(_db.labels)
      ..where(
        (label) =>
            label.scopeId.isNull() &
            label.kind.equals(labelKindUser) &
            label.isDeleted.equals(false),
      )
      ..orderBy([(label) => OrderingTerm.asc(label.orderKey)]);
    return statement.watch();
  }

  Future<List<LabelRow>> activeUserLabels() {
    return (_db.select(_db.labels)..where(
          (label) =>
              label.scopeId.isNull() &
              label.kind.equals(labelKindUser) &
              label.isDeleted.equals(false),
        ))
        .get();
  }

  Future<void> insertLabel(LabelsCompanion label) {
    return _db.into(_db.labels).insert(label);
  }

  Future<int> updateIcon(String id, String icon, DateTime updatedAt) {
    return (_db.update(_db.labels)..where(
          (row) =>
              row.id.equals(id) &
              row.kind.equals(labelKindUser) &
              row.isDeleted.equals(false),
        ))
        .write(LabelsCompanion(icon: Value(icon), updatedAt: Value(updatedAt)));
  }

  Future<LabelRow?> findActiveUserLabel(String id) {
    return (_db.select(_db.labels)
          ..where(
            (label) =>
                label.id.equals(id) &
                label.scopeId.isNull() &
                label.kind.equals(labelKindUser) &
                label.isDeleted.equals(false),
          )
          ..limit(1))
        .getSingleOrNull();
  }

  Future<void> markDeleted(String id, DateTime updatedAt) {
    return (_db.update(
      _db.labels,
    )..where((label) => label.id.equals(id))).write(
      LabelsCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(updatedAt),
      ),
    );
  }
}

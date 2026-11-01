import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:drift/drift.dart';
import 'package:file_selector/file_selector.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';

typedef CsvExportOwner = ({String? userId, String? generation});

final class CsvTaskExportService {
  CsvTaskExportService(
    this._db, {
    Future<String?> Function(String)? selectPath,
    Future<void> Function(Uint8List, String, String)? writeFile,
  }) : selectPath = selectPath ?? _selectPath,
       writeFile = writeFile ?? _writeFile;

  final AppDatabase _db;
  final Future<String?> Function(String name) selectPath;
  final Future<void> Function(Uint8List bytes, String name, String path)
  writeFile;

  Future<CsvExportOwner> owner() async {
    final row =
        await (_db.select(_db.syncState)
              ..where((r) => r.id.equals('pomodoist-account-owner-v1')))
            .getSingleOrNull();
    return (userId: row?.cursor, generation: row?.deviceId);
  }

  // shortcut: exports are buffered in memory, stream if task volumes cause memory pressure.
  Future<({Uint8List bytes, CsvExportOwner owner})> snapshot() =>
      _db.transaction(() async {
        final snapshotOwner = await owner();
        final tasks =
            await (_db.select(_db.tasks)
                  ..where((t) => t.isDeleted.equals(false))
                  ..orderBy([
                    (t) => OrderingTerm.asc(t.createdAt),
                    (t) => OrderingTerm.asc(t.id),
                  ]))
                .get();
        final projects = {
          for (final p in await (_db.select(
            _db.projects,
          )..where((p) => p.isDeleted.equals(false))).get())
            p.id: p,
        };
        final sections = {
          for (final s in await (_db.select(
            _db.sections,
          )..where((s) => s.isDeleted.equals(false))).get())
            s.id: s,
        };
        final labels = {
          for (final l in await (_db.select(
            _db.labels,
          )..where((l) => l.isDeleted.equals(false))).get())
            l.id: l,
        };
        final scopes = {
          for (final s in await _db.select(_db.sharedScopes).get()) s.id,
        };
        final links = await _db.select(_db.taskLabels).get();
        final taskLabels = <String, List<LabelRow>>{};
        for (final link in links) {
          final label = labels[link.labelId];
          if (label != null) {
            taskLabels.putIfAbsent(link.taskId, () => []).add(label);
          }
        }
        final rows = <List<Object?>>[_headers];
        for (final task in tasks) {
          final project = projects[task.projectId];
          final scopeId = task.scopeId ?? project?.scopeId;
          if (scopeId != null && !scopes.contains(scopeId)) continue;
          final schedule = TaskSchedule.fromJsonString(task.dueJson);
          final linked =
              (taskLabels[task.id] ?? [])
                  .where((l) => l.scopeId == scopeId)
                  .toList()
                ..sort((a, b) {
                  final order = a.orderKey.compareTo(b.orderKey);
                  return order == 0 ? a.id.compareTo(b.id) : order;
                });
          final userLabels = linked.where((l) => l.kind == labelKindUser);
          final statuses = linked.where((l) => l.kind == labelKindKanbanStatus);
          rows.add([
            task.id,
            task.content,
            task.description,
            task.status,
            task.priority,
            task.projectId,
            project?.name,
            project?.isArchived,
            task.sectionId,
            sections[task.sectionId]?.name,
            task.parentId,
            jsonEncode(userLabels.map((l) => l.name).toList()),
            statuses.firstOrNull?.name,
            _dateOnly(schedule?.date),
            _utc(schedule?.start),
            _utc(schedule?.end),
            schedule?.timeZone,
            schedule?.recurrence?.unit.name,
            schedule?.recurrence?.interval,
            _deadline(task.deadlineJson),
            task.durationSeconds,
            task.estimatedFocusIntervals,
            task.isFocusEstimateManual,
            task.completedFocusIntervals,
            task.totalFocusSeconds,
            _utc(task.createdAt),
            _utc(task.updatedAt),
            _utc(task.completedAt),
            scopeId,
            task.createdBy,
            task.completedBy,
            jsonEncode(jsonDecode(task.assigneeIdsJson)),
          ]);
        }
        final csv = Csv(
          addBom: true,
          encoderTransform: (value, _, _) =>
              value is String && _formulaStart.hasMatch(value)
              ? "'$value"
              : value,
        ).encode(rows);
        return (
          bytes: Uint8List.fromList(utf8.encode(csv)),
          owner: snapshotOwner,
        );
      });

  static Future<String?> _selectPath(String name) async =>
      (await getSaveLocation(
        suggestedName: name,
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'CSV',
            extensions: ['csv'],
            mimeTypes: ['text/csv'],
          ),
        ],
      ))?.path;

  static Future<void> _writeFile(Uint8List bytes, String name, String path) =>
      XFile.fromData(bytes, name: name, mimeType: 'text/csv').saveTo(path);

  static String? _utc(DateTime? date) => date?.toUtc().toIso8601String();
  static String? _dateOnly(DateTime? date) => date == null
      ? null
      : '${date.year.toString().padLeft(4, '0')}-'
            '${date.month.toString().padLeft(2, '0')}-'
            '${date.day.toString().padLeft(2, '0')}';
  static String? _deadline(String? raw) => raw == null
      ? null
      : _dateOnly(
          DateTime.parse(
            (jsonDecode(raw) as Map<String, dynamic>)['date'] as String,
          ),
        );
}

final _formulaStart = RegExp(r'^\s*[=+\-@\t\r\n]');

const _headers = <String>[
  'id',
  'content',
  'description',
  'status',
  'priority',
  'project_id',
  'project',
  'project_archived',
  'section_id',
  'section',
  'parent_id',
  'labels',
  'kanban_status',
  'due_date',
  'start_at',
  'end_at',
  'time_zone',
  'recurrence',
  'recurrence_interval',
  'deadline',
  'duration_seconds',
  'estimated_focus_intervals',
  'is_focus_estimate_manual',
  'completed_focus_intervals',
  'total_focus_seconds',
  'created_at',
  'updated_at',
  'completed_at',
  'scope_id',
  'created_by',
  'completed_by',
  'assignee_ids',
];

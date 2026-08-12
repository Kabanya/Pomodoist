import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:drift/drift.dart';
import 'package:timezone/data/latest.dart' as time_zone_data;
import 'package:timezone/timezone.dart' as time_zone;
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/sync/sync_queue_repository.dart';
import '../domain/task_models.dart';
import 'kanban_repository_impl.dart';
import 'kanban_transition_coordinator.dart';
import 'task_repository_impl.dart';

const pomodoistCsvContractVersion = 'pomodoist_csv_v1';
const pomodoistCsvHeaders = <String>[
  'key',
  'content',
  'description',
  'project',
  'labels',
  'priority',
  'due_date',
  'start_at',
  'end_at',
  'time_zone',
  'recurrence',
  'recurrence_interval',
  'deadline',
  'estimate',
  'kanban_status',
  'parent_key',
];
const pomodoistCsvHeader =
    'key,content,description,project,labels,priority,due_date,start_at,end_at,'
    'time_zone,recurrence,recurrence_interval,deadline,estimate,'
    'kanban_status,parent_key';
const pomodoistCsvAgentInstructions =
    '''
Pomodoist CSV import contract: pomodoist_csv_v1

Create UTF-8 CSV files with this canonical header:
$pomodoistCsvHeader

Rules:
- Use comma as the canonical delimiter. Pomodoist also accepts semicolon. A UTF-8 BOM is allowed. Quote fields that contain a delimiter, quote, or newline; escape a quote by doubling it.
- Maximum file size: 16 MiB. Maximum tasks: 1000. Header order is flexible, unused known headers may be omitted, content is required, and unknown or duplicate headers are invalid.
- One row creates one open task. Re-importing the same file creates duplicates intentionally. Completed tasks, sections, internal IDs, focus statistics, and duration are not imported.
- content: required text. description: optional text. project: optional; empty means Inbox. Missing projects are created and existing names are reused case-insensitively.
- labels: optional names separated by |. Missing labels are created and existing names are reused case-insensitively.
- priority: 1, 2, 3, or 4; empty means 4.
- Schedule: use due_date as YYYY-MM-DD for an all-day task, or use all three of start_at, end_at, and time_zone for a timed task. start_at and end_at must be RFC3339 with an explicit UTC offset, end_at must be later, and time_zone must be an IANA name such as Europe/Moscow. Do not combine due_date with timed fields.
- recurrence: day, week, or month. recurrence_interval: integer 1..999, default 1. Recurrence requires a schedule.
- deadline: optional YYYY-MM-DD. estimate: optional integer 1..999 Pomodoro intervals.
- kanban_status: optional open workflow status; empty means Backlog. Missing statuses are created and existing names are reused case-insensitively. Done is invalid.
- key: optional case-sensitive row key matching [A-Za-z0-9][A-Za-z0-9._:-]{0,199}. Keys must be unique. parent_key references another row key anywhere in the file. References must exist and must not form cycles. A child with an empty project inherits its parent's project; an explicit child project must match its parent's project case-insensitively.

Example:
key,content,project,labels,priority,due_date,kanban_status,parent_key
launch,Plan launch,Work,planning|urgent,1,2026-08-10,In progress,
venue,Book venue,Work,calls,2,2026-08-08,Backlog,launch
''';

class CsvTaskImportIssue {
  const CsvTaskImportIssue({required this.row, required this.message});

  final int row;
  final String message;
}

class CsvTaskImportException implements Exception {
  const CsvTaskImportException(this.issues);

  final List<CsvTaskImportIssue> issues;

  @override
  String toString() => issues.map((issue) => issue.message).join('\n');
}

class CsvTaskImportDraft {
  const CsvTaskImportDraft({
    required this.rowNumber,
    required this.content,
    required this.labelNames,
    required this.priority,
    required this.recurrenceInterval,
    this.key,
    this.description,
    this.projectName,
    this.schedule,
    this.recurrenceUnit,
    this.deadline,
    this.estimatedFocusIntervals,
    this.kanbanStatusName,
    this.parentKey,
  });

  final int rowNumber;
  final String? key;
  final String content;
  final String? description;
  final String? projectName;
  final List<String> labelNames;
  final int priority;
  final TaskSchedule? schedule;
  final TaskRecurrenceUnit? recurrenceUnit;
  final int recurrenceInterval;
  final DateTime? deadline;
  final int? estimatedFocusIntervals;
  final String? kanbanStatusName;
  final String? parentKey;

  CsvTaskImportDraft withProjectName(String? value) => CsvTaskImportDraft(
    rowNumber: rowNumber,
    key: key,
    content: content,
    description: description,
    projectName: value,
    labelNames: labelNames,
    priority: priority,
    schedule: schedule,
    recurrenceUnit: recurrenceUnit,
    recurrenceInterval: recurrenceInterval,
    deadline: deadline,
    estimatedFocusIntervals: estimatedFocusIntervals,
    kanbanStatusName: kanbanStatusName,
    parentKey: parentKey,
  );
}

class CsvTaskImportDocument {
  const CsvTaskImportDocument(this.tasks);

  static const maximumBytes = 16 * 1024 * 1024;
  static const maximumTasks = 1000;

  final List<CsvTaskImportDraft> tasks;

  factory CsvTaskImportDocument.parse(List<int> bytes) {
    if (bytes.length > maximumBytes) {
      throw const CsvTaskImportException([
        CsvTaskImportIssue(row: 0, message: 'CSV file exceeds 16 MiB.'),
      ]);
    }
    final String text;
    try {
      text = utf8.decode(bytes).trim();
    } on FormatException {
      throw const CsvTaskImportException([
        CsvTaskImportIssue(row: 0, message: 'CSV must be valid UTF-8.'),
      ]);
    }
    if (text.isEmpty) {
      throw const CsvTaskImportException([
        CsvTaskImportIssue(row: 1, message: 'CSV header is missing.'),
      ]);
    }
    final List<List<dynamic>> rows;
    try {
      final commaRows = Csv(
        fieldDelimiter: ',',
        autoDetect: false,
      ).decode(text);
      final semicolonRows = Csv(
        fieldDelimiter: ';',
        autoDetect: false,
      ).decode(text);
      rows = semicolonRows.first.length > commaRows.first.length
          ? semicolonRows
          : commaRows;
    } on FormatException catch (error) {
      throw CsvTaskImportException([
        CsvTaskImportIssue(row: 0, message: 'Malformed CSV: $error'),
      ]);
    }
    if (rows.isEmpty) {
      throw const CsvTaskImportException([
        CsvTaskImportIssue(row: 1, message: 'CSV header is missing.'),
      ]);
    }
    final headers = rows.first
        .map((value) => '$value'.trim().replaceFirst('\ufeff', ''))
        .toList();
    final issues = <CsvTaskImportIssue>[];
    final index = <String, int>{};
    for (var i = 0; i < headers.length; i++) {
      final header = headers[i];
      if (!pomodoistCsvHeaders.contains(header)) {
        issues.add(
          CsvTaskImportIssue(row: 1, message: 'Unknown header "$header".'),
        );
      } else if (index.containsKey(header)) {
        issues.add(
          CsvTaskImportIssue(row: 1, message: 'Duplicate header "$header".'),
        );
      } else {
        index[header] = i;
      }
    }
    if (!index.containsKey('content')) {
      issues.add(
        const CsvTaskImportIssue(
          row: 1,
          message: 'content header is required.',
        ),
      );
    }
    if (issues.isNotEmpty) {
      throw CsvTaskImportException(List.unmodifiable(issues));
    }
    if (rows.length - 1 > maximumTasks) {
      throw const CsvTaskImportException([
        CsvTaskImportIssue(
          row: 0,
          message: 'CSV cannot contain more than 1000 tasks.',
        ),
      ]);
    }
    final tasks = <CsvTaskImportDraft>[];
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      final rowNumber = i + 1;
      if (row.length > headers.length) {
        issues.add(
          CsvTaskImportIssue(
            row: rowNumber,
            message: 'Row has more fields than the header.',
          ),
        );
      }
      String cell(String name) {
        final column = index[name];
        return column == null || column >= row.length
            ? ''
            : '${row[column]}'.trim();
      }

      void issue(String message) =>
          issues.add(CsvTaskImportIssue(row: rowNumber, message: message));

      final content = cell('content');
      if (content.isEmpty) issue('content is required.');

      final priorityRaw = cell('priority');
      final priority = priorityRaw.isEmpty ? 4 : int.tryParse(priorityRaw);
      if (priority == null || priority < 1 || priority > 4) {
        issue('priority must be an integer from 1 to 4.');
      }

      final dueRaw = cell('due_date');
      final dueDate = _validatedDate(dueRaw);
      if (dueRaw.isNotEmpty && dueDate == null) {
        issue('due_date must use YYYY-MM-DD.');
      }
      final startRaw = cell('start_at');
      final endRaw = cell('end_at');
      final zone = cell('time_zone');
      final hasTimedValue =
          startRaw.isNotEmpty || endRaw.isNotEmpty || zone.isNotEmpty;
      if (dueRaw.isNotEmpty && hasTimedValue) {
        issue('due_date cannot be combined with a timed schedule.');
      }
      DateTime? startAt;
      DateTime? endAt;
      var zoneIsValid = false;
      if (hasTimedValue) {
        if (startRaw.isEmpty || endRaw.isEmpty || zone.isEmpty) {
          issue('A timed schedule requires start_at, end_at and time_zone.');
        }
        startAt = _validatedDateTime(startRaw);
        endAt = _validatedDateTime(endRaw);
        if (startRaw.isNotEmpty && startAt == null) {
          issue('start_at must be RFC3339 with an explicit UTC offset.');
        }
        if (endRaw.isNotEmpty && endAt == null) {
          issue('end_at must be RFC3339 with an explicit UTC offset.');
        }
        if (zone.isNotEmpty) {
          zoneIsValid = _isValidTimeZone(zone);
          if (!zoneIsValid) issue('time_zone must be a valid IANA name.');
        }
      }
      TaskSchedule? schedule;
      if (dueDate != null && !hasTimedValue) {
        schedule = TaskSchedule.allDay(dueDate);
      } else if (startAt != null && endAt != null && zoneIsValid) {
        if (endAt.isAfter(startAt)) {
          schedule = TaskSchedule.timed(
            start: startAt,
            end: endAt,
            timeZone: zone,
          );
        } else {
          issue('end_at must be after start_at.');
        }
      }

      final recurrenceRaw = cell('recurrence');
      TaskRecurrenceUnit? recurrenceUnit;
      if (recurrenceRaw.isNotEmpty) {
        recurrenceUnit = switch (recurrenceRaw) {
          'day' => TaskRecurrenceUnit.day,
          'week' => TaskRecurrenceUnit.week,
          'month' => TaskRecurrenceUnit.month,
          _ => null,
        };
        if (recurrenceUnit == null) {
          issue('recurrence must be day, week or month.');
        }
      }
      final intervalRaw = cell('recurrence_interval');
      final interval = intervalRaw.isEmpty ? 1 : int.tryParse(intervalRaw);
      if (interval == null || interval < 1 || interval > 999) {
        issue('recurrence_interval must be an integer from 1 to 999.');
      }
      if (intervalRaw.isNotEmpty && recurrenceRaw.isEmpty) {
        issue('recurrence_interval requires recurrence.');
      }
      if (recurrenceRaw.isNotEmpty && schedule == null) {
        issue('recurrence requires a schedule.');
      }

      final deadlineRaw = cell('deadline');
      final deadline = _validatedDate(deadlineRaw);
      if (deadlineRaw.isNotEmpty && deadline == null) {
        issue('deadline must use YYYY-MM-DD.');
      }
      final estimateRaw = cell('estimate');
      final estimate = estimateRaw.isEmpty ? null : int.tryParse(estimateRaw);
      if (estimateRaw.isNotEmpty &&
          (estimate == null || estimate < 1 || estimate > 999)) {
        issue('estimate must be an integer from 1 to 999.');
      }

      final status = _nullable(cell('kanban_status')) ?? 'Backlog';
      if (status.toLowerCase() == 'done') {
        issue('Done tasks cannot be imported.');
      }
      final key = _nullable(cell('key'));
      final parentKey = _nullable(cell('parent_key'));
      if (key != null && !_keyPattern.hasMatch(key)) {
        issue('key has an invalid format.');
      }
      if (parentKey != null && !_keyPattern.hasMatch(parentKey)) {
        issue('parent_key has an invalid format.');
      }

      tasks.add(
        CsvTaskImportDraft(
          rowNumber: rowNumber,
          key: key,
          content: content,
          description: _nullable(cell('description')),
          projectName: _nullable(cell('project')),
          labelNames: _uniqueNames(cell('labels').split('|')),
          priority: priority ?? 4,
          schedule: schedule,
          recurrenceUnit: recurrenceUnit,
          recurrenceInterval: interval ?? 1,
          deadline: deadline,
          estimatedFocusIntervals: estimate,
          kanbanStatusName: status,
          parentKey: parentKey,
        ),
      );
    }
    if (tasks.isEmpty) {
      issues.add(
        const CsvTaskImportIssue(row: 0, message: 'CSV contains no tasks.'),
      );
    }
    final ordered = _resolveRelationships(tasks, issues);
    if (issues.isNotEmpty) {
      throw CsvTaskImportException(List.unmodifiable(issues));
    }
    return CsvTaskImportDocument(List.unmodifiable(ordered));
  }
}

class CsvTaskImportPreview {
  const CsvTaskImportPreview({
    required this.document,
    required this.newProjects,
    required this.newLabels,
    required this.newKanbanStatuses,
  });

  final CsvTaskImportDocument document;
  final List<String> newProjects;
  final List<String> newLabels;
  final List<String> newKanbanStatuses;

  int get taskCount => document.tasks.length;
  int get subtaskCount =>
      document.tasks.where((task) => task.parentKey != null).length;
}

class CsvTaskImportResult {
  const CsvTaskImportResult(this.taskIds);

  final List<String> taskIds;
}

class CsvTaskImporter {
  CsvTaskImporter(this._db, this._syncQueue, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final SyncQueueRepository _syncQueue;
  final Uuid _uuid;

  Future<CsvTaskImportPreview> prepare(List<int> bytes) async {
    final document = CsvTaskImportDocument.parse(bytes);
    final projects = await (_db.select(
      _db.projects,
    )..where((row) => row.isDeleted.equals(false))).get();
    final labels =
        await (_db.select(_db.labels)..where(
              (row) =>
                  row.kind.equals(labelKindUser) & row.isDeleted.equals(false),
            ))
            .get();
    final statuses =
        await (_db.select(_db.labels)..where(
              (row) =>
                  row.kind.equals(labelKindKanbanStatus) &
                  row.isDeleted.equals(false),
            ))
            .get();

    return CsvTaskImportPreview(
      document: document,
      newProjects: _missingNames(
        document.tasks.map((task) => task.projectName).whereType<String>(),
        projects.map((project) => project.name),
      ),
      newLabels: _missingNames(
        document.tasks.expand((task) => task.labelNames),
        labels.map((label) => label.name),
      ),
      newKanbanStatuses: _missingNames(
        document.tasks.map((task) => task.kanbanStatusName).whereType<String>(),
        statuses.map((status) => status.name),
      ),
    );
  }

  Future<CsvTaskImportResult> commit(CsvTaskImportPreview preview) {
    return _db.transaction(() async {
      await _db.ensureSeedData();
      final transitions = KanbanTransitionCoordinator(_db, _syncQueue);
      final projects = DriftProjectRepository(_db, _syncQueue, uuid: _uuid);
      final statuses = DriftKanbanRepository(
        _db,
        syncQueue: _syncQueue,
        kanbanTransitions: transitions,
        uuid: _uuid,
      );
      final tasks = DriftTaskRepository(
        _db,
        _syncQueue,
        uuid: _uuid,
        kanbanTransitions: transitions,
      );

      final projectIds = <String, String>{
        for (final row in await (_db.select(
          _db.projects,
        )..where((row) => row.isDeleted.equals(false))).get())
          row.name.toLowerCase(): row.id,
      };
      for (final name in _uniqueNames(
        preview.document.tasks
            .map((task) => task.projectName)
            .whereType<String>(),
      )) {
        projectIds[name.toLowerCase()] ??= await projects.createProject(name);
      }

      final statusIds = <String, String>{
        for (final row
            in await (_db.select(_db.labels)..where(
                  (row) =>
                      row.kind.equals(labelKindKanbanStatus) &
                      row.isDeleted.equals(false),
                ))
                .get())
          row.name.toLowerCase(): row.id,
      };
      for (final name in _uniqueNames(
        preview.document.tasks
            .map((task) => task.kanbanStatusName)
            .whereType<String>(),
      )) {
        statusIds[name.toLowerCase()] ??= await statuses.createStatus(name);
      }

      final labelNames = <String, String>{
        for (final row
            in await (_db.select(_db.labels)..where(
                  (row) =>
                      row.kind.equals(labelKindUser) &
                      row.isDeleted.equals(false),
                ))
                .get())
          row.name.toLowerCase(): row.name,
      };

      final createdByKey = <String, String>{};
      final createdIds = <String>[];
      for (final draft in preview.document.tasks) {
        var schedule = draft.schedule;
        if (draft.recurrenceUnit != null) {
          schedule = schedule!.withRecurrence(
            TaskRecurrence(
              interval: draft.recurrenceInterval,
              unit: draft.recurrenceUnit!,
              seriesId: _uuid.v4(),
            ),
          );
        }
        final id = await tasks.createTask(
          CreateTaskInput(
            content: draft.content,
            description: draft.description,
            projectId: draft.projectName == null
                ? inboxProjectId
                : projectIds[draft.projectName!.toLowerCase()],
            parentId: draft.parentKey == null
                ? null
                : createdByKey[draft.parentKey],
            priority: draft.priority,
            labelNames: [
              for (final name in draft.labelNames)
                labelNames.putIfAbsent(name.toLowerCase(), () => name),
            ],
            schedule: schedule,
            deadline: draft.deadline,
            estimatedFocusIntervals: draft.estimatedFocusIntervals,
            kanbanStatusId: statusIds[draft.kanbanStatusName!.toLowerCase()],
          ),
        );
        createdIds.add(id);
        if (draft.key != null) createdByKey[draft.key!] = id;
      }
      return CsvTaskImportResult(List.unmodifiable(createdIds));
    });
  }
}

String? _nullable(String value) => value.isEmpty ? null : value;

final _keyPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,199}$');

DateTime? _validatedDate(String value) {
  if (value.isEmpty) return null;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final date = DateTime(year, month, day);
  return date.year == year && date.month == month && date.day == day
      ? date
      : null;
}

DateTime? _validatedDateTime(String value) {
  if (!RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:Z|[+-]\d{2}:\d{2})$',
  ).hasMatch(value)) {
    return null;
  }
  return DateTime.tryParse(value);
}

bool _timeZonesInitialized = false;

bool _isValidTimeZone(String value) {
  if (!_timeZonesInitialized) {
    time_zone_data.initializeTimeZones();
    _timeZonesInitialized = true;
  }
  try {
    time_zone.getLocation(value);
    return true;
  } on time_zone.LocationNotFoundException {
    return false;
  }
}

List<String> _uniqueNames(Iterable<String> values) {
  final seen = <String>{};
  return [
    for (final value in values)
      if (value.trim().isNotEmpty && seen.add(value.trim().toLowerCase()))
        value.trim(),
  ];
}

List<String> _missingNames(
  Iterable<String> requested,
  Iterable<String> existing,
) {
  final known = existing.map((name) => name.trim().toLowerCase()).toSet();
  return [
    for (final name in _uniqueNames(requested))
      if (!known.contains(name.toLowerCase())) name,
  ];
}

List<CsvTaskImportDraft> _resolveRelationships(
  List<CsvTaskImportDraft> tasks,
  List<CsvTaskImportIssue> issues,
) {
  final byKey = <String, CsvTaskImportDraft>{};
  for (final task in tasks) {
    final key = task.key;
    if (key != null && byKey.containsKey(key)) {
      issues.add(
        CsvTaskImportIssue(
          row: task.rowNumber,
          message: 'Duplicate key "$key".',
        ),
      );
    } else if (key != null) {
      byKey[key] = task;
    }
  }

  final ordered = <CsvTaskImportDraft>[];
  final visiting = <CsvTaskImportDraft>{};
  final resolved = <CsvTaskImportDraft, CsvTaskImportDraft>{};

  CsvTaskImportDraft visit(CsvTaskImportDraft task) {
    final done = resolved[task];
    if (done != null) return done;
    if (!visiting.add(task)) {
      issues.add(
        CsvTaskImportIssue(
          row: task.rowNumber,
          message: 'parent_key references form a cycle.',
        ),
      );
      return task;
    }

    var result = task;
    final parentKey = task.parentKey;
    if (parentKey != null) {
      final parent = byKey[parentKey];
      if (parent == null) {
        issues.add(
          CsvTaskImportIssue(
            row: task.rowNumber,
            message: 'parent_key "$parentKey" does not exist.',
          ),
        );
      } else {
        final resolvedParent = visit(parent);
        final parentProject = resolvedParent.projectName;
        if (task.projectName == null) {
          result = task.withProjectName(parentProject);
        } else if (_projectIdentity(parentProject) !=
            _projectIdentity(task.projectName)) {
          issues.add(
            CsvTaskImportIssue(
              row: task.rowNumber,
              message: 'A child task must use the same project as its parent.',
            ),
          );
        }
      }
    }
    visiting.remove(task);
    resolved[task] = result;
    ordered.add(result);
    return result;
  }

  for (final task in tasks) {
    visit(task);
  }
  return ordered;
}

String _projectIdentity(String? name) => (name ?? 'Inbox').trim().toLowerCase();

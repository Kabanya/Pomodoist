import 'package:pomodoist/data/repositories/kanban/kanban_repository.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/utils/result.dart';

import 'strict_fake.dart';

final _emptyBoard = KanbanBoardSnapshot(
  statuses: const [],
  settings: KanbanSettings(
    id: 'kanban-settings',
    userId: 'user-1',
    selectedProjectIds: const [],
    focusStatusLabelId: '',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  ),
  focusedStatusId: '',
  availableProjects: const [],
  cardsByStatusId: const {},
);

/// In-memory [KanbanRepository] double.
///
/// Succeeding calls answer from the mutable fields below, every call is
/// recorded in its `<method>Calls` list, and a call whose `<method>Error`
/// field is non-null fails with that error instead of succeeding.
class FakeKanbanRepository extends StrictFake implements KanbanRepository {
  /// Board emitted by [watchBoard]; while unset an empty board is emitted.
  KanbanBoardSnapshot? board;

  /// Id [createStatus] succeeds with.
  String createdStatusId = 'status-1';

  Object? createStatusError;
  Object? renameStatusError;
  Object? reorderStatusError;
  Object? deleteStatusError;
  Object? setSelectedProjectIdsError;
  Object? setFocusStatusError;
  Object? moveTaskError;

  final watchBoardCalls = <void>[];
  final createStatusCalls = <({String name, String? color})>[];
  final renameStatusCalls = <({String id, String name})>[];
  final reorderStatusCalls = <({String id, int targetIndex})>[];
  final deleteStatusCalls = <String>[];
  final setSelectedProjectIdsCalls = <Set<String>>[];
  final setFocusStatusCalls = <String>[];
  final moveTaskCalls = <({String taskId, String statusId, int? targetIndex})>[];

  @override
  Stream<KanbanBoardSnapshot> watchBoard() {
    watchBoardCalls.add(null);
    return Stream.value(board ?? _emptyBoard);
  }

  @override
  Future<Result<String>> createStatus(String name, {String? color}) async {
    createStatusCalls.add((name: name, color: color));
    final error = createStatusError;
    if (error != null) return Result.error(error, StackTrace.current);
    return Result.ok(createdStatusId);
  }

  @override
  Future<Result<void>> renameStatus(String id, String name) async {
    renameStatusCalls.add((id: id, name: name));
    final error = renameStatusError;
    if (error != null) return Result.error(error, StackTrace.current);
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> reorderStatus(String id, int targetIndex) async {
    reorderStatusCalls.add((id: id, targetIndex: targetIndex));
    final error = reorderStatusError;
    if (error != null) return Result.error(error, StackTrace.current);
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> deleteStatus(String id) async {
    deleteStatusCalls.add(id);
    final error = deleteStatusError;
    if (error != null) return Result.error(error, StackTrace.current);
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> setSelectedProjectIds(Set<String> projectIds) async {
    setSelectedProjectIdsCalls.add(projectIds);
    final error = setSelectedProjectIdsError;
    if (error != null) return Result.error(error, StackTrace.current);
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> setFocusStatus(String statusId) async {
    setFocusStatusCalls.add(statusId);
    final error = setFocusStatusError;
    if (error != null) return Result.error(error, StackTrace.current);
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> moveTask(
    String taskId, {
    required String statusId,
    int? targetIndex,
  }) async {
    moveTaskCalls.add((
      taskId: taskId,
      statusId: statusId,
      targetIndex: targetIndex,
    ));
    final error = moveTaskError;
    if (error != null) return Result.error(error, StackTrace.current);
    return const Result.ok(null);
  }
}

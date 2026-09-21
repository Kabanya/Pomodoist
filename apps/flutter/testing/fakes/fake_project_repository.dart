import 'package:pomodoist/data/repositories/projects/project_repository.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/utils/result.dart';

import 'strict_fake.dart';

/// In-memory double for [ProjectRepository].
///
/// Every method answers without stubbing: reads come from the public fields,
/// writes only record their arguments. Assigning the matching `<method>Error`
/// field makes that call record itself and fail instead.
class FakeProjectRepository extends StrictFake implements ProjectRepository {
  /// Arguments of each [createProject] call.
  final created = <({String name, String? color, String? parentId})>[];

  /// Arguments of each [moveProject] call.
  final moved = <({String id, String? parentId, String? beforeProjectId})>[];

  /// Arguments of each [updateProject] call.
  final updated = <({String id, UpdateProjectPatch patch})>[];

  /// Ids passed to [deleteProject].
  final deleted = <String>[];

  /// Names passed to [findByName].
  final foundByName = <String>[];

  /// When non-null, the matching method fails with it.
  Object? findByNameError;
  Object? createProjectError;
  Object? moveProjectError;
  Object? updateProjectError;
  Object? deleteProjectError;

  /// Emitted by [watchProjects].
  List<ProjectItem> projects = const [];

  /// Returned by [findByName] when [findByNameError] is null.
  ProjectItem? projectByName;

  /// Returned by [createProject] when [createProjectError] is null.
  String createdProjectId = 'created-project';

  @override
  Stream<List<ProjectItem>> watchProjects() => Stream.value(projects);

  @override
  Future<Result<ProjectItem?>> findByName(String name) async {
    foundByName.add(name);
    final error = findByNameError;
    if (error != null) return Result.error(error, StackTrace.empty);
    return Result.ok(projectByName);
  }

  @override
  Future<Result<String>> createProject(
    String name, {
    String? color,
    String? parentId,
  }) async {
    created.add((name: name, color: color, parentId: parentId));
    final error = createProjectError;
    if (error != null) return Result.error(error, StackTrace.empty);
    return Result.ok(createdProjectId);
  }

  @override
  Future<Result<void>> moveProject(
    String id, {
    required String? parentId,
    String? beforeProjectId,
  }) async {
    moved.add((id: id, parentId: parentId, beforeProjectId: beforeProjectId));
    final error = moveProjectError;
    if (error != null) return Result.error(error, StackTrace.empty);
    return Result.ok(null);
  }

  @override
  Future<Result<void>> updateProject(
    String id,
    UpdateProjectPatch patch,
  ) async {
    updated.add((id: id, patch: patch));
    final error = updateProjectError;
    if (error != null) return Result.error(error, StackTrace.empty);
    return Result.ok(null);
  }

  @override
  Future<Result<void>> deleteProject(String id) async {
    deleted.add(id);
    final error = deleteProjectError;
    if (error != null) return Result.error(error, StackTrace.empty);
    return Result.ok(null);
  }
}

import 'package:pomodoist/utils/result.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';

abstract interface class ProjectRepository {
  Stream<List<ProjectItem>> watchProjects();
  Future<Result<ProjectItem?>> findByName(String name);
  Future<Result<String>> createProject(
    String name, {
    String? color,
    String? parentId,
  });
  Future<Result<void>> moveProject(
    String id, {
    required String? parentId,
    String? beforeProjectId,
  });
  Future<Result<void>> updateProject(String id, UpdateProjectPatch patch);
  Future<Result<void>> deleteProject(String id);
}

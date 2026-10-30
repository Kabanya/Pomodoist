import 'package:pomodoist/config/collaboration_dependencies.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_models.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/files_dependencies.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/data/repositories/files/files_repository_contract.dart';
import 'package:pomodoist/domain/models/files/file_attachment.dart';

typedef TaskCreateContextQuery = ({
  String text,
  String? projectId,
  DateTime? defaultDate,
});
typedef TaskCreateContext = ({
  ProjectItem? project,
  SharedScope? scope,
  bool ready,
  String? projectName,
});
final taskCreateContextViewModelProvider = Provider.autoDispose
    .family<TaskCreateContext, TaskCreateContextQuery>((ref, query) {
      final parsed = ref
          .watch(quickAddParserProvider)
          .parse(
            query.text,
            now: ref.read(clockProvider).now(),
            defaultDate: query.defaultDate,
          );
      final projects = ref.watch(projectsProvider);
      ProjectItem? selected;
      for (final project in projects.value ?? const <ProjectItem>[]) {
        if (!project.isDeleted &&
            (parsed.project != null
                ? project.name.trim().toLowerCase() ==
                      parsed.project!.trim().toLowerCase()
                : project.id == query.projectId)) {
          selected = project;
          break;
        }
      }
      final scopeId = selected?.scopeId;
      final scope = scopeId == null
          ? null
          : ref.watch(sharedScopeProvider(scopeId));
      return (
        project: selected,
        projectName: parsed.project,
        scope: scope,
        ready: projects.hasValue && (scopeId == null || scope != null),
      );
    });

class TaskDraftFile {
  const TaskDraftFile(this.file, this.bytes);
  final XFile file;
  final int bytes;
}

typedef TaskCreateState = ({
  List<TaskDraftFile> files,
  Set<String> assigneeIds,
  String? assigneeScopeId,
  String? taskId,
  bool busy,
  Object? error,
});

final taskCreateViewModelProvider = NotifierProvider.autoDispose
    .family<TaskCreateViewModel, TaskCreateState, Object>(
      TaskCreateViewModel.new,
    );

class TaskCreateViewModel extends Notifier<TaskCreateState> {
  TaskCreateViewModel(this.identity);
  final Object identity;
  FilesRepositoryContract? _files;
  TaskDraftFile? _failedUpload;

  @override
  TaskCreateState build() => (
    files: const [],
    assigneeIds: const {},
    assigneeScopeId: null,
    taskId: null,
    busy: false,
    error: null,
  );

  void setAssignees(String scopeId, Set<String> ids) {
    if (state.busy || state.taskId != null) return;
    state = (
      files: state.files,
      assigneeIds: Set.unmodifiable(ids),
      assigneeScopeId: scopeId,
      taskId: null,
      busy: false,
      error: null,
    );
  }

  Future<void> pickFile() async {
    if (state.busy || state.taskId != null) return;
    _files ??= ref.read(filesRepositoryProvider);
    final repository = _files;
    if (repository == null) throw const FileFailure('unauthorized');
    final file = await repository.pickFile();
    if (file == null || !ref.mounted) return;
    final bytes = await file.length();
    if (bytes < 1 || bytes > 20000000) {
      throw const FileFailure('file_too_large');
    }
    if (!ref.mounted || state.busy || state.taskId != null) return;
    state = (
      files: List.unmodifiable([...state.files, TaskDraftFile(file, bytes)]),
      assigneeIds: state.assigneeIds,
      assigneeScopeId: state.assigneeScopeId,
      taskId: null,
      busy: false,
      error: null,
    );
  }

  void removeFile(TaskDraftFile file) {
    if (state.busy) return;
    if (identical(_failedUpload, file)) _failedUpload = null;
    state = (
      files: List.unmodifiable(state.files.where((item) => item != file)),
      assigneeIds: state.assigneeIds,
      assigneeScopeId: state.assigneeScopeId,
      taskId: state.taskId,
      busy: false,
      error: null,
    );
  }

  Future<String?> submit({
    required String text,
    required String description,
    String? scopeId,
    int? priority,
    DateTime? defaultDate,
    String? projectId,
    String? kanbanStatusId,
    String? labelId,
  }) async {
    if (state.busy || (state.taskId == null && text.trim().isEmpty)) {
      return null;
    }
    _update(busy: true);
    try {
      var id = state.taskId;
      if (id == null) {
        id =
            (await ref
                    .read(quickAddUseCaseProvider)
                    .createTask(
                      text,
                      description: description,
                      priority: priority,
                      defaultDate: defaultDate,
                      projectId: projectId,
                      kanbanStatusId: kanbanStatusId,
                      labelId: labelId,
                      assigneeIds:
                          scopeId != null && scopeId == state.assigneeScopeId
                          ? state.assigneeIds.toList()
                          : const [],
                    ))
                .getOrThrow();
        if (!ref.mounted) return null;
        // Commit the identity before uploads: retries must never create a second task.
        _update(taskId: id, busy: true);
      }
      final target = FileTarget(taskId: id);
      while (state.files.isNotEmpty) {
        final pending = state.files.first;
        final repository = _files;
        if (repository == null) throw const FileFailure('unauthorized');
        if (identical(_failedUpload, pending) &&
            await repository.watchUpload(target).first != null) {
          await repository.retry(target);
        } else {
          _failedUpload = pending;
          await repository.upload(target, pending.file);
        }
        if (!ref.mounted) return null;
        _failedUpload = null;
        state = (
          files: List.unmodifiable(state.files.skip(1)),
          assigneeIds: state.assigneeIds,
          assigneeScopeId: state.assigneeScopeId,
          taskId: id,
          busy: true,
          error: null,
        );
      }
      _update(busy: false);
      return id;
    } catch (error) {
      if (ref.mounted) _update(busy: false, error: error);
      return null;
    }
  }

  void _update({required bool busy, String? taskId, Object? error}) {
    state = (
      files: state.files,
      assigneeIds: state.assigneeIds,
      assigneeScopeId: state.assigneeScopeId,
      taskId: taskId ?? state.taskId,
      busy: busy,
      error: error,
    );
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';

final projectViewModelProvider = NotifierProvider.autoDispose
    .family<ProjectViewModel, ProjectItem?, String>(ProjectViewModel.new);

class ProjectViewModel extends Notifier<ProjectItem?> {
  ProjectViewModel(this.projectId);
  final String projectId;
  @override
  ProjectItem? build() =>
      (ref.watch(projectsProvider).value ?? const <ProjectItem>[])
          .where((item) => item.id == projectId)
          .firstOrNull;
}

final labelViewModelProvider = NotifierProvider.autoDispose
    .family<LabelViewModel, AsyncValue<LabelItem?>, String>(LabelViewModel.new);

class LabelViewModel extends Notifier<AsyncValue<LabelItem?>> {
  LabelViewModel(this.labelId);
  final String labelId;
  @override
  AsyncValue<LabelItem?> build() => ref
      .watch(labelsProvider)
      .whenData(
        (items) => items.where((item) => item.id == labelId).firstOrNull,
      );
  void retry() => ref.invalidate(labelsProvider);
  Future<void> updateIcon(String icon) async {
    await ref.read(labelRepositoryProvider).updateLabelIcon(labelId, icon);
  }
}

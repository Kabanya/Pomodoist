import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/collaboration_dependencies.dart';
import 'package:pomodoist/data/repositories/collaboration/collaboration_repository.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_models.dart';
import 'package:pomodoist/domain/models/collaboration/public_project.dart';

enum PublicProjectFailure { unavailable, retryable }

final class PublicProjectState {
  const PublicProjectState({this.project, this.failure, this.loading = false});
  final PublicProject? project;
  final PublicProjectFailure? failure;
  final bool loading;
}

final publicProjectViewModelProvider = NotifierProvider.autoDispose
    .family<PublicProjectViewModel, PublicProjectState, String>(
      PublicProjectViewModel.new,
    );

class PublicProjectViewModel extends Notifier<PublicProjectState> {
  PublicProjectViewModel(this.token);
  final String token;
  CollaborationRepository? _repository;
  var _generation = 0;
  @override
  PublicProjectState build() {
    _repository = ref.watch(publicCollaborationRepositoryProvider);
    ref.onDispose(() => _generation++);
    Future.microtask(reload);
    return const PublicProjectState(loading: true);
  }

  Future<void> reload() async {
    final generation = ++_generation;
    final value = token.trim();
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value)) {
      state = const PublicProjectState(
        failure: PublicProjectFailure.unavailable,
      );
      return;
    }
    state = const PublicProjectState(loading: true);
    try {
      final repository = _repository;
      if (repository == null) throw const CollaborationException('unavailable');
      final project = (await repository.publicRead(value)).getOrThrow();
      if (!ref.mounted || generation != _generation) return;
      state = PublicProjectState(project: project);
    } catch (error) {
      if (!ref.mounted || generation != _generation) return;
      state = PublicProjectState(
        failure: error is CollaborationException && error.code == '42501'
            ? PublicProjectFailure.unavailable
            : PublicProjectFailure.retryable,
      );
    }
  }
}

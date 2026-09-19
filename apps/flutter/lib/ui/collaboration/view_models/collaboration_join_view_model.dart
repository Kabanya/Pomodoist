import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/collaboration_dependencies.dart';
import 'package:pomodoist/data/repositories/collaboration/collaboration_repository.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_models.dart';

enum JoinPhase { loading, ready, working, accepted, failed }

final class CollaborationJoinState {
  const CollaborationJoinState({
    required this.valid,
    required this.signedIn,
    this.phase = JoinPhase.loading,
    this.role,
    this.projectId,
    this.error,
  });
  final bool valid;
  final bool signedIn;
  final JoinPhase phase;
  final String? role;
  final String? projectId;
  final Object? error;
  bool get canRetry =>
      error is! CollaborationException ||
      (error as CollaborationException).code != '42501';
}

final collaborationJoinViewModelProvider = NotifierProvider.autoDispose
    .family<CollaborationJoinViewModel, CollaborationJoinState, String>(
      CollaborationJoinViewModel.new,
    );

class CollaborationJoinViewModel extends Notifier<CollaborationJoinState> {
  CollaborationJoinViewModel(this.token);
  final String token;
  CollaborationRepository? _repository;
  var _generation = 0;
  @override
  CollaborationJoinState build() {
    _repository = ref.watch(collaborationRepositoryProvider);
    final valid = RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(token);
    final generation = ++_generation;
    ref.onDispose(() => _generation++);
    if (valid && _repository != null) Future.microtask(() => _load(generation));
    return CollaborationJoinState(valid: valid, signedIn: _repository != null);
  }

  Future<void> _load(int generation) async {
    String? role;
    final result = await _repository!.state();
    try {
      for (final invitation in collaborationMaps(
        result.getOrThrow()['invitations'],
      )) {
        if (invitation['token'] != token) continue;
        final value = invitation['role'];
        if (value is String) role = value;
        break;
      }
    } catch (_) {
      // The accept endpoint remains authoritative if the optional listing fails.
    }
    if (!ref.mounted || generation != _generation) return;
    state = CollaborationJoinState(
      valid: true,
      signedIn: true,
      phase: JoinPhase.ready,
      role: role,
    );
  }

  Future<void> accept() async {
    if (!state.valid || state.phase == JoinPhase.working) return;
    final repository = _repository;
    if (repository == null) return;
    final generation = ++_generation;
    state = CollaborationJoinState(
      valid: true,
      signedIn: true,
      role: state.role,
      phase: JoinPhase.working,
    );
    try {
      final result = (await repository.acceptInvitation(token)).getOrThrow();
      if (!ref.mounted || generation != _generation) return;
      final scope = result['scope'];
      state = CollaborationJoinState(
        valid: true,
        signedIn: true,
        phase: JoinPhase.accepted,
        projectId: scope is Map ? scope['rootProjectId']?.toString() : null,
      );
    } catch (error) {
      if (!ref.mounted || generation != _generation) return;
      state = CollaborationJoinState(
        valid: true,
        signedIn: true,
        phase: JoinPhase.failed,
        error: error,
      );
    }
  }
}

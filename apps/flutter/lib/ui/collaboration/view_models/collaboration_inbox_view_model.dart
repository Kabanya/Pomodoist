import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/collaboration_dependencies.dart';
import 'package:pomodoist/data/repositories/collaboration/collaboration_repository.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_responses.dart';

final class CollaborationInboxState {
  CollaborationInboxState({
    this.loading = false,
    this.busy = false,
    this.error,
    List<CollaborationInvitation> invitations = const [],
    List<CollaborationNotification> notifications = const [],
  }) : invitations = List.unmodifiable(invitations),
       notifications = List.unmodifiable(notifications);
  final bool loading;
  final bool busy;
  final Object? error;
  final List<CollaborationInvitation> invitations;
  final List<CollaborationNotification> notifications;
}

final collaborationInboxViewModelProvider =
    NotifierProvider.autoDispose<
      CollaborationInboxViewModel,
      CollaborationInboxState
    >(CollaborationInboxViewModel.new);

class CollaborationInboxViewModel extends Notifier<CollaborationInboxState> {
  CollaborationRepository? _repository;
  var _generation = 0;
  @override
  CollaborationInboxState build() {
    _repository = ref.watch(collaborationRepositoryProvider);
    final generation = ++_generation;
    ref.onDispose(() => _generation++);
    Future.microtask(() => _load(generation));
    return CollaborationInboxState(loading: true);
  }

  Future<void> _load(int generation) async {
    try {
      final repository = _repository;
      final snapshot = repository == null
          ? null
          : (await repository.state()).getOrThrow();
      if (!ref.mounted || generation != _generation) return;
      state = CollaborationInboxState(
        invitations: snapshot?.invitations ?? const [],
        notifications: snapshot?.notifications ?? const [],
      );
    } catch (error) {
      if (!ref.mounted || generation != _generation) return;
      state = CollaborationInboxState(
        invitations: state.invitations,
        notifications: state.notifications,
        error: error,
      );
    }
  }

  Future<bool> accept(String token) => token.isEmpty
      ? Future.value(false)
      : _run((repository) async {
          (await repository.acceptInvitation(token)).getOrThrow();
        });
  Future<bool> markRead(String id) => _run((repository) async {
    (await repository.markNotificationRead(id)).getOrThrow();
  });
  Future<bool> markAllRead() {
    final ids = state.notifications
        .where((notification) => notification.isUnread)
        .map((notification) => notification.id)
        .take(50)
        .toList();
    return _run((repository) async {
      for (final id in ids) {
        (await repository.markNotificationRead(id)).getOrThrow();
      }
    });
  }

  Future<bool> _run(
    Future<void> Function(CollaborationRepository) action,
  ) async {
    final repository = _repository;
    if (repository == null || state.busy) return false;
    final generation = ++_generation;
    state = CollaborationInboxState(
      busy: true,
      invitations: state.invitations,
      notifications: state.notifications,
    );
    try {
      await action(repository);
      await _load(generation);
      return true;
    } catch (error) {
      if (ref.mounted && generation == _generation) {
        state = CollaborationInboxState(
          invitations: state.invitations,
          notifications: state.notifications,
          error: error,
        );
      }
      return false;
    }
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/account_management_dependencies.dart';
import 'package:pomodoist/data/repositories/account/account_management_repository.dart';
import 'package:pomodoist/domain/models/account/account_management.dart';

final class ConnectedAgentsState {
  ConnectedAgentsState({
    required this.userId,
    this.loading = false,
    this.error,
    this.revokeError,
    this.revokingClientId,
    List<ConnectedAgent>? grants,
  }) : grants = grants == null ? null : List.unmodifiable(grants);
  final String? userId;
  final bool loading;
  final Object? error;
  final Object? revokeError;
  final String? revokingClientId;
  final List<ConnectedAgent>? grants;
  bool get hasError => error != null;
  bool get isLoading => loading;
}

final connectedAgentsViewModelProvider =
    NotifierProvider<ConnectedAgentsViewModel, ConnectedAgentsState>(
      ConnectedAgentsViewModel.new,
    );

class ConnectedAgentsViewModel extends Notifier<ConnectedAgentsState> {
  AccountManagementRepository? _repository;
  var _generation = 0;
  var _loadGeneration = 0;
  Future<void>? _inFlight;
  @override
  ConnectedAgentsState build() {
    _repository = ref.watch(accountManagementRepositoryProvider);
    final generation = ++_generation;
    _inFlight = null;
    ref.onDispose(() {
      _generation++;
      _inFlight = null;
    });
    if (_repository?.isCurrent != true) {
      return ConnectedAgentsState(userId: null, grants: const []);
    }
    Future.microtask(() {
      if (ref.mounted && generation == _generation) return refresh();
    });
    return ConnectedAgentsState(userId: _repository!.userId, loading: true);
  }

  bool _isCurrent(int generation) =>
      ref.mounted &&
      generation == _generation &&
      _repository?.isCurrent == true;
  Future<void> refresh() {
    final generation = _generation;
    if (!_isCurrent(generation)) return Future.value();
    if (_inFlight case final pending?) return pending;
    final loadGeneration = ++_loadGeneration;
    return _inFlight = _load(generation, loadGeneration).whenComplete(() {
      if (generation == _generation && loadGeneration == _loadGeneration) {
        _inFlight = null;
      }
    });
  }

  Future<void> _load(int generation, int loadGeneration) async {
    try {
      final grants = (await _repository!.connectedAgents()).getOrThrow();
      if (!_isCurrent(generation) || loadGeneration != _loadGeneration) return;
      state = ConnectedAgentsState(
        userId: state.userId,
        grants: grants,
        revokingClientId: state.revokingClientId,
        revokeError: state.revokeError,
      );
    } catch (error) {
      if (_isCurrent(generation) && loadGeneration == _loadGeneration) {
        state = ConnectedAgentsState(
          userId: state.userId,
          grants: state.grants,
          error: error,
          revokingClientId: state.revokingClientId,
          revokeError: state.revokeError,
        );
      }
    }
  }

  Future<void> revoke(String clientId, String expectedUserId) async {
    final generation = _generation;
    if (!_isCurrent(generation) ||
        state.revokingClientId != null ||
        state.userId != expectedUserId) {
      return;
    }
    state = ConnectedAgentsState(
      userId: state.userId,
      grants: state.grants,
      error: state.error,
      revokingClientId: clientId,
    );
    try {
      (await _repository!.revokeAgent(clientId)).getOrThrow();
      if (!_isCurrent(generation)) return;
      _loadGeneration++;
      _inFlight = null;
      state = ConnectedAgentsState(
        userId: state.userId,
        grants: [
          for (final grant in state.grants ?? <ConnectedAgent>[])
            if (grant.clientId != clientId) grant,
        ],
        revokingClientId: clientId,
      );
      await refresh();
      if (_isCurrent(generation)) {
        state = ConnectedAgentsState(
          userId: state.userId,
          grants: state.grants,
          error: state.error,
        );
      }
    } catch (error) {
      if (_isCurrent(generation)) {
        state = ConnectedAgentsState(
          userId: state.userId,
          grants: state.grants,
          error: state.error,
          revokeError: error,
        );
      }
    }
  }
}

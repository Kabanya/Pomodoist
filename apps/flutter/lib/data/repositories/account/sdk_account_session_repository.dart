import 'dart:async';

import 'package:app_account/app_account.dart' show AccountAuthState;

import 'package:pomodoist/data/repositories/account/account_session_repository.dart';
import 'package:pomodoist/domain/models/account/account_overview.dart';
import 'package:pomodoist/domain/models/account/account_session.dart';
import 'package:pomodoist/utils/result.dart';

final class SdkAccountSessionRepository implements AccountSessionRepository {
  SdkAccountSessionRepository({
    required String? Function() currentUserId,
    required Stream<AccountAuthState> Function() authChanges,
    required Future<PomodoistAccountOverview?> Function() overviewLoader,
  }) : _currentUserId = currentUserId,
       _authChanges = authChanges,
       _overviewLoader = overviewLoader;

  final String? Function() _currentUserId;
  final Stream<AccountAuthState> Function() _authChanges;
  final Future<PomodoistAccountOverview?> Function() _overviewLoader;

  final _sessionController = StreamController<AccountSession>.broadcast();
  final _profileController =
      StreamController<PomodoistAccountProfile?>.broadcast();
  StreamSubscription<AccountAuthState>? _subscription;
  AccountSession _session = (userId: null, generation: 0);
  PomodoistAccountProfile? _profile;
  bool _started = false;
  bool _disposed = false;
  int _sourceGeneration = 0;
  @override
  AccountSession get currentSession {
    _ensureStarted();
    return _session;
  }

  /// Rebind the source without replacing this account-generation owner.
  void reconnect() {
    if (_disposed) return;
    ++_sourceGeneration;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _started = false;
    _session = (userId: _session.userId, generation: _session.generation + 1);
    _ensureStarted();
    _sessionController.add(_session);
  }

  void _ensureStarted() {
    if (_started || _disposed) {
      return;
    }
    _started = true;
    _setSession(_currentUserId());
    final sourceGeneration = _sourceGeneration;
    try {
      _subscription = _authChanges().listen((state) {
        if (!_disposed && sourceGeneration == _sourceGeneration) {
          _setSession(
            state.signedIn ? (state.session?.userId ?? _currentUserId()) : null,
          );
        }
      }, onError: (Object _, StackTrace _) {});
    } catch (_) {
      // The source may be unavailable before the account client is ready; the
      // captured identity remains valid and refresh() still reloads the profile.
    }
  }

  void _setSession(String? userId) {
    if (_disposed || userId == _session.userId) {
      return;
    }
    _session = (userId: userId, generation: _session.generation + 1);
    _sessionController.add(_session);
    _profile = null;
    _profileController.add(null);
    if (userId != null) {
      unawaited(_loadProfile(_session.generation));
    }
  }

  Future<void> _loadProfile(int generation) async {
    try {
      final overview = await _overviewLoader();
      if (_disposed || generation != _session.generation) {
        return;
      }
      _profile = overview?.profile;
    } catch (_) {
      if (_disposed || generation != _session.generation) {
        return;
      }
    }
    if (_disposed || generation != _session.generation) {
      return;
    }
    _profileController.add(_profile);
  }

  @override
  Stream<AccountSession> watchSession() async* {
    _ensureStarted();
    yield _session;
    yield* _sessionController.stream;
  }

  @override
  Stream<PomodoistAccountProfile?> watchProfile() async* {
    _ensureStarted();
    yield _profile;
    yield* _profileController.stream;
  }

  @override
  Future<Result<void>> refresh() async {
    _ensureStarted();
    if (_session.userId == null) {
      return const Success(null);
    }
    final generation = _session.generation;
    try {
      final overview = await _overviewLoader();
      if (_disposed || generation != _session.generation) {
        return const Success(null);
      }
      _profile = overview?.profile;
      _profileController.add(_profile);
      return const Success(null);
    } catch (error, stackTrace) {
      return Failure(error, stackTrace);
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    ++_sourceGeneration;
    await _subscription?.cancel();
    _subscription = null;
    await _sessionController.close();
    await _profileController.close();
  }
}

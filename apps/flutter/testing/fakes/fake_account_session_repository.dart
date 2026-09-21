import 'package:pomodoist/data/repositories/account/account_session_repository.dart';
import 'package:pomodoist/domain/models/account/account_overview.dart';
import 'package:pomodoist/domain/models/account/account_session.dart';
import 'package:pomodoist/utils/result.dart';

import 'strict_fake.dart';

/// In-memory [AccountSessionRepository] double.
///
/// Succeeding calls answer from the mutable fields below, every call is
/// recorded in its `<method>Calls` list, and a call whose `<method>Error`
/// field is non-null fails with that error instead of succeeding.
class FakeAccountSessionRepository extends StrictFake
    implements AccountSessionRepository {
  final watchSessionCalls = <void>[];
  final watchProfileCalls = <void>[];
  final refreshCalls = <void>[];

  /// Session [currentSession] and [watchSession] answer with.
  AccountSession session = (userId: null, generation: 0);

  /// Profile [watchProfile] answers with.
  PomodoistAccountProfile? profile;

  Object? refreshError;

  @override
  AccountSession get currentSession => session;

  /// Replays [session] once.
  @override
  Stream<AccountSession> watchSession() {
    watchSessionCalls.add(null);
    return Stream.value(session);
  }

  /// Replays [profile] once.
  @override
  Stream<PomodoistAccountProfile?> watchProfile() {
    watchProfileCalls.add(null);
    return Stream.value(profile);
  }

  @override
  Future<Result<void>> refresh() async {
    refreshCalls.add(null);
    final error = refreshError;
    if (error != null) return Result.error(error, StackTrace.current);
    return const Result.ok(null);
  }
}

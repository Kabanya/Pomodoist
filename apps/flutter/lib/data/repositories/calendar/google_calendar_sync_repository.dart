import 'package:pomodoist/utils/result.dart';

/// Domain failure for calendar connect/sync/disconnect operations. Callers
/// branch on [requiresAuthorization] instead of inspecting service exception
/// types or server error codes.
class GoogleCalendarFailure implements Exception {
  const GoogleCalendarFailure(this.code, this.message);

  final GoogleCalendarFailureCode code;
  final String message;

  bool get requiresAuthorization =>
      code == GoogleCalendarFailureCode.authorizationRequired;

  @override
  String toString() => message;
}

enum GoogleCalendarFailureCode { authorizationRequired, unavailable }

abstract interface class GoogleCalendarSyncRepository {
  Future<Result<void>> connect();
  Future<Result<void>> sync();
  Future<Result<void>> disconnect();
}

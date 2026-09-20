import 'package:pomodoist/data/repositories/calendar/google_calendar_sync_repository.dart';
import 'package:pomodoist/data/services/google_calendar/google_calendar_sync_controller.dart';
import 'package:pomodoist/utils/result.dart';

/// Server-backed calendar synchronization. Server error codes are translated
/// into [GoogleCalendarFailure] so the UI never sees the service exception.
class GoogleCalendarServerSyncRepository
    implements GoogleCalendarSyncRepository {
  GoogleCalendarServerSyncRepository(this._service);

  final GoogleCalendarSyncController _service;

  static const _authorizationCodes = {
    'auth_required',
    'authorization_unavailable',
    'invalid_grant',
    'unauthorized',
  };

  @override
  Future<Result<void>> connect() => _capture(_service.connect);

  @override
  Future<Result<void>> sync() =>
      _capture(() => _service.syncNow(interactive: true));

  @override
  Future<Result<void>> disconnect() => _capture(_service.disconnect);

  Future<Result<void>> _capture(Future<void> Function() operation) async {
    try {
      await operation();
      return const Success(null);
    } on GoogleCalendarServerException catch (error) {
      return Failure(
        GoogleCalendarFailure(
          _authorizationCodes.contains(error.code)
              ? GoogleCalendarFailureCode.authorizationRequired
              : GoogleCalendarFailureCode.unavailable,
          error.message,
        ),
        StackTrace.current,
      );
    } catch (error, stackTrace) {
      return Failure(
        GoogleCalendarFailure(
          GoogleCalendarFailureCode.unavailable,
          error.toString(),
        ),
        stackTrace,
      );
    }
  }
}

import 'package:pomodoist/data/services/google_calendar/google_calendar_sync_controller.dart';
import 'package:pomodoist/utils/result.dart';

class GoogleCalendarSyncRepository {
  GoogleCalendarSyncRepository(this._service);
  final GoogleCalendarSyncController _service;

  Future<Result<void>> connect() => Result.capture(_service.connect);
  Future<Result<void>> sync() =>
      Result.capture(() => _service.syncNow(interactive: true));
  Future<Result<void>> disconnect() => Result.capture(_service.disconnect);

  bool requiresAuthorization(Object error) =>
      error is GoogleCalendarServerException &&
      const {
        'auth_required',
        'authorization_unavailable',
        'invalid_grant',
        'unauthorized',
      }.contains(error.code);
}

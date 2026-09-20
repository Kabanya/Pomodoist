import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/calendar_dependencies.dart';
import 'package:pomodoist/utils/result.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/data/repositories/calendar/google_calendar_sync_repository.dart';
import 'package:pomodoist/domain/models/calendar/calendar_models.dart';

enum CalendarFailure { authRequired, unavailable }

class GoogleCalendarState {
  const GoogleCalendarState(this.connection, this.busy);
  final AsyncValue<GoogleCalendarConnection?> connection;
  final bool busy;
}

final googleCalendarViewModelProvider =
    NotifierProvider.autoDispose<GoogleCalendarViewModel, GoogleCalendarState>(
      GoogleCalendarViewModel.new,
    );

class GoogleCalendarViewModel extends Notifier<GoogleCalendarState> {
  late GoogleCalendarSyncRepository _repository;
  bool _busy = false;
  @override
  GoogleCalendarState build() {
    _repository = ref.watch(googleCalendarSyncRepositoryProvider);
    final value = ref.watch(googleCalendarConnectionProvider);
    return GoogleCalendarState(
      value.hasError
          ? AsyncError(classify(value.error!), value.stackTrace!)
          : value,
      _busy,
    );
  }

  CalendarFailure classify(Object error) =>
      error is GoogleCalendarFailure && error.requiresAuthorization
      ? CalendarFailure.authRequired
      : CalendarFailure.unavailable;
  void retry() => ref.invalidate(googleCalendarConnectionProvider);
  Future<CalendarFailure?> connect() => _run(_repository.connect);
  Future<CalendarFailure?> sync() => _run(_repository.sync);
  Future<CalendarFailure?> disconnect() => _run(_repository.disconnect);
  Future<CalendarFailure?> _run(Future<Result<void>> Function() action) async {
    if (_busy) return null;
    _busy = true;
    state = GoogleCalendarState(state.connection, true);
    try {
      final result = await action();
      if (result is Failure<void>) {
        return classify(result.error);
      }
      return null;
    } finally {
      _busy = false;
      if (ref.mounted) state = GoogleCalendarState(state.connection, false);
    }
  }
}

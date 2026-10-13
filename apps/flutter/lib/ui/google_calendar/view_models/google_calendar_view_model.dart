import 'package:pomodoist/domain/models/calendar/provider_calendar_models.dart';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/calendar_dependencies.dart';
import 'package:pomodoist/utils/result.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/data/repositories/calendar/google_calendar_sync_repository.dart';
import 'package:pomodoist/domain/models/calendar/calendar_models.dart';

enum CalendarFailure {
  authRequired,
  rateLimited,
  unavailable;

  static CalendarFailure fromError(Object error) {
    if (error is CalendarFailure) return error;
    if (error == 'authorization_required') return authRequired;
    if (error == 'rate_limited') return rateLimited;
    if (error is GoogleCalendarFailure && error.requiresAuthorization) {
      return authRequired;
    }
    final message = error is GoogleCalendarFailure ? error.message : error;
    if (message is String) {
      try {
        if (jsonDecode(message) case {'error': {'errors': List errors}}) {
          for (final detail in errors) {
            if (detail case {
              'reason': 'rateLimitExceeded' || 'userRateLimitExceeded',
            }) {
              return rateLimited;
            }
          }
        }
      } on FormatException {
        // Older saved errors may contain plain text instead of Google JSON.
      }
    }
    return unavailable;
  }
}

class GoogleCalendarState {
  const GoogleCalendarState(this.connection, this.busy);
  final AsyncValue<GoogleCalendarConnection?> connection;
  final bool busy;
}

final googleCalendarViewModelProvider =
    NotifierProvider.autoDispose<GoogleCalendarViewModel, GoogleCalendarState>(
      GoogleCalendarViewModel.new,
    );

final outlookCalendarViewModelProvider =
    NotifierProvider.autoDispose<GoogleCalendarViewModel, GoogleCalendarState>(
      () => GoogleCalendarViewModel(CalendarProvider.outlook),
    );

class GoogleCalendarViewModel extends Notifier<GoogleCalendarState> {
  GoogleCalendarViewModel([this.provider = CalendarProvider.google]);
  final CalendarProvider provider;
  late GoogleCalendarSyncRepository _repository;
  bool _busy = false;
  @override
  GoogleCalendarState build() {
    _repository = ref.watch(calendarSyncRepositoryProvider(provider));
    final connections = ref.watch(calendarConnectionsProvider);
    final legacy = provider == CalendarProvider.google
        ? ref.watch(googleCalendarConnectionProvider)
        : const AsyncData<GoogleCalendarConnection?>(null);
    final value = connections.whenData<GoogleCalendarConnection?>(
      (rows) =>
          rows.where((row) => row.provider == provider).firstOrNull ??
          legacy.value,
    );
    return GoogleCalendarState(
      value.hasError
          ? AsyncError(classify(value.error!), value.stackTrace!)
          : value,
      _busy,
    );
  }

  CalendarFailure classify(Object error) => CalendarFailure.fromError(error);
  void retry() {
    ref.invalidate(calendarConnectionsProvider);
    if (provider == CalendarProvider.google) {
      ref.invalidate(googleCalendarConnectionProvider);
    }
  }

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

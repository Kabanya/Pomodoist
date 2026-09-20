import 'package:app_account/app_account.dart';

import 'package:pomodoist/data/services/google_calendar/google_calendar_sync_controller.dart';

/// Authenticated account transport for Google Calendar server actions.
final class GoogleCalendarAccountTransport {
  const GoogleCalendarAccountTransport(this._account);

  final AccountClient? Function() _account;

  Future<AccountFunctionResponse> call(Map<String, Object?> body) {
    final account = _account();
    if (account?.currentUserId == null) {
      throw const GoogleCalendarServerException(
        'Sign in to connect Google Calendar.',
      );
    }
    return account!.invokeFunction('pomodoist-google-calendar', body: body);
  }
}

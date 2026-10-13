import 'package:app_account/app_account.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/calendar_dependencies.dart';
import 'package:pomodoist/domain/models/calendar/provider_calendar_models.dart';
import 'package:pomodoist/utils/result.dart';

void main() {
  test(
    'Google and Outlook actions use independent authenticated endpoints',
    () async {
      final account = _Account();
      final container = ProviderContainer(
        overrides: [accountClientProvider.overrideWithValue(account)],
      );
      addTearDown(container.dispose);
      final google = container.read(
        calendarSyncRepositoryProvider(CalendarProvider.google),
      );
      final outlook = container.read(
        calendarSyncRepositoryProvider(CalendarProvider.outlook),
      );
      expect(await google.sync(), isA<Success<void>>());
      expect(await outlook.sync(), isA<Success<void>>());
      expect(await outlook.disconnect(), isA<Success<void>>());
      expect(account.calls, [
        ('pomodoist-google-calendar', 'sync'),
        ('pomodoist-outlook-calendar', 'sync'),
        ('pomodoist-outlook-calendar', 'disconnect'),
      ]);
    },
  );
}

class _Account implements AccountClient {
  final calls = <(String, Object?)>[];
  @override
  String get currentUserId => 'user';
  @override
  Future<AccountFunctionResponse> invokeFunction(
    String name, {
    Map<String, String>? headers,
    Object? body,
    Map<String, dynamic>? queryParameters,
    String? region,
  }) async {
    calls.add((name, (body as Map)['action']));
    return const AccountFunctionResponse(status: 200, data: {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

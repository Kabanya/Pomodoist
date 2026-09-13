import 'package:app_account/app_account.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/features/integrations/google_calendar/data/google_calendar_sync_controller.dart';

void main() {
  test(
    'connect opens the server OAuth URL returned by the Edge Function',
    () async {
      final calls = <Map<String, Object?>>[];
      Uri? opened;
      final controller = GoogleCalendarSyncController(
        invoke: (body) async {
          calls.add(body);
          return const AccountFunctionResponse(
            status: 200,
            data: {'authorizationUrl': 'https://accounts.google.test/auth'},
          );
        },
        openUrl: (url) async {
          opened = url;
          return true;
        },
      );

      await controller.connect();

      expect(calls, [
        {'action': 'start'},
      ]);
      expect(opened, Uri.parse('https://accounts.google.test/auth'));
    },
  );

  test(
    'sync and disconnect call the server without local Google API work',
    () async {
      final calls = <Map<String, Object?>>[];
      final controller = GoogleCalendarSyncController(
        invoke: (body) async {
          calls.add(body);
          return AccountFunctionResponse(
            status: 200,
            data: body['action'] == 'sync'
                ? const {'queued': true}
                : const {'disconnected': true},
          );
        },
        openUrl: (_) async => true,
      );

      await controller.syncNow(interactive: true);
      await controller.disconnect();

      expect(calls, [
        {'action': 'sync'},
        {'action': 'disconnect'},
      ]);
    },
  );

  test(
    'server errors surface without changing local connection state',
    () async {
      final controller = GoogleCalendarSyncController(
        invoke: (_) async => const AccountFunctionResponse(
          status: 503,
          data: {'error': 'Google Calendar is not configured.'},
        ),
        openUrl: (_) async => true,
      );

      await expectLater(
        controller.syncNow(),
        throwsA(
          isA<GoogleCalendarServerException>().having(
            (error) => error.message,
            'message',
            'Google Calendar is not configured.',
          ),
        ),
      );
    },
  );
}

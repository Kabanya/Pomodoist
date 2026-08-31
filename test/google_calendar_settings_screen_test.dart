import 'package:app_account/app_account.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/providers.dart';
import 'package:pomodoist/app/account_providers.dart';
import 'package:pomodoist/core/db/app_database.dart';
import 'package:pomodoist/features/integrations/google_calendar/data/google_calendar_sync_controller.dart';
import 'package:pomodoist/features/integrations/google_calendar/presentation/google_calendar_settings_screen.dart';

void main() {
  testWidgets('settings ignores legacy owner device and uses server actions', (
    tester,
  ) async {
    final actions = <String>[];
    final now = DateTime.utc(2026, 8, 26);
    final controller = GoogleCalendarSyncController(
      invoke: (body) async {
        actions.add(body['action']! as String);
        return AccountFunctionResponse(
          status: 200,
          data: body['action'] == 'sync'
              ? const {'queued': true}
              : const {'disconnected': true},
        );
      },
      openUrl: (_) async => true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          googleCalendarSyncControllerProvider.overrideWithValue(controller),
          googleCalendarConnectionProvider.overrideWith(
            (ref) => Stream.value(
              GoogleCalendarConnectionRow(
                id: 'primary',
                accountEmail: 'user@example.com',
                calendarId: 'calendar-1',
                ownerDeviceId: 'another-device',
                calendarName: 'Pomodoist',
                syncToken: null,
                status: 'connected',
                lastError: null,
                warning: null,
                lastSyncStartedAt: now,
                lastSyncFinishedAt: now,
                createdAt: now,
                updatedAt: now,
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: GoogleCalendarSettingsScreen()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Sync now'), findsOneWidget);
    expect(find.text('Disconnect'), findsOneWidget);
    expect(find.text('Use this device'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Sync now'));
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Disconnect'));
    await tester.pump();

    expect(actions, ['sync', 'disconnect']);
  });

  testWidgets('settings hides transport exception details', (tester) async {
    final now = DateTime.utc(2026, 8, 31);
    final controller = GoogleCalendarSyncController(
      invoke: (_) => throw Exception('DioException private transport details'),
      openUrl: (_) async => true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          googleCalendarSyncControllerProvider.overrideWithValue(controller),
          googleCalendarConnectionProvider.overrideWith(
            (ref) => Stream.value(
              GoogleCalendarConnectionRow(
                id: 'primary',
                accountEmail: 'user@example.com',
                calendarId: 'calendar-1',
                ownerDeviceId: 'google-calendar-server',
                calendarName: 'Pomodoist',
                syncToken: null,
                status: 'connected',
                lastError: null,
                warning: null,
                lastSyncStartedAt: now,
                lastSyncFinishedAt: now,
                createdAt: now,
                updatedAt: now,
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: GoogleCalendarSettingsScreen()),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Sync now'));
    await tester.pump();

    expect(find.textContaining('DioException'), findsNothing);
    expect(find.textContaining('temporarily unavailable'), findsOneWidget);
  });
}

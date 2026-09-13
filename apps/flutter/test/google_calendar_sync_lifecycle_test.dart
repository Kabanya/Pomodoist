import 'dart:async';

import 'package:app_account/app_account.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/core/db/app_database.dart';
import 'package:pomodoist/features/integrations/google_calendar/data/google_calendar_sync_controller.dart';
import 'package:pomodoist/features/integrations/google_calendar/data/google_calendar_sync_lifecycle.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('connected calendar syncs once per foreground session', (
    tester,
  ) async {
    final connections = StreamController<GoogleCalendarConnectionRow?>();
    var syncs = 0;
    final lifecycle = GoogleCalendarSyncLifecycle(
      connections: connections.stream,
      syncController: GoogleCalendarSyncController(
        invoke: (body) async {
          if (body['action'] == 'sync') syncs++;
          return const AccountFunctionResponse(
            status: 200,
            data: {'queued': true},
          );
        },
        openUrl: (_) async => true,
      ),
    )..start();
    addTearDown(() async {
      lifecycle.dispose();
      await connections.close();
    });

    connections.add(_connection(status: 'disconnected', calendarId: null));
    await tester.pump();
    expect(syncs, 0);

    connections.add(_connection());
    await tester.pump();
    expect(syncs, 1);

    connections.add(_connection(updatedAt: DateTime.utc(2026, 8, 31, 12)));
    await tester.pump();
    expect(syncs, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(syncs, 2);
  });
}

GoogleCalendarConnectionRow _connection({
  String status = 'connected',
  String? calendarId = 'calendar-1',
  DateTime? updatedAt,
}) {
  final now = updatedAt ?? DateTime.utc(2026, 8, 31, 10);
  return GoogleCalendarConnectionRow(
    id: 'primary',
    accountEmail: 'user@example.com',
    calendarId: calendarId,
    ownerDeviceId: 'google-calendar-server',
    calendarName: 'Pomodoist',
    syncToken: null,
    status: status,
    lastError: null,
    warning: null,
    lastSyncStartedAt: now,
    lastSyncFinishedAt: now,
    createdAt: now,
    updatedAt: now,
  );
}

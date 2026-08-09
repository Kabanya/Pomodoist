import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/account_providers.dart';
import 'package:pomodoist/app/providers.dart';
import 'package:pomodoist/core/db/app_database.dart';
import 'package:pomodoist/features/integrations/google_calendar/data/auth/google_calendar_auth_contract.dart';
import 'package:pomodoist/features/integrations/google_calendar/data/google_calendar_api_client.dart';
import 'package:pomodoist/features/integrations/google_calendar/data/google_calendar_repository.dart';
import 'package:pomodoist/features/integrations/google_calendar/domain/google_calendar_event.dart';
import 'package:pomodoist/features/integrations/google_calendar/presentation/google_calendar_settings_screen.dart';
import 'package:pomodoist/features/integrations/google_calendar/presentation/google_calendar_web_sign_in_button.dart';

void main() {
  testWidgets('Google sign-in surface stays one button tall', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              GoogleCalendarWebSignInButton(),
              Text('After Google sign-in'),
            ],
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(GoogleCalendarWebSignInButton)).height,
      40,
    );
    expect(tester.getTopLeft(find.text('After Google sign-in')).dy, 40);
  });

  testWidgets('settings screen shows connected state and sync errors', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 5);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pomodoistDeviceIdProvider.overrideWith((ref) async => 'device-1'),
          googleCalendarAuthServiceProvider.overrideWithValue(
            const _NoopGoogleCalendarAuthService(),
          ),
          googleCalendarConnectionProvider.overrideWith(
            (ref) => Stream.value(
              GoogleCalendarConnectionRow(
                id: 'primary',
                accountEmail: 'user@example.com',
                calendarId: 'calendar-1',
                calendarName: 'Pomodoist',
                syncToken: 'sync-token',
                status: 'error',
                lastError: 'Auth expired',
                warning:
                    'Recurring Google Calendar events are not supported yet.',
                lastSyncStartedAt: now,
                lastSyncFinishedAt: now,
                createdAt: now,
                updatedAt: now,
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: GoogleCalendarSettingsScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Google Calendar'), findsOneWidget);
    expect(find.text('Sync now'), findsOneWidget);
    expect(find.text('Disconnect'), findsOneWidget);
    expect(find.text('user@example.com'), findsOneWidget);
    expect(find.text('Auth expired'), findsOneWidget);
    expect(find.textContaining('Recurring Google Calendar'), findsOneWidget);
  });

  testWidgets('connect button uses fake auth and API without network', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureSeedData();
    final auth = _FakeGoogleCalendarAuthService();
    final api = _FakeGoogleCalendarApiClient();

    await _pumpSettingsScreen(tester, db: db, auth: auth, api: api);

    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await _pumpFrames(tester);

    final connection = await DriftCalendarIntegrationRepository(
      db,
    ).getConnection();
    expect(auth.signInCount, 1);
    expect(auth.accessTokenCount, 1);
    expect(api.createCalendarCount, 1);
    expect(api.listEventsCount, 1);
    expect(connection?.status, 'connected');
    expect(connection?.calendarId, 'calendar-1');
    expect(find.text('Sync now'), findsOneWidget);
    await _disposeApp(tester);
  });

  testWidgets(
    'sync and disconnect buttons use fake auth and API without network',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.ensureSeedData();
      final integrationRepository = DriftCalendarIntegrationRepository(db);
      await integrationRepository.saveConnected(
        accountEmail: 'user@example.com',
        calendarId: 'calendar-1',
        calendarName: 'Pomodoist',
      );
      final auth = _FakeGoogleCalendarAuthService();
      final api = _FakeGoogleCalendarApiClient();

      await _pumpSettingsScreen(tester, db: db, auth: auth, api: api);

      await tester.tap(find.widgetWithText(FilledButton, 'Sync now'));
      await _pumpFrames(tester);
      expect(auth.accessTokenCount, 1);
      expect(api.listEventsCount, 1);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Disconnect'));
      await _pumpFrames(tester);

      final connection = await integrationRepository.getConnection();
      expect(auth.disconnectCount, 1);
      expect(connection?.status, 'disconnected');
      expect(connection?.calendarId, isNull);
      expect(find.text('Connect'), findsOneWidget);
      await _disposeApp(tester);
    },
  );
}

Future<void> _pumpSettingsScreen(
  WidgetTester tester, {
  required AppDatabase db,
  required _FakeGoogleCalendarAuthService auth,
  required _FakeGoogleCalendarApiClient api,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        googleCalendarAuthServiceProvider.overrideWithValue(auth),
        googleCalendarApiClientProvider.overrideWithValue(api),
      ],
      child: const MaterialApp(home: GoogleCalendarSettingsScreen()),
    ),
  );
  await _pumpFrames(tester);
}

Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump();
}

Future<void> _disposeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
}

class _NoopGoogleCalendarAuthService implements GoogleCalendarAuthService {
  const _NoopGoogleCalendarAuthService();

  @override
  Future<String?> accessToken({bool interactive = false}) async => null;

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<GoogleCalendarAuthAccount> signIn() async {
    return const GoogleCalendarAuthAccount();
  }
}

class _FakeGoogleCalendarAuthService implements GoogleCalendarAuthService {
  int initializeCount = 0;
  int signInCount = 0;
  int accessTokenCount = 0;
  int disconnectCount = 0;

  @override
  Future<void> initialize() async {
    initializeCount++;
  }

  @override
  Future<GoogleCalendarAuthAccount> signIn() async {
    signInCount++;
    return const GoogleCalendarAuthAccount(email: 'user@example.com');
  }

  @override
  Future<String?> accessToken({bool interactive = false}) async {
    accessTokenCount++;
    return 'token';
  }

  @override
  Future<void> disconnect() async {
    disconnectCount++;
  }
}

class _FakeGoogleCalendarApiClient implements GoogleCalendarApiClient {
  int createCalendarCount = 0;
  int getCalendarCount = 0;
  int listEventsCount = 0;
  int insertEventCount = 0;
  int patchEventCount = 0;
  int deleteEventCount = 0;

  @override
  Future<GoogleCalendarApiCalendar> createCalendar(String name) async {
    createCalendarCount++;
    return const GoogleCalendarApiCalendar(
      id: 'calendar-1',
      summary: 'Pomodoist',
    );
  }

  @override
  Future<GoogleCalendarApiCalendar> getCalendar(String calendarId) async {
    getCalendarCount++;
    return GoogleCalendarApiCalendar(id: calendarId, summary: 'Pomodoist');
  }

  @override
  Future<GoogleCalendarListResult> listEvents({
    required String calendarId,
    String? syncToken,
    String? pageToken,
  }) async {
    listEventsCount++;
    return const GoogleCalendarListResult(
      events: [],
      nextSyncToken: 'next-sync-token',
    );
  }

  @override
  Future<GoogleCalendarEvent> insertEvent({
    required String calendarId,
    required GoogleCalendarEvent event,
  }) async {
    insertEventCount++;
    return const GoogleCalendarEvent(id: 'event-1');
  }

  @override
  Future<GoogleCalendarEvent> patchEvent({
    required String calendarId,
    required String eventId,
    required GoogleCalendarEvent event,
  }) async {
    patchEventCount++;
    return GoogleCalendarEvent(id: eventId);
  }

  @override
  Future<void> deleteEvent({
    required String calendarId,
    required String eventId,
  }) async {
    deleteEventCount++;
  }
}

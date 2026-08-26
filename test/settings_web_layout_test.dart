import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/account_providers.dart';
import 'package:pomodoist/app/providers.dart';
import 'package:pomodoist/features/billing/billing.dart';
import 'package:pomodoist/features/integrations/google_calendar/presentation/google_calendar_settings_screen.dart';
import 'package:pomodoist/features/settings/presentation/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('web settings leaves Google Calendar on its integrations route', (
    tester,
  ) async {
    if (!kIsWeb) return;
    SharedPreferences.setMockInitialValues(const {});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountBootstrapInitializerProvider.overrideWithValue(
            () async => null,
          ),
          accountOverviewProvider.overrideWith((ref) async => null),
          applePurchasesSupportedProvider.overrideWithValue(false),
          googleCalendarConnectionProvider.overrideWith(
            (ref) => Stream.value(null),
          ),
          pomodoistDeviceIdProvider.overrideWith((ref) async => 'device-1'),
        ],
        child: const MaterialApp(home: Scaffold(body: SettingsScreen())),
      ),
    );
    await tester.pump();
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    for (var i = 0; i < 3; i += 1) {
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pump();
    }

    expect(find.byType(GoogleCalendarSettingsScreen), findsNothing);
  });
}

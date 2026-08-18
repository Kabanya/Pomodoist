import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/features/billing/billing.dart';
import 'package:pomodoist/features/settings/presentation/app_info_card.dart';
import 'package:pomodoist/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
  });

  testWidgets('shows the installed version and free plan on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appVersionProvider.overrideWith((ref) async => '2.4.1 (37)'),
          applePurchasesSupportedProvider.overrideWithValue(false),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SettingsAppInfoCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-app-info-card')), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
    expect(find.text('Version'), findsOneWidget);
    expect(find.text('2.4.1 (37)'), findsOneWidget);
    expect(find.text('Plan'), findsOneWidget);
    expect(find.text('Free'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows a dash when installed version loading fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appVersionProvider.overrideWith(
            (ref) => Future<String>.error(StateError('unavailable')),
          ),
          applePurchasesSupportedProvider.overrideWithValue(false),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SettingsAppInfoCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(find.byKey(const Key('settings-app-version-value')))
          .data,
      '—',
    );
  });

  testWidgets('shows a dash while the installed version is loading', (
    tester,
  ) async {
    final pendingVersion = Completer<String>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appVersionProvider.overrideWith((ref) => pendingVersion.future),
          applePurchasesSupportedProvider.overrideWithValue(false),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SettingsAppInfoCard()),
        ),
      ),
    );
    await tester.pump();

    expect(
      tester
          .widget<Text>(find.byKey(const Key('settings-app-version-value')))
          .data,
      '—',
    );
  });

  testWidgets('shows Monthly for an active monthly plan', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appVersionProvider.overrideWith((ref) async => '2.4.1 (37)'),
          billingControllerProvider.overrideWith(
            () => _StaticBillingController(
              const BillingState(
                loading: false,
                activeProductId: pomodoistMonthlyProductId,
                activeStoreKitProductIds: {pomodoistMonthlyProductId},
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SettingsAppInfoCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Monthly'), findsOneWidget);
  });

  testWidgets('shows Annual for an active annual plan', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appVersionProvider.overrideWith((ref) async => '2.4.1 (37)'),
          billingControllerProvider.overrideWith(
            () => _StaticBillingController(
              const BillingState(
                loading: false,
                activeProductId: pomodoistAnnualProductId,
                activeStoreKitProductIds: {pomodoistAnnualProductId},
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SettingsAppInfoCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Annual'), findsOneWidget);
  });

  testWidgets('shows Lifetime for an active lifetime plan', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appVersionProvider.overrideWith((ref) async => '2.4.1 (37)'),
          billingControllerProvider.overrideWith(
            () => _StaticBillingController(
              const BillingState(
                loading: false,
                activeProductId: pomodoistLifetimeProductId,
                activeStoreKitProductIds: {pomodoistLifetimeProductId},
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SettingsAppInfoCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Lifetime'), findsOneWidget);
  });

  testWidgets('shows Pro without exposing an unknown active product id', (
    tester,
  ) async {
    const unknownProductId = 'internal.legacy.product';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appVersionProvider.overrideWith((ref) async => '2.4.1 (37)'),
          billingControllerProvider.overrideWith(
            () => _StaticBillingController(
              const BillingState(
                loading: false,
                activeProductId: unknownProductId,
                activeStoreKitProductIds: {unknownProductId},
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SettingsAppInfoCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pomodoist Pro'), findsOneWidget);
    expect(find.text(unknownProductId), findsNothing);
  });

  testWidgets('updates the displayed plan when billing state changes', (
    tester,
  ) async {
    final billingController = _StaticBillingController(
      const BillingState(loading: false),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appVersionProvider.overrideWith((ref) async => '2.4.1 (37)'),
          billingControllerProvider.overrideWith(() => billingController),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SettingsAppInfoCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Free'), findsOneWidget);

    billingController.replaceState(
      const BillingState(
        loading: false,
        activeProductId: pomodoistMonthlyProductId,
        activeStoreKitProductIds: {pomodoistMonthlyProductId},
      ),
    );
    await tester.pump();

    expect(find.text('Monthly'), findsOneWidget);
    expect(find.text('Free'), findsNothing);
  });
}

class _StaticBillingController extends BillingController {
  _StaticBillingController(this.initialState);

  final BillingState initialState;

  @override
  BillingState build() => initialState;

  void replaceState(BillingState nextState) {
    state = nextState;
  }
}

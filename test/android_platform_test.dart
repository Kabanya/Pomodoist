import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/core/notifications/android_alarm_policy.dart';
import 'package:pomodoist/features/billing/billing.dart';
import 'package:pomodoist/features/focus/presentation/focus_view_mode.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('uses inexact scheduling when exact access was not granted', () async {
    final modes = <AndroidScheduleMode>[];
    await scheduleAndroidAlarm(
      canScheduleExact: () async => false,
      schedule: (mode) async => modes.add(mode),
    );
    expect(modes, [AndroidScheduleMode.inexactAllowWhileIdle]);
  });

  test('uses exact scheduling only with existing permission', () async {
    final modes = <AndroidScheduleMode>[];
    await scheduleAndroidAlarm(
      canScheduleExact: () async => true,
      schedule: (mode) async => modes.add(mode),
    );
    expect(modes, [AndroidScheduleMode.exactAllowWhileIdle]);
  });

  test('permission revoked between check and schedule falls back once', () async {
    final modes = <AndroidScheduleMode>[];
    await scheduleAndroidAlarm(
      canScheduleExact: () async => true,
      schedule: (mode) async {
        modes.add(mode);
        if (mode == AndroidScheduleMode.exactAllowWhileIdle) {
          throw PlatformException(code: 'exact_alarms_not_permitted');
        }
      },
    );
    expect(modes, [
      AndroidScheduleMode.exactAllowWhileIdle,
      AndroidScheduleMode.inexactAllowWhileIdle,
    ]);
  });

  test('failed capability check does not prevent inexact reminders', () async {
    final modes = <AndroidScheduleMode>[];
    await scheduleAndroidAlarm(
      canScheduleExact: () async => throw PlatformException(code: 'unavailable'),
      schedule: (mode) async => modes.add(mode),
    );
    expect(modes, [AndroidScheduleMode.inexactAllowWhileIdle]);
  });

  test('unrelated scheduling errors are not hidden or retried', () async {
    var calls = 0;
    await expectLater(
      scheduleAndroidAlarm(
        canScheduleExact: () async => true,
        schedule: (_) async {
          calls++;
          throw PlatformException(code: 'invalid_icon');
        },
      ),
      throwsA(isA<PlatformException>()),
    );
    expect(calls, 1);
  });

  testWidgets('Android preserves account access without initializing StoreKit', (
    tester,
  ) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) async => null),
          billingChannelProvider.overrideWithValue(BillingChannel.storeKit),
          billingAccountEntitlementProvider.overrideWithValue(true),
          billingStoreProvider.overrideWith(
            (ref) => throw StateError('StoreKit must not be initialized on Android'),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(applePurchasesSupported, isFalse);
      container.read(billingControllerProvider);
      await tester.pump();
      final state = container.read(billingControllerProvider);
      expect(state.loading, isFalse);
      expect(state.canPurchase, isFalse);
      expect(state.accountEntitlementActive, isTrue);
      expect(state.hasActiveEntitlement, isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });
}

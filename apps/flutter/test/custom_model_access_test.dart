import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/clock_provider.dart';
import 'package:pomodoist/config/custom_model_access.dart';
import 'package:pomodoist/domain/models/billing/billing_models.dart';
import 'package:pomodoist/utils/clock.dart';

void main() {
  final now = DateTime.utc(2026, 11, 22);
  final expiry = now.add(const Duration(days: 1));
  BillingTransactionProof proof(
    String sku, [
    Map<String, Object?> fields = const {},
  ]) {
    return BillingTransactionProof(
      productId: sku,
      jws: 'verified',
      localVerificationData: jsonEncode({
        'productId': sku,
        'price': 4990,
        'inAppOwnershipType': 'PURCHASED',
        'expiresDate': expiry.millisecondsSinceEpoch,
        ...fields,
      }),
    );
  }

  test('monthly access ends with the paid period', () {
    final paid = proof(pomodoistMonthlyProductId);
    expect(customModelStoreGrant([paid], now), (
      permanent: false,
      validUntil: expiry,
    ));
    expect(customModelStoreGrant([paid], expiry), (
      permanent: false,
      validUntil: null,
    ));
    expect(
      customModelStoreGrant([
        proof(pomodoistMonthlyProductId, {'isUpgraded': true}),
      ], now).validUntil,
      isNull,
    );
  });

  test(
    'a historical paid annual or either lifetime SKU grants permanent access',
    () {
      for (final product in [
        pomodoistAnnualProductId,
        pomodoistLifetimeProductId,
        pomodoistLifetimeLaunchProductId,
      ]) {
        expect(
          customModelStoreGrant([proof(product)], expiry).permanent,
          isTrue,
        );
      }
      final refunded = proof(pomodoistAnnualProductId, {'revocationDate': 1});
      expect(
        customModelStoreGrant([
          refunded,
          proof(pomodoistAnnualProductId),
        ], expiry).permanent,
        isTrue,
      );
      expect(
        customModelStoreGrant([
          refunded,
          proof(pomodoistMonthlyProductId),
        ], now),
        (permanent: false, validUntil: expiry),
      );
    },
  );

  test(
    'trials, missing amounts, unowned purchases and refunds do not qualify',
    () {
      for (final field in [
        {'price': 0},
        {'price': null},
        {'offerDiscountType': 'FREE_TRIAL'},
        {'inAppOwnershipType': 'FAMILY_SHARED'},
        {'revocationDate': 1},
        {'productId': 'unrelated'},
      ]) {
        expect(
          customModelStoreGrant([
            proof(pomodoistAnnualProductId, field),
          ], now).permanent,
          isFalse,
        );
      }
      expect(
        customModelStoreGrant([proof('unrelated')], now).permanent,
        isFalse,
      );
    },
  );

  test(
    'an open consumer refreshes at expiry without a new purchase or login',
    () {
      fakeAsync((time) {
        final clock = FixedClock(now);
        final container = ProviderContainer(
          overrides: [
            clockProvider.overrideWithValue(clock),
            customModelGrantLoaderProvider.overrideWithValue(
              (_) async => (permanent: false, validUntil: expiry),
            ),
          ],
        );
        container.listen(customModelAccessProvider, (_, _) {});
        time.flushMicrotasks();
        expect(container.read(customModelAccessProvider).requireValue, isTrue);
        clock.value = expiry;
        time.elapse(const Duration(days: 1));
        time.flushMicrotasks();
        expect(container.read(customModelAccessProvider).requireValue, isFalse);
        container.dispose();
      });
    },
  );
}

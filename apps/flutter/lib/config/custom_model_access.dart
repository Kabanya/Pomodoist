import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/billing_dependencies.dart';
import 'package:pomodoist/config/billing_store_dependencies.dart';
import 'package:pomodoist/config/clock_provider.dart';
import 'package:pomodoist/domain/models/billing/billing_models.dart';

typedef CustomModelGrant = ({bool permanent, DateTime? validUntil});

const _noGrant = (permanent: false, validUntil: null);

/// Only native StoreKit-verified proofs may be supplied to this projection.
CustomModelGrant customModelStoreGrant(
  Iterable<BillingTransactionProof> proofs,
  DateTime now,
) {
  DateTime? validUntil;
  for (final proof in proofs) {
    final Object? data;
    try {
      data = jsonDecode(proof.localVerificationData);
    } on FormatException {
      continue;
    }
    if (data is! Map ||
        data['productId'] != proof.productId ||
        data['inAppOwnershipType'] != 'PURCHASED' ||
        data['revocationDate'] != null ||
        data['offerDiscountType'] == 'FREE_TRIAL' ||
        data['price'] is! num ||
        (data['price'] as num) <= 0) {
      continue;
    }
    if (proof.productId == pomodoistAnnualProductId ||
        proof.productId == pomodoistLifetimeProductId ||
        proof.productId == pomodoistLifetimeLaunchProductId) {
      return (permanent: true, validUntil: null);
    }
    if (proof.productId == pomodoistMonthlyProductId &&
        data['isUpgraded'] != true) {
      final expiry = appleBillingDate(data['expiresDate']);
      if (expiry != null &&
          expiry.isAfter(now) &&
          (validUntil == null || expiry.isAfter(validUntil))) {
        validUntil = expiry;
      }
    }
  }
  return (permanent: false, validUntil: validUntil);
}

final customModelGrantLoaderProvider =
    Provider<Future<CustomModelGrant> Function(Ref)>(
      (ref) => _loadCustomModelGrant,
    );

Future<CustomModelGrant> _loadCustomModelGrant(Ref ref) async {
  final lifecycle = AppLifecycleListener(onResume: ref.invalidateSelf);
  ref.onDispose(lifecycle.dispose);
  ref.watch(billingAccountIdentityProvider);
  ref.watch(billingAccountRefreshTokenProvider);
  ref.watch(billingAccessProvider);
  final account = ref.watch(accountClientProvider);
  final owner = account?.currentUserId;
  if (owner != null) {
    final response = await ref
        .watch(accountOverviewSupabaseClientProvider)
        .schema('api_v1')
        .rpc('pomodoist_custom_model_access')
        .timeout(ref.watch(accountRequestTimeoutProvider));
    if (account?.currentUserId != owner) return _noGrant;
    if (response is! Map || response['permanent'] is! bool) {
      throw const FormatException('Invalid custom model entitlement.');
    }
    return (
      permanent: response['permanent'] as bool,
      validUntil: response['validUntil'] == null
          ? null
          : DateTime.parse(response['validUntil'] as String).toUtc(),
    );
  }
  if (!ref.watch(applePurchasesSupportedProvider) ||
      ref.watch(billingChannelProvider) != BillingChannel.storeKit) {
    return _noGrant;
  }
  final store = ref.watch(billingStoreProvider);
  final clock = ref.watch(clockProvider);
  final active = await store.refreshCurrentEntitlements();
  final grant = customModelStoreGrant(active, clock.now());
  if (grant.permanent) return grant;
  final history = await store.paidAnnualTransactions();
  return customModelStoreGrant([...active, ...history], clock.now());
}

/// Paid monthly access expires at the end of the paid period. A verified
/// annual payment or lifetime purchase continues to work after Pro expires.
final customModelAccessProvider = FutureProvider<bool>((ref) async {
  final clock = ref.watch(clockProvider);
  final grant = await ref.watch(customModelGrantLoaderProvider)(ref);
  if (grant.permanent) return true;
  final remaining = grant.validUntil?.difference(clock.now());
  if (remaining == null || remaining <= Duration.zero || !ref.mounted) {
    return false;
  }
  final timer = Timer(remaining, ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return true;
});

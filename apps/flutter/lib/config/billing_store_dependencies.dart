import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/data/repositories/billing/billing_repository.dart';
import 'package:pomodoist/data/repositories/billing/store_billing_repository.dart';
import 'package:pomodoist/data/repositories/billing/unavailable_billing_repository.dart';
import 'package:pomodoist/data/services/billing/billing_store.dart';
import 'package:pomodoist/domain/models/billing/billing_models.dart';

final billingStoreProvider = Provider<BillingStore>((ref) => BillingStore());
final billingRepositoryProvider = Provider<BillingRepository>(
  (ref) => ref.watch(applePurchasesSupportedProvider)
      ? StoreBillingRepository(ref.watch(billingStoreProvider))
      : const UnavailableBillingRepository(),
);
final billingStoreTimeoutProvider = Provider<Duration>(
  (ref) => billingStoreTimeout,
);
final billingPurchaseTimeoutProvider = Provider<Duration>(
  (ref) => billingPurchaseTimeout,
);
final applePurchasesSupportedProvider = Provider<bool>(
  (ref) =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS),
);

import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/billing_store_dependencies.dart';
import 'package:pomodoist/config/clock_provider.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/data/repositories/billing/billing_repository.dart';
import 'package:pomodoist/data/repositories/billing/billing_repository_impl.dart';
import 'package:pomodoist/domain/models/billing/billing_access.dart';
import 'package:pomodoist/domain/models/billing/billing_models.dart';

typedef BillingAppAccountTokenLoader = Future<String?> Function();

/// StoreKit/Stripe channel selection for the current build.
final billingChannelProvider = Provider<BillingChannel>(
  (ref) => defaultBillingChannel,
);

/// Account entitlement inputs injected into the shared access repository.
final billingActiveAccountEntitlementProvider = Provider<BillingEntitlement?>(
  (ref) => null,
);
final billingAccountEntitlementProvider = Provider<bool>(
  (ref) => ref.watch(billingActiveAccountEntitlementProvider) != null,
);
final billingEnvironmentEntitlementProvider = Provider<bool>((ref) => false);
final billingSignedInProvider = Provider<bool>((ref) => false);
final billingAccountIdentityProvider = Provider<Object?>((ref) => null);
final billingAccountRefreshTokenProvider = Provider<Object?>((ref) => null);
final billingAppAccountTokenLoaderProvider =
    Provider<BillingAppAccountTokenLoader>(
      (ref) =>
          () async => null,
    );
final billingPurchaseLinkerProvider = Provider<BillingPurchaseLinker?>(
  (ref) => null,
);

/// The single owner of verified entitlement state for the current account.
final billingRepositoryProvider = Provider<BillingRepository>((ref) {
  final repository = AppBillingRepository(
    store: ref.watch(billingStoreProvider),
    preferences: ref.watch(preferencesServiceProvider),
    now: () => ref.read(clockProvider).now(),
    channel: ref.watch(billingChannelProvider),
    storeSupported: ref.watch(applePurchasesSupportedProvider),
    signedIn: ref.read(billingSignedInProvider),
    purchaseLinker: () => ref.read(billingPurchaseLinkerProvider),
    storeTimeout: ref.watch(billingStoreTimeoutProvider),
    purchaseTimeout: ref.watch(billingPurchaseTimeoutProvider),
    stripeGateway: () => ref.read(billingStripeGatewayProvider),
    offerRequest: () => ref.read(billingOfferRequestProvider),
    accountToken: () => ref.read(billingAppAccountTokenLoaderProvider)(),
    surface: kIsWeb
        ? BillingCheckoutSurface.web
        : BillingCheckoutSurface.native,
  );
  repository
    ..setAccountEntitlement(ref.read(billingActiveAccountEntitlementProvider))
    ..setAccountEntitlementActive(ref.read(billingAccountEntitlementProvider))
    ..setEnvironmentEntitlement(
      ref.read(billingEnvironmentEntitlementProvider),
    );
  ref.listen<bool>(
    billingAccountEntitlementProvider,
    (_, next) => repository.setAccountEntitlementActive(next),
  );
  ref.listen<BillingEntitlement?>(
    billingActiveAccountEntitlementProvider,
    (_, next) => repository.setAccountEntitlement(next),
  );
  ref.listen<bool>(
    billingEnvironmentEntitlementProvider,
    (_, next) => repository.setEnvironmentEntitlement(next),
  );
  ref.listen<bool>(
    billingSignedInProvider,
    (_, next) => repository.handleSignedInChanged(next),
  );
  ref.listen<Object?>(billingAccountIdentityProvider, (previous, next) {
    if (previous == next) return;
    repository.handleAccountIdentityChanged();
  });
  ref.listen<Object?>(billingAccountRefreshTokenProvider, (previous, next) {
    if (previous == next || next == null) return;
    repository.handleAccountRefreshTokenChanged();
  });
  final lifecycleListener = AppLifecycleListener(
    onResume: repository.handleAppResume,
  );
  ref.onDispose(() {
    lifecycleListener.dispose();
    repository.dispose();
  });
  return repository;
});

/// Read-only access projection for consumers that only need entitlement state.
final billingAccessProvider = StreamProvider<BillingAccess>(
  (ref) => ref.watch(billingRepositoryProvider).watchAccess(),
);

final billingStripeGatewayProvider = Provider<BillingStripeGateway?>(
  (ref) => null,
);

final billingOfferRequestProvider = Provider<BillingOfferRequest?>(
  (ref) => null,
);

final billingReturnOffersProvider =
    FutureProvider.autoDispose<BillingReturnOffers>((ref) {
      ref.watch(billingAccessProvider);
      ref.watch(billingAccountIdentityProvider);
      ref.watch(billingOfferRequestProvider);
      return ref.watch(billingRepositoryProvider).loadReturnOffers();
    });

typedef BillingSignInPrompt = Future<void> Function(BuildContext context);
typedef BillingEntitlementRefresher = Future<bool> Function();

final billingSignInPromptProvider = Provider<BillingSignInPrompt?>(
  (ref) => null,
);
final billingEntitlementRefresherProvider =
    Provider<BillingEntitlementRefresher>(
      (ref) =>
          () async => false,
    );
final billingStripePollIntervalProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 3),
);

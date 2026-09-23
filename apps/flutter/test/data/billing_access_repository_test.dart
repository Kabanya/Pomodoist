import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:pomodoist/data/repositories/billing/billing_repository_impl.dart';
import 'package:pomodoist/data/services/billing/billing_store.dart';
import 'package:pomodoist/data/services/local/preferences_service.dart';
import 'package:pomodoist/domain/models/billing/billing_models.dart';
import 'package:pomodoist/utils/result.dart';
import 'package:shared_preferences/shared_preferences.dart';

BillingTransactionProof _proof(
  String productId, {
  DateTime? expires,
  bool revoked = false,
  String? transactionId,
}) => BillingTransactionProof(
  productId: productId,
  transactionId: transactionId ?? 'transaction-$productId',
  jws: 'proof-$productId',
  localVerificationData: jsonEncode({
    if (expires != null) 'expiresDate': expires.millisecondsSinceEpoch,
    if (revoked) 'revocationDate': 1,
  }),
);

PurchaseDetails _pendingDetails(BillingTransactionProof proof) =>
    billingPurchaseFromTransactionProof(proof)..pendingCompletePurchase = true;

({AppBillingRepository repository, _FakeBillingStore store}) _build({
  _FakeBillingStore? store,
  bool storeSupported = true,
  bool signedIn = false,
  DateTime Function()? now,
  Future<void> Function(List<String>)? linker,
}) {
  final billingStore = store ?? _FakeBillingStore();
  final repository = AppBillingRepository(
    store: billingStore,
    preferences: PreferencesService(
      () async => SharedPreferences.getInstance(),
    ),
    now: now ?? () => DateTime.utc(2026, 1, 1),
    channel: BillingChannel.storeKit,
    storeSupported: storeSupported,
    signedIn: signedIn,
    purchaseLinker: () => linker,
  );
  addTearDown(repository.dispose);
  addTearDown(billingStore.events.close);
  return (repository: repository, store: billingStore);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'catalog requests from multiple screens share one source request',
    () async {
      final gate = Completer<StripeBillingCatalog>();
      var calls = 0;
      final repository = _stripeRepository(
        BillingStripeGateway(
          loadCatalog: () {
            calls++;
            return gate.future;
          },
          createCheckout: (_, _, _) async =>
              Uri.https('checkout.stripe.com', '/test'),
          openCheckout: (_) async => true,
        ),
      );
      final first = repository.loadCatalog();
      final second = repository.loadCatalog();
      await pumpEventQueue();
      expect(calls, 1);
      gate.complete(
        StripeBillingCatalog(
          enabled: true,
          introEligible: false,
          launchOfferEligible: false,
          launchOfferEndsAt: null,
          prices: {pomodoistMonthlyProductId: '5'},
        ),
      );
      await Future.wait([first, second]);
      expect(repository.catalog.products.keys, [pomodoistMonthlyProductId]);
      expect(() => repository.catalog.products.clear(), throwsUnsupportedError);
    },
  );

  test(
    'Stripe purchase preserves selected return offer and never retries at full price',
    () async {
      final selections = <String?>[];
      var opens = 0;
      final repository = _stripeRepository(
        BillingStripeGateway(
          loadCatalog: () async => StripeBillingCatalog(
            enabled: true,
            introEligible: false,
            subscriptionOffer: 'return',
            launchOfferEligible: false,
            launchOfferEndsAt: null,
          ),
          createCheckout: (_, _, offer) async {
            selections.add(offer);
            throw const StripeBillingException('offer_not_eligible');
          },
          openCheckout: (_) async {
            opens++;
            return true;
          },
        ),
      );
      await repository.loadCatalog();
      final result = await repository.purchase(pomodoistMonthlyProductId);
      expect(result, isA<Failure<bool>>());
      expect(selections, ['return']);
      expect(opens, 0);
    },
  );

  test('concurrent purchase commands open only one checkout', () async {
    final gate = Completer<Uri>();
    var creates = 0;
    var opens = 0;
    final repository = _stripeRepository(
      BillingStripeGateway(
        loadCatalog: () async => StripeBillingCatalog(
          enabled: true,
          introEligible: false,
          launchOfferEligible: false,
          launchOfferEndsAt: null,
        ),
        createCheckout: (_, _, _) {
          creates++;
          return gate.future;
        },
        openCheckout: (_) async {
          opens++;
          return true;
        },
      ),
    );
    final first = repository.purchase(pomodoistMonthlyProductId);
    final second = repository.purchase(pomodoistMonthlyProductId);
    expect(repository.pendingProductId, pomodoistMonthlyProductId);
    expect(creates, 1);
    gate.complete(Uri.https('checkout.stripe.com', '/test'));
    expect((await first).getOrThrow(), isTrue);
    expect((await second).getOrThrow(), isTrue);
    expect(opens, 1);
    expect(repository.pendingProductId, isNull);
  });

  test(
    'account switch discards a stale catalog and loads the new account',
    () async {
      final gates = [
        Completer<StripeBillingCatalog>(),
        Completer<StripeBillingCatalog>(),
      ];
      var calls = 0;
      final repository = _stripeRepository(
        BillingStripeGateway(
          loadCatalog: () => gates[calls++].future,
          createCheckout: (_, _, _) async =>
              Uri.https('checkout.stripe.com', '/test'),
          openCheckout: (_) async => true,
        ),
      );
      final pending = repository.loadCatalog();
      await pumpEventQueue();
      repository.handleAccountIdentityChanged();
      gates.first.complete(
        StripeBillingCatalog(
          enabled: true,
          introEligible: true,
          launchOfferEligible: true,
          launchOfferEndsAt: null,
          prices: {pomodoistMonthlyProductId: 'old'},
        ),
      );
      await pending;
      await pumpEventQueue();
      expect(repository.catalog.products, isEmpty);
      expect(calls, 2);
      gates.last.complete(
        StripeBillingCatalog(
          enabled: true,
          introEligible: false,
          launchOfferEligible: false,
          launchOfferEndsAt: null,
          prices: {pomodoistMonthlyProductId: 'new'},
        ),
      );
      await repository.loadCatalog();
      expect(
        repository.catalog.products[pomodoistMonthlyProductId]!.price,
        'new',
      );
    },
  );

  test('free account reports no active entitlement', () async {
    final h = _build();

    expect(h.repository.currentAccess.loading, isTrue);
    final result = await h.repository.refresh();

    expect(result, isA<Success<void>>());
    expect(h.repository.currentAccess.loading, isFalse);
    expect(h.repository.currentAccess.hasActiveEntitlement, isFalse);
    expect(h.repository.currentAccess.hasLocalStoreKitEntitlement, isFalse);
    expect(h.repository.purchasedProductIds, isEmpty);
  });

  test('monthly, annual and lifetime proofs grant local access', () async {
    for (final (productId, expectedProduct) in [
      (pomodoistMonthlyProductId, pomodoistMonthlyProductId),
      (pomodoistAnnualProductId, pomodoistAnnualProductId),
      (pomodoistLifetimeProductId, pomodoistLifetimeProductId),
    ]) {
      SharedPreferences.setMockInitialValues({});
      final store = _FakeBillingStore()
        ..transactions = [
          _proof(
            productId,
            expires: DateTime.utc(2030),
            transactionId: 'transaction-$productId',
          ),
        ];
      final h = _build(store: store);

      await h.repository.refresh();

      expect(
        h.repository.currentAccess.hasLocalStoreKitEntitlement,
        isTrue,
        reason: productId,
      );
      expect(h.repository.activeProductId, expectedProduct);
      expect(h.repository.activeStoreKitProductIds, {productId});
      expect(h.repository.purchasedProductIds, contains(productId));
      expect(h.store.finished, isEmpty);
    }
  });

  test(
    'expired subscription cannot grant access but stays in history',
    () async {
      final h = _build(now: () => DateTime.utc(2026, 6, 1));
      h.store.transactions = [
        _proof(pomodoistMonthlyProductId, expires: DateTime.utc(2026, 1, 1)),
        _proof(pomodoistAnnualProductId, expires: DateTime.utc(2030, 1, 1)),
      ];

      await h.repository.refresh();

      expect(h.repository.currentAccess.hasLocalStoreKitEntitlement, isTrue);
      expect(h.repository.activeProductId, pomodoistAnnualProductId);
      expect(h.repository.activeStoreKitProductIds, {pomodoistAnnualProductId});
      expect(
        h.repository.purchasedProductIds,
        containsAll([pomodoistMonthlyProductId, pomodoistAnnualProductId]),
      );
    },
  );

  test('expired-only proofs grant nothing', () async {
    final h = _build(now: () => DateTime.utc(2026, 6, 1));
    h.store.transactions = [
      _proof(pomodoistMonthlyProductId, expires: DateTime.utc(2026, 1, 1)),
    ];

    await h.repository.refresh();

    expect(h.repository.currentAccess.hasLocalStoreKitEntitlement, isFalse);
    expect(h.repository.currentAccess.hasActiveEntitlement, isFalse);
    expect(h.repository.activeProductId, isNull);
  });

  test('restore surfaces the verified purchase as success', () async {
    final proof = _proof(pomodoistAnnualProductId, expires: DateTime.utc(2030));
    final h = _build();
    h.store.restore = () async => [proof];

    final result = await h.repository.restore();

    expect(result, isA<Success<void>>());
    expect(h.repository.currentAccess.hasLocalStoreKitEntitlement, isTrue);
    expect(h.repository.purchaseSuccessProductId, pomodoistAnnualProductId);
  });

  test('an unavailable store never grants access and stays inert', () async {
    final h = _build(storeSupported: false);

    final result = await h.repository.refresh();

    expect(result, isA<Success<void>>());
    expect(h.repository.currentAccess.loading, isFalse);
    expect(h.repository.currentAccess.hasActiveEntitlement, isFalse);
    expect(h.repository.storeAvailable, isFalse);
  });

  test('watchAccess starts with the current snapshot', () async {
    final h = _build();

    final first = await h.repository.watchAccess().first;

    expect(first.hasActiveEntitlement, isFalse);
    expect(first.loading, isTrue);
  });

  test('duplicate purchase callback finishes the transaction once', () async {
    final proof = _proof(
      pomodoistLifetimeProductId,
      transactionId: 'transaction-lifetime',
    );
    final h = _build();
    h.store.transactions = [proof];
    final finish = Completer<void>();
    h.store.finish = (_, id) async {
      if (id == proof.transactionId) await finish.future;
    };
    final update = h.store.mapPurchase(_pendingDetails(proof));

    await h.repository.processPurchaseUpdate(update);
    await h.repository.processPurchaseUpdate(update);
    await pumpEventQueue();

    expect(h.repository.currentAccess.hasLocalStoreKitEntitlement, isTrue);
    expect(h.store.finishCalls, 1);
    finish.complete();
    await pumpEventQueue();
    expect(h.store.finishCalls, 1);
  });

  test('unverified purchase proof cannot grant access or finish', () async {
    final links = <String>[];
    final h = _build(
      signedIn: true,
      linker: (transactions) async => links.addAll(transactions),
    );
    h.repository.beginPurchase(pomodoistLifetimeProductId);
    h.store.snapshot = () async =>
        throw PlatformException(code: 'storekit_unverified_transaction');
    final proof = _proof(pomodoistLifetimeProductId);

    await h.repository.processPurchaseUpdate(
      h.store.mapPurchase(_pendingDetails(proof)),
    );
    await pumpEventQueue();

    expect(h.repository.currentAccess.hasActiveEntitlement, isFalse);
    expect(h.repository.confirmationFailure, isNotNull);
    expect(links, isEmpty);
    expect(h.store.finished, isEmpty);
  });

  test('cancellation during restore keeps the verified access', () async {
    final h = _build();
    h.store.transactions = [
      _proof(pomodoistLifetimeProductId, transactionId: 'transaction-lifetime'),
    ];
    await h.repository.refresh();
    expect(h.repository.currentAccess.hasLocalStoreKitEntitlement, isTrue);
    h.store.restore = () async =>
        throw PlatformException(code: 'userCancelled');

    final result = await h.repository.restore();

    expect(result, isA<Failure<void>>());
    expect(h.repository.currentAccess.hasLocalStoreKitEntitlement, isTrue);
  });

  test(
    'late snapshot after account change cannot link to the new account',
    () async {
      final links = <String>[];
      final stale = Completer<List<BillingTransactionProof>>();
      var requests = 0;
      final h = _build(
        signedIn: true,
        linker: (transactions) async => links.addAll(transactions),
      );
      h.store.snapshot = () {
        requests++;
        return requests == 1
            ? stale.future
            : Future.value([
                _proof(pomodoistAnnualProductId, expires: DateTime.utc(2030)),
              ]);
      };
      final refresh = h.repository.refresh();
      await pumpEventQueue();
      h.repository.handleAccountIdentityChanged();
      stale.complete([
        _proof(pomodoistLifetimeProductId, expires: DateTime.utc(2030)),
      ]);
      await refresh;
      await pumpEventQueue();

      expect(links, ['proof-$pomodoistAnnualProductId']);
      expect(h.repository.activeProductId, pomodoistAnnualProductId);
    },
  );

  test('late stale snapshot cannot clear newer verified access', () async {
    final stale = Completer<List<BillingTransactionProof>>();
    var requests = 0;
    final h = _build();
    h.store.snapshot = () {
      requests++;
      return requests == 1
          ? stale.future
          : Future.value([
              _proof(pomodoistLifetimeProductId, expires: DateTime.utc(2030)),
            ]);
    };
    final first = h.repository.refresh();
    await pumpEventQueue();
    final proof = _proof(pomodoistLifetimeProductId);
    h.store.transactions.add(proof);
    await h.repository.processPurchaseUpdate(
      h.store.mapPurchase(billingPurchaseFromTransactionProof(proof)),
    );
    stale.complete(const <BillingTransactionProof>[]);
    await first;
    await pumpEventQueue();

    expect(requests, 2);
    expect(h.repository.currentAccess.hasLocalStoreKitEntitlement, isTrue);
  });
  test(
    'verified entitlement snapshots cannot mutate repository access',
    () async {
      final h = _build();
      h.store.transactions = [_proof(pomodoistLifetimeProductId)];
      await h.repository.refresh();
      expect(
        () => h.repository.activeStoreKitProductIds.clear(),
        throwsUnsupportedError,
      );
      expect(h.repository.currentAccess.hasLocalStoreKitEntitlement, isTrue);
    },
  );
}

class _FakeBillingStore extends BillingStore {
  final events = StreamController<List<PurchaseDetails>>.broadcast();
  List<BillingTransactionProof> transactions = [];
  final finished = <String?>[];
  var finishCalls = 0;
  Future<void> Function(PurchaseDetails purchase, String? id)? finish;
  BillingTransactionLoader? snapshot;
  Future<List<BillingTransactionProof>> Function()? restore;
  bool failRefresh = false;
  int refreshRequests = 0;
  int restoreRequests = 0;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => events.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<List<BillingTransactionProof>> refreshCurrentEntitlements() async {
    refreshRequests += 1;
    if (snapshot != null) return snapshot!();
    if (failRefresh) throw StateError('StoreKit unavailable');
    return List.of(transactions);
  }

  @override
  Future<List<BillingTransactionProof>> restorePurchases() {
    restoreRequests += 1;
    return restore != null ? restore!() : refreshCurrentEntitlements();
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    finishCalls += 1;
    finished.add(purchase.purchaseID);
    await finish?.call(purchase, purchase.purchaseID);
  }

  @override
  Future<bool> isVerifiedInactivePurchase(PurchaseDetails purchase) async =>
      false;
}

AppBillingRepository _stripeRepository(BillingStripeGateway gateway) {
  final store = _FakeBillingStore();
  final repository = AppBillingRepository(
    store: store,
    preferences: PreferencesService(
      () async => SharedPreferences.getInstance(),
    ),
    now: () => DateTime.utc(2026),
    channel: BillingChannel.stripe,
    storeSupported: false,
    signedIn: true,
    purchaseLinker: () => null,
    stripeGateway: () => gateway,
  );
  addTearDown(repository.dispose);
  addTearDown(store.events.close);
  return repository;
}

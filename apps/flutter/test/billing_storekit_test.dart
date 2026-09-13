import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:pomodoist/app/providers.dart';
import 'package:pomodoist/core/time/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:pomodoist/features/billing/billing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('catalog retry does not wait for an unrelated entitlement read', () {
    fakeAsync((time) {
      final snapshot = Completer<List<BillingTransactionProof>>();
      var requests = 0;
      final store = _Store()
        ..snapshot = (() => snapshot.future)
        ..catalog = () async {
          requests++;
          return _catalog({});
        };
      final container = _ready(store, time);
      expect(
        container.read(billingControllerProvider).needsCatalogRetry,
        isTrue,
      );
      container.read(billingControllerProvider.notifier).reload();
      time.flushMicrotasks();
      expect(requests, 2);
      snapshot.complete([]);
      time.flushMicrotasks();
    });
  });

  test('partial catalog retry does not wait for introductory eligibility', () {
    fakeAsync((time) {
      final eligibility = Completer<bool>();
      var requests = 0;
      final store = _Store()
        ..eligibility = ((_) => eligibility.future)
        ..catalog = () async {
          requests++;
          return _catalog({pomodoistAnnualProductId});
        };
      final container = _ready(store, time);
      store.catalog = () async {
        requests++;
        return _catalog({pomodoistLifetimeProductId});
      };
      container.read(billingControllerProvider.notifier).reload();
      time.flushMicrotasks();
      expect(requests, 2);
      eligibility.complete(true);
      time.flushMicrotasks();
      expect(
        container
            .read(billingControllerProvider)
            .eligibleIntroductoryProductIds,
        isEmpty,
      );
    });
  });

  test(
    'purchase finishes only after verification and retries a failed finish',
    () {
      fakeAsync((time) {
        final store = _Store();
        final container = _ready(store, time);
        final snapshot = Completer<List<BillingTransactionProof>>();
        store.snapshot = () => snapshot.future;
        final purchase = _purchase(pomodoistLifetimeProductId)
          ..pendingCompletePurchase = true;
        store.emit([purchase]);
        time.flushMicrotasks();
        expect(store.finished, isEmpty);
        snapshot.completeError(StateError('verification unavailable'));
        time.flushMicrotasks();
        expect(store.finished, isEmpty);

        store.snapshot = null;
        store.finish = (_) async => throw StateError('finish unavailable');
        container.read(billingControllerProvider.notifier).reload();
        time.flushMicrotasks();
        expect(
          container.read(billingControllerProvider).hasLocalStoreKitEntitlement,
          isTrue,
        );
        expect(store.finished, [purchase.purchaseID]);

        final finish = Completer<void>();
        store.finish = (_) => finish.future;
        container.read(billingControllerProvider.notifier).reload();
        time.flushMicrotasks();
        store.emit([purchase, purchase]);
        time.flushMicrotasks();
        expect(store.finished, [purchase.purchaseID, purchase.purchaseID]);
        finish.complete();
        time.flushMicrotasks();
        container.read(billingControllerProvider.notifier).reload();
        time.flushMicrotasks();
        expect(store.finished, hasLength(2));
      });
    },
  );

  test('Restore allows both sync and the subsequent snapshot to complete', () {
    fakeAsync((time) {
      final sync = Completer<void>();
      final snapshot = Completer<List<BillingTransactionProof>>();
      final nativeStore = BillingStore(
        restoreSynchronizer: () => sync.future,
        transactionLoader: () => snapshot.future,
      );
      final store = _Store()..restore = nativeStore.restorePurchases;
      final container = _ready(store, time);
      container.read(billingControllerProvider.notifier).restorePurchases();
      time.elapse(const Duration(seconds: 20));
      sync.complete();
      time.flushMicrotasks();
      time.elapse(const Duration(seconds: 20));
      expect(container.read(billingControllerProvider).restoring, isTrue);
      snapshot.complete([
        BillingTransactionProof.fromPurchase(
          _purchase(pomodoistLifetimeProductId),
        ),
      ]);
      time.flushMicrotasks();
      expect(container.read(billingControllerProvider).error, isNull);
      expect(
        container.read(billingControllerProvider).hasLocalStoreKitEntitlement,
        isTrue,
      );
    });
  });

  test('verified revoked transaction can finish without restoring access', () {
    fakeAsync((time) {
      final store = _Store();
      final container = _ready(store, time);
      final purchase = _purchase(pomodoistAnnualProductId, revoked: true)
        ..pendingCompletePurchase = true;
      store.snapshot = () async => [];
      store.inactiveVerifiedIds.add(purchase.purchaseID!);
      store.emit([purchase]);
      time.flushMicrotasks();
      expect(store.finished, [purchase.purchaseID]);
      expect(
        container.read(billingControllerProvider).hasLocalStoreKitEntitlement,
        isFalse,
      );
    });
  });

  test('failed refresh preserves previously verified lifetime access', () {
    fakeAsync((time) {
      final store = _Store();
      final container = _ready(store, time);
      store.emit([_purchase(pomodoistLifetimeProductId)]);
      time.flushMicrotasks();
      expect(
        container.read(billingControllerProvider).hasLocalStoreKitEntitlement,
        isTrue,
      );
      store.failRefresh = true;
      container.read(billingControllerProvider.notifier).reload();
      time.flushMicrotasks();
      expect(
        container.read(billingControllerProvider).hasLocalStoreKitEntitlement,
        isTrue,
      );
    });
  });

  test('separate transaction events preserve every active purchase', () {
    fakeAsync((time) {
      final store = _Store();
      final container = _ready(store, time);
      store.emit([_purchase(pomodoistLifetimeProductId)]);
      store.emit([_purchase(pomodoistAnnualProductId)]);
      time.flushMicrotasks();
      expect(
        container.read(billingControllerProvider).activeStoreKitProductIds,
        {pomodoistLifetimeProductId, pomodoistAnnualProductId},
      );
    });
  });

  test('empty catalog remains unavailable so the customer can retry', () {
    fakeAsync((time) {
      final container = _ready(_Store(emptyCatalog: true), time);
      expect(container.read(billingControllerProvider).storeAvailable, isFalse);
    });
  });

  test('collects all proofs from the complete entitlement snapshot', () {
    fakeAsync((time) {
      final store = _Store()
        ..transactions = [
          _purchase(pomodoistLifetimeProductId),
          _purchase(pomodoistAnnualProductId),
        ];
      addTearDown(store.events.close);
      List<String>? result;
      store.pomodoistTransactionJws().then((value) => result = value);
      time.flushMicrotasks();
      time.elapse(Duration.zero);
      expect(result?.toSet(), {
        'proof-$pomodoistLifetimeProductId',
        'proof-$pomodoistAnnualProductId',
      });
    });
  });

  test(
    'successful empty snapshot removes local rights and saved active product',
    () {
      fakeAsync((time) {
        final store = _Store()
          ..transactions = [_purchase(pomodoistLifetimeProductId)];
        final container = _ready(store, time);
        expect(
          container.read(billingControllerProvider).hasLocalStoreKitEntitlement,
          isTrue,
        );
        store.transactions = [];
        container.read(billingControllerProvider.notifier).reload();
        time.flushMicrotasks();
        expect(
          container.read(billingControllerProvider).hasLocalStoreKitEntitlement,
          isFalse,
        );
        SharedPreferences.getInstance().then((prefs) {
          expect(prefs.getString(billingActiveProductIdPreferenceKey), isNull);
          expect(
            prefs.getStringList(billingPurchasedProductIdsPreferenceKey),
            contains(pomodoistLifetimeProductId),
          );
        });
        time.flushMicrotasks();
      });
    },
  );

  test(
    'subscription expires during StoreKit outage without another request',
    () {
      fakeAsync((time) {
        final clock = FixedClock(DateTime.utc(2026));
        final expires = clock.now().add(const Duration(minutes: 1));
        final store = _Store()
          ..transactions = [
            _purchase(pomodoistAnnualProductId, expires: expires),
          ];
        final container = _ready(
          store,
          time,
          overrides: [clockProvider.overrideWithValue(clock)],
        );
        store.failRefresh = true;
        clock.value = expires;
        time.elapse(const Duration(minutes: 1));
        expect(
          container.read(billingControllerProvider).hasLocalStoreKitEntitlement,
          isFalse,
        );
        expect(store.refreshRequests, 1);
      });
    },
  );

  test('resume rechecks expiration while an entitlement read fails', () {
    fakeAsync((time) {
      final clock = FixedClock(DateTime.utc(2026));
      final store = _Store()
        ..transactions = [
          _purchase(
            pomodoistMonthlyProductId,
            expires: clock.now().add(const Duration(hours: 1)),
          ),
        ];
      final container = _ready(
        store,
        time,
        overrides: [clockProvider.overrideWithValue(clock)],
      );
      store.failRefresh = true;
      clock.value = clock.now().add(const Duration(hours: 2));
      WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.inactive,
      );
      WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      time.flushMicrotasks();
      expect(
        container.read(billingControllerProvider).hasLocalStoreKitEntitlement,
        isFalse,
      );
      expect(store.refreshRequests, 2);
    });
  });

  test('revocation is immediate even while a snapshot fails', () {
    fakeAsync((time) {
      final store = _Store()
        ..transactions = [_purchase(pomodoistLifetimeProductId)];
      final container = _ready(store, time);
      final snapshot = Completer<List<BillingTransactionProof>>();
      store.snapshot = () => snapshot.future;
      container.read(billingControllerProvider.notifier).reload();
      time.flushMicrotasks();
      store.emit([_purchase(pomodoistLifetimeProductId, revoked: true)]);
      time.flushMicrotasks();
      expect(
        container.read(billingControllerProvider).hasLocalStoreKitEntitlement,
        isFalse,
      );
      snapshot.completeError(StateError('offline'));
      time.flushMicrotasks();
      expect(
        container.read(billingControllerProvider).hasLocalStoreKitEntitlement,
        isFalse,
      );
    });
  });

  test('purchase during snapshot waits for one fresh verified snapshot', () {
    fakeAsync((time) {
      final store = _Store();
      final stale = Completer<List<BillingTransactionProof>>();
      final fresh = Completer<List<BillingTransactionProof>>();
      store.snapshot = () =>
          store.refreshRequests == 1 ? stale.future : fresh.future;
      final container = _ready(store, time);
      store.emit([_purchase(pomodoistLifetimeProductId)]);
      time.flushMicrotasks();
      stale.complete([]);
      time.flushMicrotasks();
      expect(
        container.read(billingControllerProvider).hasLocalStoreKitEntitlement,
        isFalse,
      );
      expect(store.refreshRequests, 2);
      fresh.complete([
        BillingTransactionProof.fromPurchase(
          _purchase(pomodoistLifetimeProductId),
        ),
      ]);
      time.flushMicrotasks();
      expect(
        container.read(billingControllerProvider).activeProductId,
        pomodoistLifetimeProductId,
      );
      expect(store.refreshRequests, 2);
    });
  });

  test(
    'duplicate events link once and lifetime outranks annual and monthly',
    () {
      fakeAsync((time) {
        final linked = <List<String>>[];
        final store = _Store();
        final container = _ready(
          store,
          time,
          overrides: [
            billingSignedInProvider.overrideWithValue(true),
            billingPurchaseLinkerProvider.overrideWithValue(
              (proofs) async => linked.add(proofs),
            ),
          ],
        );
        for (final id in [
          pomodoistMonthlyProductId,
          pomodoistAnnualProductId,
          pomodoistLifetimeProductId,
          pomodoistLifetimeProductId,
        ]) {
          store.emit([_purchase(id)]);
        }
        time.flushMicrotasks();
        final state = container.read(billingControllerProvider);
        expect(state.activeProductId, pomodoistLifetimeProductId);
        expect(state.activeStoreKitProductIds, {
          pomodoistMonthlyProductId,
          pomodoistAnnualProductId,
          pomodoistLifetimeProductId,
        });
        expect(linked.expand((list) => list).length, 3);
        store.emit([_purchase(pomodoistLifetimeProductId, revoked: true)]);
        time.flushMicrotasks();
        expect(
          container.read(billingControllerProvider).activeProductId,
          pomodoistAnnualProductId,
        );
      });
    },
  );

  test(
    'slow account linking cannot block later purchases or local settings',
    () {
      fakeAsync((time) {
        final linking = Completer<void>();
        final store = _Store()
          ..transactions = [_purchase(pomodoistMonthlyProductId)];
        final container = _ready(
          store,
          time,
          overrides: [
            billingSignedInProvider.overrideWithValue(true),
            billingPurchaseLinkerProvider.overrideWithValue(
              (_) => linking.future,
            ),
          ],
        );
        store.emit([_purchase(pomodoistLifetimeProductId)]);
        time.flushMicrotasks();
        expect(
          container.read(billingControllerProvider).activeProductId,
          pomodoistLifetimeProductId,
        );
        SharedPreferences.getInstance().then(
          (prefs) => expect(
            prefs.getString(billingActiveProductIdPreferenceKey),
            pomodoistLifetimeProductId,
          ),
        );
        time.flushMicrotasks();
        linking.complete();
        time.flushMicrotasks();
      });
    },
  );

  test(
    'partial catalog can sell found products and recover missing products',
    () {
      fakeAsync((time) {
        final store = _Store()..catalogIds = {pomodoistAnnualProductId};
        final container = _ready(store, time);
        var state = container.read(billingControllerProvider);
        expect(state.canPurchase, isTrue);
        expect(state.needsCatalogRetry, isTrue);
        expect(
          state.missingProductIds,
          billingProductIds.difference({pomodoistAnnualProductId}),
        );
        final catalog = Completer<ProductDetailsResponse>();
        store.catalog = () => catalog.future;
        container.read(billingControllerProvider.notifier).reload();
        time.flushMicrotasks();
        state = container.read(billingControllerProvider);
        expect(state.loading, isFalse);
        expect(state.productDetailsById.keys, [pomodoistAnnualProductId]);
        container
            .read(billingControllerProvider.notifier)
            .purchase(pomodoistAnnualProductId);
        time.flushMicrotasks();
        expect(store.bought, [pomodoistAnnualProductId]);
        catalog.complete(_catalog(billingProductIds));
        time.flushMicrotasks();
        expect(
          container.read(billingControllerProvider).needsCatalogRetry,
          isFalse,
        );
      });
    },
  );

  test('background catalog error retains products and retry recovers', () {
    fakeAsync((time) {
      final store = _Store();
      final container = _ready(store, time);
      store.catalog = () async => throw StateError('catalog unavailable');
      container.read(billingControllerProvider.notifier).reload();
      time.flushMicrotasks();
      final state = container.read(billingControllerProvider);
      expect(state.productDetailsById.keys.toSet(), billingProductIds);
      expect(state.canPurchase, isTrue);
      expect(state.catalogError, contains('catalog unavailable'));
      expect(state.error, isNull);
      store.catalog = null;
      container.read(billingControllerProvider.notifier).reload();
      time.flushMicrotasks();
      expect(
        container.read(billingControllerProvider).needsCatalogRetry,
        isFalse,
      );
    });
  });

  test('Restore cancellation keeps access and permits another restore', () {
    fakeAsync((time) {
      final store = _Store()
        ..transactions = [_purchase(pomodoistLifetimeProductId)];
      final container = _ready(store, time);
      store.restore = () async => throw PlatformException(
        code: 'storekit2_failed_to_sync_to_app_store',
        details: 'StoreKitError.userCancelled',
      );
      container.read(billingControllerProvider.notifier).restorePurchases();
      time.flushMicrotasks();
      final state = container.read(billingControllerProvider);
      expect(state.restoring, isFalse);
      expect(state.error, isNull);
      expect(state.hasLocalStoreKitEntitlement, isTrue);
      store.restore = () async => [];
      container.read(billingControllerProvider.notifier).restorePurchases();
      time.flushMicrotasks();
      expect(store.restoreRequests, 2);
      expect(
        container.read(billingControllerProvider).hasLocalStoreKitEntitlement,
        isFalse,
      );
    });
  });

  test('explicit restore relinks all proofs and merges repeat taps', () {
    fakeAsync((time) {
      final links = <List<String>>[];
      final store = _Store()
        ..transactions = [
          _purchase(pomodoistMonthlyProductId),
          _purchase(pomodoistLifetimeProductId),
        ];
      final container = _ready(
        store,
        time,
        overrides: [
          billingSignedInProvider.overrideWithValue(true),
          billingPurchaseLinkerProvider.overrideWithValue(
            (proofs) async => links.add(proofs),
          ),
        ],
      );
      expect(links.single.length, 2);
      final result = Completer<List<BillingTransactionProof>>();
      store.restore = () => result.future;
      final controller = container.read(billingControllerProvider.notifier);
      controller.restorePurchases();
      controller.restorePurchases();
      expect(store.restoreRequests, 1);
      result.complete(
        store.transactions.map(BillingTransactionProof.fromPurchase).toList(),
      );
      time.flushMicrotasks();
      expect(links.length, 2);
      expect(links.last.toSet(), links.first.toSet());
      expect(container.read(billingControllerProvider).restoring, isFalse);
    });
  });

  test('late snapshot after account change cannot link to the new account', () {
    fakeAsync((time) {
      final links = <String>[];
      final old = Completer<List<BillingTransactionProof>>();
      final fresh = Completer<List<BillingTransactionProof>>();
      final store = _Store();
      store.snapshot = () =>
          store.refreshRequests == 1 ? old.future : fresh.future;
      final container = _ready(
        store,
        time,
        overrides: [
          billingSignedInProvider.overrideWithValue(true),
          billingAccountIdentityProvider.overrideWith(
            (ref) => ref.watch(_identityProvider),
          ),
          billingPurchaseLinkerProvider.overrideWithValue(
            (proofs) async => links.addAll(proofs),
          ),
        ],
      );
      container.read(_identityProvider.notifier).change('account-b');
      time.flushMicrotasks();
      old.complete([
        BillingTransactionProof.fromPurchase(
          _purchase(pomodoistLifetimeProductId),
        ),
      ]);
      time.flushMicrotasks();
      expect(links, isEmpty);
      expect(store.refreshRequests, 2);
      fresh.complete([
        BillingTransactionProof.fromPurchase(
          _purchase(pomodoistAnnualProductId),
        ),
      ]);
      time.flushMicrotasks();
      expect(links, ['proof-$pomodoistAnnualProductId']);
    });
  });

  test('unverified plugin success cannot grant access or link its JWS', () {
    fakeAsync((time) {
      final links = <String>[];
      final store = _Store();
      final container = _ready(
        store,
        time,
        overrides: [
          billingSignedInProvider.overrideWithValue(true),
          billingPurchaseLinkerProvider.overrideWithValue(
            (proofs) async => links.addAll(proofs),
          ),
        ],
      );
      container
          .read(billingControllerProvider.notifier)
          .purchase(pomodoistLifetimeProductId);
      time.flushMicrotasks();
      store.snapshot = () async =>
          throw PlatformException(code: 'storekit_unverified_transaction');
      // The plugin sends exactly this event for both verified and unverified purchases.
      store.events.add([
        _purchase(pomodoistLifetimeProductId)..pendingCompletePurchase = true,
      ]);
      time.flushMicrotasks();
      final state = container.read(billingControllerProvider);
      expect(state.hasLocalStoreKitEntitlement, isFalse);
      expect(state.purchaseSuccessProductId, isNull);
      expect(state.error, contains('storekit_unverified_transaction'));
      expect(links, isEmpty);
      expect(store.finished, isEmpty);
    });
  });

  test(
    'account refresh survives an old snapshot completing during Restore',
    () {
      fakeAsync((time) {
        final links = <String>[];
        final store = _Store();
        final container = _ready(
          store,
          time,
          overrides: [
            billingSignedInProvider.overrideWithValue(true),
            billingAccountIdentityProvider.overrideWith(
              (ref) => ref.watch(_identityProvider),
            ),
            billingPurchaseLinkerProvider.overrideWithValue(
              (proofs) async => links.addAll(proofs),
            ),
          ],
        );
        final old = Completer<List<BillingTransactionProof>>();
        final synced = Completer<List<BillingTransactionProof>>();
        final fresh = Completer<List<BillingTransactionProof>>();
        store.snapshot = () =>
            store.refreshRequests == 2 ? old.future : fresh.future;
        store.restore = () => synced.future;
        final controller = container.read(billingControllerProvider.notifier);
        controller.reload();
        time.flushMicrotasks();
        controller.restorePurchases();
        container.read(_identityProvider.notifier).change('account-b');
        container.read(billingAccountIdentityProvider);
        time.flushMicrotasks();
        old.complete([]);
        time.flushMicrotasks();
        synced.complete([
          BillingTransactionProof.fromPurchase(
            _purchase(pomodoistLifetimeProductId),
          ),
        ]);
        time.flushMicrotasks();
        expect(links, isEmpty);
        expect(store.refreshRequests, 3);
        fresh.complete([
          BillingTransactionProof.fromPurchase(
            _purchase(pomodoistAnnualProductId),
          ),
        ]);
        time.flushMicrotasks();
        expect(links, ['proof-$pomodoistAnnualProductId']);
      });
    },
  );

  test(
    'Restore success survives a transaction event invalidating its snapshot',
    () {
      fakeAsync((time) {
        final store = _Store();
        final container = _ready(store, time);
        final restored = Completer<List<BillingTransactionProof>>();
        final fresh = Completer<List<BillingTransactionProof>>();
        store.restore = () => restored.future;
        store.snapshot = () => fresh.future;
        container.read(billingControllerProvider.notifier).restorePurchases();
        store.emit([_purchase(pomodoistAnnualProductId)]);
        time.flushMicrotasks();
        restored.complete([]);
        time.flushMicrotasks();
        expect(
          container.read(billingControllerProvider).purchaseSuccessProductId,
          isNull,
        );
        fresh.complete([
          BillingTransactionProof.fromPurchase(
            _purchase(pomodoistAnnualProductId),
          ),
        ]);
        time.flushMicrotasks();
        expect(
          container.read(billingControllerProvider).purchaseSuccessProductId,
          pomodoistAnnualProductId,
        );
      });
    },
  );

  test('late token after account change cannot start a purchase', () {
    fakeAsync((time) {
      final token = Completer<String?>();
      final store = _Store();
      final container = _ready(
        store,
        time,
        overrides: [
          billingAccountIdentityProvider.overrideWith(
            (ref) => ref.watch(_identityProvider),
          ),
          billingAppAccountTokenLoaderProvider.overrideWithValue(
            () => token.future,
          ),
        ],
      );
      container
          .read(billingControllerProvider.notifier)
          .purchase(pomodoistAnnualProductId);
      container.read(_identityProvider.notifier).change('account-b');
      time.flushMicrotasks();
      token.complete('old-account-token');
      time.flushMicrotasks();
      expect(store.bought, isEmpty);
      expect(
        container.read(billingControllerProvider).pendingProductId,
        isNull,
      );
    });
  });

  test(
    'late snapshot after controller disposal neither persists nor links',
    () {
      fakeAsync((time) {
        final snapshot = Completer<List<BillingTransactionProof>>();
        final linked = <String>[];
        final store = _Store()..snapshot = () => snapshot.future;
        final container = _ready(
          store,
          time,
          overrides: [
            billingSignedInProvider.overrideWithValue(true),
            billingPurchaseLinkerProvider.overrideWithValue(
              (proofs) async => linked.addAll(proofs),
            ),
          ],
        );
        container.dispose();
        snapshot.complete([
          BillingTransactionProof.fromPurchase(
            _purchase(pomodoistLifetimeProductId),
          ),
        ]);
        time.flushMicrotasks();
        expect(linked, isEmpty);
        SharedPreferences.getInstance().then(
          (prefs) => expect(
            prefs.getString(billingActiveProductIdPreferenceKey),
            isNull,
          ),
        );
        time.flushMicrotasks();
      });
    },
  );
}

ProviderContainer _ready(
  _Store store,
  FakeAsync time, {
  List<Override> overrides = const [],
}) {
  final container = ProviderContainer(
    overrides: [
      billingStoreProvider.overrideWithValue(store),
      applePurchasesSupportedProvider.overrideWithValue(true),
      ...overrides,
    ],
  );
  addTearDown(() {
    container.dispose();
    store.events.close();
  });
  container.read(billingControllerProvider);
  time.flushMicrotasks();
  return container;
}

PurchaseDetails _purchase(
  String productId, {
  DateTime? expires,
  bool revoked = false,
}) => PurchaseDetails(
  productID: productId,
  purchaseID: 'transaction-$productId',
  transactionDate: '1788912000000',
  verificationData: PurchaseVerificationData(
    localVerificationData: jsonEncode({
      'expiresDate': expires?.millisecondsSinceEpoch ?? 4102444800000,
      if (revoked) 'revocationDate': 1,
    }),
    serverVerificationData: 'proof-$productId',
    source: 'app_store',
  ),
  status: PurchaseStatus.restored,
);

class _Store extends BillingStore {
  _Store({this.emptyCatalog = false});
  bool emptyCatalog;
  Set<String>? catalogIds;
  Future<ProductDetailsResponse> Function()? catalog;
  Future<bool> Function(String)? eligibility;
  Future<void> Function(PurchaseDetails)? finish;
  BillingTransactionLoader? snapshot;
  BillingTransactionLoader? restore;
  int refreshRequests = 0;
  int restoreRequests = 0;
  final bought = <String>[];
  final finished = <String?>[];
  final inactiveVerifiedIds = <String>{};
  List<PurchaseDetails> transactions = [];
  final events = StreamController<List<PurchaseDetails>>.broadcast();
  void emit(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      transactions.removeWhere((old) => old.purchaseID == purchase.purchaseID);
      transactions.add(purchase);
    }
    events.add(purchases);
  }

  bool failRefresh = false;
  @override
  Stream<List<PurchaseDetails>> get purchaseStream => events.stream;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<bool> isIntroductoryOfferEligible(String productId) async =>
      eligibility == null ? false : eligibility!(productId);
  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> productIds,
  ) async => catalog != null
      ? catalog!()
      : _catalog(emptyCatalog ? {} : catalogIds ?? productIds);
  @override
  Future<List<BillingTransactionProof>> refreshCurrentEntitlements() async {
    refreshRequests += 1;
    if (snapshot != null) return snapshot!();
    if (failRefresh) throw StateError('StoreKit unavailable');
    return transactions.map(BillingTransactionProof.fromPurchase).toList();
  }

  @override
  Future<List<BillingTransactionProof>> restorePurchases() {
    restoreRequests += 1;
    return restore != null ? restore!() : refreshCurrentEntitlements();
  }

  @override
  Future<bool> buy(
    ProductDetails productDetails, {
    String? appAccountToken,
  }) async {
    bought.add(productDetails.id);
    return true;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    finished.add(purchase.purchaseID);
    await finish?.call(purchase);
  }

  @override
  Future<bool> isVerifiedInactivePurchase(PurchaseDetails purchase) async =>
      inactiveVerifiedIds.contains(purchase.purchaseID);
}

ProductDetailsResponse _catalog(Set<String> ids) => ProductDetailsResponse(
  productDetails: [
    for (final id in ids)
      ProductDetails(
        id: id,
        title: id,
        description: id,
        price: '1',
        rawPrice: 1,
        currencyCode: 'USD',
      ),
  ],
  notFoundIDs: billingProductIds.difference(ids).toList(),
);

final _identityProvider = NotifierProvider<_Identity, String>(_Identity.new);

class _Identity extends Notifier<String> {
  @override
  String build() => 'account-a';
  void change(String value) => state = value;
}

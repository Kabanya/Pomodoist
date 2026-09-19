import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';
import 'package:pomodoist/config/billing_dependencies.dart';
import 'package:pomodoist/ui/billing/widgets/billing_offer_copy.dart';
import 'package:pomodoist/ui/core/localization/app_localizations_en.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _promo = SK2SubscriptionOffer(
  id: billingReturnOfferIds[pomodoistMonthlyProductId],
  price: 1.99,
  type: SK2SubscriptionOfferType.promotional,
  period: const SK2SubscriptionPeriod(
    value: 1,
    unit: SK2SubscriptionPeriodUnit.month,
  ),
  periodCount: 3,
  paymentMode: SK2SubscriptionOfferPaymentMode.payAsYouGo,
);
final _trial = SK2SubscriptionOffer(
  price: 0,
  type: SK2SubscriptionOfferType.introductory,
  period: const SK2SubscriptionPeriod(
    value: 1,
    unit: SK2SubscriptionPeriodUnit.week,
  ),
  periodCount: 1,
  paymentMode: SK2SubscriptionOfferPaymentMode.freeTrial,
);
final _product = AppStoreProduct2Details.fromSK2Product(
  SK2Product(
    id: pomodoistMonthlyProductId,
    displayName: 'Pro',
    displayPrice: r'$4.99',
    description: 'Pro',
    price: 4.99,
    type: SK2ProductType.autoRenewable,
    priceLocale: SK2PriceLocale(currencyCode: 'USD', currencySymbol: r'$'),
    subscription: SK2SubscriptionInfo(
      subscriptionGroupID: '22266202',
      subscriptionPeriod: const SK2SubscriptionPeriod(
        value: 1,
        unit: SK2SubscriptionPeriodUnit.month,
      ),
      promotionalOffers: [_trial, _promo],
    ),
  ),
);
Map<String, Object?> _signature() => {
  'offerId': _promo.id,
  'compactJws': 'header.payload.signature',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('trial and return presentation uses Apple metadata and eligibility', () {
    final l10n = AppLocalizationsEn();
    final product = billingProductFromStore(_product);
    final trial = billingOfferForProduct(product, introductoryEligible: true)!;
    final promotion = billingOfferForProduct(
      product,
      returnOfferId: _promo.id,
    )!;
    expect(billingStoreKitOffer(_product), isNull);
    expect(
      billingStoreKitOffer(_product, introductoryEligible: true),
      same(_trial),
    );
    expect(billingOfferPrice(l10n, product, trial), 'Free for 7 days');
    expect(
      billingStoreKitOffer(
        _product,
        introductoryEligible: true,
        returnOfferId: _promo.id,
      ),
      same(_promo),
    );
    expect(billingOfferPrice(l10n, product, promotion), r'$1.99/month');
    expect(billingOfferDuration(l10n, promotion), '3 months');
    expect(billingStoreKitOffer(_product, returnOfferId: 'unknown'), isNull);
    expect(
      billingReturnOfferMatchesProduct(pomodoistAnnualProductId, promotion),
      isFalse,
    );
    expect(
      billingPlanForProduct(pomodoistMonthlyProductId)!.fallbackPrice,
      r'$5.99/month',
    );
    expect(
      billingPlanForProduct(pomodoistAnnualProductId)!.fallbackPrice,
      r'$39/year',
    );
  });

  test(
    'eligibility and signature reject mismatched campaigns and malformed data',
    () {
      final offers = BillingReturnOffers.fromJson({
        'eligible': true,
        'offerIds': billingReturnOfferIds,
      }, 'proof');
      expect(offers.offerIds.length, 2);
      expect(
        () => BillingReturnOffers.fromJson({
          'eligible': false,
          'offerIds': billingReturnOfferIds,
        }, 'proof'),
        throwsFormatException,
      );
      expect(
        () => BillingReturnOffers.fromJson({
          'eligible': true,
          'offerIds': {'bad': 'bad'},
        }, 'proof'),
        throwsFormatException,
      );
      expect(
        () => BillingReturnOffers.fromJson({
          'eligible': false,
          'offerIds': {},
          'code': 'offer_pending',
        }, 'proof'),
        throwsFormatException,
      );
      expect(
        billingOfferSignature(_signature(), _promo.id!),
        'header.payload.signature',
      );
      expect(
        () => billingOfferSignature(_signature(), 'wrong'),
        throwsFormatException,
      );
      expect(
        () => billingOfferSignature({
          'offerId': _promo.id,
          'signature': {},
        }, _promo.id!),
        throwsFormatException,
      );
    },
  );

  test('checking, failed and reserved offers block regular-price checkout', () {
    expect(billingReturnOfferBlocksPurchase(null), isFalse); // Stripe
    expect(billingReturnOfferBlocksPurchase(const AsyncLoading()), isTrue);
    expect(
      billingReturnOfferBlocksPurchase(
        AsyncError(StateError('offline'), StackTrace.current),
      ),
      isTrue,
    );
    expect(
      billingReturnOfferBlocksPurchase(
        AsyncData(BillingReturnOffers(retryAfter: DateTime.utc(2026, 9, 15))),
      ),
      isTrue,
    );
    expect(
      billingReturnOfferBlocksPurchase(const AsyncData(BillingReturnOffers())),
      isFalse,
    );
    expect(
      billingReturnOfferBlocksPurchase(
        const AsyncData(BillingReturnOffers(offerIds: billingReturnOfferIds)),
      ),
      isFalse,
    );
  });

  test(
    'native JWS result uses existing plugin purchase details for completion',
    () async {
      const channel = MethodChannel('pomodoist/storekit');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'purchasePromotionalOffer');
        expect(call.arguments, {
          'productId': _product.id,
          'offerId': _promo.id,
          'compactJws': 'header.payload.signature',
        });
        return {
          'status': 'purchased',
          'productId': _product.id,
          'transactionId': '18446744073709551615',
          'jws': 'verified-proof',
          'localVerificationData':
              '{"purchaseDate":1000,"offerIdentifier":"return_monthly_2026_v1"}',
        };
      });
      final store = BillingStore();
      final purchase = await store.buyPromotional(
        _product,
        _promo,
        'header.payload.signature',
      );
      expect(purchase, isA<SK2PurchaseDetails>());
      expect(purchase.pendingCompletePurchase, isTrue);
      expect(purchase.purchaseID, '18446744073709551615');
      expect(
        purchase.verificationData.serverVerificationData,
        'verified-proof',
      );
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {'status': 'pending'},
      );
      expect(
        (await store.buyPromotional(
          _product,
          _promo,
          'header.payload.signature',
        )).status,
        PurchaseStatus.pending,
      );
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {'status': 'purchased'},
      );
      await expectLater(
        store.buyPromotional(_product, _promo, 'header.payload.signature'),
        throwsFormatException,
      );
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: 'userCancelled');
      });
      await expectLater(
        store.buyPromotional(_product, _promo, 'header.payload.signature'),
        throwsA(isA<PlatformException>()),
      );
    },
  );

  for (final result in [
    'success',
    'pending',
    'cancelled',
    'verification_failed',
    'offer_pending',
    'wrong_signature',
  ]) {
    test(
      '$result never turns a discounted purchase into a regular purchase',
      () {
        fakeAsync((time) {
          final store = _OfferStore()
            ..cancel = result == 'cancelled'
            ..pending = result == 'pending';
          var signs = 0;
          final container = ProviderContainer(
            overrides: [
              billingStoreProvider.overrideWithValue(store),
              applePurchasesSupportedProvider.overrideWithValue(true),
              billingOfferRequestProvider.overrideWithValue((body) async {
                expect(body['transaction'], 'past-proof');
                expect(body.containsKey('appAccountToken'), isFalse);
                if (body['action'] == 'eligibility') {
                  return {'eligible': true, 'offerIds': billingReturnOfferIds};
                }
                signs++;
                if (['verification_failed', 'offer_pending'].contains(result)) {
                  throw BillingOfferException(result);
                }
                return {
                  ..._signature(),
                  if (result == 'wrong_signature') 'offerId': 'wrong',
                };
              }),
            ],
          );
          addTearDown(() {
            container.dispose();
            store.events.close();
          });
          container.read(billingViewModelProvider);
          time.flushMicrotasks();
          container
              .read(billingViewModelProvider.notifier)
              .purchase(pomodoistMonthlyProductId, returnOfferId: _promo.id);
          time.flushMicrotasks();
          expect(signs, 1);
          expect(store.normalBuys, 0);
          expect(
            store.promoBuys,
            ['success', 'pending', 'cancelled'].contains(result) ? 1 : 0,
          );
          final state = container.read(billingViewModelProvider);
          if (result == 'cancelled') {
            expect(state.error, isNull);
            expect(state.pendingProductId, isNull);
          } else if (result == 'success') {
            expect(state.hasLocalStoreKitEntitlement, isTrue);
            expect(store.finished, 1);
          } else if (result == 'pending') {
            expect(state.hasLocalStoreKitEntitlement, isFalse);
            expect(state.pendingProductId, pomodoistMonthlyProductId);
          } else {
            expect(state.error, startsWith('subscription_offer:'));
            expect(state.pendingProductId, isNull);
          }
        });
      },
    );
  }
}

class _OfferStore extends BillingStore {
  final events = StreamController<List<PurchaseDetails>>.broadcast();
  var normalBuys = 0;
  var promoBuys = 0;
  var cancel = false;
  var pending = false;
  var finished = 0;
  final transactions = <BillingTransactionProof>[];
  @override
  Stream<List<PurchaseDetails>> get purchaseStream => events.stream;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<bool> isIntroductoryOfferEligible(String id) async => false;
  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async =>
      ProductDetailsResponse(productDetails: [_product], notFoundIDs: []);
  @override
  Future<List<BillingTransactionProof>> refreshCurrentEntitlements() async =>
      transactions;
  @override
  Future<BillingTransactionProof?> latestSubscriptionTransaction() async =>
      const BillingTransactionProof(
        productId: pomodoistMonthlyProductId,
        jws: 'past-proof',
      );
  @override
  Future<bool> buy(ProductDetails product, {String? appAccountToken}) async {
    normalBuys++;
    return true;
  }

  @override
  Future<PurchaseDetails> buyPromotional(
    ProductDetails product,
    SK2SubscriptionOffer offer,
    String signature, {
    String? appAccountToken,
  }) async {
    promoBuys++;
    expect(offer.id, _promo.id);
    expect(signature, 'header.payload.signature');
    if (cancel) throw PlatformException(code: 'userCancelled');
    if (!pending) {
      transactions.add(
        BillingTransactionProof(
          productId: product.id,
          transactionId: '10001',
          jws: 'fresh-proof',
          localVerificationData: '{"expiresDate":4102444800000}',
        ),
      );
    }
    return SK2PurchaseDetails(
      productID: product.id,
      purchaseID: pending ? null : '10001',
      verificationData: PurchaseVerificationData(
        localVerificationData: '{}',
        serverVerificationData: '',
        source: 'app_store',
      ),
      transactionDate: null,
      status: pending ? PurchaseStatus.pending : PurchaseStatus.purchased,
    );
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    finished++;
  }
}

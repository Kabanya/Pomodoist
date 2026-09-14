import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'billing_models.dart';

class BillingStripeGateway {
  const BillingStripeGateway({
    required this.loadCatalog,
    required this.createCheckout,
    required this.openCheckout,
  });

  final Future<StripeBillingCatalog> Function() loadCatalog;
  final Future<Uri> Function(String productId, BillingCheckoutSurface surface)
  createCheckout;
  final Future<bool> Function(Uri url) openCheckout;
}

String? pomodoistEffectiveActiveProductId(String? activeProductId) {
  return activeProductId ??
      (pomodoistDevUnlock ? pomodoistLifetimeProductId : null);
}

bool pomodoistStoreKitPurchaseIsActive(PurchaseDetails purchase, DateTime now) {
  final plan = billingPlanForProduct(purchase.productID);
  if (plan == null) {
    return false;
  }
  if (pomodoistLocalStoreKit) {
    return true;
  }
  try {
    final decoded = jsonDecode(purchase.verificationData.localVerificationData);
    if (decoded is! Map) {
      return false;
    }
    final value = Map<String, dynamic>.from(decoded);
    if (value['revocationDate'] != null || value['isUpgraded'] == true) {
      return false;
    }
    if (plan.kind == BillingPlanKind.lifetime) {
      return true;
    }
    final expiry = appleBillingDate(
      value['expiresDate'] ?? value['expirationDate'],
    );
    return expiry != null && expiry.isAfter(now.toUtc());
  } on Object {
    return false;
  }
}

DateTime? appleBillingDate(Object? value) {
  if (value is num && value.isFinite) {
    return DateTime.fromMillisecondsSinceEpoch(value.round(), isUtc: true);
  }
  if (value is String && value.trim().isNotEmpty) {
    final milliseconds = num.tryParse(value);
    if (milliseconds != null && milliseconds.isFinite) {
      return DateTime.fromMillisecondsSinceEpoch(
        milliseconds.round(),
        isUtc: true,
      );
    }
    return DateTime.tryParse(value)?.toUtc();
  }
  return null;
}

class BillingStore {
  BillingStore({
    BillingTransactionLoader? transactionLoader,
    Future<void> Function()? restoreSynchronizer,
  }) : _transactionLoader = transactionLoader,
       _restoreSynchronizer = restoreSynchronizer,
       _localPurchases = pomodoistLocalStoreKit
           ? StreamController<List<PurchaseDetails>>.broadcast()
           : null;

  InAppPurchase get _purchase => InAppPurchase.instance;
  final BillingTransactionLoader? _transactionLoader;
  final Future<void> Function()? _restoreSynchronizer;
  static const _channel = MethodChannel('pomodoist/storekit');
  Future<List<BillingTransactionProof>>? _entitlementsLoad;
  Future<List<BillingTransactionProof>>? _restoreLoad;
  final StreamController<List<PurchaseDetails>>? _localPurchases;
  final _localPurchasedProductIds = <String>{};

  Stream<List<PurchaseDetails>> get purchaseStream =>
      _localPurchases?.stream ?? _purchase.purchaseStream;

  Future<bool> isAvailable() async {
    if (pomodoistLocalStoreKit) {
      return true;
    }
    return _purchase.isAvailable();
  }

  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> productIds,
  ) async {
    if (pomodoistLocalStoreKit) {
      return ProductDetailsResponse(
        productDetails: [
          for (final plan in billingPlans)
            if (productIds.contains(plan.productId))
              plan.kind == BillingPlanKind.subscription
                  ? AppStoreProduct2Details.fromSK2Product(
                      SK2Product(
                        id: plan.productId,
                        displayName: plan.productId,
                        displayPrice:
                            plan.productId == pomodoistMonthlyProductId
                            ? r'$4.99'
                            : r'$29.99',
                        description: plan.productId,
                        price: plan.productId == pomodoistMonthlyProductId
                            ? 4.99
                            : 29.99,
                        type: SK2ProductType.autoRenewable,
                        priceLocale: SK2PriceLocale(
                          currencyCode: 'USD',
                          currencySymbol: r'$',
                        ),
                        subscription: SK2SubscriptionInfo(
                          subscriptionGroupID: '30000001',
                          subscriptionPeriod: SK2SubscriptionPeriod(
                            value: 1,
                            unit: plan.productId == pomodoistMonthlyProductId
                                ? SK2SubscriptionPeriodUnit.month
                                : SK2SubscriptionPeriodUnit.year,
                          ),
                          promotionalOffers: [
                            SK2SubscriptionOffer(
                              price: 0,
                              type: SK2SubscriptionOfferType.introductory,
                              period: const SK2SubscriptionPeriod(
                                value: 1,
                                unit: SK2SubscriptionPeriodUnit.week,
                              ),
                              periodCount: 1,
                              paymentMode:
                                  SK2SubscriptionOfferPaymentMode.freeTrial,
                            ),
                          ],
                        ),
                      ),
                    )
                  : ProductDetails(
                      id: plan.productId,
                      title: plan.productId,
                      description: plan.productId,
                      price: plan.fallbackPrice,
                      rawPrice: 0,
                      currencyCode: 'USD',
                      currencySymbol: r'$',
                    ),
        ],
        notFoundIDs: [
          for (final productId in productIds)
            if (billingPlanForProduct(productId) == null) productId,
        ],
      );
    }
    return _purchase.queryProductDetails(productIds);
  }

  Future<bool> isIntroductoryOfferEligible(String productId) async {
    if (pomodoistLocalStoreKit) {
      return billingPlanForProduct(productId)?.kind ==
              BillingPlanKind.subscription &&
          !_localPurchasedProductIds.any(
            (id) =>
                billingPlanForProduct(id)?.kind == BillingPlanKind.subscription,
          );
    }
    if (!applePurchasesSupported) {
      return false;
    }
    return SK2Product.isIntroductoryOfferEligible(productId);
  }

  Future<bool> buy(ProductDetails productDetails, {String? appAccountToken}) {
    if (pomodoistLocalStoreKit) {
      _localPurchasedProductIds.add(productDetails.id);
      _localPurchases?.add([
        _localPurchase(productDetails.id, PurchaseStatus.purchased),
      ]);
      return Future.value(true);
    }
    return _purchase.buyNonConsumable(
      purchaseParam: PurchaseParam(
        productDetails: productDetails,
        applicationUserName: appAccountToken,
      ),
    );
  }

  Future<BillingTransactionProof?> latestSubscriptionTransaction() async {
    if (pomodoistLocalStoreKit || !applePurchasesSupported) return null;
    final value = await _channel
        .invokeMethod<Object?>('latestSubscriptionTransaction')
        .timeout(billingStoreTimeout);
    return value == null ? null : _decodeTransaction(value);
  }

  Future<PurchaseDetails> buyPromotional(
    ProductDetails product,
    SK2SubscriptionOffer offer,
    String compactJws, {
    String? appAccountToken,
  }) async {
    final value = await _channel
        .invokeMapMethod<String, Object?>('purchasePromotionalOffer', {
          'productId': product.id,
          'offerId': offer.id,
          'compactJws': compactJws,
          'appAccountToken': ?appAccountToken,
        });
    if (value == null || !['pending', 'purchased'].contains(value['status'])) {
      throw const FormatException('Invalid promotional purchase result.');
    }
    final proof = value['status'] == 'purchased'
        ? _decodeTransaction(value)
        : null;
    if (proof != null && proof.productId != product.id) {
      throw const FormatException('Mismatched promotional purchase.');
    }
    return SK2PurchaseDetails(
      productID: product.id,
      purchaseID: proof?.transactionId,
      verificationData: PurchaseVerificationData(
        localVerificationData: proof?.localVerificationData ?? '{}',
        serverVerificationData: proof?.jws ?? '',
        source: 'app_store',
      ),
      transactionDate: proof == null
          ? null
          : appleBillingDate(
              (jsonDecode(proof.localVerificationData) as Map)['purchaseDate'],
            )?.millisecondsSinceEpoch.toString(),
      status: proof == null ? PurchaseStatus.pending : PurchaseStatus.purchased,
      appAccountToken: appAccountToken,
    );
  }

  Future<List<BillingTransactionProof>> restorePurchases() =>
      _restoreLoad ??= _restore().whenComplete(() => _restoreLoad = null);

  Future<List<BillingTransactionProof>> _restore() async {
    if (!pomodoistLocalStoreKit) {
      await (_restoreSynchronizer ?? AppStore().sync)().timeout(
        billingStoreTimeout,
      );
    }
    // A read begun before sync cannot represent its result. Its completion
    // must not clear the new in-flight read.
    _entitlementsLoad = null;
    return refreshCurrentEntitlements();
  }

  Future<List<BillingTransactionProof>> refreshCurrentEntitlements() {
    final existing = _entitlementsLoad;
    if (existing != null) return existing;
    late final Future<List<BillingTransactionProof>> operation;
    operation = _readCurrentEntitlements()
        .timeout(billingStoreTimeout)
        .whenComplete(() {
          if (identical(_entitlementsLoad, operation)) _entitlementsLoad = null;
        });
    return _entitlementsLoad = operation;
  }

  Future<List<BillingTransactionProof>> _readCurrentEntitlements() async {
    if (pomodoistLocalStoreKit) {
      return [
        for (final productId in _localPurchasedProductIds)
          BillingTransactionProof.fromPurchase(
            _localPurchase(productId, PurchaseStatus.restored),
          ),
      ];
    }
    if (_transactionLoader != null) return _transactionLoader();
    if (!applePurchasesSupported) return const [];
    final values = await _channel.invokeListMethod<Object?>(
      'currentEntitlements',
    );
    if (values == null) {
      throw const FormatException('Missing StoreKit snapshot.');
    }
    return [for (final value in values) _decodeTransaction(value)];
  }

  BillingTransactionProof _decodeTransaction(Object? value) {
    if (value is! Map ||
        ['productId', 'transactionId', 'jws', 'localVerificationData'].any(
          (key) => value[key] is! String || (value[key] as String).isEmpty,
        )) {
      throw const FormatException('Invalid StoreKit snapshot.');
    }
    final local = value['localVerificationData'] as String;
    if (jsonDecode(local) is! Map) {
      throw const FormatException('Invalid StoreKit transaction data.');
    }
    return BillingTransactionProof(
      productId: value['productId'] as String,
      transactionId: value['transactionId'] as String,
      jws: value['jws'] as String,
      localVerificationData: local,
    );
  }

  Future<void> completePurchase(PurchaseDetails purchase) {
    if (pomodoistLocalStoreKit) {
      return Future.value();
    }
    return _purchase.completePurchase(purchase);
  }

  Future<bool> isVerifiedInactivePurchase(PurchaseDetails purchase) async {
    // The plugin's unfinished API returns only native .verified transactions.
    // Expired/refunded transactions are absent from currentEntitlements.
    for (final transaction in await SK2Transaction.unfinishedTransactions()) {
      if (transaction.id != purchase.purchaseID ||
          transaction.productId != purchase.productID) {
        continue;
      }
      final proof = BillingTransactionProof(
        productId: transaction.productId,
        transactionId: transaction.id,
        jws: transaction.receiptData ?? '',
        localVerificationData: transaction.jsonRepresentation ?? '{}',
      );
      return !pomodoistStoreKitPurchaseIsActive(
        proof.toPurchase(),
        DateTime.now(),
      );
    }
    return false;
  }

  Future<List<String>> pomodoistTransactionJws() async {
    if (pomodoistLocalStoreKit) {
      return const [];
    }
    final transactions = await refreshCurrentEntitlements();
    return {
      for (final transaction in transactions)
        if (billingProductIds.contains(transaction.productId) &&
            transaction.jws.isNotEmpty)
          transaction.jws,
    }.toList(growable: false);
  }
}

PurchaseDetails _localPurchase(String productId, PurchaseStatus status) {
  return PurchaseDetails(
    productID: productId,
    purchaseID: 'local-$productId',
    transactionDate: DateTime.now().millisecondsSinceEpoch.toString(),
    status: status,
    verificationData: PurchaseVerificationData(
      localVerificationData: productId,
      serverVerificationData: productId,
      source: 'pomodoist-local-storekit',
    ),
  );
}

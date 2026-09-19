import 'dart:developer' as developer;

import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:pomodoist/data/repositories/billing/billing_repository.dart';
import 'package:pomodoist/data/services/billing/billing_offers.dart';
import 'package:pomodoist/data/services/billing/billing_store.dart';
import 'package:pomodoist/domain/models/billing/billing_models.dart';
import 'package:pomodoist/domain/models/billing/billing_store_models.dart';

class StoreBillingRepository implements BillingRepository {
  StoreBillingRepository(this._store);

  final BillingStore _store;
  final _products = <String, ProductDetails>{};
  final _purchases = <String, PurchaseDetails>{};

  @override
  Stream<List<BillingPurchaseUpdate>> get purchaseStream =>
      _store.purchaseStream.map((items) => items.map(_mapPurchase).toList());

  @override
  Future<bool> isAvailable() => _store.isAvailable();

  @override
  Future<BillingCatalogSnapshot> queryProducts(Set<String> productIds) async {
    final response = await _store.queryProductDetails(productIds);
    final returned = <String>{};
    final products = <String, BillingProduct>{};
    for (final product in response.productDetails) {
      _products[product.id] = product;
      returned.add(product.id);
      products[product.id] = billingProductFromStore(product);
    }
    return BillingCatalogSnapshot(
      products: products,
      returnedProductIds: returned,
      error: response.error,
      errorMessage: response.error?.message,
    );
  }

  @override
  Future<bool> isIntroductoryOfferEligible(String productId) =>
      _store.isIntroductoryOfferEligible(productId);

  @override
  Future<bool> buy(String productId, {String? appAccountToken}) {
    final product = _products[productId];
    if (product == null) throw StateError('Product is not loaded: $productId');
    return _store.buy(product, appAccountToken: appAccountToken);
  }

  @override
  Future<BillingPurchaseUpdate> buyPromotional(
    String productId,
    String returnOfferId,
    String compactJws, {
    String? appAccountToken,
  }) async {
    final product = _products[productId];
    final offer = billingStoreKitOffer(product, returnOfferId: returnOfferId);
    if (product == null || offer == null) {
      throw const BillingOfferException('not_eligible');
    }
    return _mapPurchase(
      await _store.buyPromotional(
        product,
        offer,
        compactJws,
        appAccountToken: appAccountToken,
      ),
    );
  }

  @override
  Future<BillingTransactionProof?> latestSubscriptionTransaction() =>
      _store.latestSubscriptionTransaction();
  @override
  Future<List<BillingTransactionProof>> restorePurchases() =>
      _store.restorePurchases();
  @override
  Future<List<BillingTransactionProof>> refreshCurrentEntitlements() =>
      _store.refreshCurrentEntitlements();

  @override
  Future<void> completePurchase(String completionId) {
    final purchase = _purchases[completionId];
    if (purchase == null) return Future.value();
    return _store
        .completePurchase(purchase)
        .whenComplete(() => _purchases.remove(completionId));
  }

  @override
  Future<bool> isVerifiedInactivePurchase(String completionId) {
    final purchase = _purchases[completionId];
    return purchase == null
        ? Future.value(false)
        : _store.isVerifiedInactivePurchase(purchase);
  }

  @override
  bool isPurchaseActive(BillingPurchaseUpdate purchase, DateTime now) {
    final details = _purchases[purchase.completionId];
    return details != null && pomodoistStoreKitPurchaseIsActive(details, now);
  }

  @override
  bool isTransactionActive(BillingTransactionProof transaction, DateTime now) =>
      pomodoistStoreKitPurchaseIsActive(
        billingPurchaseFromTransactionProof(transaction),
        now,
      );

  BillingPurchaseUpdate _mapPurchase(PurchaseDetails purchase) {
    final completionId =
        purchase.purchaseID ??
        '${purchase.productID}:${identityHashCode(purchase)}';
    _purchases[completionId] = purchase;
    return BillingPurchaseUpdate(
      productId: purchase.productID,
      transactionId: purchase.purchaseID,
      completionId: completionId,
      state: switch (purchase.status) {
        PurchaseStatus.pending => BillingPurchaseState.pending,
        PurchaseStatus.purchased => BillingPurchaseState.purchased,
        PurchaseStatus.restored => BillingPurchaseState.restored,
        PurchaseStatus.error => BillingPurchaseState.error,
        PurchaseStatus.canceled => BillingPurchaseState.canceled,
      },
      pendingCompletion: purchase.pendingCompletePurchase,
      proof:
          purchase.status == PurchaseStatus.purchased ||
              purchase.status == PurchaseStatus.restored
          ? billingTransactionProofFromPurchase(purchase)
          : null,
      error: purchase.error,
      errorMessage: purchase.error?.message,
    );
  }

  @override
  bool isTransientError(Object error) {
    final message = '$error';
    return message.contains('NSURLErrorDomain') &&
        RegExp(r'-(?:1001|1003|1004|1005|1008|1009)\b').hasMatch(message);
  }

  @override
  bool isCancellation(Object error) =>
      error is PlatformException &&
      (error.code == 'userCancelled' ||
          RegExp(
            r'\buserCancelled\b|\bSKErrorDomain\b[^\n]*\bCode=2\b',
          ).hasMatch('${error.details}'));

  @override
  void recordError(String stage, Object error) {
    var code = switch (error) {
      PlatformException() => error.code,
      IAPError() => error.code,
      _ => error.runtimeType.toString(),
    };
    code = code.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '');
    if (code.length > 80) code = code.substring(0, 80);
    final native = RegExp(
      r'([A-Za-z][A-Za-z0-9_.]*ErrorDomain)[^\n]*?(?:Code[=:]\s*|error\s+)(-?\d+)',
    ).allMatches('$error').map((m) => '${m[1]}:${m[2]}').toSet();
    if (error case PlatformException(details: final Map details)) {
      final domain = details['domain'];
      final number = details['code'];
      if (domain is String &&
          number is num &&
          RegExp(r'^[A-Za-z0-9_.]{1,80}$').hasMatch(domain)) {
        native.add('$domain:$number');
      }
    }
    developer.log(
      '$stage code=$code native=${native.join(',')}',
      name: 'pomodoist.storekit',
    );
  }
}

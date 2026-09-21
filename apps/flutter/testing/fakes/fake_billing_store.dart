import 'dart:async';

import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';
import 'package:pomodoist/data/services/billing/billing_store.dart';
import 'package:pomodoist/domain/models/billing/billing_models.dart';

/// In-memory [BillingStore] whose StoreKit surface is scripted by fields.
///
/// Every member that would reach the native plugin is overridden, so a test can
/// script a catalog, a purchase, a restore, or a verified snapshot without a
/// platform channel. Mapping, cancellation, and verification helpers keep the
/// inherited implementation.
class FakeBillingStore extends BillingStore {
  FakeBillingStore() : super();

  final _events = StreamController<List<PurchaseDetails>>.broadcast();

  /// Whether [isAvailable] reports a usable store.
  bool storeAvailable = true;

  /// Whether [buy] emits the purchased update a native store would send.
  bool emitPurchase = true;

  /// Whether [restorePurchases] reports [restoredProductId] as verified.
  bool emitRestore = true;

  /// Product the restore path reports when [emitRestore] is true.
  String restoredProductId = pomodoistAnnualProductId;

  /// Products [isIntroductoryOfferEligible] accepts.
  Set<String> eligibleProductIds = const {
    pomodoistAnnualProductId,
    pomodoistMonthlyProductId,
  };

  /// Products [isIntroductoryOfferEligible] fails for.
  Set<String> eligibilityErrorProductIds = const {};

  /// Catalog entries [queryProductDetails] returns in place of plan defaults.
  Map<String, ProductDetails> productDetailsById = const {};

  /// Products the verified snapshot reports as owned.
  Set<String> entitlementProductIds = const {};

  /// Verified snapshot [refreshCurrentEntitlements] returns.
  ///
  /// [emit] and [restorePurchases] append to it, so a scripted purchase is
  /// verifiable the way a native snapshot would be.
  List<BillingTransactionProof> transactions = [];

  /// Replaces the snapshot read when set, as a native read would.
  BillingTransactionLoader? snapshot;

  /// Pending native work that [buy], [restorePurchases], and
  /// [completePurchase] wait for.
  ///
  /// Set it to keep those calls in flight, which is how a test observes the
  /// request timeout and the duplicate-callback paths.
  Future<void>? gate;

  /// Fails [buy] when set; a `userCancelled` [PlatformException] scripts a
  /// user cancellation.
  Object? buyError;

  /// Fails [restorePurchases] when set.
  Object? restoreError;

  /// Fails [refreshCurrentEntitlements] when set.
  Object? refreshError;

  /// Fails [completePurchase] when set.
  Object? completeError;

  /// Fails [isIntroductoryOfferEligible] when set.
  Object? eligibilityError;

  /// Catalog failure [queryProductDetails] reports when set.
  IAPError? catalogError;

  /// Product ids passed to [buy], in call order.
  final purchases = <String>[];

  /// Product ids passed to [completePurchase], in call order.
  final completions = <String>[];

  /// Product ids checked for introductory eligibility.
  final eligibilityChecks = <String>{};

  /// Token of the most recent [buy] call.
  String? lastAppAccountToken;

  /// Number of [restorePurchases] calls.
  var restoreCount = 0;

  /// Number of [refreshCurrentEntitlements] calls.
  var refreshCount = 0;

  /// Number of [queryProductDetails] calls.
  var catalogRequests = 0;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _events.stream;

  /// Pushes [updates] to [purchaseStream] as a native store update would.
  ///
  /// An active purchase or restore is also appended to [transactions], which is
  /// how the native verified snapshot would report it.
  void emit(List<PurchaseDetails> updates) {
    for (final update in updates) {
      if (update.status != PurchaseStatus.purchased &&
          update.status != PurchaseStatus.restored) {
        continue;
      }
      transactions.removeWhere((proof) => proof.productId == update.productID);
      if (pomodoistStoreKitPurchaseIsActive(update, _snapshotNow)) {
        transactions.add(billingTransactionProofFromPurchase(update));
      }
    }
    _events.add(updates);
  }

  /// Closes [purchaseStream].
  Future<void> close() => _events.close();

  @override
  Future<bool> isAvailable() async => storeAvailable;

  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> productIds,
  ) async {
    catalogRequests += 1;
    final error = catalogError;
    if (error != null) {
      return ProductDetailsResponse(
        productDetails: const [],
        notFoundIDs: productIds.toList(),
        error: error,
      );
    }
    return ProductDetailsResponse(
      productDetails: [
        for (final plan in billingPlans)
          productDetailsById[plan.productId] ?? _planDetails(plan),
      ],
      notFoundIDs: const [],
    );
  }

  @override
  Future<bool> isIntroductoryOfferEligible(String productId) async {
    eligibilityChecks.add(productId);
    final error = eligibilityError;
    if (error != null) {
      throw error;
    }
    if (eligibilityErrorProductIds.contains(productId)) {
      throw StateError('eligibility unavailable');
    }
    return eligibleProductIds.contains(productId);
  }

  @override
  Future<bool> buy(
    ProductDetails productDetails, {
    String? appAccountToken,
  }) async {
    await gate;
    purchases.add(productDetails.id);
    lastAppAccountToken = appAccountToken;
    final error = buyError;
    if (error != null) {
      throw error;
    }
    if (emitPurchase) {
      emit([
        _purchase(productDetails.id, PurchaseStatus.purchased)
          ..pendingCompletePurchase = true,
      ]);
    }
    return true;
  }

  @override
  Future<PurchaseDetails> buyPromotional(
    ProductDetails product,
    SK2SubscriptionOffer offer,
    String compactJws, {
    String? appAccountToken,
  }) async {
    await buy(product, appAccountToken: appAccountToken);
    return _purchase(product.id, PurchaseStatus.purchased);
  }

  @override
  Future<BillingTransactionProof?> latestSubscriptionTransaction() async =>
      null;

  @override
  Future<List<BillingTransactionProof>> restorePurchases() async {
    restoreCount += 1;
    await gate;
    final error = restoreError;
    if (error != null) {
      throw error;
    }
    if (emitRestore) {
      transactions.add(
        billingTransactionProofFromPurchase(
          _purchase(restoredProductId, PurchaseStatus.restored),
        ),
      );
    }
    return refreshCurrentEntitlements();
  }

  @override
  Future<List<BillingTransactionProof>> refreshCurrentEntitlements() async {
    refreshCount += 1;
    final loader = snapshot;
    if (loader != null) {
      return loader();
    }
    final error = refreshError;
    if (error != null) {
      throw error;
    }
    return [
      for (final productId in entitlementProductIds)
        billingTransactionProofFromPurchase(
          _purchase(productId, PurchaseStatus.restored),
        ),
      ...transactions,
    ];
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completions.add(purchase.productID);
    await gate;
    final error = completeError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<bool> isVerifiedInactivePurchase(PurchaseDetails purchase) async =>
      false;
}

final _snapshotNow = DateTime.utc(2026);

ProductDetails _planDetails(BillingPlan plan) => ProductDetails(
  id: plan.productId,
  title: plan.productId,
  description: plan.productId,
  price: plan.fallbackPrice,
  rawPrice: 1,
  currencyCode: 'USD',
  currencySymbol: r'$',
);

PurchaseDetails _purchase(String productId, PurchaseStatus status) =>
    PurchaseDetails(
      productID: productId,
      purchaseID: 'purchase-$productId',
      transactionDate: DateTime.utc(2026).millisecondsSinceEpoch.toString(),
      status: status,
      verificationData: PurchaseVerificationData(
        localVerificationData:
            billingPlanForProduct(productId)?.kind == BillingPlanKind.lifetime
            ? '{}'
            : '{"expiresDate":4102444800000}',
        serverVerificationData: 'server-$productId',
        source: 'test',
      ),
    );

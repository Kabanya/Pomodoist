import 'package:pomodoist/data/repositories/billing/billing_repository.dart';
import 'package:pomodoist/domain/models/billing/billing_access.dart';
import 'package:pomodoist/domain/models/billing/billing_models.dart';
import 'package:pomodoist/domain/models/billing/billing_store_models.dart';
import 'package:pomodoist/utils/result.dart';

import 'strict_fake.dart';

/// In-memory [BillingRepository] double.
///
/// Succeeding calls answer from the mutable fields below, every call is
/// recorded in its `<method>Calls` list, and a call whose `<method>Error`
/// field is non-null fails with that error instead of succeeding.
class FakeBillingRepository extends StrictFake implements BillingRepository {
  final isCancellationCalls = <Object>[];
  final watchAccessCalls = <void>[];
  final refreshCalls = <void>[];
  final restoreCalls = <void>[];
  final processPurchaseUpdateCalls = <BillingPurchaseUpdate>[];
  final beginPurchaseCalls = <String>[];
  final cancelPurchaseCalls = <void>[];
  final setStoreAvailableCalls = <bool>[];
  final clearPurchaseSuccessCalls = <void>[];
  final clearErrorCalls = <void>[];
  final loadCatalogCalls = <void>[];
  final purchaseCalls = <({String productId, String? returnOfferId})>[];
  final loadReturnOffersCalls = <void>[];

  bool isCancellationValue = false;
  BillingAccess currentAccessValue = (
    hasActiveEntitlement: false,
    hasLocalStoreKitEntitlement: false,
    loading: false,
  );
  String? activeProductIdValue;
  Set<String> activeStoreKitProductIdsValue = const {};
  Set<String> purchasedProductIdsValue = const {};
  bool accountEntitlementActiveValue = false;
  bool environmentEntitlementActiveValue = false;
  BillingEntitlement? activeAccountEntitlementValue;
  bool storeAvailableValue = false;
  String? purchaseSuccessProductIdValue;
  BillingFailure? confirmationFailureValue;
  BillingCatalog catalogValue = BillingCatalog();
  String? pendingProductIdValue;
  bool purchaseResultValue = true;
  BillingReturnOffers returnOffersValue = BillingReturnOffers();
  @override
  Stream<BillingPurchaseUpdate> purchaseUpdates = const Stream.empty();

  @override
  Stream<BillingFailure> purchaseErrors = const Stream.empty();

  Object? refreshError;
  Object? restoreError;
  Object? purchaseError;

  @override
  bool isCancellation(Object error) {
    isCancellationCalls.add(error);
    return isCancellationValue;
  }

  @override
  BillingAccess get currentAccess => currentAccessValue;

  /// Replays [currentAccessValue] once.
  @override
  Stream<BillingAccess> watchAccess() {
    watchAccessCalls.add(null);
    return Stream.value(currentAccessValue);
  }

  @override
  Future<Result<void>> refresh() async {
    refreshCalls.add(null);
    final error = refreshError;
    if (error != null) return Result.error(error, StackTrace.current);
    return const Result.ok(null);
  }

  @override
  String? get activeProductId => activeProductIdValue;

  @override
  Set<String> get activeStoreKitProductIds => activeStoreKitProductIdsValue;

  @override
  Set<String> get purchasedProductIds => purchasedProductIdsValue;

  @override
  bool get accountEntitlementActive => accountEntitlementActiveValue;

  @override
  bool get environmentEntitlementActive => environmentEntitlementActiveValue;

  @override
  BillingEntitlement? get activeAccountEntitlement =>
      activeAccountEntitlementValue;

  @override
  bool get storeAvailable => storeAvailableValue;

  @override
  String? get purchaseSuccessProductId => purchaseSuccessProductIdValue;

  @override
  BillingFailure? get confirmationFailure => confirmationFailureValue;

  @override
  Future<Result<void>> restore() async {
    restoreCalls.add(null);
    final error = restoreError;
    if (error != null) return Result.error(error, StackTrace.current);
    return const Result.ok(null);
  }

  @override
  Future<void> processPurchaseUpdate(BillingPurchaseUpdate purchase) async {
    processPurchaseUpdateCalls.add(purchase);
  }

  /// Records the call and mirrors [productId] into [pendingProductIdValue].
  @override
  void beginPurchase(String productId) {
    beginPurchaseCalls.add(productId);
    pendingProductIdValue = productId;
  }

  /// Records the call and clears [pendingProductIdValue].
  @override
  void cancelPurchase() {
    cancelPurchaseCalls.add(null);
    pendingProductIdValue = null;
  }

  /// Records the call and mirrors [available] into [storeAvailableValue].
  @override
  void setStoreAvailable(bool available) {
    setStoreAvailableCalls.add(available);
    storeAvailableValue = available;
  }

  /// Records the call and clears [purchaseSuccessProductIdValue].
  @override
  void clearPurchaseSuccess() {
    clearPurchaseSuccessCalls.add(null);
    purchaseSuccessProductIdValue = null;
  }

  /// Records the call and clears [confirmationFailureValue].
  @override
  void clearError() {
    clearErrorCalls.add(null);
    confirmationFailureValue = null;
  }

  @override
  BillingCatalog get catalog => catalogValue;

  @override
  Future<void> loadCatalog() async {
    loadCatalogCalls.add(null);
  }

  @override
  Future<Result<bool>> purchase(
    String productId, {
    String? returnOfferId,
  }) async {
    purchaseCalls.add((productId: productId, returnOfferId: returnOfferId));
    final error = purchaseError;
    if (error != null) return Result.error(error, StackTrace.current);
    return Result.ok(purchaseResultValue);
  }

  @override
  String? get pendingProductId => pendingProductIdValue;

  @override
  Future<BillingReturnOffers> loadReturnOffers() async {
    loadReturnOffersCalls.add(null);
    return returnOffersValue;
  }
}

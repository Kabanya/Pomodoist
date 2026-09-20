import 'package:pomodoist/domain/models/billing/billing_models.dart';
import 'package:pomodoist/domain/models/billing/billing_store_models.dart';
import 'package:pomodoist/domain/models/billing/billing_access.dart';
import 'package:pomodoist/utils/result.dart';

typedef BillingPurchaseLinker =
    Future<void> Function(List<String> transactions);

abstract interface class BillingRepository {
  bool isCancellation(Object error);
  BillingAccess get currentAccess;
  Stream<BillingAccess> watchAccess();
  Future<Result<void>> refresh();

  String? get activeProductId;
  Set<String> get activeStoreKitProductIds;
  Set<String> get purchasedProductIds;
  bool get accountEntitlementActive;
  bool get environmentEntitlementActive;
  BillingEntitlement? get activeAccountEntitlement;
  bool get storeAvailable;
  String? get purchaseSuccessProductId;
  BillingFailure? get confirmationFailure;
  Stream<BillingPurchaseUpdate> get purchaseUpdates;
  Stream<BillingFailure> get purchaseErrors;

  Future<Result<void>> restore();
  Future<void> processPurchaseUpdate(BillingPurchaseUpdate purchase);
  void beginPurchase(String productId);
  void cancelPurchase();
  void setStoreAvailable(bool available);
  void clearPurchaseSuccess();
  void clearError();

  BillingCatalog get catalog;
  Future<void> loadCatalog();
  Future<Result<bool>> purchase(String productId, {String? returnOfferId});
  String? get pendingProductId;
  Future<BillingReturnOffers> loadReturnOffers();
}

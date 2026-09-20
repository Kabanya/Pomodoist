import 'dart:async';
import 'dart:convert';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:pomodoist/data/services/billing/billing_offers.dart';

import 'package:pomodoist/data/repositories/billing/billing_repository.dart';
import 'package:pomodoist/data/services/billing/billing_store.dart';
import 'package:pomodoist/data/services/local/preferences_service.dart';
import 'package:pomodoist/domain/models/billing/billing_access.dart';
import 'package:pomodoist/domain/models/billing/billing_models.dart';
import 'package:pomodoist/domain/models/billing/billing_store_models.dart';
import 'package:pomodoist/utils/result.dart';

/// Owns the shared, account-scoped entitlement state for the application.
///
/// It is the single subscriber of [BillingStore.purchaseStream] and the only
/// place that accepts verified StoreKit snapshots, links transactions, finishes
/// purchases and persists purchase history.
final class AppBillingRepository implements BillingRepository {
  AppBillingRepository({
    required BillingStore store,
    required PreferencesService preferences,
    required DateTime Function() now,
    required BillingChannel channel,
    required bool storeSupported,
    required bool signedIn,
    required BillingPurchaseLinker? Function() purchaseLinker,
    Duration storeTimeout = billingStoreTimeout,
    Duration purchaseTimeout = billingPurchaseTimeout,
    BillingStripeGateway? Function()? stripeGateway,
    BillingOfferRequest? Function()? offerRequest,
    Future<String?> Function()? accountToken,
    BillingCheckoutSurface surface = BillingCheckoutSurface.native,
  }) : _store = store,
       _preferences = preferences,
       _now = now,
       _channel = channel,
       _storeSupported = storeSupported,
       _signedIn = signedIn,
       _purchaseLinker = purchaseLinker,
       _storeTimeout = storeTimeout,
       _purchaseTimeout = purchaseTimeout,
       _stripeGateway = stripeGateway,
       _offerRequest = offerRequest,
       _accountToken = accountToken,
       _surface = surface {
    if (_channel == BillingChannel.storeKit && _storeSupported) {
      _subscription = _store.purchaseStream
          .map((items) => items.map(_store.mapPurchase).toList(growable: false))
          .listen(
            (purchases) => unawaited(_processPurchases(purchases)),
            onError: (Object error) {
              _store.recordError('updates', error);
              if (!_disposed) {
                _purchaseErrors.add(_billingFailure(error));
              }
            },
          );
    }
    _initialized = _initialize();
  }

  final BillingStore _store;
  final PreferencesService _preferences;
  final DateTime Function() _now;
  final BillingChannel _channel;
  final bool _storeSupported;
  final BillingPurchaseLinker? Function() _purchaseLinker;
  final Duration _storeTimeout;
  final Duration _purchaseTimeout;
  final BillingStripeGateway? Function()? _stripeGateway;
  final BillingOfferRequest? Function()? _offerRequest;
  final Future<String?> Function()? _accountToken;
  final BillingCheckoutSurface _surface;
  final _products = <String, ProductDetails>{};
  BillingCatalog _catalog = BillingCatalog();
  Future<void>? _catalogLoad;
  Future<Result<bool>>? _purchaseRequest;
  Timer? _purchaseWatchdog;
  int _catalogRevision = 0;
  @override
  BillingCatalog get catalog => _catalog;
  @override
  String? get pendingProductId => _pendingProductId;

  bool _signedIn;
  StreamSubscription<List<BillingPurchaseUpdate>>? _subscription;
  late final Future<void> _initialized;

  final _access = StreamController<BillingAccess>.broadcast();
  final _purchaseUpdates = StreamController<BillingPurchaseUpdate>.broadcast();
  final _purchaseErrors = StreamController<BillingFailure>.broadcast();
  final _verifiedTransactions = <String, BillingTransactionProof>{};
  final _purchasesToFinish = <String, BillingPurchaseUpdate>{};
  final _finishingPurchases = <String>{};
  final _operationTimers = <Timer>{};
  final _attemptedTransactionJws = <String>{};

  Future<void> _stateChanges = Future<void>.value();
  Future<Result<void>>? _silentRefresh;
  Future<Result<void>>? _restoreFuture;
  Timer? _expiryTimer;
  var _silentRefreshQueued = false;
  var _explicitRestoreInProgress = false;
  var _restoreSuccessPending = false;
  var _skipNextAccountRefresh = false;
  var _accountGeneration = 0;
  var _entitlementRevision = 0;
  var _disposed = false;
  var _loading = true;
  bool _accountEntitlementActive = false;
  bool _environmentEntitlementActive = false;
  BillingEntitlement? _activeAccountEntitlement;
  String? _activeProductId;
  Set<String> _activeStoreKitProductIds = const {};
  Set<String> _purchasedProductIds = const {};
  bool _storeAvailable = false;
  String? _purchaseSuccessProductId;
  BillingFailure? _confirmationFailure;
  String? _pendingProductId;

  @override
  BillingAccess get currentAccess => (
    hasActiveEntitlement: _hasActiveEntitlement,
    hasLocalStoreKitEntitlement: _hasLocalStoreKitEntitlement,
    loading: _loading,
  );

  bool get _hasLocalStoreKitEntitlement =>
      pomodoistDevUnlock || _activeStoreKitProductIds.isNotEmpty;
  bool get _hasActiveEntitlement =>
      _hasLocalStoreKitEntitlement ||
      _accountEntitlementActive ||
      _environmentEntitlementActive;

  @override
  String? get activeProductId => _activeProductId;
  @override
  Set<String> get activeStoreKitProductIds =>
      Set.unmodifiable(_activeStoreKitProductIds);
  @override
  Set<String> get purchasedProductIds => Set.unmodifiable(_purchasedProductIds);
  @override
  bool get accountEntitlementActive => _accountEntitlementActive;
  @override
  bool get environmentEntitlementActive => _environmentEntitlementActive;
  @override
  BillingEntitlement? get activeAccountEntitlement => _activeAccountEntitlement;
  @override
  bool get storeAvailable => _storeAvailable;
  @override
  String? get purchaseSuccessProductId => _purchaseSuccessProductId;
  @override
  BillingFailure? get confirmationFailure => _confirmationFailure;
  @override
  Stream<BillingPurchaseUpdate> get purchaseUpdates => _purchaseUpdates.stream;
  @override
  Stream<BillingFailure> get purchaseErrors => _purchaseErrors.stream;

  @override
  Stream<BillingAccess> watchAccess() {
    final controller = StreamController<BillingAccess>();
    controller.add(currentAccess);
    final subscription = _access.stream.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    controller.onCancel = subscription.cancel;
    return controller.stream;
  }

  Future<void> _initialize() async {
    try {
      final preferences = (await _preferences.read(const [
        billingActiveProductIdPreferenceKey,
        billingPurchasedProductIdsPreferenceKey,
      ])).getOrThrow();
      if (_disposed) return;
      final activeProductId =
          preferences[billingActiveProductIdPreferenceKey] as String?;
      _activeProductId = pomodoistEffectiveActiveProductId(activeProductId);
      _purchasedProductIds =
          (preferences[billingPurchasedProductIdsPreferenceKey]
                  as List<String>?)
              ?.toSet() ??
          const <String>{};
      if (_channel != BillingChannel.storeKit || !_storeSupported) {
        _loading = false;
      }
      _emit();
    } on Object catch (error) {
      _store.recordError('purchase_history', error);
      _loading = false;
      _emit();
    }
    if (_channel == BillingChannel.storeKit && _storeSupported) {
      unawaited(_refreshInternal(queueIfRunning: false));
    }
  }

  @override
  Future<Result<void>> refresh() async {
    await _initialized;
    return _refreshInternal(queueIfRunning: false);
  }

  Future<Result<void>> _refreshInternal({required bool queueIfRunning}) {
    if (_disposed || _channel != BillingChannel.storeKit || !_storeSupported) {
      return Future.value(const Success(null));
    }
    if (_explicitRestoreInProgress) {
      _silentRefreshQueued |= queueIfRunning;
      return Future.value(const Success(null));
    }
    final existing = _silentRefresh;
    if (existing != null) {
      _silentRefreshQueued |= queueIfRunning;
      return existing;
    }
    final operation = _runSilentRefresh();
    _silentRefresh = operation;
    operation.then<void>((_) {
      if (identical(_silentRefresh, operation)) {
        _silentRefresh = null;
        if (_silentRefreshQueued && !_explicitRestoreInProgress) {
          _silentRefreshQueued = false;
          unawaited(_refreshInternal(queueIfRunning: false));
        }
      }
    });
    return operation;
  }

  Future<Result<void>> _runSilentRefresh() async {
    final revision = _entitlementRevision;
    final accountGeneration = _accountGeneration;
    try {
      final transactions = await _withTimeout(
        _store.refreshCurrentEntitlements(),
      );
      _loading = false;
      await _acceptSnapshot(transactions, revision, accountGeneration);
      return const Success(null);
    } on Object catch (error, stackTrace) {
      _loading = false;
      _emit();
      _store.recordError('entitlements', error);
      if (!_disposed && _pendingConfirmation) {
        _confirmationFailure = _billingFailure(error);
        _emit();
      }
      // Transport failure cannot invalidate a previously verified purchase.
      return Failure(error, stackTrace);
    }
  }

  bool get _pendingConfirmation => _purchaseToConfirm != null;
  String? _purchaseToConfirm;

  Future<void> _acceptSnapshot(
    List<BillingTransactionProof> transactions,
    int revision,
    int accountGeneration, {
    bool explicitRestore = false,
  }) async {
    if (_disposed) return;
    var accepted = false;
    await _changeEntitlements(() async {
      if (revision != _entitlementRevision) {
        _silentRefreshQueued = true;
        return;
      }
      _verifiedTransactions
        ..clear()
        ..addEntries(
          transactions
              .where((p) => billingProductIds.contains(p.productId))
              .map(
                (p) => MapEntry(
                  p.transactionId.isEmpty ? p.productId : p.transactionId,
                  p,
                ),
              ),
        );
      await _commitEntitlements();
      if (_disposed) return;
      accepted = true;
      final purchased = _purchaseToConfirm;
      if (purchased != null && _activeStoreKitProductIds.contains(purchased)) {
        _purchaseToConfirm = null;
        _confirmationFailure = null;
        _purchaseSuccessProductId = purchased;
        _emit();
      } else if (explicitRestore || _restoreSuccessPending) {
        _purchaseSuccessProductId = _hasLocalStoreKitEntitlement
            ? _activeProductId
            : null;
        _emit();
      }
      _restoreSuccessPending = false;
    });
    if (accepted && !_disposed) {
      unawaited(_finishVerifiedPurchases());
      unawaited(
        _linkTransactions([
          for (final p in transactions)
            if (billingProductIds.contains(p.productId) && p.jws.isNotEmpty)
              p.jws,
        ], accountGeneration),
      );
    }
  }

  @override
  Future<Result<void>> restore() {
    if (_pendingProductId != null) return Future.value(const Success(null));
    if (_disposed || _channel != BillingChannel.storeKit || !_storeSupported) {
      return Future.value(const Success(null));
    }
    final existing = _restoreFuture;
    if (existing != null) return existing;
    _attemptedTransactionJws.clear();
    _explicitRestoreInProgress = true;
    _restoreSuccessPending = true;
    final revision = ++_entitlementRevision;
    final accountGeneration = _accountGeneration;
    late final Future<Result<void>> operation;
    operation = _runRestore(revision, accountGeneration).whenComplete(() {
      _explicitRestoreInProgress = false;
      if (!_disposed && _silentRefreshQueued) {
        _silentRefreshQueued = false;
        unawaited(_refreshInternal(queueIfRunning: false));
      }
      if (identical(_restoreFuture, operation)) {
        _restoreFuture = null;
      }
    });
    _restoreFuture = operation;
    return operation;
  }

  Future<Result<void>> _runRestore(int revision, int accountGeneration) async {
    final pending = _withTimeout(
      _store.restorePurchases(),
      // Restore performs two bounded operations: sync, then a fresh snapshot.
      _storeTimeout * 2,
    );
    await _initialized;
    if (_disposed) return const Success(null);
    try {
      final transactions = await pending;
      await _acceptSnapshot(
        transactions,
        revision,
        accountGeneration,
        explicitRestore: true,
      );
      return const Success(null);
    } on Object catch (error, stackTrace) {
      _restoreSuccessPending = false;
      if (!_store.isCancellation(error)) {
        _store.recordError('restore', error);
      }
      return Failure(error, stackTrace);
    }
  }

  @override
  Future<void> processPurchaseUpdate(BillingPurchaseUpdate purchase) async {
    await _initialized;
    if (_disposed) return;
    await _processPurchases([purchase]);
  }

  @override
  void beginPurchase(String productId) {
    _pendingProductId = productId;
    _startPurchaseWatchdog(productId);
    _emit();
  }

  @override
  void cancelPurchase() {
    _pendingProductId = null;
    _purchaseWatchdog?.cancel();
    _emit();
  }

  @override
  void clearPurchaseSuccess() {
    if (_purchaseSuccessProductId == null) return;
    _purchaseSuccessProductId = null;
    _emit();
  }

  @override
  void clearError() {
    if (_confirmationFailure == null) return;
    _confirmationFailure = null;
    _emit();
  }

  @override
  void setStoreAvailable(bool available) {
    if (_storeAvailable == available) return;
    _storeAvailable = available;
    _emit();
  }

  void setAccountEntitlement(BillingEntitlement? entitlement) {
    if (_sameEntitlement(_activeAccountEntitlement, entitlement)) return;
    _activeAccountEntitlement = entitlement;
    _emit();
  }

  void setAccountEntitlementActive(bool active) {
    if (_accountEntitlementActive == active) return;
    _accountEntitlementActive = active;
    _emit();
  }

  void setEnvironmentEntitlement(bool active) {
    if (_environmentEntitlementActive == active) return;
    _environmentEntitlementActive = active;
    _emit();
  }

  void handleAccountIdentityChanged() {
    _accountGeneration += 1;
    _resetAccountCatalog();
    _attemptedTransactionJws.clear();
    _skipNextAccountRefresh = false;
    if (_signedIn) {
      unawaited(_refreshInternal(queueIfRunning: true));
    }
  }

  void handleSignedInChanged(bool signedIn) {
    final wasSignedIn = _signedIn;
    _signedIn = signedIn;
    _accountGeneration += 1;
    _resetAccountCatalog();
    _attemptedTransactionJws.clear();
    _skipNextAccountRefresh = false;
    if (!wasSignedIn && signedIn && _channel != BillingChannel.stripe) {
      _attemptedTransactionJws.clear();
      unawaited(_refreshInternal(queueIfRunning: true));
    }
  }

  void handleAccountRefreshTokenChanged() {
    if (!_signedIn) return;
    if (_skipNextAccountRefresh) {
      _skipNextAccountRefresh = false;
      return;
    }
    _attemptedTransactionJws.clear();
    unawaited(_refreshInternal(queueIfRunning: true));
  }

  void handleAppResume() {
    if (_disposed || _channel != BillingChannel.storeKit || !_storeSupported) {
      return;
    }
    unawaited(_changeEntitlements(_commitEntitlements));
    if (!_explicitRestoreInProgress) {
      unawaited(_refreshInternal(queueIfRunning: false));
    }
  }

  Future<void> _processPurchases(List<BillingPurchaseUpdate> purchases) async {
    if (_disposed) return;
    if (purchases.any(
      (p) =>
          billingProductIds.contains(p.productId) &&
          (p.state == BillingPurchaseState.purchased ||
              p.state == BillingPurchaseState.restored),
    )) {
      _entitlementRevision += 1;
    }
    if (purchases.isEmpty) return;
    var refreshEntitlements = false;
    final toFinish = <BillingPurchaseUpdate>[];
    await _changeEntitlements(() async {
      for (final purchase in purchases) {
        if (_disposed) return;
        if (!billingProductIds.contains(purchase.productId)) {
          continue;
        }
        switch (purchase.state) {
          case BillingPurchaseState.pending:
            if (_pendingProductId == null ||
                _pendingProductId == purchase.productId) {
              _pendingProductId = purchase.productId;
              _startPurchaseWatchdog(purchase.productId);
            }
          case BillingPurchaseState.purchased:
          case BillingPurchaseState.restored:
            final matchesPending = _pendingProductId == purchase.productId;
            // The plugin also emits purchased for StoreKit .unverified results.
            // Only the native verified snapshot can add or extend access.
            refreshEntitlements = true;
            final transaction = purchase.proof!;
            if (!_store.isMappedPurchaseActive(purchase.completionId, _now())) {
              _verifiedTransactions.remove(transaction.transactionId);
              await _commitEntitlements();
              if (_disposed) return;
            }
            if (matchesPending) _purchaseToConfirm = purchase.productId;
            if (matchesPending) _pendingProductId = null;
          case BillingPurchaseState.error:
            if (purchase.error != null) {
              _store.recordError('purchase_event', purchase.error!);
            }
            if (_pendingProductId != null &&
                _pendingProductId != purchase.productId) {
              break;
            }
            _pendingProductId = null;
          case BillingPurchaseState.canceled:
            if (_pendingProductId != null &&
                _pendingProductId != purchase.productId) {
              break;
            }
            _pendingProductId = null;
        }
        if (purchase.pendingCompletion &&
            purchase.state != BillingPurchaseState.pending) {
          if (purchase.state == BillingPurchaseState.purchased ||
              purchase.state == BillingPurchaseState.restored) {
            final id = purchase.transactionId;
            if (id != null) _purchasesToFinish[id] = purchase;
          } else {
            toFinish.add(purchase);
          }
        }
      }
    });
    if (refreshEntitlements && !_disposed) {
      unawaited(_refreshInternal(queueIfRunning: true));
    }
    if (_pendingProductId == null) _purchaseWatchdog?.cancel();
    _emit();
    if (!_disposed) {
      for (final purchase in purchases) {
        _purchaseUpdates.add(purchase);
      }
    }
    for (final purchase in toFinish) {
      if (_disposed) return;
      try {
        await _withTimeout(
          _store.completeMappedPurchase(purchase.completionId),
        );
      } on Object catch (error) {
        _store.recordError('finish', error);
      }
    }
  }

  Future<void> _linkTransactions(
    List<String> transactionJws,
    int accountGeneration,
  ) async {
    if (_disposed) return;
    if (accountGeneration != _accountGeneration) return;
    final linker = _signedIn ? _purchaseLinker() : null;
    final unattemptedJws = transactionJws
        .toSet()
        .difference(_attemptedTransactionJws)
        .toList(growable: false);
    if (linker != null && unattemptedJws.isNotEmpty) {
      _attemptedTransactionJws.addAll(unattemptedJws);
      try {
        await _withTimeout(linker(unattemptedJws));
        if (!_disposed && accountGeneration == _accountGeneration) {
          _skipNextAccountRefresh = true;
        }
      } on Object catch (error) {
        if (!_disposed && accountGeneration == _accountGeneration) {
          _attemptedTransactionJws.removeAll(unattemptedJws);
        }
        _store.recordError('account_link', error);
      }
    }
  }

  Future<void> _finishVerifiedPurchases() async {
    for (final entry in _purchasesToFinish.entries.toList()) {
      if (_disposed) return;
      if (!_finishingPurchases.add(entry.key)) continue;
      try {
        final proof = _verifiedTransactions[entry.key];
        if (proof?.productId != entry.value.productId &&
            !await _withTimeout(
              _store.isMappedPurchaseVerifiedInactive(entry.value.completionId),
            )) {
          continue;
        }
        if (_disposed) return;
        await _withTimeout(
          _store.completeMappedPurchase(entry.value.completionId),
        );
        _purchasesToFinish.remove(entry.key);
      } on Object catch (error) {
        // Keep the verified transaction pending for the next refresh/Restore.
        _store.recordError('finish', error);
      } finally {
        _finishingPurchases.remove(entry.key);
      }
    }
  }

  Future<void> _changeEntitlements(Future<void> Function() change) {
    final operation = _stateChanges.then((_) async {
      if (!_disposed) await change();
    });
    return _stateChanges = operation.catchError((
      Object error,
      StackTrace stack,
    ) {
      _store.recordError('entitlement_state', error);
    });
  }

  Future<void> _commitEntitlements() async {
    if (_disposed) return;
    final now = _now();
    final active = {
      for (final transaction in _verifiedTransactions.values)
        if (_isTransactionActive(transaction, now)) transaction.productId,
    };
    final preferred = [
      pomodoistLifetimeProductId,
      pomodoistLifetimeLaunchProductId,
      pomodoistAnnualProductId,
      pomodoistMonthlyProductId,
    ].where(active.contains).firstOrNull;
    final purchased = {
      ..._purchasedProductIds,
      ..._verifiedTransactions.values.map((p) => p.productId),
    };
    _activeProductId = preferred;
    _activeStoreKitProductIds = active;
    _purchasedProductIds = purchased;
    _emit();
    _expiryTimer?.cancel();
    DateTime? nextExpiry;
    for (final transaction in _verifiedTransactions.values) {
      if (billingPlanForProduct(transaction.productId)?.kind !=
          BillingPlanKind.subscription) {
        continue;
      }
      try {
        final data = jsonDecode(transaction.localVerificationData) as Map;
        final expiry = appleBillingDate(
          data['expiresDate'] ?? data['expirationDate'],
        );
        if (expiry != null &&
            expiry.isAfter(now) &&
            (nextExpiry == null || expiry.isBefore(nextExpiry))) {
          nextExpiry = expiry;
        }
      } on Object {
        /* Malformed proof cannot grant access. */
      }
    }
    if (nextExpiry != null) {
      _expiryTimer = Timer(nextExpiry.difference(now), () {
        unawaited(_changeEntitlements(_commitEntitlements));
      });
    }
    // Preferences record purchase history, never authority to grant Pro.
    try {
      if (_disposed) return;
      (await _preferences.write({
        billingActiveProductIdPreferenceKey: preferred,
      })).getOrThrow();
      if (_disposed) return;
      (await _preferences.write({
        billingPurchasedProductIdsPreferenceKey: purchased.toList()..sort(),
      })).getOrThrow();
    } on Object catch (error) {
      _store.recordError('purchase_history', error);
    }
  }

  bool _isTransactionActive(
    BillingTransactionProof transaction,
    DateTime now,
  ) => pomodoistStoreKitPurchaseIsActive(
    billingPurchaseFromTransactionProof(transaction),
    now,
  );

  Future<T> _withTimeout<T>(Future<T> operation, [Duration? timeout]) {
    final completer = Completer<T>();
    late final Timer timer;
    timer = Timer(timeout ?? _storeTimeout, () {
      _operationTimers.remove(timer);
      if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException('Billing operation timed out.', timeout),
        );
      }
    });
    _operationTimers.add(timer);
    operation.then(
      (value) {
        timer.cancel();
        _operationTimers.remove(timer);
        if (!completer.isCompleted) {
          completer.complete(value);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        timer.cancel();
        _operationTimers.remove(timer);
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
    );
    return completer.future;
  }

  void _emit() {
    if (_disposed) return;
    _access.add(currentAccess);
  }

  bool _sameEntitlement(BillingEntitlement? a, BillingEntitlement? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    return a.entitlementId == b.entitlementId &&
        a.status == b.status &&
        a.productId == b.productId &&
        a.purchaseType == b.purchaseType &&
        a.validUntil == b.validUntil &&
        a.renewsAt == b.renewsAt;
  }

  void dispose() {
    _purchaseWatchdog?.cancel();
    if (_disposed) return;
    _disposed = true;
    _subscription?.cancel();
    _expiryTimer?.cancel();
    for (final timer in _operationTimers.toList()) {
      timer.cancel();
    }
    _operationTimers.clear();
    unawaited(_access.close());
    unawaited(_purchaseUpdates.close());
    unawaited(_purchaseErrors.close());
  }

  Future<bool> _isAvailable() => _store.isAvailable();

  Future<BillingCatalogSnapshot> _queryProducts(Set<String> productIds) async {
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

  Future<bool> _isIntroductoryOfferEligible(String productId) =>
      _store.isIntroductoryOfferEligible(productId);

  Future<bool> _buy(String productId, {String? appAccountToken}) {
    final product = _products[productId];
    if (product == null) throw StateError('Product is not loaded: $productId');
    return _store.buy(product, appAccountToken: appAccountToken);
  }

  Future<BillingPurchaseUpdate> _buyPromotional(
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
    return _store.mapPurchase(
      await _store.buyPromotional(
        product,
        offer,
        compactJws,
        appAccountToken: appAccountToken,
      ),
    );
  }

  Future<BillingTransactionProof?> _latestSubscriptionTransaction() =>
      _store.latestSubscriptionTransaction();
  bool _isTransientError(Object error) {
    final message = '$error';
    return message.contains('NSURLErrorDomain') &&
        RegExp(r'-(?:1001|1003|1004|1005|1008|1009)\b').hasMatch(message);
  }

  @override
  bool isCancellation(Object error) => _store.isCancellation(error);

  void _recordError(String stage, Object error) =>
      _store.recordError(stage, error);

  @override
  Future<void> loadCatalog() {
    final generation = _accountGeneration;
    return _catalogLoad ??= _loadCatalog().whenComplete(() {
      _catalogLoad = null;
      if (!_disposed &&
          _channel == BillingChannel.stripe &&
          generation != _accountGeneration) {
        unawaited(loadCatalog());
      }
    });
  }

  void _resetAccountCatalog() {
    if (_disposed || _channel != BillingChannel.stripe) return;
    _publishCatalog(BillingCatalog(available: true));
    unawaited(loadCatalog());
  }

  void _publishCatalog(BillingCatalog value) {
    if (_disposed) return;
    _catalog = value;
    _storeAvailable = value.available;
    _emit();
  }

  Future<void> _loadCatalog() async {
    final revision = ++_catalogRevision;
    final generation = _accountGeneration;
    await _initialized;
    if (_disposed) return;
    if (_channel == BillingChannel.stripe) {
      if (!_signedIn) {
        _publishCatalog(BillingCatalog(available: true));
        return;
      }
      final gateway = _stripeGateway?.call();
      try {
        if (gateway == null) {
          throw StateError('Stripe billing is not configured.');
        }
        final value = await _withTimeout(gateway.loadCatalog());
        if (_disposed || generation != _accountGeneration) return;
        _publishCatalog(
          BillingCatalog(
            available: value.enabled,
            products: {
              for (final entry in value.prices.entries)
                if (billingProductIds.contains(entry.key))
                  entry.key: BillingProduct(
                    id: entry.key,
                    title: entry.key,
                    description: entry.key,
                    price: entry.value,
                    rawPrice: 0,
                    currencyCode: 'USD',
                    currencySymbol: r'$',
                  ),
            },
            eligibleIntroductoryProductIds: value.introEligible
                ? {pomodoistMonthlyProductId, pomodoistAnnualProductId}
                : {},
            stripeLaunchOfferEligible: value.launchOfferEligible,
            stripeLaunchOfferEndsAt: value.launchOfferEndsAt,
          ),
        );
      } catch (error) {
        if (_disposed || generation != _accountGeneration) return;
        _publishCatalog(BillingCatalog(error: '$error'));
      }
      return;
    }
    if (!_storeSupported) {
      _publishCatalog(BillingCatalog(platformSupported: false));
      return;
    }
    unawaited(refresh());
    try {
      if (!await _withTimeout(_isAvailable())) {
        _publishCatalog(BillingCatalog());
        return;
      }
      late BillingCatalogSnapshot response;
      for (var attempt = 0; ; attempt++) {
        try {
          response = await _withTimeout(_queryProducts(billingProductIds));
          if (response.error == null ||
              attempt == 2 ||
              !_isTransientError(response.error!)) {
            break;
          }
        } catch (error) {
          if (attempt == 2 || !_isTransientError(error)) rethrow;
        }
        await Future<void>.delayed(Duration(seconds: attempt + 1));
        if (_disposed) return;
      }
      if (_disposed || revision != _catalogRevision) return;
      if (response.error != null) _recordError('catalog', response.error!);
      final products = {..._catalog.products, ...response.products};
      _publishCatalog(
        BillingCatalog(
          available: products.isNotEmpty,
          products: products,
          eligibleIntroductoryProductIds: _catalog
              .eligibleIntroductoryProductIds
              .where(products.containsKey)
              .toSet(),
          missingProductIds: billingProductIds.difference(
            response.products.keys.toSet(),
          ),
          error: response.errorMessage,
        ),
      );
      unawaited(
        _refreshEligibility(response.products.values.toList(), revision),
      );
    } catch (error) {
      _recordError('catalog', error);
      _publishCatalog(
        BillingCatalog(
          available: _catalog.products.isNotEmpty,
          products: _catalog.products,
          eligibleIntroductoryProductIds:
              _catalog.eligibleIntroductoryProductIds,
          error: '$error',
        ),
      );
    }
  }

  Future<void> _refreshEligibility(
    List<BillingProduct> products,
    int revision,
  ) async {
    for (final product in products) {
      if (_disposed || revision != _catalogRevision) return;
      if (billingPlanForProduct(product.id)?.kind !=
          BillingPlanKind.subscription) {
        continue;
      }
      var eligible = false;
      try {
        eligible = await _withTimeout(_isIntroductoryOfferEligible(product.id));
      } on Object {
        /* Store eligibility must not block the catalog. */
      }
      if (_disposed || revision != _catalogRevision) return;
      _publishCatalog(
        BillingCatalog(
          available: _catalog.available,
          products: _catalog.products,
          missingProductIds: _catalog.missingProductIds,
          error: _catalog.error,
          eligibleIntroductoryProductIds: {
            ..._catalog.eligibleIntroductoryProductIds.where(
              (id) => id != product.id,
            ),
            if (eligible) product.id,
          },
        ),
      );
    }
  }

  @override
  Future<BillingReturnOffers> loadReturnOffers() async {
    final request = _offerRequest?.call();
    if (_channel != BillingChannel.storeKit ||
        currentAccess.hasActiveEntitlement ||
        !_storeAvailable ||
        request == null) {
      return BillingReturnOffers();
    }
    final generation = _accountGeneration;
    final proof = await _withTimeout(_latestSubscriptionTransaction());
    if (proof == null || _disposed || generation != _accountGeneration) {
      return BillingReturnOffers();
    }
    final response = await _withTimeout(
      request({'action': 'eligibility', 'transaction': proof.jws}),
    );
    if (_disposed || generation != _accountGeneration) {
      return BillingReturnOffers();
    }
    return BillingReturnOffers.fromJson(response, proof.jws);
  }

  @override
  Future<Result<bool>> purchase(String productId, {String? returnOfferId}) {
    if (_purchaseRequest != null) return _purchaseRequest!;
    if (_pendingProductId != null || _restoreFuture != null) {
      return Future.value(const Success(false));
    }
    if (_disposed) {
      return Future.value(
        Failure(StateError('Billing disposed.'), StackTrace.current),
      );
    }
    beginPurchase(productId);
    return _purchaseRequest = _purchase(productId, returnOfferId).whenComplete(
      () {
        _purchaseRequest = null;
      },
    );
  }

  Future<Result<bool>> _purchase(
    String productId,
    String? returnOfferId,
  ) async {
    final generation = _accountGeneration;
    try {
      if (!billingProductIds.contains(productId)) {
        throw StateError('This product is not available yet.');
      }
      if (_channel == BillingChannel.stripe) {
        if (!_signedIn) throw StateError('Sign in to continue.');
        final gateway = _stripeGateway?.call();
        if (gateway == null) {
          throw StateError('Stripe billing is not configured.');
        }
        final url = await _withTimeout(
          gateway.createCheckout(productId, _surface),
        );
        if (_disposed || generation != _accountGeneration) {
          cancelPurchase();
          return const Success(false);
        }
        if (url.scheme != 'https') {
          throw StateError('Stripe returned an unsafe checkout URL.');
        }
        if (!await _withTimeout(gateway.openCheckout(url))) {
          throw StateError('Could not open Stripe Checkout.');
        }
        cancelPurchase();
        return const Success(true);
      }
      if (!_storeSupported) {
        throw StateError('Purchases are available on Apple devices.');
      }
      String? token;
      try {
        token = await _withTimeout(_accountToken?.call() ?? Future.value(null));
      } on Object {
        /* Account availability must not disable local purchases. */
      }
      if (_disposed || generation != _accountGeneration) {
        cancelPurchase();
        return const Success(false);
      }
      bool sent;
      if (returnOfferId != null) {
        final request = _offerRequest?.call();
        final proof = await _withTimeout(_latestSubscriptionTransaction());
        if (request == null ||
            proof == null ||
            currentAccess.hasActiveEntitlement) {
          throw const BillingOfferException('not_eligible');
        }
        final response = await _withTimeout(
          request({
            'action': 'sign',
            'transaction': proof.jws,
            'productId': productId,
            'appAccountToken': ?token,
          }),
        );
        if (_disposed ||
            generation != _accountGeneration ||
            currentAccess.hasActiveEntitlement) {
          throw const BillingOfferException('not_eligible');
        }
        final result = await _withTimeout(
          _buyPromotional(
            productId,
            returnOfferId,
            billingOfferSignature(response, returnOfferId),
            appAccountToken: token,
          ),
          _purchaseTimeout,
        );
        await processPurchaseUpdate(result);
        sent = true;
      } else {
        sent = await _withTimeout(
          _buy(productId, appAccountToken: token),
          _purchaseTimeout,
        );
      }
      if (!sent) cancelPurchase();
      return Success(sent);
    } catch (error, stack) {
      if (!isCancellation(error)) _recordError('purchase', error);
      cancelPurchase();
      return Failure(error, stack);
    }
  }

  void _startPurchaseWatchdog(String productId) {
    _purchaseWatchdog?.cancel();
    _purchaseWatchdog = Timer(_purchaseTimeout, () {
      if (_disposed || _pendingProductId != productId) return;
      cancelPurchase();
      _purchaseErrors.add(
        const BillingFailure(
          code: 'purchase_timeout',
          message: 'The purchase timed out. Please try again.',
        ),
      );
    });
  }

  BillingFailure _billingFailure(Object error) {
    if (error is BillingFailure) return error;
    if (error is IAPError) {
      return BillingFailure(code: error.code, message: error.message);
    }
    return BillingFailure(
      code: error.runtimeType.toString(),
      message: '$error',
    );
  }
}

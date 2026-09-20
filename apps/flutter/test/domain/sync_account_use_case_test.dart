import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/repositories/account/account_session_repository.dart';
import 'package:pomodoist/data/repositories/billing/billing_repository.dart';
import 'package:pomodoist/data/repositories/sync/sync_repository.dart';
import 'package:pomodoist/domain/models/account/account_overview.dart';
import 'package:pomodoist/domain/models/account/account_session.dart';
import 'package:pomodoist/domain/models/billing/billing_access.dart';
import 'package:pomodoist/domain/models/billing/billing_models.dart';
import 'package:pomodoist/domain/models/billing/billing_store_models.dart';
import 'package:pomodoist/domain/use_cases/account/pomodoist_retention.dart';
import 'package:pomodoist/domain/use_cases/account/sync_account_use_case.dart';
import 'package:pomodoist/utils/result.dart';

class _FakeSessions implements AccountSessionRepository {
  _FakeSessions(this.session);

  AccountSession session;

  @override
  AccountSession get currentSession => session;
  @override
  Stream<AccountSession> watchSession() async* {
    yield session;
  }

  @override
  Stream<PomodoistAccountProfile?> watchProfile() => const Stream.empty();

  @override
  Future<Result<void>> refresh() async => const Success(null);
}

class _FakeAccess extends Fake implements BillingRepository {
  _FakeAccess({this.hasLocalStoreKitEntitlement = false});

  bool hasLocalStoreKitEntitlement;

  @override
  BillingAccess get currentAccess => (
    hasActiveEntitlement: hasLocalStoreKitEntitlement,
    hasLocalStoreKitEntitlement: hasLocalStoreKitEntitlement,
    loading: false,
  );

  @override
  Stream<BillingAccess> watchAccess() => const Stream.empty();
  @override
  String? get activeProductId => null;
  @override
  Set<String> get activeStoreKitProductIds => const {};
  @override
  Set<String> get purchasedProductIds => const {};
  @override
  bool get accountEntitlementActive => false;
  @override
  bool get environmentEntitlementActive => false;
  @override
  BillingEntitlement? get activeAccountEntitlement => null;
  @override
  bool get storeAvailable => false;
  @override
  String? get purchaseSuccessProductId => null;
  @override
  Object? get confirmationFailure => null;
  @override
  Stream<BillingPurchaseUpdate> get purchaseUpdates => const Stream.empty();
  @override
  Stream<Object> get purchaseErrors => const Stream.empty();
  @override
  Future<Result<void>> refresh() async => const Success(null);
  @override
  Future<Result<void>> restore() async => const Success(null);
  @override
  Future<void> processPurchaseUpdate(BillingPurchaseUpdate purchase) async {}
  @override
  void beginPurchase(String productId) {}
  @override
  void cancelPurchase() {}
  @override
  void setStoreAvailable(bool available) {}
  @override
  void clearPurchaseSuccess() {}
  @override
  void clearError() {}
}

class _FakeSync implements SyncRepository {
  _FakeSync({this.onSync});

  final Future<Result<Set<String>>> Function(AccountSession session)? onSync;
  AccountSession? captured;
  DateTime? capturedCutoff;

  @override
  Future<Result<Set<String>>> syncNow({
    required AccountSession session,
    required DateTime? retentionCutoff,
  }) async {
    captured = session;
    capturedCutoff = retentionCutoff;
    return onSync?.call(session) ?? const Success({'task'});
  }
}

PomodoistAccountOverview _overview({bool isPro = false}) =>
    PomodoistAccountOverview(
      profile: PomodoistAccountProfile(id: 'a', isPro: isPro),
      apps: const [],
      generatedAt: DateTime.utc(2026, 1, 1),
    );

SyncAccountUseCase _useCase({
  required _FakeSessions sessions,
  required _FakeSync sync,
  bool selfHosted = false,
  bool hasLocalEntitlement = false,
  PomodoistAccountOverview? overview,
  Future<PomodoistHistoryPolicy> Function()? loadHistoryPolicy,
}) {
  return SyncAccountUseCase(
    sessions: sessions,
    sync: sync,
    access: _FakeAccess(hasLocalStoreKitEntitlement: hasLocalEntitlement),
    loadOverview: () async => overview,
    selfHostedFeaturesUnlocked: () => selfHosted,
    loadHistoryPolicy:
        loadHistoryPolicy ??
        () async => (historyUnlimited: false, graceEndsAt: null),
  );
}

void main() {
  test('captures the session before syncing and computes the cutoff', () async {
    final sessions = _FakeSessions((userId: 'a', generation: 3));
    final sync = _FakeSync();
    final useCase = _useCase(
      sessions: sessions,
      sync: sync,
      overview: _overview(),
    );

    final result = await useCase.call();

    expect(result.getOrThrow(), {'task'});
    expect(sync.captured, (userId: 'a', generation: 3));
    final cutoff = sync.capturedCutoff;
    expect(cutoff, isNotNull);
    expect(
      cutoff!.isAfter(
        DateTime.now().toUtc().subtract(
          pomodoistFreeTaskHistoryRetention + const Duration(days: 1),
        ),
      ),
      isTrue,
    );
  });

  test('a generation change during sync drops the result', () async {
    final sessions = _FakeSessions((userId: 'a', generation: 3));
    final sync = _FakeSync(
      onSync: (session) async {
        sessions.session = (
          userId: session.userId,
          generation: session.generation + 1,
        );
        return const Success({'task'});
      },
    );
    final useCase = _useCase(sessions: sessions, sync: sync);

    final result = await useCase.call();

    expect(result.getOrThrow(), isEmpty);
  });

  test('signed-out sessions do not sync', () async {
    final sessions = _FakeSessions((userId: null, generation: 2));
    final sync = _FakeSync();
    var overviewLoads = 0;
    final useCase = SyncAccountUseCase(
      sessions: sessions,
      sync: sync,
      access: _FakeAccess(),
      loadOverview: () async {
        overviewLoads++;
        return null;
      },
      selfHostedFeaturesUnlocked: () => false,
      loadHistoryPolicy: () async =>
          (historyUnlimited: false, graceEndsAt: null),
    );

    final result = await useCase.call();

    expect(result.getOrThrow(), isEmpty);
    expect(sync.captured, isNull);
    expect(overviewLoads, 0);
  });

  test('sync failures propagate', () async {
    final sessions = _FakeSessions((userId: 'a', generation: 3));
    final sync = _FakeSync(
      onSync: (_) async => Failure(StateError('offline'), StackTrace.current),
    );
    final useCase = _useCase(sessions: sessions, sync: sync);

    expect(await useCase.call(), isA<Failure<Set<String>>>());
  });

  test(
    'self-hosted builds skip the cutoff without loading the overview',
    () async {
      final sync = _FakeSync();
      var overviewLoads = 0;
      final useCase = SyncAccountUseCase(
        sessions: _FakeSessions((userId: 'a', generation: 1)),
        sync: sync,
        access: _FakeAccess(),
        loadOverview: () async {
          overviewLoads++;
          return null;
        },
        selfHostedFeaturesUnlocked: () => true,
        loadHistoryPolicy: () async =>
            (historyUnlimited: false, graceEndsAt: null),
      );

      await useCase.call();

      expect(sync.capturedCutoff, isNull);
      expect(overviewLoads, 0);
    },
  );

  test('local StoreKit entitlement skips the cutoff', () async {
    final sync = _FakeSync();
    var overviewLoads = 0;
    final useCase = SyncAccountUseCase(
      sessions: _FakeSessions((userId: 'a', generation: 1)),
      sync: sync,
      access: _FakeAccess(hasLocalStoreKitEntitlement: true),
      loadOverview: () async {
        overviewLoads++;
        return null;
      },
      selfHostedFeaturesUnlocked: () => false,
      loadHistoryPolicy: () async =>
          (historyUnlimited: false, graceEndsAt: null),
    );

    await useCase.call();

    expect(sync.capturedCutoff, isNull);
    expect(overviewLoads, 0);
  });

  test('unlimited history policy disables the cutoff', () async {
    final sync = _FakeSync();
    final useCase = _useCase(
      sessions: _FakeSessions((userId: 'a', generation: 1)),
      sync: sync,
      overview: _overview(),
      loadHistoryPolicy: () async =>
          (historyUnlimited: true, graceEndsAt: null),
    );

    await useCase.call();

    expect(sync.capturedCutoff, isNull);
  });

  test('active paid entitlement disables the cutoff', () async {
    final sync = _FakeSync();
    final useCase = _useCase(
      sessions: _FakeSessions((userId: 'a', generation: 1)),
      sync: sync,
      overview: _overview(isPro: true),
    );

    await useCase.call();

    expect(sync.capturedCutoff, isNull);
  });

  test('history policy failures fall back to no cutoff', () async {
    final sync = _FakeSync();
    final useCase = _useCase(
      sessions: _FakeSessions((userId: 'a', generation: 1)),
      sync: sync,
      overview: _overview(),
      loadHistoryPolicy: () async => throw StateError('missing policy'),
    );

    await useCase.call();

    expect(sync.capturedCutoff, isNull);
  });
}

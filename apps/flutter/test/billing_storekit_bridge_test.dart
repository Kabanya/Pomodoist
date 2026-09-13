import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/features/billing/billing.dart';

const _channel = MethodChannel('pomodoist/storekit');
const _old = BillingTransactionProof(
  productId: pomodoistLifetimeProductId,
  jws: 'old-proof',
);
const _fresh = BillingTransactionProof(
  productId: pomodoistAnnualProductId,
  jws: 'fresh-proof',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.macOS);
  tearDown(() {
    messenger.setMockMethodCallHandler(_channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'native snapshot preserves all proofs and large string IDs silently',
    () {
      fakeAsync((time) {
        final response = Completer<Object?>();
        var reads = 0;
        var syncs = 0;
        messenger.setMockMethodCallHandler(_channel, (call) {
          expect(call.method, 'currentEntitlements');
          expect(call.arguments, isNull);
          reads++;
          return response.future;
        });
        final store = BillingStore(restoreSynchronizer: () async => syncs++);
        final snapshot = store.refreshCurrentEntitlements();
        expect(store.refreshCurrentEntitlements(), same(snapshot));
        expect(store.pomodoistTransactionJws(), completion(['jws-1', 'jws-2']));
        List<BillingTransactionProof>? received;
        snapshot.then((value) => received = value);
        time.flushMicrotasks();
        expect(reads, 1);
        expect(received, isNull);

        response.complete([
          _nativeRow(transactionId: '18446744073709551615'),
          _nativeRow(productId: pomodoistAnnualProductId, jws: 'jws-2'),
        ]);
        time.flushMicrotasks();
        expect(received?.map((proof) => proof.productId), [
          pomodoistLifetimeProductId,
          pomodoistAnnualProductId,
        ]);
        expect(received?.first.transactionId, '18446744073709551615');
        expect(
          received?.first.localVerificationData,
          '{"signedDate":1788955200000}',
        );
        expect(syncs, 0);
      });
    },
  );

  test('empty native snapshot completes successfully', () {
    fakeAsync((time) {
      messenger.setMockMethodCallHandler(_channel, (_) async => []);
      expect(BillingStore().refreshCurrentEntitlements(), completion(isEmpty));
      time.flushMicrotasks();
    });
  });

  for (final malformed in <String, Object?>{
    'non-map row': 42,
    'numeric transaction ID': {..._nativeRow(), 'transactionId': 42},
    'missing proof': {..._nativeRow(), 'jws': ''},
    'invalid JSON': {..._nativeRow(), 'localVerificationData': '{'},
    'non-object JSON': {..._nativeRow(), 'localVerificationData': '[]'},
  }.entries) {
    test('${malformed.key} rejects the entire native snapshot', () {
      fakeAsync((time) {
        messenger.setMockMethodCallHandler(
          _channel,
          (_) async => [_nativeRow(), malformed.value],
        );
        expect(
          BillingStore().refreshCurrentEntitlements(),
          throwsA(isA<FormatException>()),
        );
        time.flushMicrotasks();
      });
    });
  }

  test(
    'missing snapshot and native verification failure are not empty reads',
    () {
      fakeAsync((time) {
        messenger.setMockMethodCallHandler(_channel, (_) async => null);
        final store = BillingStore();
        expect(
          store.refreshCurrentEntitlements(),
          throwsA(isA<FormatException>()),
        );
        time.flushMicrotasks();

        messenger.setMockMethodCallHandler(_channel, (_) async {
          throw PlatformException(
            code: 'storekit_unverified_transaction',
            details: {'domain': 'StoreKit.VerificationError', 'code': 4},
          );
        });
        expect(
          store.refreshCurrentEntitlements(),
          throwsA(
            isA<PlatformException>().having(
              (error) => error.code,
              'code',
              'storekit_unverified_transaction',
            ),
          ),
        );
        time.flushMicrotasks();
      });
    },
  );

  test('failed coalesced read releases the next attempt', () {
    fakeAsync((time) {
      final failed = Completer<List<BillingTransactionProof>>();
      final retry = Completer<List<BillingTransactionProof>>();
      var reads = 0;
      final store = BillingStore(
        transactionLoader: () => ++reads == 1 ? failed.future : retry.future,
      );
      final first = store.refreshCurrentEntitlements();
      expect(store.refreshCurrentEntitlements(), same(first));
      expect(first, throwsStateError);
      failed.completeError(StateError('read failed'));
      time.flushMicrotasks();

      final second = store.refreshCurrentEntitlements();
      expect(second, isNot(same(first)));
      expect(second, completion([_fresh]));
      expect(reads, 2);
      retry.complete([_fresh]);
      time.flushMicrotasks();
    });
  });

  test(
    'timed-out read releases coalescing and its late result cannot clear retry',
    () {
      fakeAsync((time) {
        final hung = Completer<List<BillingTransactionProof>>();
        final retry = Completer<List<BillingTransactionProof>>();
        var reads = 0;
        final store = BillingStore(
          transactionLoader: () => ++reads == 1 ? hung.future : retry.future,
        );
        final first = store.refreshCurrentEntitlements();
        expect(store.refreshCurrentEntitlements(), same(first));
        expect(first, throwsA(isA<TimeoutException>()));
        time.elapse(billingStoreTimeout);

        final second = store.refreshCurrentEntitlements();
        expect(second, completion([_fresh]));
        hung.complete([_old]);
        time.flushMicrotasks();
        expect(store.refreshCurrentEntitlements(), same(second));
        expect(reads, 2);
        retry.complete([_fresh]);
        time.flushMicrotasks();
      });
    },
  );

  test(
    'explicit restore coalesces sync and reads fresh after a pre-sync read',
    () {
      fakeAsync((time) {
        final beforeSync = Completer<List<BillingTransactionProof>>();
        final afterSync = Completer<List<BillingTransactionProof>>();
        final sync = Completer<void>();
        var reads = 0;
        var syncs = 0;
        final store = BillingStore(
          transactionLoader: () =>
              ++reads == 1 ? beforeSync.future : afterSync.future,
          restoreSynchronizer: () {
            syncs++;
            return sync.future;
          },
        );
        final oldRead = store.refreshCurrentEntitlements();
        expect(oldRead, completion([_old]));
        final restore = store.restorePurchases();
        expect(store.restorePurchases(), same(restore));
        expect(restore, completion([_fresh]));
        time.flushMicrotasks();
        expect(syncs, 1);
        expect(reads, 1);

        sync.complete();
        time.flushMicrotasks();
        expect(reads, 2);
        final freshRead = store.refreshCurrentEntitlements();
        expect(freshRead, isNot(same(oldRead)));
        beforeSync.complete([_old]);
        time.flushMicrotasks();
        expect(store.refreshCurrentEntitlements(), same(freshRead));
        expect(reads, 2);
        afterSync.complete([_fresh]);
        time.flushMicrotasks();
      });
    },
  );

  test(
    'cancelled sync leaves automatic reads and explicit restore retryable',
    () {
      fakeAsync((time) {
        final cancelled = Completer<void>();
        var reads = 0;
        var syncs = 0;
        final store = BillingStore(
          transactionLoader: () async {
            reads++;
            return [_fresh];
          },
          restoreSynchronizer: () =>
              ++syncs == 1 ? cancelled.future : Future.value(),
        );
        final restore = store.restorePurchases();
        expect(store.restorePurchases(), same(restore));
        expect(
          restore,
          throwsA(
            isA<PlatformException>().having(
              (error) => error.code,
              'code',
              'userCancelled',
            ),
          ),
        );
        cancelled.completeError(PlatformException(code: 'userCancelled'));
        time.flushMicrotasks();
        expect(reads, 0);

        expect(store.refreshCurrentEntitlements(), completion([_fresh]));
        time.flushMicrotasks();
        expect(syncs, 1);
        expect(store.restorePurchases(), completion([_fresh]));
        time.flushMicrotasks();
        expect(syncs, 2);
        expect(reads, 2);
      });
    },
  );

  test('timed-out sync allows retry and its late completion cannot read', () {
    fakeAsync((time) {
      final hung = Completer<void>();
      final retry = Completer<void>();
      var syncs = 0;
      var reads = 0;
      final store = BillingStore(
        restoreSynchronizer: () => ++syncs == 1 ? hung.future : retry.future,
        transactionLoader: () async {
          reads++;
          return [_fresh];
        },
      );
      final first = store.restorePurchases();
      expect(first, throwsA(isA<TimeoutException>()));
      time.elapse(billingStoreTimeout);
      expect(reads, 0);

      final second = store.restorePurchases();
      expect(second, isNot(same(first)));
      expect(second, completion([_fresh]));
      expect(syncs, 2);
      hung.complete();
      time.flushMicrotasks();
      expect(reads, 0);
      expect(store.restorePurchases(), same(second));

      retry.complete();
      time.flushMicrotasks();
      expect(reads, 1);
    });
  });
}

Map<String, Object?> _nativeRow({
  String productId = pomodoistLifetimeProductId,
  String transactionId = '123',
  String jws = 'jws-1',
}) => {
  'productId': productId,
  'transactionId': transactionId,
  'jws': jws,
  'localVerificationData': '{"signedDate":1788955200000}',
};

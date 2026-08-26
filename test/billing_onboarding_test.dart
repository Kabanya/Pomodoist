import 'dart:async';

import 'package:app_account/app_account.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';
import 'package:pomodoist/app/account_providers.dart';
import 'package:pomodoist/app/app_language.dart';
import 'package:pomodoist/app/app_theme_mode.dart';
import 'package:pomodoist/app/providers.dart';
import 'package:pomodoist/app/theme/app_theme.dart';
import 'package:pomodoist/core/time/clock.dart';
import 'package:pomodoist/features/billing/billing.dart';
import 'package:pomodoist/features/billing/purchase_success_screen.dart';
import 'package:pomodoist/features/focus/presentation/focus_view_mode.dart';
import 'package:pomodoist/features/onboarding/onboarding_gate.dart';
import 'package:pomodoist/features/settings/presentation/settings_screen.dart';
import 'package:pomodoist/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('billing catalog contains the requested products', () {
    expect(billingPlans, hasLength(4));
    expect(billingPlans.map((plan) => plan.productId), [
      pomodoistAnnualProductId,
      pomodoistMonthlyProductId,
      pomodoistLifetimeProductId,
      pomodoistLifetimeLaunchProductId,
    ]);
    expect(
      billingPlans.map((plan) => plan.productId),
      isNot(contains('pomodoist.pro.lifetime.full')),
    );
    expect(
      billingPlanForProduct(pomodoistAnnualProductId)?.highlighted,
      isTrue,
    );
    expect(
      billingPlanForProduct(pomodoistLifetimeLaunchProductId)?.highlighted,
      isFalse,
    );
    expect(
      billingPlanForProduct(
        pomodoistMonthlyProductId,
      )?.introductoryFallbackPrice,
      r'$2.99/month',
    );
    expect(
      billingPlanForProduct(
        pomodoistAnnualProductId,
      )?.introductoryFallbackPrice,
      r'$19/year',
    );
    expect(
      billingPlanForProduct(pomodoistMonthlyProductId)?.fallbackPrice,
      r'$5.99/month',
    );
    expect(
      billingPlanForProduct(pomodoistAnnualProductId)?.fallbackPrice,
      r'$39/year',
    );
    expect(
      billingPlanForProduct(pomodoistLifetimeProductId)?.kind,
      BillingPlanKind.lifetime,
    );
    expect(
      billingPlanForProduct(pomodoistLifetimeProductId)?.fallbackPrice,
      r'$99',
    );
    expect(
      billingPlanForProduct(pomodoistLifetimeLaunchProductId)?.fallbackPrice,
      r'$89',
    );
  });

  test('release billing channel must be explicit', () {
    expect(
      billingChannelForBuild(value: 'storekit', releaseMode: true),
      BillingChannel.storeKit,
    );
    expect(
      billingChannelForBuild(value: 'stripe', releaseMode: true),
      BillingChannel.stripe,
    );
    expect(
      () => billingChannelForBuild(value: '', releaseMode: true),
      throwsStateError,
    );
    expect(
      billingChannelForBuild(value: '', releaseMode: false),
      BillingChannel.storeKit,
    );
  });

  test('Stripe billing accepts the server catalog and HTTPS Checkout only', () {
    expect(stripePurchaseFallbackUrl, 'pomodoist://purchase-success');
    final catalog = StripeBillingCatalog.fromJson({
      'enabled': true,
      'introEligible': false,
      'launchOffer': {'eligible': true, 'endsAt': '2026-08-03T18:00:00Z'},
    });

    expect(catalog.enabled, isTrue);
    expect(catalog.introEligible, isFalse);
    expect(catalog.launchOfferEligible, isTrue);
    expect(catalog.launchOfferEndsAt, DateTime.utc(2026, 8, 3, 18));
    expect(
      stripeCheckoutUrlFromJson({
        'url': 'https://checkout.stripe.com/c/pay/test',
      }).host,
      'checkout.stripe.com',
    );
    expect(
      () => stripeCheckoutUrlFromJson({'url': 'http://example.test/pay'}),
      throwsFormatException,
    );
    expect(
      stripeLaunchOfferRemaining(
        now: DateTime.utc(2026, 8, 3, 17, 30),
        endsAt: catalog.launchOfferEndsAt,
      ),
      const Duration(minutes: 30),
    );
    expect(
      stripeLaunchOfferRemaining(
        now: DateTime.utc(2026, 8, 3, 18, 1),
        endsAt: catalog.launchOfferEndsAt,
      ),
      Duration.zero,
    );
  });

  test(
    'Stripe channel opens hosted Checkout without granting Pro locally',
    () async {
      String? requestedProductId;
      BillingCheckoutSurface? requestedSurface;
      Uri? openedUrl;
      final gateway = BillingStripeGateway(
        loadCatalog: () async => StripeBillingCatalog(
          enabled: true,
          introEligible: true,
          launchOfferEligible: true,
          launchOfferEndsAt: DateTime.utc(2026, 8, 3, 18),
        ),
        createCheckout: (productId, surface) async {
          requestedProductId = productId;
          requestedSurface = surface;
          return Uri.parse('https://checkout.stripe.com/c/pay/test');
        },
        openCheckout: (url) async {
          openedUrl = url;
          return true;
        },
      );
      final container = ProviderContainer(
        overrides: [
          billingChannelProvider.overrideWithValue(BillingChannel.stripe),
          billingStripeGatewayProvider.overrideWithValue(gateway),
          billingSignedInProvider.overrideWithValue(true),
        ],
      );
      addTearDown(container.dispose);

      container.read(billingControllerProvider);
      await _settle();
      final catalog = container.read(billingControllerProvider);
      expect(catalog.storeAvailable, isTrue);
      expect(catalog.eligibleIntroductoryProductIds, {
        pomodoistMonthlyProductId,
        pomodoistAnnualProductId,
      });
      expect(catalog.stripeLaunchOfferEligible, isTrue);

      await container
          .read(billingControllerProvider.notifier)
          .purchase(pomodoistAnnualProductId);

      expect(requestedProductId, pomodoistAnnualProductId);
      expect(requestedSurface, BillingCheckoutSurface.native);
      expect(openedUrl?.host, 'checkout.stripe.com');
      expect(
        container.read(billingControllerProvider).hasActiveEntitlement,
        false,
      );
      expect(
        container.read(billingControllerProvider).purchaseSuccessProductId,
        isNull,
      );
      expect(
        container.read(billingControllerProvider).pendingProductId,
        isNull,
      );
    },
  );

  testWidgets('signed-out Stripe purchase asks for sign-in and stops', (
    tester,
  ) async {
    var prompts = 0;
    var checkouts = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          billingChannelProvider.overrideWithValue(BillingChannel.stripe),
          billingSignedInProvider.overrideWithValue(false),
          billingSignInPromptProvider.overrideWithValue((_) async {
            prompts += 1;
          }),
          billingStripeGatewayProvider.overrideWithValue(
            BillingStripeGateway(
              loadCatalog: () => throw UnimplementedError(),
              createCheckout: (_, _) async {
                checkouts += 1;
                return Uri.parse('https://checkout.stripe.com/c/pay/test');
              },
              openCheckout: (_) async => true,
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SingleChildScrollView(child: BillingPaywall()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('billing-buy-pomodoist.pro.annual')),
    );
    await tester.pump();

    expect(prompts, 1);
    expect(checkouts, 0);
  });

  testWidgets('paywall keeps privacy policy and terms accessible', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          billingStoreProvider.overrideWithValue(_FakeBillingStore()),
          applePurchasesSupportedProvider.overrideWithValue(true),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SingleChildScrollView(child: BillingPaywall()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('billing-privacy-policy')), findsOneWidget);
    expect(find.byKey(const Key('billing-terms-of-use')), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('Terms of Use'), findsOneWidget);
  });

  testWidgets('Stripe failure does not claim the App Store is unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          billingChannelProvider.overrideWithValue(BillingChannel.stripe),
          billingSignedInProvider.overrideWithValue(true),
          billingStripeGatewayProvider.overrideWithValue(
            BillingStripeGateway(
              loadCatalog: () => throw Exception('Stripe catalog failed.'),
              createCheckout: (_, _) => throw UnimplementedError(),
              openCheckout: (_) async => false,
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SingleChildScrollView(child: BillingPaywall()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('The App Store is not available right now.'),
      findsNothing,
    );
    expect(find.textContaining('Stripe catalog failed.'), findsOneWidget);
  });

  testWidgets('disabled web checkout shows an availability notice', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          billingChannelProvider.overrideWithValue(BillingChannel.stripe),
          billingSignedInProvider.overrideWithValue(true),
          billingStripeGatewayProvider.overrideWithValue(
            BillingStripeGateway(
              loadCatalog: () async => const StripeBillingCatalog(
                enabled: false,
                introEligible: false,
                launchOfferEligible: false,
                launchOfferEndsAt: null,
              ),
              createCheckout: (_, _) => throw UnimplementedError(),
              openCheckout: (_) async => false,
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SingleChildScrollView(child: BillingPaywall()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Покупки доступны через App Store.'), findsOneWidget);
    expect(find.textContaining('Stripe checkout is disabled.'), findsNothing);
  });

  testWidgets('Stripe purchase waits for external browser confirmation', (
    tester,
  ) async {
    var checkouts = 0;
    var opened = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          billingChannelProvider.overrideWithValue(BillingChannel.stripe),
          billingSignedInProvider.overrideWithValue(true),
          billingStripeGatewayProvider.overrideWithValue(
            BillingStripeGateway(
              loadCatalog: () async => const StripeBillingCatalog(
                enabled: true,
                introEligible: false,
                launchOfferEligible: false,
                launchOfferEndsAt: null,
              ),
              createCheckout: (_, _) async {
                checkouts += 1;
                return Uri.parse('https://checkout.stripe.com/c/pay/test');
              },
              openCheckout: (_) async {
                opened = true;
                return true;
              },
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SingleChildScrollView(child: BillingPaywall()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('billing-buy-pomodoist.pro.annual')),
    );
    await tester.pumpAndSettle();

    expect(checkouts, 0);
    expect(opened, isFalse);
    expect(find.text('Payment opens in your browser'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(checkouts, 0);

    await tester.tap(
      find.byKey(const ValueKey('billing-buy-pomodoist.pro.annual')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(checkouts, 1);
    expect(opened, isTrue);
  });

  test('billing combines local and account entitlements', () async {
    for (final fixture in [
      (local: false, account: false, expected: false),
      (local: true, account: false, expected: true),
      (local: false, account: true, expected: true),
      (local: true, account: true, expected: true),
    ]) {
      final state = BillingState(
        loading: false,
        activeStoreKitProductIds: fixture.local
            ? const {pomodoistLifetimeProductId}
            : const <String>{},
        accountEntitlementActive: fixture.account,
      );
      expect(state.hasActiveEntitlement, fixture.expected);
    }

    final account = _FakeEntitlementController();
    final container = ProviderContainer(
      overrides: [
        applePurchasesSupportedProvider.overrideWithValue(false),
        _fakeAccountEntitlementProvider.overrideWith(() => account),
        billingAccountEntitlementProvider.overrideWith(
          (ref) => ref.watch(_fakeAccountEntitlementProvider),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(billingControllerProvider);
    await _settle();

    expect(
      container.read(billingControllerProvider).hasActiveEntitlement,
      false,
    );
    account.setActive(true);
    await _settle();
    expect(
      container.read(billingControllerProvider).hasActiveEntitlement,
      true,
    );
    account.setActive(false);
    await _settle();
    expect(
      container.read(billingControllerProvider).hasActiveEntitlement,
      false,
    );
  });

  test('verified StoreKit tier wins over account metadata', () {
    expect(
      billingAccessTier(
        const BillingState(
          loading: false,
          activeStoreKitProductIds: {pomodoistAnnualProductId},
          activeProductId: pomodoistAnnualProductId,
          accountEntitlementActive: true,
          activeAccountEntitlement: AccountEntitlement(
            appId: AccountAppId.pomodoist,
            entitlementId: 'stripe:lifetime',
            status: 'active',
            purchaseType: 'lifetime',
            source: 'stripe',
            productId: pomodoistLifetimeProductId,
          ),
        ),
      ),
      BillingAccessTier.annual,
    );
  });

  test(
    'sign-out clears account fallback but keeps verified StoreKit Pro',
    () async {
      final account = _FakeEntitlementController();
      final store = _FakeBillingStore();
      final container = ProviderContainer(
        overrides: [
          billingStoreProvider.overrideWithValue(store),
          applePurchasesSupportedProvider.overrideWithValue(true),
          _fakeAccountEntitlementProvider.overrideWith(() => account),
          billingAccountEntitlementProvider.overrideWith(
            (ref) => ref.watch(_fakeAccountEntitlementProvider),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(billingControllerProvider);
      await _settle();

      account.setActive(true);
      store.emit([
        _purchase(pomodoistAnnualProductId, PurchaseStatus.restored),
      ]);
      await _settle();
      account.setActive(false);
      await _settle();

      final state = container.read(billingControllerProvider);
      expect(state.accountEntitlementActive, isFalse);
      expect(state.activeStoreKitProductIds, {pomodoistAnnualProductId});
      expect(state.hasActiveEntitlement, isTrue);
    },
  );

  test('billing validates current StoreKit transaction state', () {
    final now = DateTime.utc(2026, 7, 27);
    expect(
      pomodoistStoreKitPurchaseIsActive(
        _purchase(
          pomodoistMonthlyProductId,
          PurchaseStatus.restored,
          localJson: '{"expiresDate":1787832000000}',
        ),
        now,
      ),
      isTrue,
    );
    expect(
      pomodoistStoreKitPurchaseIsActive(
        _purchase(
          pomodoistAnnualProductId,
          PurchaseStatus.restored,
          localJson: '{"expirationDate":1756296000000}',
        ),
        now,
      ),
      isFalse,
    );
    expect(
      pomodoistStoreKitPurchaseIsActive(
        _purchase(
          pomodoistLifetimeProductId,
          PurchaseStatus.restored,
          localJson: '{"revocationDate":1754049600000}',
        ),
        now,
      ),
      isFalse,
    );
    expect(
      pomodoistStoreKitPurchaseIsActive(
        _purchase(
          pomodoistLifetimeProductId,
          PurchaseStatus.restored,
          localJson: 'not-json',
        ),
        now,
      ),
      pomodoistLocalStoreKit,
    );
  });

  test('startup silently refreshes verified StoreKit access', () async {
    final store = _FakeBillingStore(
      refreshedProductIds: const {pomodoistLifetimeProductId},
    );
    final container = ProviderContainer(
      overrides: [
        billingStoreProvider.overrideWithValue(store),
        applePurchasesSupportedProvider.overrideWithValue(true),
      ],
    );
    addTearDown(container.dispose);

    container.read(billingControllerProvider);
    await _settle();

    final state = container.read(billingControllerProvider);
    expect(store.refreshCount, 1);
    expect(state.activeStoreKitProductIds, {pomodoistLifetimeProductId});
    expect(state.purchaseSuccessProductId, isNull);
    expect(state.restoring, isFalse);
  });

  test(
    'purchase passes account token and links after local activation',
    () async {
      final store = _FakeBillingStore();
      final linked = <String>[];
      final container = ProviderContainer(
        overrides: [
          billingStoreProvider.overrideWithValue(store),
          applePurchasesSupportedProvider.overrideWithValue(true),
          billingSignedInProvider.overrideWithValue(true),
          billingAppAccountTokenLoaderProvider.overrideWithValue(
            () async => '22222222-2222-4222-8222-222222222222',
          ),
          billingPurchaseLinkerProvider.overrideWithValue(
            (transactions) async => linked.addAll(transactions),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(billingControllerProvider);
      await _settle();

      await container
          .read(billingControllerProvider.notifier)
          .purchase(pomodoistAnnualProductId);
      await _settle();

      final state = container.read(billingControllerProvider);
      expect(store.lastAppAccountToken, '22222222-2222-4222-8222-222222222222');
      expect(linked, ['server-$pomodoistAnnualProductId']);
      expect(state.activeStoreKitProductIds, {pomodoistAnnualProductId});
      expect(state.purchaseSuccessProductId, pomodoistAnnualProductId);
    },
  );

  test(
    'finish failure does not turn a successful purchase into an error',
    () async {
      final store = _FakeBillingStore(
        completeError: StateError('finish unavailable'),
      );
      final container = ProviderContainer(
        overrides: [
          billingStoreProvider.overrideWithValue(store),
          applePurchasesSupportedProvider.overrideWithValue(true),
        ],
      );
      addTearDown(container.dispose);
      container.read(billingControllerProvider);
      await _settle();

      await container
          .read(billingControllerProvider.notifier)
          .purchase(pomodoistAnnualProductId);
      await _settle();

      final state = container.read(billingControllerProvider);
      expect(state.activeStoreKitProductIds, {pomodoistAnnualProductId});
      expect(state.purchaseSuccessProductId, pomodoistAnnualProductId);
      expect(state.error, isNull);
    },
  );

  test('explicit restore keeps feedback and links the restored JWS', () async {
    final store = _FakeBillingStore(
      restoredProductId: pomodoistLifetimeLaunchProductId,
    );
    final linked = <String>[];
    final container = ProviderContainer(
      overrides: [
        billingStoreProvider.overrideWithValue(store),
        applePurchasesSupportedProvider.overrideWithValue(true),
        billingSignedInProvider.overrideWithValue(true),
        billingPurchaseLinkerProvider.overrideWithValue(
          (transactions) async => linked.addAll(transactions),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(billingControllerProvider);
    await _settle();

    await container.read(billingControllerProvider.notifier).restorePurchases();
    await _settle();

    final state = container.read(billingControllerProvider);
    expect(store.restoreCount, 1);
    expect(state.restoring, isFalse);
    expect(state.purchaseSuccessProductId, pomodoistLifetimeLaunchProductId);
    expect(linked, ['server-$pomodoistLifetimeLaunchProductId']);
  });

  test(
    'sign-in refresh retries failed links without an overview loop',
    () async {
      final store = _FakeBillingStore(
        refreshedProductIds: const {pomodoistLifetimeProductId},
      );
      var attempts = 0;
      final container = ProviderContainer(
        overrides: [
          billingStoreProvider.overrideWithValue(store),
          applePurchasesSupportedProvider.overrideWithValue(true),
          billingSignedInProvider.overrideWith(
            (ref) => ref.watch(_fakeSignedInProvider),
          ),
          billingAccountRefreshTokenProvider.overrideWith(
            (ref) => ref.watch(_fakeOverviewTokenProvider),
          ),
          billingPurchaseLinkerProvider.overrideWithValue((_) async {
            attempts += 1;
            if (attempts == 1) throw StateError('link unavailable');
          }),
        ],
      );
      addTearDown(container.dispose);
      container.read(billingControllerProvider);
      await _waitFor(
        () =>
            store.refreshCount >= 1 &&
            container
                .read(billingControllerProvider)
                .activeStoreKitProductIds
                .contains(pomodoistLifetimeProductId),
        'startup StoreKit refresh',
      );
      expect(store.refreshCount, 1);
      expect(attempts, 0);
      expect(container.read(billingSignedInProvider), isFalse);
      expect(container.read(billingControllerProvider).storeAvailable, isTrue);

      container.read(_fakeSignedInProvider.notifier).setValue(true);
      expect(container.read(_fakeSignedInProvider), isTrue);
      expect(container.read(billingSignedInProvider), isTrue);
      await _waitFor(
        () => store.refreshCount >= 2,
        'signed-in StoreKit refresh',
      );
      await _waitFor(() => attempts >= 1, 'signed-in StoreKit link attempt');
      expect(container.read(_fakeSignedInProvider), isTrue);
      expect(container.read(billingSignedInProvider), isTrue);
      expect(store.refreshCount, 2);
      expect(attempts, 1);
      expect(
        container.read(billingControllerProvider).hasLocalStoreKitEntitlement,
        isTrue,
      );

      container
          .read(_fakeOverviewTokenProvider.notifier)
          .setValue('retry-after-failure');
      expect(container.read(_fakeOverviewTokenProvider), 'retry-after-failure');
      expect(
        container.read(billingAccountRefreshTokenProvider),
        'retry-after-failure',
      );
      await _waitFor(
        () => store.refreshCount >= 3 && attempts >= 2,
        'overview-triggered StoreKit link retry',
      );
      expect(store.refreshCount, 3);
      expect(attempts, 2);
      await _settle();

      container
          .read(_fakeOverviewTokenProvider.notifier)
          .setValue('link-invalidation');
      await _settle();
      expect(store.refreshCount, 3);
      expect(attempts, 2);
    },
  );

  test('link failure keeps local Pro without purchase error', () async {
    final store = _FakeBillingStore();
    final container = ProviderContainer(
      overrides: [
        billingStoreProvider.overrideWithValue(store),
        applePurchasesSupportedProvider.overrideWithValue(true),
        billingSignedInProvider.overrideWithValue(true),
        billingPurchaseLinkerProvider.overrideWithValue(
          (_) async => throw StateError('purchase_already_linked'),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(billingControllerProvider);
    await _settle();

    await container
        .read(billingControllerProvider.notifier)
        .purchase(pomodoistLifetimeProductId);
    await _settle();

    final state = container.read(billingControllerProvider);
    expect(state.hasLocalStoreKitEntitlement, isTrue);
    expect(state.hasActiveEntitlement, isTrue);
    expect(state.error, isNull);
  });

  test(
    'inactive StoreKit updates remove only their own local source',
    () async {
      final store = _FakeBillingStore();
      final container = ProviderContainer(
        overrides: [
          billingStoreProvider.overrideWithValue(store),
          applePurchasesSupportedProvider.overrideWithValue(true),
          billingAccountEntitlementProvider.overrideWithValue(true),
        ],
      );
      addTearDown(container.dispose);
      container.read(billingControllerProvider);
      await _settle();

      store.emit([
        _purchase(pomodoistLifetimeProductId, PurchaseStatus.restored),
        _purchase(pomodoistAnnualProductId, PurchaseStatus.restored),
      ]);
      await _settle();
      store.emit([
        _purchase(
          pomodoistAnnualProductId,
          PurchaseStatus.restored,
          localJson: '{"revocationDate":1754049600000}',
        ),
      ]);
      await _settle();
      expect(
        container.read(billingControllerProvider).activeStoreKitProductIds,
        {pomodoistLifetimeProductId},
      );

      store.emit([
        _purchase(
          pomodoistLifetimeProductId,
          PurchaseStatus.restored,
          localJson: '{"revocationDate":1754049600000}',
        ),
      ]);
      await _settle();
      final state = container.read(billingControllerProvider);
      expect(state.activeStoreKitProductIds, isEmpty);
      expect(state.hasActiveEntitlement, isTrue);
    },
  );

  test(
    'cached product id alone cannot grant production StoreKit Pro',
    () async {
      SharedPreferences.setMockInitialValues({
        billingActiveProductIdPreferenceKey: pomodoistLifetimeProductId,
      });
      final container = ProviderContainer(
        overrides: [
          billingStoreProvider.overrideWithValue(_FakeBillingStore()),
          applePurchasesSupportedProvider.overrideWithValue(true),
        ],
      );
      addTearDown(container.dispose);
      container.read(billingControllerProvider);
      await _settle();

      expect(
        container.read(billingControllerProvider).hasActiveEntitlement,
        pomodoistDevUnlock,
      );
    },
  );

  test('billing store returns signed Pomodoist transaction proofs', () async {
    final store = BillingStore(
      transactionLoader: () async => const [
        BillingTransactionProof(
          productId: pomodoistLifetimeProductId,
          jws: 'signed-pomodoist',
        ),
        BillingTransactionProof(productId: pomodoistAnnualProductId, jws: ''),
        BillingTransactionProof(
          productId: 'other.product',
          jws: 'signed-other',
        ),
      ],
    );

    expect(await store.pomodoistTransactionJws(), ['signed-pomodoist']);
  });

  test('billing store restores a signed current entitlement proof', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final store = _FakeBillingStore();

    expect(await store.pomodoistTransactionJws(), [
      'server-$pomodoistAnnualProductId',
    ]);
  });

  test(
    'billing controller keeps successful intro eligibility when one check fails',
    () async {
      final store = _FakeBillingStore(
        eligibleProductIds: const {pomodoistMonthlyProductId},
        eligibilityErrorProductIds: const {pomodoistAnnualProductId},
      );
      final container = ProviderContainer(
        overrides: [
          billingStoreProvider.overrideWithValue(store),
          applePurchasesSupportedProvider.overrideWithValue(true),
        ],
      );
      addTearDown(container.dispose);

      container.read(billingControllerProvider);
      await _settle();

      final state = container.read(billingControllerProvider);
      expect(state.storeAvailable, isTrue);
      expect(state.error, isNull);
      expect(state.eligibleIntroductoryProductIds, {pomodoistMonthlyProductId});
      expect(store.eligibilityChecks, {
        pomodoistAnnualProductId,
        pomodoistMonthlyProductId,
      });
    },
  );

  testWidgets('paywall uses localized StoreKit introductory prices', (
    tester,
  ) async {
    final store = _FakeBillingStore(productDetailsById: _euroBillingProducts());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          billingStoreProvider.overrideWithValue(store),
          applePurchasesSupportedProvider.overrideWithValue(true),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: BillingPaywall(
                launchOfferMode: true,
                launchOfferTimerLabel: '12:00:00',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final annual = find.byKey(
      const ValueKey('billing-plan-pomodoist.pro.annual'),
    );
    final monthly = find.byKey(
      const ValueKey('billing-plan-pomodoist.pro.monthly'),
    );
    final lifetime = find.byKey(
      const ValueKey('billing-plan-pomodoist.pro.lifetime.launch'),
    );

    expect(annual, findsOneWidget);
    expect(monthly, findsOneWidget);
    expect(lifetime, findsOneWidget);
    expect(
      find.descendant(of: annual, matching: find.text('€17.99/year')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: annual, matching: find.text('€34.99/year')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: annual, matching: find.text('Then €34.99/year.')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: monthly, matching: find.text('€2.99/month')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: monthly, matching: find.text('€5.99/month')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: monthly,
        matching: find.text('First 3 months, then €5.99/month.'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: lifetime, matching: find.text('€89.99')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: lifetime, matching: find.text('€179.99')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: annual, matching: find.text('Best value')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: lifetime, matching: find.text('Best value')),
      findsNothing,
    );
    expect(
      find.descendant(of: lifetime, matching: find.text('12:00:00')),
      findsOneWidget,
    );
    expect(find.textContaining('trial'), findsNothing);
  });

  testWidgets('ineligible paywall shows regular subscription prices', (
    tester,
  ) async {
    final store = _FakeBillingStore(
      eligibleProductIds: const {},
      productDetailsById: _euroBillingProducts(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          billingStoreProvider.overrideWithValue(store),
          applePurchasesSupportedProvider.overrideWithValue(true),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SingleChildScrollView(child: BillingPaywall()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('€34.99/year'), findsOneWidget);
    expect(find.text('€5.99/month'), findsOneWidget);
    expect(find.text('€179.99'), findsOneWidget);
    expect(find.text('€17.99/year'), findsNothing);
    expect(find.text('€2.99/month'), findsNothing);
    expect(find.textContaining('First 3 months'), findsNothing);
    expect(find.textContaining('Then €34.99'), findsNothing);
    expect(
      find.byKey(const ValueKey('billing-plan-pomodoist.pro.lifetime.launch')),
      findsNothing,
    );
  });

  testWidgets(r'24-hour offer shows subscription promo prices everywhere', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          billingStoreProvider.overrideWithValue(
            _FakeBillingStore(eligibleProductIds: const {}),
          ),
          applePurchasesSupportedProvider.overrideWithValue(true),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: BillingPaywall(launchOfferMode: true),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final annual = find.byKey(
      const ValueKey('billing-plan-pomodoist.pro.annual'),
    );
    expect(
      find.descendant(of: annual, matching: find.text(r'$19/year')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: annual, matching: find.text(r'$39/year')),
      findsOneWidget,
    );
    final monthly = find.byKey(
      const ValueKey('billing-plan-pomodoist.pro.monthly'),
    );
    expect(
      find.descendant(of: monthly, matching: find.text(r'$2.99/month')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: monthly, matching: find.text(r'$5.99/month')),
      findsOneWidget,
    );
  });

  test('promo offer repeats for 24 hours every 7 days', () {
    final startedAt = DateTime.utc(2026, 1, 1, 10);

    expect(
      launchOfferRemaining(
        now: DateTime.utc(2026, 1, 1, 10),
        startedAt: startedAt,
      ),
      const Duration(hours: 24),
    );
    expect(
      formatLaunchOfferRemaining(
        launchOfferRemaining(
          now: DateTime.utc(2026, 1, 2, 9, 59, 59),
          startedAt: startedAt,
        ),
      ),
      '00:00:01',
    );
    expect(
      launchOfferRemaining(
        now: DateTime.utc(2026, 1, 2, 10),
        startedAt: startedAt,
      ),
      Duration.zero,
    );
    expect(
      launchOfferRemaining(
        now: DateTime.utc(2026, 1, 8, 10),
        startedAt: startedAt,
      ),
      const Duration(hours: 24),
    );
    expect(
      launchOfferRemaining(
        now: DateTime.utc(2026, 1, 15, 10),
        startedAt: startedAt,
      ),
      const Duration(hours: 24),
    );
    expect(
      launchOfferRemaining(
        now: DateTime.utc(2026, 1, 1, 9, 59, 59),
        startedAt: startedAt,
      ),
      Duration.zero,
    );
  });

  test(
    'promo offer keeps its original anchor across months and years',
    () async {
      final januaryStart = DateTime.utc(2026, 1, 1, 10);
      SharedPreferences.setMockInitialValues({
        launchOfferStartedAtPreferenceKey: januaryStart.toIso8601String(),
      });
      final container = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(
            FixedClock(DateTime.utc(2026, 1, 2, 11)),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(onboardingControllerProvider);
      await _settle();

      var prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(launchOfferStartedAtPreferenceKey),
        januaryStart.toIso8601String(),
      );

      final nextYear = DateTime.utc(2027, 2, 1, 8);
      SharedPreferences.setMockInitialValues({
        launchOfferStartedAtPreferenceKey: januaryStart.toIso8601String(),
      });
      final nextYearContainer = ProviderContainer(
        overrides: [clockProvider.overrideWithValue(FixedClock(nextYear))],
      );
      addTearDown(nextYearContainer.dispose);

      nextYearContainer.read(onboardingControllerProvider);
      await _settle();

      prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(launchOfferStartedAtPreferenceKey),
        januaryStart.toIso8601String(),
      );
    },
  );

  test('billing controller stores a purchased entitlement', () async {
    final store = _FakeBillingStore();
    final container = ProviderContainer(
      overrides: [
        billingStoreProvider.overrideWithValue(store),
        applePurchasesSupportedProvider.overrideWithValue(true),
      ],
    );
    addTearDown(container.dispose);

    container.read(billingControllerProvider);
    await _settle();
    expect(container.read(billingControllerProvider).storeAvailable, isTrue);

    await container
        .read(billingControllerProvider.notifier)
        .purchase(pomodoistAnnualProductId);
    await _settle();

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(billingActiveProductIdPreferenceKey),
      pomodoistAnnualProductId,
    );
    expect(store.completedProductIds, [pomodoistAnnualProductId]);
    expect(
      container.read(billingControllerProvider).hasActiveEntitlement,
      isTrue,
    );
    expect(
      container.read(billingControllerProvider).purchaseSuccessProductId,
      pomodoistAnnualProductId,
    );

    container.read(billingControllerProvider.notifier).clearPurchaseSuccess();
    expect(
      container.read(billingControllerProvider).purchaseSuccessProductId,
      isNull,
    );
    expect(
      container.read(billingControllerProvider).hasActiveEntitlement,
      isTrue,
    );
  });

  test(
    'local StoreKit define activates entitlement through billing store',
    () async {
      if (!pomodoistLocalStoreKit) {
        return;
      }
      final container = ProviderContainer(
        overrides: [applePurchasesSupportedProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      container.read(billingControllerProvider);
      await _settle();

      expect(container.read(billingControllerProvider).storeAvailable, isTrue);
      expect(
        container
            .read(billingControllerProvider)
            .productDetailsById[pomodoistLifetimeLaunchProductId]
            ?.price,
        r'$89',
      );

      await container
          .read(billingControllerProvider.notifier)
          .purchase(pomodoistLifetimeLaunchProductId);
      await _settle();

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(billingActiveProductIdPreferenceKey),
        pomodoistLifetimeLaunchProductId,
      );
      expect(
        container.read(billingControllerProvider).hasActiveEntitlement,
        isTrue,
      );
      expect(
        container.read(billingControllerProvider).purchaseSuccessProductId,
        pomodoistLifetimeLaunchProductId,
      );
      container.read(billingControllerProvider.notifier).clearPurchaseSuccess();
      expect(
        container.read(billingControllerProvider).purchaseSuccessProductId,
        isNull,
      );
      expect(
        container.read(billingControllerProvider).hasActiveEntitlement,
        isTrue,
      );
    },
  );

  test('billing controller unlocks lifetime products', () async {
    for (final productId in [
      pomodoistLifetimeProductId,
      pomodoistLifetimeLaunchProductId,
    ]) {
      SharedPreferences.setMockInitialValues({});
      final store = _FakeBillingStore();
      final container = ProviderContainer(
        overrides: [
          billingStoreProvider.overrideWithValue(store),
          applePurchasesSupportedProvider.overrideWithValue(true),
        ],
      );
      addTearDown(container.dispose);

      container.read(billingControllerProvider);
      await _settle();
      await container
          .read(billingControllerProvider.notifier)
          .purchase(productId);
      await _settle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(billingActiveProductIdPreferenceKey), productId);
      expect(store.completedProductIds, [productId]);
      expect(
        container.read(billingControllerProvider).hasActiveEntitlement,
        isTrue,
      );
    }
  });

  test('dev unlock grants entitlement without storing prefs', () async {
    final store = _FakeBillingStore();
    final container = ProviderContainer(
      overrides: [
        billingStoreProvider.overrideWithValue(store),
        applePurchasesSupportedProvider.overrideWithValue(true),
      ],
    );
    addTearDown(container.dispose);

    container.read(billingControllerProvider);
    await _settle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(billingActiveProductIdPreferenceKey), isNull);
    expect(
      container.read(billingControllerProvider).activeProductId,
      pomodoistDevUnlock ? pomodoistLifetimeProductId : isNull,
    );
    expect(
      container.read(billingControllerProvider).hasActiveEntitlement,
      pomodoistDevUnlock,
    );
  });

  test(
    'billing controller restores entitlement without account sign-in',
    () async {
      final store = _FakeBillingStore(
        restoredProductId: pomodoistLifetimeLaunchProductId,
      );
      final container = ProviderContainer(
        overrides: [
          accountClientProvider.overrideWithValue(null),
          billingStoreProvider.overrideWithValue(store),
          applePurchasesSupportedProvider.overrideWithValue(true),
        ],
      );
      addTearDown(container.dispose);

      container.read(billingControllerProvider);
      await _settle();

      await container
          .read(billingControllerProvider.notifier)
          .restorePurchases();
      await _settle();

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(billingActiveProductIdPreferenceKey),
        pomodoistLifetimeLaunchProductId,
      );
      expect(store.completedProductIds, [pomodoistLifetimeLaunchProductId]);
      expect(
        container.read(billingControllerProvider).hasActiveEntitlement,
        isTrue,
      );
      expect(
        container.read(billingControllerProvider).purchaseSuccessProductId,
        pomodoistLifetimeLaunchProductId,
      );
      container.read(billingControllerProvider.notifier).clearPurchaseSuccess();
      expect(
        container.read(billingControllerProvider).purchaseSuccessProductId,
        isNull,
      );
      expect(
        container.read(billingControllerProvider).hasActiveEntitlement,
        isTrue,
      );
    },
  );

  test('billing catalog timeout clears loading state', () async {
    final container = ProviderContainer(
      overrides: [
        billingStoreProvider.overrideWithValue(_SlowBillingStore()),
        applePurchasesSupportedProvider.overrideWithValue(true),
        billingStoreTimeoutProvider.overrideWithValue(
          const Duration(milliseconds: 10),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(billingControllerProvider);
    await _waitFor(
      () => !container.read(billingControllerProvider).loading,
      'billing catalog timeout',
    );

    final state = container.read(billingControllerProvider);
    expect(state.loading, isFalse);
    expect(state.storeAvailable, isFalse);
    expect(state.error, contains('TimeoutException'));
  });

  test('restore without purchase events clears restoring state', () async {
    final store = _FakeBillingStore(emitRestore: false);
    final container = ProviderContainer(
      overrides: [
        billingStoreProvider.overrideWithValue(store),
        applePurchasesSupportedProvider.overrideWithValue(true),
        billingStoreTimeoutProvider.overrideWithValue(
          const Duration(milliseconds: 10),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(billingControllerProvider);
    await _settle();

    await container.read(billingControllerProvider.notifier).restorePurchases();

    expect(container.read(billingControllerProvider).restoring, isFalse);
  });

  test('restore timeout clears restoring state and reports error', () async {
    final container = ProviderContainer(
      overrides: [
        billingStoreProvider.overrideWithValue(_HangingRestoreBillingStore()),
        applePurchasesSupportedProvider.overrideWithValue(true),
        billingStoreTimeoutProvider.overrideWithValue(
          const Duration(milliseconds: 10),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(billingControllerProvider);
    await _settle();

    await container.read(billingControllerProvider.notifier).restorePurchases();

    final state = container.read(billingControllerProvider);
    expect(state.restoring, isFalse);
    expect(state.error, contains('TimeoutException'));
  });

  test('purchase watchdog clears a purchase with no terminal event', () async {
    final store = _FakeBillingStore(emitPurchase: false);
    final container = ProviderContainer(
      overrides: [
        billingStoreProvider.overrideWithValue(store),
        applePurchasesSupportedProvider.overrideWithValue(true),
        billingPurchaseTimeoutProvider.overrideWithValue(
          const Duration(milliseconds: 10),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(billingControllerProvider);
    await _settle();

    await container
        .read(billingControllerProvider.notifier)
        .purchase(pomodoistAnnualProductId);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final state = container.read(billingControllerProvider);
    expect(state.pendingProductId, isNull);
    expect(state.error, contains('timed out'));
  });

  test('purchase request timeout clears pending product', () async {
    final container = ProviderContainer(
      overrides: [
        billingStoreProvider.overrideWithValue(_HangingPurchaseBillingStore()),
        applePurchasesSupportedProvider.overrideWithValue(true),
        billingPurchaseTimeoutProvider.overrideWithValue(
          const Duration(milliseconds: 10),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(billingControllerProvider);
    await _settle();

    await container
        .read(billingControllerProvider.notifier)
        .purchase(pomodoistAnnualProductId);

    final state = container.read(billingControllerProvider);
    expect(state.pendingProductId, isNull);
    expect(state.error, contains('timed out'));
  });

  test('StoreKit user cancellation clears purchase without an error', () async {
    final container = ProviderContainer(
      overrides: [
        billingStoreProvider.overrideWithValue(
          _CancelledPurchaseBillingStore(),
        ),
        applePurchasesSupportedProvider.overrideWithValue(true),
      ],
    );
    addTearDown(container.dispose);
    container.read(billingControllerProvider);
    await _settle();

    await container
        .read(billingControllerProvider.notifier)
        .purchase(pomodoistAnnualProductId);

    final state = container.read(billingControllerProvider);
    expect(state.pendingProductId, isNull);
    expect(state.error, isNull);
  });

  test('terminal purchase event cancels the purchase watchdog', () async {
    final store = _FakeBillingStore();
    final container = ProviderContainer(
      overrides: [
        billingStoreProvider.overrideWithValue(store),
        applePurchasesSupportedProvider.overrideWithValue(true),
        billingPurchaseTimeoutProvider.overrideWithValue(
          const Duration(milliseconds: 10),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(billingControllerProvider);
    await _settle();

    await container
        .read(billingControllerProvider.notifier)
        .purchase(pomodoistAnnualProductId);
    await _settle();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final state = container.read(billingControllerProvider);
    expect(state.pendingProductId, isNull);
    expect(state.activeProductId, pomodoistAnnualProductId);
    expect(state.error, isNull);
  });

  test('unrelated restored product keeps current purchase watchdog', () async {
    final store = _FakeBillingStore(emitPurchase: false);
    final container = ProviderContainer(
      overrides: [
        billingStoreProvider.overrideWithValue(store),
        applePurchasesSupportedProvider.overrideWithValue(true),
        billingPurchaseTimeoutProvider.overrideWithValue(
          const Duration(milliseconds: 30),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(billingControllerProvider);
    await _settle();

    await container
        .read(billingControllerProvider.notifier)
        .purchase(pomodoistAnnualProductId);
    store.emit([
      _purchase(pomodoistLifetimeProductId, PurchaseStatus.restored),
    ]);
    await _settle();

    expect(
      container.read(billingControllerProvider).pendingProductId,
      pomodoistAnnualProductId,
    );
    await Future<void>.delayed(const Duration(milliseconds: 40));
    final state = container.read(billingControllerProvider);
    expect(state.pendingProductId, isNull);
    expect(state.error, contains('timed out'));
    expect(state.activeProductId, pomodoistLifetimeProductId);
  });

  testWidgets('onboarding supports back, settings, paywall, and mini timer', (
    tester,
  ) async {
    final clock = FixedClock(DateTime.utc(2026, 1, 1, 10));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          billingStoreProvider.overrideWithValue(_FakeBillingStore()),
          applePurchasesSupportedProvider.overrideWithValue(true),
          clockProvider.overrideWithValue(clock),
        ],
        child: const _OnboardingHarness(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('onboarding-step-language')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('onboarding-close-button')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('onboarding-next-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboarding-next-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('onboarding-step-timer')), findsOneWidget);
    expect(find.byKey(const Key('onboarding-close-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding-back-button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('onboarding-step-language')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('onboarding-next-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bar'));
    await tester.pumpAndSettle();
    expect(
      (await SharedPreferences.getInstance()).getString(
        focusTimerVisualStylePreferenceKey,
      ),
      FocusTimerVisualStyle.bar.storageValue,
    );

    await tester.tap(find.byKey(const Key('onboarding-next-button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('onboarding-step-paywall')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('onboarding-close-button')), findsOneWidget);
    expect(find.text('Pomodoist Pro'), findsOneWidget);
    final subtitleFinder = find.byWidgetPredicate(
      (widget) =>
          widget is RichText &&
          widget.text.toPlainText() ==
              'Dictate tasks in natural language, and Pomodoist turns your '
                  'words into tasks. Task history is saved forever.',
    );
    expect(subtitleFinder, findsOneWidget);
    final subtitleText =
        tester.widget<RichText>(subtitleFinder).text as TextSpan;
    final highlightedSubtitleSpan = _findTextSpan(
      subtitleText,
      'natural language',
    )!;
    expect(highlightedSubtitleSpan.style?.fontWeight, FontWeight.w800);
    expect(find.text('Cancel anytime.'), findsOneWidget);
    final annualPlan = find.byKey(
      const ValueKey('billing-plan-pomodoist.pro.annual'),
    );
    expect(annualPlan, findsOneWidget);
    expect(
      find.byKey(const ValueKey('billing-plan-pomodoist.pro.monthly')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('billing-plan-pomodoist.pro.lifetime')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('billing-plan-pomodoist.pro.lifetime.full')),
      findsNothing,
    );
    final launchPlan = find.byKey(
      const ValueKey('billing-plan-pomodoist.pro.lifetime.launch'),
    );
    expect(launchPlan, findsOneWidget);
    expect(
      find.descendant(of: annualPlan, matching: find.text('Best value')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: launchPlan, matching: find.text('Best value')),
      findsNothing,
    );
    expect(
      find.descendant(of: launchPlan, matching: find.text('24:00:00')),
      findsOneWidget,
    );
    final comparePrice = find.descendant(
      of: launchPlan,
      matching: find.byKey(
        const ValueKey('billing-compare-pomodoist.pro.lifetime.launch'),
      ),
    );
    expect(comparePrice, findsOneWidget);
    expect(
      tester.widget<Text>(comparePrice).style?.decoration,
      TextDecoration.lineThrough,
    );
    expect(
      find.descendant(of: launchPlan, matching: find.text(r'$99')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: launchPlan, matching: find.text(r'$89')),
      findsOneWidget,
    );
    final annualComparePrice = find.descendant(
      of: annualPlan,
      matching: find.byKey(
        const ValueKey('billing-compare-pomodoist.pro.annual'),
      ),
    );
    expect(annualComparePrice, findsOneWidget);
    expect(
      tester.widget<Text>(annualComparePrice).style?.decoration,
      TextDecoration.lineThrough,
    );
    expect(
      find.descendant(of: annualPlan, matching: find.text(r'$39/year')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: annualPlan, matching: find.text(r'$19/year')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: annualPlan, matching: find.text(r'Then $39/year.')),
      findsOneWidget,
    );
    expect(find.textContaining('trial'), findsNothing);
    expect(find.byKey(const Key('launch-offer-countdown')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('onboarding-next-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboarding-next-button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('onboarding-step-account')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('onboarding-close-button')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('onboarding-next-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboarding-next-button')));
    await tester.pumpAndSettle();
    expect(
      (await SharedPreferences.getInstance()).getBool(
        onboardingCompletedPreferenceKey,
      ),
      isTrue,
    );
    if (pomodoistDevUnlock) {
      expect(find.byKey(const Key('launch-offer-mini-window')), findsNothing);
      return;
    }
    expect(find.byKey(const Key('launch-offer-mini-window')), findsOneWidget);

    await tester.tap(find.byKey(const Key('launch-offer-mini-window')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('billing-paywall')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('billing-plan-pomodoist.pro.annual.launch')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('billing-plan-pomodoist.pro.annual')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('billing-plan-pomodoist.pro.lifetime')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('billing-plan-pomodoist.pro.lifetime.full')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('billing-plan-pomodoist.pro.lifetime.launch')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('billing-compare-pomodoist.pro.annual')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('billing-compare-pomodoist.pro.lifetime')),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey('billing-compare-pomodoist.pro.lifetime.launch'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('billing-paywall-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('billing-paywall')), findsNothing);

    await tester.tap(find.byKey(const Key('launch-offer-mini-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('launch-offer-mini-window')), findsNothing);

    clock.value = DateTime.utc(2026, 1, 8, 10);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const Key('launch-offer-mini-window')), findsOneWidget);
  });

  testWidgets('expired Lifetime offer shows regular Lifetime in onboarding', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      launchOfferStartedAtPreferenceKey: DateTime.utc(
        2026,
        1,
        1,
        10,
      ).toIso8601String(),
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          billingStoreProvider.overrideWithValue(_FakeBillingStore()),
          applePurchasesSupportedProvider.overrideWithValue(true),
          clockProvider.overrideWithValue(
            FixedClock(DateTime.utc(2026, 1, 2, 11)),
          ),
        ],
        child: const _OnboardingHarness(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('onboarding-next-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboarding-next-button')));
    await tester.pumpAndSettle();

    final annualPlan = find.byKey(
      const ValueKey('billing-plan-pomodoist.pro.annual'),
    );
    expect(annualPlan, findsOneWidget);
    expect(
      find.descendant(of: annualPlan, matching: find.text(r'$19/year')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('billing-plan-pomodoist.pro.lifetime')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('billing-plan-pomodoist.pro.lifetime.full')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('billing-plan-pomodoist.pro.lifetime.launch')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('billing-plan-pomodoist.pro.annual.launch')),
      findsNothing,
    );
    expect(find.byKey(const Key('launch-offer-countdown')), findsNothing);
    expect(
      find.byKey(const ValueKey('billing-compare-pomodoist.pro.annual.launch')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('billing-compare-pomodoist.pro.annual')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('billing-compare-pomodoist.pro.lifetime')),
      findsNothing,
    );
  });

  testWidgets('onboarding language can be selected and wizard can close', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          billingStoreProvider.overrideWithValue(_FakeBillingStore()),
          applePurchasesSupportedProvider.overrideWithValue(true),
          clockProvider.overrideWithValue(FixedClock(DateTime.utc(2026))),
        ],
        child: const _OnboardingHarness(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('onboarding-language-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Русский').last);
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(appLanguagePreferenceKey),
      AppLanguage.ru.storageValue,
    );

    await tester.tap(find.byKey(const Key('onboarding-close-button')));
    await tester.pumpAndSettle();

    expect(prefs.getBool(onboardingCompletedPreferenceKey), isTrue);
    expect(
      find.byKey(const ValueKey('onboarding-step-language')),
      findsNothing,
    );
  });

  testWidgets('expired promo offer does not show mini timer', (tester) async {
    SharedPreferences.setMockInitialValues({
      onboardingCompletedPreferenceKey: true,
      launchOfferStartedAtPreferenceKey: DateTime.utc(
        2026,
        1,
        1,
        10,
      ).toIso8601String(),
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          billingStoreProvider.overrideWithValue(_FakeBillingStore()),
          applePurchasesSupportedProvider.overrideWithValue(true),
          clockProvider.overrideWithValue(
            FixedClock(DateTime.utc(2026, 1, 2, 11)),
          ),
        ],
        child: const _OnboardingHarness(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('launch-offer-mini-window')), findsNothing);
  });

  testWidgets('active Pro suppresses the weekly mini offer', (tester) async {
    final startedAt = DateTime.utc(2026, 1, 1, 10);
    SharedPreferences.setMockInitialValues({
      onboardingCompletedPreferenceKey: true,
      launchOfferStartedAtPreferenceKey: startedAt.toIso8601String(),
      billingActiveProductIdPreferenceKey: pomodoistLifetimeProductId,
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          billingStoreProvider.overrideWithValue(_FakeBillingStore()),
          applePurchasesSupportedProvider.overrideWithValue(true),
          billingAccountEntitlementProvider.overrideWithValue(true),
          clockProvider.overrideWithValue(FixedClock(startedAt)),
        ],
        child: const _OnboardingHarness(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('launch-offer-mini-window')), findsNothing);
  });

  testWidgets('settings changes only Lifetime during the promo window', (
    tester,
  ) async {
    final startedAt = DateTime.utc(2026, 1, 1, 10);
    final clock = FixedClock(startedAt);
    SharedPreferences.setMockInitialValues({
      launchOfferStartedAtPreferenceKey: startedAt.toIso8601String(),
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          billingStoreProvider.overrideWithValue(_FakeBillingStore()),
          applePurchasesSupportedProvider.overrideWithValue(true),
          clockProvider.overrideWithValue(clock),
          pomodoistDeviceIdProvider.overrideWith((ref) async => 'device-1'),
          googleCalendarConnectionProvider.overrideWith(
            (ref) => Stream.value(null),
          ),
        ],
        child: const _SettingsHarness(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('billing-plan-pomodoist.pro.monthly')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('billing-plan-pomodoist.pro.annual')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('billing-plan-pomodoist.pro.annual.launch')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('billing-plan-pomodoist.pro.lifetime')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('billing-plan-pomodoist.pro.lifetime.full')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('billing-plan-pomodoist.pro.lifetime.launch')),
      findsOneWidget,
    );

    clock.value = startedAt.add(const Duration(hours: 25));
    await tester.pump(const Duration(seconds: 1));

    expect(
      find.byKey(const ValueKey('billing-plan-pomodoist.pro.annual.launch')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('billing-plan-pomodoist.pro.lifetime.launch')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('billing-plan-pomodoist.pro.annual')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('billing-plan-pomodoist.pro.lifetime')),
      findsOneWidget,
    );
  });

  testWidgets('settings collapses active Pro paywall until header tap', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      billingActiveProductIdPreferenceKey: pomodoistLifetimeProductId,
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          billingStoreProvider.overrideWithValue(_FakeBillingStore()),
          applePurchasesSupportedProvider.overrideWithValue(true),
          billingAccountEntitlementProvider.overrideWithValue(true),
          pomodoistDeviceIdProvider.overrideWith((ref) async => 'device-1'),
          googleCalendarConnectionProvider.overrideWith(
            (ref) => Stream.value(null),
          ),
        ],
        child: const _SettingsHarness(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Pomodoist Pro is active on this device.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('billing-plan-pomodoist.pro.monthly')),
      findsNothing,
    );
    expect(find.byKey(const Key('billing-restore-button')), findsNothing);

    await tester.tap(find.byKey(const Key('billing-pro-header')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('billing-plan-pomodoist.pro.monthly')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('billing-restore-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('billing-paywall-close')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('billing-plan-pomodoist.pro.monthly')),
      findsNothing,
    );
    expect(find.byKey(const Key('billing-restore-button')), findsNothing);
  });

  testWidgets('Stripe subscription shows Link management without restore', (
    tester,
  ) async {
    Uri? openedUrl;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          billingChannelProvider.overrideWithValue(BillingChannel.stripe),
          billingSignedInProvider.overrideWithValue(true),
          billingActiveAccountEntitlementProvider.overrideWithValue(
            const AccountEntitlement(
              appId: AccountAppId.pomodoist,
              entitlementId: 'stripe:sub_test',
              status: 'active',
              purchaseType: 'subscription',
              source: 'stripe',
              store: 'stripe',
            ),
          ),
          billingStripeGatewayProvider.overrideWithValue(
            BillingStripeGateway(
              loadCatalog: () async => const StripeBillingCatalog(
                enabled: true,
                introEligible: false,
                launchOfferEligible: false,
                launchOfferEndsAt: null,
              ),
              createCheckout: (_, _) => throw UnimplementedError(),
              openCheckout: (url) async {
                openedUrl = url;
                return true;
              },
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: BillingPaywall()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('billing-manage-link')), findsOneWidget);
    expect(find.byKey(const Key('billing-restore-button')), findsNothing);
    await tester.tap(find.byKey(const Key('billing-manage-link')));
    await tester.pump();
    expect(openedUrl, Uri.parse('https://link.com'));
  });

  testWidgets('settings may be disposed while sign-out is pending', (
    tester,
  ) async {
    final pending = Completer<void>();
    var calls = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          billingStoreProvider.overrideWithValue(_FakeBillingStore()),
          applePurchasesSupportedProvider.overrideWithValue(true),
          accountOverviewProvider.overrideWith(
            (ref) async => AccountOverview.empty('user-1'),
          ),
          googleCalendarConnectionProvider.overrideWith(
            (ref) => Stream.value(null),
          ),
        ],
        child: _SettingsHarness(
          signOutOverride: () {
            calls += 1;
            return pending.future;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final signOut = find.byKey(const Key('account-sign-out-button'));
    await tester.ensureVisible(signOut);
    await tester.tap(signOut);
    await tester.pump();
    expect(calls, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('paywall shows plans while StoreKit products are loading', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          billingStoreProvider.overrideWithValue(_SlowBillingStore()),
          applePurchasesSupportedProvider.overrideWithValue(true),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: BillingPaywall(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(
      find.byKey(const ValueKey('billing-plan-pomodoist.pro.monthly')),
      findsOneWidget,
    );
    expect(find.text(r'$5.99/month'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('billing-buy-pomodoist.pro.monthly')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('buying from settings opens success route and returns', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      onboardingCompletedPreferenceKey: true,
      launchOfferStartedAtPreferenceKey: DateTime.utc(
        2026,
        1,
        1,
      ).toIso8601String(),
    });
    late GoRouter router;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          billingStoreProvider.overrideWithValue(_FakeBillingStore()),
          applePurchasesSupportedProvider.overrideWithValue(true),
          pomodoistDeviceIdProvider.overrideWith((ref) async => 'device-1'),
          googleCalendarConnectionProvider.overrideWith(
            (ref) => Stream.value(null),
          ),
        ],
        child: _SettingsRouterHarness(onRouter: (value) => router = value),
      ),
    );
    await tester.pumpAndSettle();

    final buyButton = find.byKey(
      const ValueKey('billing-buy-pomodoist.pro.monthly'),
    );
    await tester.ensureVisible(buyButton);
    await tester.pumpAndSettle();
    await tester.tap(buyButton);
    await tester.pumpAndSettle();

    expect(_routerUri(router), '/purchase-success?returnTo=%2Fsettings');
    expect(find.byKey(const Key('purchase-success-title')), findsOneWidget);

    await tester.tap(find.byKey(const Key('purchase-success-continue')));
    await tester.pumpAndSettle();

    expect(_routerUri(router), '/settings');
  });

  testWidgets('Stripe success waits for the server entitlement', (
    tester,
  ) async {
    var refreshes = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          billingEntitlementRefresherProvider.overrideWithValue(() async {
            refreshes += 1;
            return refreshes >= 3;
          }),
          billingStripePollIntervalProvider.overrideWithValue(Duration.zero),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const PurchaseSuccessScreen(
            returnTo: '/today',
            source: 'stripe',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(refreshes, 3);
    expect(find.byKey(const Key('purchase-success-title')), findsOneWidget);
    expect(find.byKey(const Key('purchase-processing-title')), findsNothing);
  });

  testWidgets('purchase success continues onboarding from paywall', (
    tester,
  ) async {
    late GoRouter router;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          billingStoreProvider.overrideWithValue(_FakeBillingStore()),
          applePurchasesSupportedProvider.overrideWithValue(true),
          clockProvider.overrideWithValue(FixedClock(DateTime.utc(2026))),
        ],
        child: _OnboardingRouterHarness(onRouter: (value) => router = value),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('onboarding-next-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboarding-next-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('onboarding-step-paywall')),
      findsOneWidget,
    );

    final buyButton = find.byKey(
      const ValueKey('billing-buy-pomodoist.pro.monthly'),
    );
    await tester.ensureVisible(buyButton);
    await tester.pumpAndSettle();
    await tester.tap(buyButton);
    await tester.pumpAndSettle();

    expect(_routerUri(router), '/purchase-success?returnTo=%2Ftoday');
    await tester.tap(find.byKey(const Key('purchase-success-continue')));
    await tester.pumpAndSettle();

    expect(_routerUri(router), '/today');
    expect(
      find.byKey(const ValueKey('onboarding-step-account')),
      findsOneWidget,
    );
  });
}

TextSpan? _findTextSpan(InlineSpan span, String text) {
  if (span is! TextSpan) {
    return null;
  }
  if (span.text == text) {
    return span;
  }
  for (final child in span.children ?? const <InlineSpan>[]) {
    final match = _findTextSpan(child, text);
    if (match != null) {
      return match;
    }
  }
  return null;
}

Future<void> _settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

Future<void> _waitFor(bool Function() condition, String description) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for $description.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class _FakeBillingStore extends BillingStore {
  _FakeBillingStore({
    this.restoredProductId = pomodoistAnnualProductId,
    this.emitPurchase = true,
    this.emitRestore = true,
    this.eligibleProductIds = const {
      pomodoistAnnualProductId,
      pomodoistMonthlyProductId,
    },
    this.eligibilityErrorProductIds = const {},
    this.productDetailsById = const {},
    this.refreshedProductIds = const {},
    this.completeError,
  }) : super();

  final _controller = StreamController<List<PurchaseDetails>>.broadcast();
  final completedProductIds = <String>[];
  final String restoredProductId;
  final bool emitPurchase;
  final bool emitRestore;
  final Set<String> eligibleProductIds;
  final Set<String> eligibilityErrorProductIds;
  final Map<String, ProductDetails> productDetailsById;
  final Set<String> refreshedProductIds;
  final Object? completeError;
  final eligibilityChecks = <String>{};
  var refreshCount = 0;
  var restoreCount = 0;
  String? lastAppAccountToken;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _controller.stream;

  void emit(List<PurchaseDetails> purchases) => _controller.add(purchases);

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> isIntroductoryOfferEligible(String productId) async {
    eligibilityChecks.add(productId);
    if (eligibilityErrorProductIds.contains(productId)) {
      throw StateError('eligibility unavailable');
    }
    return eligibleProductIds.contains(productId);
  }

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> productIds) {
    return Future.value(
      ProductDetailsResponse(
        productDetails: [
          for (final plan in billingPlans)
            productDetailsById[plan.productId] ??
                ProductDetails(
                  id: plan.productId,
                  title: plan.productId,
                  description: plan.productId,
                  price: plan.fallbackPrice,
                  rawPrice: 1,
                  currencyCode: 'USD',
                  currencySymbol: r'$',
                ),
        ],
        notFoundIDs: const [],
      ),
    );
  }

  @override
  Future<bool> buy(
    ProductDetails productDetails, {
    String? appAccountToken,
  }) async {
    lastAppAccountToken = appAccountToken;
    if (emitPurchase) {
      final purchase = _purchase(productDetails.id, PurchaseStatus.purchased);
      purchase.pendingCompletePurchase = true;
      _controller.add([purchase]);
    }
    return true;
  }

  @override
  Future<void> restorePurchases() async {
    restoreCount += 1;
    if (emitRestore) {
      final purchase = _purchase(restoredProductId, PurchaseStatus.restored);
      purchase.pendingCompletePurchase = true;
      _controller.add([purchase]);
    }
  }

  @override
  Future<void> refreshCurrentEntitlements() async {
    refreshCount += 1;
    if (refreshedProductIds.isNotEmpty) {
      _controller.add([
        for (final productId in refreshedProductIds)
          _purchase(productId, PurchaseStatus.restored),
      ]);
    }
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    final error = completeError;
    if (error != null) throw error;
    completedProductIds.add(purchase.productID);
  }
}

Map<String, ProductDetails> _euroBillingProducts() {
  return {
    pomodoistAnnualProductId: _storeKitSubscription(
      productId: pomodoistAnnualProductId,
      price: 34.99,
      displayPrice: '€34.99',
      introductoryPrice: 17.99,
      period: SK2SubscriptionPeriodUnit.year,
      paymentMode: SK2SubscriptionOfferPaymentMode.payUpFront,
    ),
    pomodoistMonthlyProductId: _storeKitSubscription(
      productId: pomodoistMonthlyProductId,
      price: 5.99,
      displayPrice: '€5.99',
      introductoryPrice: 2.99,
      period: SK2SubscriptionPeriodUnit.month,
      paymentMode: SK2SubscriptionOfferPaymentMode.payAsYouGo,
      introductoryPeriodCount: 3,
    ),
    pomodoistLifetimeProductId: _product(
      pomodoistLifetimeProductId,
      '€179.99',
      179.99,
    ),
    pomodoistLifetimeLaunchProductId: _product(
      pomodoistLifetimeLaunchProductId,
      '€89.99',
      89.99,
    ),
  };
}

ProductDetails _storeKitSubscription({
  required String productId,
  required double price,
  required String displayPrice,
  required double introductoryPrice,
  required SK2SubscriptionPeriodUnit period,
  required SK2SubscriptionOfferPaymentMode paymentMode,
  int introductoryPeriodCount = 1,
}) {
  return AppStoreProduct2Details.fromSK2Product(
    SK2Product(
      id: productId,
      displayName: productId,
      displayPrice: displayPrice,
      description: productId,
      price: price,
      type: SK2ProductType.autoRenewable,
      priceLocale: SK2PriceLocale(currencyCode: 'EUR', currencySymbol: '€'),
      subscription: SK2SubscriptionInfo(
        subscriptionGroupID: 'pomodoist-pro',
        promotionalOffers: [
          SK2SubscriptionOffer(
            price: introductoryPrice,
            type: SK2SubscriptionOfferType.introductory,
            period: SK2SubscriptionPeriod(value: 1, unit: period),
            periodCount: introductoryPeriodCount,
            paymentMode: paymentMode,
          ),
        ],
        subscriptionPeriod: SK2SubscriptionPeriod(value: 1, unit: period),
      ),
    ),
  );
}

ProductDetails _product(String id, String price, double rawPrice) {
  return ProductDetails(
    id: id,
    title: id,
    description: id,
    price: price,
    rawPrice: rawPrice,
    currencyCode: 'EUR',
    currencySymbol: '€',
  );
}

class _SlowBillingStore extends BillingStore {
  _SlowBillingStore() : super();

  final _controller = StreamController<List<PurchaseDetails>>.broadcast();
  final _products = Completer<ProductDetailsResponse>();

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _controller.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> productIds) {
    return _products.future;
  }
}

class _HangingRestoreBillingStore extends _FakeBillingStore {
  @override
  Future<void> restorePurchases() => Completer<void>().future;
}

class _HangingPurchaseBillingStore extends _FakeBillingStore {
  @override
  Future<bool> buy(ProductDetails productDetails, {String? appAccountToken}) =>
      Completer<bool>().future;
}

class _CancelledPurchaseBillingStore extends _FakeBillingStore {
  @override
  Future<bool> buy(ProductDetails productDetails, {String? appAccountToken}) =>
      Future.error(PlatformException(code: 'userCancelled'));
}

final _fakeAccountEntitlementProvider =
    NotifierProvider<_FakeEntitlementController, bool>(
      _FakeEntitlementController.new,
    );

class _FakeEntitlementController extends Notifier<bool> {
  @override
  bool build() => false;

  void setActive(bool value) => state = value;
}

final _fakeSignedInProvider = NotifierProvider<_FakeBoolController, bool>(
  _FakeBoolController.new,
);
final _fakeOverviewTokenProvider =
    NotifierProvider<_FakeObjectController, Object?>(_FakeObjectController.new);

class _FakeBoolController extends Notifier<bool> {
  @override
  bool build() => false;

  void setValue(bool value) => state = value;
}

class _FakeObjectController extends Notifier<Object?> {
  @override
  Object? build() => null;

  void setValue(Object? value) => state = value;
}

PurchaseDetails _purchase(
  String productId,
  PurchaseStatus status, {
  String? localJson,
  String? serverJws,
}) {
  return PurchaseDetails(
    productID: productId,
    purchaseID: 'purchase-$productId',
    transactionDate: DateTime.utc(2026).millisecondsSinceEpoch.toString(),
    status: status,
    verificationData: PurchaseVerificationData(
      localVerificationData:
          localJson ??
          (billingPlanForProduct(productId)?.kind == BillingPlanKind.lifetime
              ? '{}'
              : '{"expiresDate":4102444800000}'),
      serverVerificationData: serverJws ?? 'server-$productId',
      source: 'test',
    ),
  );
}

class _OnboardingHarness extends ConsumerWidget {
  const _OnboardingHarness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(appLanguageProvider);
    final themeMode = ref.watch(appThemeModeProvider);
    return MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode.themeMode,
      locale: language.locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(
        body: OnboardingGate(child: Center(child: Text('Home'))),
      ),
    );
  }
}

class _SettingsHarness extends ConsumerWidget {
  const _SettingsHarness({this.signOutOverride});

  final Future<void> Function()? signOutOverride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsScreen(signOutOverride: signOutOverride),
    );
  }
}

class _SettingsRouterHarness extends StatelessWidget {
  const _SettingsRouterHarness({required this.onRouter});

  final ValueChanged<GoRouter> onRouter;

  @override
  Widget build(BuildContext context) {
    final router = GoRouter(
      initialLocation: '/settings',
      routes: [
        GoRoute(
          path: '/settings',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: SettingsScreen()),
        ),
        GoRoute(
          path: '/purchase-success',
          pageBuilder: (context, state) => NoTransitionPage(
            child: PurchaseSuccessScreen(
              returnTo: state.uri.queryParameters['returnTo'] ?? '/today',
            ),
          ),
        ),
      ],
    );
    onRouter(router);
    return MaterialApp.router(
      theme: AppTheme.light(),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    );
  }
}

class _OnboardingRouterHarness extends StatelessWidget {
  const _OnboardingRouterHarness({required this.onRouter});

  final ValueChanged<GoRouter> onRouter;

  @override
  Widget build(BuildContext context) {
    final router = GoRouter(
      initialLocation: '/today',
      routes: [
        GoRoute(
          path: '/today',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: Scaffold(
              body: OnboardingGate(child: Center(child: Text('Home'))),
            ),
          ),
        ),
        GoRoute(
          path: '/purchase-success',
          pageBuilder: (context, state) => NoTransitionPage(
            child: PurchaseSuccessScreen(
              returnTo: state.uri.queryParameters['returnTo'] ?? '/today',
            ),
          ),
        ),
      ],
    );
    onRouter(router);
    return MaterialApp.router(
      theme: AppTheme.light(),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    );
  }
}

String _routerUri(GoRouter router) {
  return router.routeInformationProvider.value.uri.toString();
}

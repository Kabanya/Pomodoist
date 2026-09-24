import 'package:app_account/app_account.dart';
import 'package:pomodoist/data/services/billing/account_billing_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/domain/models/billing/billing_models.dart';

void main() {
  Map<String, Object?> catalog(String kind) => {
    'enabled': true,
    'introEligible': false,
    'offersEnabled': true,
    'subscriptionOffer': kind,
    'prices': {
      pomodoistMonthlyProductId: r'$4.99',
      pomodoistAnnualProductId: r'$29.99',
    },
    'launchOffer': {'eligible': false, 'endsAt': null},
  };
  test(
    'only development transport opts in and sends the selected offer',
    () async {
      for (final develop in [false, true]) {
        final account = _BillingAccount();
        final service = AccountBillingService(
          account: account,
          stripeTestOffers: develop,
          locale: () => 'ru',
          onLinked: () {},
        );
        account.response = AccountFunctionResponse(
          status: 200,
          data: develop
              ? catalog('return')
              : {
                  ...catalog('return'),
                  'offersEnabled': false,
                  'subscriptionOffer': null,
                },
        );
        await service.loadStripeCatalog();
        expect(account.requests.last['offerVersion'], develop ? 1 : null);
        account.response = const AccountFunctionResponse(
          status: 200,
          data: {'url': 'https://checkout.stripe.com/test'},
        );
        await service.createStripeCheckout(
          pomodoistMonthlyProductId,
          BillingCheckoutSurface.web,
          develop ? 'return' : null,
        );
        expect(
          account.requests.last['selectedOffer'],
          develop ? 'return' : null,
        );
        expect(account.requests.last['offerVersion'], develop ? 1 : null);
      }
    },
  );
  test(
    'production transport rejects a test offer instead of silently omitting it',
    () async {
      final account = _BillingAccount();
      final service = AccountBillingService(
        account: account,
        locale: () => 'en',
        onLinked: () {},
      );
      account.response = AccountFunctionResponse(
        status: 200,
        data: catalog('trial'),
      );
      await expectLater(
        service.loadStripeCatalog(),
        throwsA(isA<StripeBillingException>()),
      );
      await expectLater(
        service.createStripeCheckout(
          pomodoistAnnualProductId,
          BillingCheckoutSurface.web,
          'return',
        ),
        throwsA(isA<StripeBillingException>()),
      );
      expect(account.requests.length, 1);
    },
  );
  test(
    'transport errors and changed account cannot start a replacement checkout',
    () async {
      final account = _BillingAccount();
      final service = AccountBillingService(
        account: account,
        stripeTestOffers: true,
        locale: () => 'en',
        onLinked: () {},
      );
      account.response = const AccountFunctionResponse(
        status: 409,
        data: {'code': 'offer_pending'},
      );
      await expectLater(
        service.createStripeCheckout(
          pomodoistAnnualProductId,
          BillingCheckoutSurface.web,
          'return',
        ),
        throwsA(
          isA<StripeBillingException>().having(
            (e) => e.code,
            'code',
            'offer_pending',
          ),
        ),
      );
      expect(account.requests.length, 1);
      account.userId = 'another-account';
      await expectLater(
        service.loadStripeCatalog(),
        throwsA(isA<StripeBillingException>()),
      );
      expect(account.requests.length, 1);
    },
  );
  test(
    'versioned catalog rejects unknown offers and mixed legacy introductions',
    () {
      expect(
        StripeBillingCatalog.fromJson(catalog('trial')).subscriptionOffer,
        'trial',
      );
      expect(
        () => StripeBillingCatalog.fromJson(catalog('unknown')),
        throwsFormatException,
      );
      expect(
        () => StripeBillingCatalog.fromJson({
          ...catalog('return'),
          'introEligible': true,
        }),
        throwsFormatException,
      );
      expect(
        () => StripeBillingCatalog.fromJson({
          ...catalog('return'),
          'offersEnabled': false,
        }),
        throwsFormatException,
      );
    },
  );
  test(
    'same localized presentation models express Stripe trial and return terms',
    () {
      for (final id in [pomodoistMonthlyProductId, pomodoistAnnualProductId]) {
        final trial = stripeSubscriptionOffer('trial', id)!;
        expect(trial.price, 0);
        expect(trial.periodValue, 7);
        expect(trial.periodUnit, BillingOfferPeriodUnit.day);
        expect(trial.paymentMode, BillingOfferPaymentMode.freeTrial);
        expect(stripeSubscriptionOffer('standard', id), isNull);
        expect(stripeSubscriptionOffer('blocked', id), isNull);
      }
      final monthly = stripeSubscriptionOffer(
        'return',
        pomodoistMonthlyProductId,
      )!;
      final annual = stripeSubscriptionOffer(
        'return',
        pomodoistAnnualProductId,
      )!;
      expect(monthly.price, 1.99);
      expect(monthly.periodCount, 3);
      expect(annual.price, 14.99);
      expect(annual.periodCount, 1);
      expect(annual.periodUnit, BillingOfferPeriodUnit.year);
      expect(
        stripeSubscriptionOffer('trial', pomodoistLifetimeProductId),
        isNull,
      );
    },
  );
}

class _BillingAccount extends Fake implements AccountClient {
  String userId = 'account';
  final requests = <Map<String, Object?>>[];
  AccountFunctionResponse response = const AccountFunctionResponse(status: 500);
  @override
  String? get currentUserId => userId;
  @override
  Future<AccountFunctionResponse> invokeFunction(
    String functionName, {
    Map<String, String>? headers,
    Object? body,
    Map<String, dynamic>? queryParameters,
    String? region,
  }) async {
    expect(functionName, 'pomodoist-stripe-billing');
    requests.add(Map<String, Object?>.from(body! as Map));
    return response;
  }
}

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';
import 'billing_models.dart';
import '../../l10n/app_localizations.dart';
import 'package:intl/intl.dart' as intl;

const billingReturnOfferIds = {
  pomodoistMonthlyProductId: 'return_monthly_2026_v1',
  pomodoistAnnualProductId: 'return_annual_2026_v1',
};

typedef BillingOfferRequest =
    Future<Object?> Function(Map<String, Object?> body);

class BillingOfferException implements Exception {
  const BillingOfferException(this.code, {this.retryAfter});
  final String code;
  final DateTime? retryAfter;
  @override
  String toString() => 'subscription_offer:$code';
}

class BillingReturnOffers {
  const BillingReturnOffers({
    this.transaction,
    this.offerIds = const {},
    this.retryAfter,
  });
  final String? transaction;
  final Map<String, String> offerIds;
  final DateTime? retryAfter;

  factory BillingReturnOffers.fromJson(Object? value, String transaction) {
    if (value is! Map ||
        value['eligible'] is! bool ||
        value['offerIds'] is! Map) {
      throw const FormatException('Invalid subscription offer eligibility.');
    }
    final ids = value['offerIds'] as Map;
    if (ids.entries.any((e) => billingReturnOfferIds[e.key] != e.value) ||
        (value['eligible'] == false && ids.isNotEmpty) ||
        (value['eligible'] == true && ids.isEmpty)) {
      throw const FormatException('Invalid subscription offer identifiers.');
    }
    final retryAfter = value['retryAfter'] is String
        ? DateTime.tryParse(value['retryAfter'] as String)?.toUtc()
        : null;
    if (value['code'] == 'offer_pending' && retryAfter == null) {
      throw const FormatException('Missing subscription offer retry date.');
    }
    return BillingReturnOffers(
      transaction: transaction,
      offerIds: Map<String, String>.from(ids),
      retryAfter: retryAfter,
    );
  }
}

SK2SubscriptionOffer? billingStoreKitOffer(
  ProductDetails? product, {
  bool introductoryEligible = false,
  String? returnOfferId,
}) {
  if (product is! AppStoreProduct2Details) return null;
  for (final offer
      in product.sk2Product.subscription?.promotionalOffers ??
          <SK2SubscriptionOffer>[]) {
    if (returnOfferId != null) {
      if (billingReturnOfferIds[product.id] == returnOfferId &&
          offer.id == returnOfferId &&
          offer.type == SK2SubscriptionOfferType.promotional &&
          billingReturnOfferMatchesProduct(product.id, offer)) {
        return offer;
      }
    } else if (introductoryEligible &&
        offer.type == SK2SubscriptionOfferType.introductory) {
      return offer;
    }
  }
  return null;
}

// Only advertise the configured campaign when Apple's actual terms match it.
bool billingReturnOfferMatchesProduct(
  String productId,
  SK2SubscriptionOffer offer,
) =>
    offer.price.isFinite &&
    offer.price > 0 &&
    switch (productId) {
      pomodoistMonthlyProductId =>
        offer.paymentMode == SK2SubscriptionOfferPaymentMode.payAsYouGo &&
            offer.period.unit == SK2SubscriptionPeriodUnit.month &&
            offer.period.value == 1 &&
            offer.periodCount == 3,
      pomodoistAnnualProductId =>
        offer.paymentMode == SK2SubscriptionOfferPaymentMode.payUpFront &&
            offer.period.unit == SK2SubscriptionPeriodUnit.year &&
            offer.period.value == 1 &&
            offer.periodCount == 1,
      _ => false,
    };

String billingOfferSignature(Object? value, String offerId) {
  if (value is! Map ||
      value['offerId'] != offerId ||
      value['compactJws'] is! String) {
    throw const FormatException('Invalid subscription offer signature.');
  }
  final jws = value['compactJws'] as String;
  if (jws.length > 32768 ||
      !RegExp(
        r'^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$',
      ).hasMatch(jws)) {
    throw const FormatException('Invalid subscription offer JWS.');
  }
  return jws;
}

bool billingReturnOfferBlocksPurchase(
  AsyncValue<BillingReturnOffers>? offers,
) =>
    offers != null &&
    (offers.isLoading ||
        offers.hasError ||
        offers.asData?.value.retryAfter != null);

String billingOfferDuration(AppLocalizations l10n, SK2SubscriptionOffer offer) {
  final count = offer.period.value * offer.periodCount;
  return switch (offer.period.unit) {
    SK2SubscriptionPeriodUnit.day => l10n.billingOfferDays(count),
    SK2SubscriptionPeriodUnit.week => l10n.billingOfferDays(count * 7),
    SK2SubscriptionPeriodUnit.month => l10n.billingOfferMonths(count),
    SK2SubscriptionPeriodUnit.year => l10n.billingOfferYears(count),
  };
}

String billingOfferPrice(
  AppLocalizations l10n,
  ProductDetails product,
  SK2SubscriptionOffer offer,
) {
  if (offer.paymentMode == SK2SubscriptionOfferPaymentMode.freeTrial) {
    return l10n.billingTrialFree(billingOfferDuration(l10n, offer));
  }
  final price = intl.NumberFormat.simpleCurrency(
    name: product.currencyCode,
    locale: l10n.localeName,
  ).format(offer.price);
  return switch (product.id) {
    pomodoistMonthlyProductId => l10n.billingPricePerMonth(price),
    pomodoistAnnualProductId => l10n.billingPricePerYear(price),
    _ => price,
  };
}

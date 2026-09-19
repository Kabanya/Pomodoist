import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;
import 'package:pomodoist/domain/models/billing/billing_models.dart';
import 'package:pomodoist/ui/core/localization/app_localizations.dart';

bool billingReturnOfferBlocksPurchase(
  AsyncValue<BillingReturnOffers>? offers,
) =>
    offers != null &&
    (offers.isLoading ||
        offers.hasError ||
        offers.asData?.value.retryAfter != null);

String billingOfferDuration(AppLocalizations l10n, BillingOffer offer) {
  final count = offer.periodValue * offer.periodCount;
  return switch (offer.periodUnit) {
    BillingOfferPeriodUnit.day => l10n.billingOfferDays(count),
    BillingOfferPeriodUnit.week => l10n.billingOfferDays(count * 7),
    BillingOfferPeriodUnit.month => l10n.billingOfferMonths(count),
    BillingOfferPeriodUnit.year => l10n.billingOfferYears(count),
  };
}

String billingOfferPrice(
  AppLocalizations l10n,
  BillingProduct product,
  BillingOffer offer,
) {
  if (offer.paymentMode == BillingOfferPaymentMode.freeTrial) {
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

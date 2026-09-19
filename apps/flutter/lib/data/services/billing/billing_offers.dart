import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';
import 'package:pomodoist/domain/models/billing/billing_models.dart';

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
          _storeReturnOfferMatchesProduct(product.id, offer)) {
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
bool _storeReturnOfferMatchesProduct(
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

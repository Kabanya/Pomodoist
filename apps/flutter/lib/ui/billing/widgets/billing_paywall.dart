import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' as intl;
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons, ShadButton;
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/platform/legal_urls.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/localization/app_localizations.dart';
import 'package:pomodoist/domain/models/app_flavor.dart';
import 'package:pomodoist/domain/models/billing/billing_models.dart';
import 'package:pomodoist/ui/billing/view_models/billing_view_model.dart';
import 'package:pomodoist/ui/billing/widgets/billing_offer_copy.dart';

String stripeBillingErrorMessage(AppLocalizations l10n, String code) {
  return switch (code) {
    'authentication_required' => l10n.billingStripeAuthenticationRequired,
    'billing_disabled' => l10n.billingStripeDisabled,
    'already_entitled' => l10n.billingStripeAlreadyEntitled,
    'offer_expired' || 'offer_not_eligible' => l10n.billingStripeOfferExpired,
    'offer_pending' => l10n.billingReturnFailed,
    'managed_payments_unavailable' =>
      l10n.billingStripeManagedPaymentsUnavailable,
    _ => l10n.billingStripeCheckoutFailed,
  };
}

String storeKitBillingErrorMessage(AppLocalizations l10n, String error) {
  if (error.startsWith('subscription_offer:')) return l10n.billingReturnFailed;
  if (error.contains('NSURLErrorDomain') ||
      error.contains('TimeoutException') ||
      error.contains('storekit_no_response') ||
      error == 'StoreKit: Failed to get response from platform.') {
    return l10n.billingStoreConnectionFailed;
  }
  return error;
}

class BillingPaywall extends ConsumerWidget {
  const BillingPaywall({
    super.key,
    this.compact = false,
    this.onClose,
    this.launchOfferTimerLabel,
    this.launchOfferMode = false,
    this.showPlansWhenActive = false,
  });

  final bool compact;
  final VoidCallback? onClose;
  final String? launchOfferTimerLabel;
  final bool launchOfferMode;
  final bool showPlansWhenActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<String?>(
      billingViewModelProvider.select(
        (state) => state.purchaseSuccessProductId,
      ),
      (previous, next) {
        if (next == null || previous == next) {
          return;
        }
        _showPurchaseSuccess(context, ref);
      },
    );

    final state = ref.watch(billingViewModelProvider);
    final channel = ref.watch(billingChannelProvider);
    final l10n = context.l10n;
    final displayedError = state.error ?? state.catalogError;
    final errorMessage = displayedError == null
        ? null
        : channel == BillingChannel.stripe
        ? stripeBillingErrorMessage(l10n, displayedError)
        : storeKitBillingErrorMessage(l10n, displayedError);
    final colors = context.appColors;
    final textTheme = Theme.of(context).textTheme;
    final returnOffers = channel == BillingChannel.storeKit
        ? ref.watch(billingReturnOffersProvider)
        : null;
    final returnPending = returnOffers?.asData?.value.retryAfter;
    final collapsedActive = state.hasActiveEntitlement && !showPlansWhenActive;
    final plans = ref
        .read(billingViewModelProvider.notifier)
        .plansForPaywall(launchOfferMode: launchOfferMode);
    final lifetimeCompareAtPrice = launchOfferMode
        ? state.productDetailsById[pomodoistLifetimeProductId]?.price ??
              billingPlanForProduct(pomodoistLifetimeProductId)?.fallbackPrice
        : null;
    return Column(
      key: const Key('billing-paywall'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _BillingProHeader(
                compact: compact,
                onTap: collapsedActive ? () => _showOffers(context) : null,
              ),
            ),
            if (onClose != null) ...[
              const SizedBox(width: 8),
              IconButton(
                key: const Key('billing-paywall-close'),
                tooltip: l10n.commonClose,
                onPressed: onClose,
                icon: const Icon(LucideIcons.x),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        if (state.hasActiveEntitlement) ...[
          Card(
            color: colors.surfaceTint,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(LucideIcons.badgeCheck, color: colors.accent),
                  const SizedBox(width: 10),
                  Expanded(child: Text(l10n.billingActive)),
                ],
              ),
            ),
          ),
          if (state.activeAccountEntitlement case final entitlement?
              when entitlement.source == 'stripe' && entitlement.subscription)
            Align(
              alignment: Alignment.centerLeft,
              child: ShadButton.ghost(
                key: const Key('billing-manage-link'),
                height: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                onPressed: () {
                  final gateway = ref.read(billingStripeGatewayProvider);
                  if (gateway != null) {
                    unawaited(
                      gateway.openCheckout(Uri.parse('https://link.com')),
                    );
                  }
                },
                leading: const Icon(LucideIcons.externalLink),
                child: Flexible(child: Text(l10n.billingManageLink)),
              ),
            ),
          const SizedBox(height: 12),
        ],
        if (!collapsedActive) ...[
          if (state.loading || returnOffers?.isLoading == true) ...[
            const LinearProgressIndicator(minHeight: 2),
            const SizedBox(height: 10),
          ],
          if (returnPending != null)
            Text(
              l10n.billingReturnPending(
                intl.DateFormat.yMd(
                  l10n.localeName,
                ).add_jm().format(returnPending.toLocal()),
              ),
              style: textTheme.bodySmall?.copyWith(color: colors.secondaryText),
            ),
          if (returnOffers?.hasError == true) ...[
            Text(l10n.billingReturnFailed, style: textTheme.bodySmall),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ShadButton.ghost(
                onPressed: () => ref.invalidate(billingReturnOffersProvider),
                child: Text(l10n.commonRetry),
              ),
            ),
          ],
          if (returnPending != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ShadButton.ghost(
                onPressed: () => ref.invalidate(billingReturnOffersProvider),
                child: Text(l10n.commonRetry),
              ),
            ),
          for (final plan in plans) ...[
            _BillingPlanTile(
              plan: plan,
              state: state,
              returnOfferId:
                  returnOffers?.asData?.value.offerIds[plan.productId],
              offerCheckBlocked:
                  plan.kind == BillingPlanKind.subscription &&
                  billingReturnOfferBlocksPurchase(returnOffers),
              forceIntroductoryPrice:
                  channel == BillingChannel.stripe &&
                  launchOfferMode &&
                  (plan.productId == pomodoistAnnualProductId ||
                      plan.productId == pomodoistMonthlyProductId),
              compareAtPrice: switch (plan.productId) {
                pomodoistLifetimeLaunchProductId => lifetimeCompareAtPrice,
                _ => null,
              },
              launchOfferTimerLabel:
                  plan.productId == pomodoistLifetimeLaunchProductId
                  ? launchOfferTimerLabel
                  : null,
            ),
            const SizedBox(height: 10),
          ],
          if (!state.platformSupported)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                l10n.billingAppleOnly,
                style: textTheme.bodySmall?.copyWith(
                  color: colors.secondaryText,
                ),
              ),
            )
          else if (channel == BillingChannel.stripe &&
              !state.storeAvailable &&
              !state.loading &&
              displayedError == null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                l10n.billingStripeDisabled,
                style: textTheme.bodySmall?.copyWith(
                  color: colors.secondaryText,
                ),
              ),
            )
          else if (channel == BillingChannel.storeKit &&
              !state.storeAvailable &&
              !state.loading &&
              displayedError == null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                l10n.billingStoreUnavailable,
                style: textTheme.bodySmall?.copyWith(
                  color: colors.secondaryText,
                ),
              ),
            ),
          if (errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              channel == BillingChannel.storeKit && state.error == null
                  ? errorMessage
                  : l10n.billingPurchaseError(errorMessage),
              style: textTheme.bodySmall?.copyWith(color: colors.error),
            ),
          ],
          const SizedBox(height: 8),
          if (channel == BillingChannel.storeKit &&
              state.platformSupported &&
              state.needsCatalogRetry)
            Align(
              alignment: Alignment.centerLeft,
              child: ShadButton.ghost(
                key: const Key('billing-retry-button'),
                leading: const Icon(LucideIcons.refreshCw),
                enabled: !state.loading,
                onPressed: state.loading
                    ? null
                    : () =>
                          ref.read(billingViewModelProvider.notifier).reload(),
                child: Text(l10n.commonRetry),
              ),
            ),
          if (channel == BillingChannel.storeKit)
            Align(
              alignment: Alignment.centerLeft,
              child: ShadButton.ghost(
                key: const Key('billing-restore-button'),
                height: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                enabled:
                    state.platformSupported &&
                    state.pendingProductId == null &&
                    !state.restoring,
                onPressed:
                    state.platformSupported &&
                        state.pendingProductId == null &&
                        !state.restoring
                    ? () => ref
                          .read(billingViewModelProvider.notifier)
                          .restorePurchases()
                    : null,
                leading: state.restoring
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.rotateCcw),
                child: Flexible(child: Text(l10n.billingRestore)),
              ),
            ),
        ],
        const SizedBox(height: 4),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          children: [
            ShadButton.ghost(
              key: const Key('billing-privacy-policy'),
              height: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              onPressed: () => unawaited(
                launchPomodoistExternalUrl(pomodoistPrivacyPolicyUrl),
              ),
              child: Flexible(child: Text(l10n.privacyPolicy)),
            ),
            ShadButton.ghost(
              key: const Key('billing-terms-of-use'),
              height: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              onPressed: () =>
                  unawaited(launchPomodoistExternalUrl(pomodoistTermsOfUseUrl)),
              child: Flexible(child: Text(l10n.termsOfUse)),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _showOffers(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (context) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: BillingPaywall(
          compact: true,
          onClose: () => Navigator.of(context).pop(),
          launchOfferMode: launchOfferMode,
          launchOfferTimerLabel: launchOfferTimerLabel,
          showPlansWhenActive: true,
        ),
      ),
    );
  }
}

void _showPurchaseSuccess(BuildContext context, WidgetRef ref) {
  final route = ModalRoute.of(context);
  if (route != null && !route.isCurrent) {
    return;
  }
  final router = GoRouter.maybeOf(context);
  if (router == null) {
    ref.read(billingViewModelProvider.notifier).clearPurchaseSuccess();
    return;
  }

  final returnTo = router.routeInformationProvider.value.uri.toString();
  if (route is PopupRoute) {
    Navigator.of(context).pop();
  }
  router.go(
    Uri(
      path: '/purchase-success',
      queryParameters: {'returnTo': returnTo},
    ).toString(),
  );
  ref.read(billingViewModelProvider.notifier).clearPurchaseSuccess();
}

class _BillingProHeader extends StatelessWidget {
  const _BillingProHeader({required this.compact, this.onTap});

  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final textTheme = Theme.of(context).textTheme;
    final iconSize = compact ? 36.0 : 40.0;

    final borderRadius = BorderRadius.circular(10);
    final content = Padding(
      padding: EdgeInsets.all(compact ? 14 : 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SizedBox.square(
              dimension: iconSize,
              child: Icon(
                LucideIcons.mic,
                color: colors.accent,
                size: compact ? 19 : 21,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.billingTitle,
                  style:
                      (compact ? textTheme.titleLarge : textTheme.headlineSmall)
                          ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text.rich(
                  _highlightedBillingSubtitle(
                    text: l10n.billingSubtitle,
                    highlight: l10n.billingSubtitleHighlight,
                    baseStyle: textTheme.bodyMedium?.copyWith(
                      color: colors.secondaryText,
                      height: 1.35,
                    ),
                    highlightStyle: textTheme.bodyMedium?.copyWith(
                      color: colors.accent,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.billingCancelAnytime,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceTint,
        borderRadius: borderRadius,
        border: Border.all(color: colors.border),
      ),
      child: onTap == null
          ? content
          : Material(
              color: Colors.transparent,
              child: InkWell(
                key: const Key('billing-pro-header'),
                borderRadius: borderRadius,
                onTap: onTap,
                child: content,
              ),
            ),
    );
  }
}

TextSpan _highlightedBillingSubtitle({
  required String text,
  required String highlight,
  required TextStyle? baseStyle,
  required TextStyle? highlightStyle,
}) {
  final index = text.indexOf(highlight);
  if (highlight.isEmpty || index < 0) {
    return TextSpan(text: text, style: baseStyle);
  }
  return TextSpan(
    style: baseStyle,
    children: [
      TextSpan(text: text.substring(0, index)),
      TextSpan(
        text: highlight,
        style:
            highlightStyle ?? baseStyle?.copyWith(fontWeight: FontWeight.w600),
      ),
      TextSpan(text: text.substring(index + highlight.length)),
    ],
  );
}

class _BillingPlanTile extends ConsumerWidget {
  const _BillingPlanTile({
    required this.plan,
    required this.state,
    required this.forceIntroductoryPrice,
    this.compareAtPrice,
    this.launchOfferTimerLabel,
    this.returnOfferId,
    this.offerCheckBlocked = false,
  });

  final String? returnOfferId;
  final bool offerCheckBlocked;
  final BillingPlan plan;
  final BillingState state;
  final bool forceIntroductoryPrice;
  final String? compareAtPrice;
  final String? launchOfferTimerLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final product = state.productDetailsById[plan.productId];
    final channel = ref.watch(billingChannelProvider);
    final signedIn = ref.watch(billingSignedInProvider);
    final productRequired = channel == BillingChannel.storeKit || signedIn;
    final active = state.activeProductId == plan.productId;
    final pending = state.pendingProductId == plan.productId;
    final highlighted = plan.highlighted;
    final background = highlighted ? colors.surfaceTint : colors.surface;
    final border = highlighted
        ? colors.accent.withValues(alpha: 0.45)
        : colors.border;
    final awaitingStripeCatalog =
        channel == BillingChannel.stripe &&
        appFlavor == AppFlavor.development &&
        product == null;
    final regularPrice = awaitingStripeCatalog
        ? '—'
        : _regularPrice(l10n, plan, product, channel);
    final offer = channel == BillingChannel.storeKit
        ? billingOfferForProduct(
            product,
            introductoryEligible: state.eligibleIntroductoryProductIds.contains(
              plan.productId,
            ),
            returnOfferId: returnOfferId,
          )
        : stripeSubscriptionOffer(
            state.stripeSubscriptionOffer,
            plan.productId,
          );
    final trial = offer?.paymentMode == BillingOfferPaymentMode.freeTrial;
    final returning = offer?.type == BillingOfferType.promotional;
    final offerBlocked =
        offerCheckBlocked ||
        (returnOfferId != null && !returning) ||
        (channel == BillingChannel.stripe &&
            state.stripeSubscriptionOffer == 'blocked');
    final introductoryPrice =
        !awaitingStripeCatalog &&
            ((state.stripeSubscriptionOffer == null &&
                    forceIntroductoryPrice) ||
                state.eligibleIntroductoryProductIds.contains(plan.productId))
        ? channel == BillingChannel.storeKit && offer == null
              ? null
              : channel == BillingChannel.storeKit
              ? _introductoryPrice(context, l10n, plan, product)
              : plan.introductoryFallbackPrice
        : null;
    final displayedPrice = offer != null && product != null
        ? billingOfferPrice(l10n, product, offer)
        : introductoryPrice ?? regularPrice;
    final displayedCompareAtPrice = trial
        ? null
        : compareAtPrice ??
              (introductoryPrice == null && !returning ? null : regularPrice);
    final subtitle = awaitingStripeCatalog && !signedIn
        ? l10n.billingStripeAuthenticationRequired
        : trial
        ? l10n.billingTrialRenewal(regularPrice)
        : returning
        ? l10n.billingReturnSubtitle(
            billingOfferDuration(l10n, offer!),
            regularPrice,
          )
        : _planSubtitle(
            l10n,
            plan,
            regularPrice,
            hasIntroductoryPrice: introductoryPrice != null,
          );

    return Card(
      key: ValueKey('billing-plan-${plan.productId}'),
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        _planTitle(l10n, plan),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (returning)
                        _Badge(
                          label: l10n.billingReturnBadge,
                          color: colors.accent,
                        ),
                      if (highlighted)
                        _Badge(
                          label: l10n.billingBestValue,
                          color: colors.accent,
                        ),
                      if (launchOfferTimerLabel != null)
                        _Badge(
                          key: const Key('launch-offer-countdown'),
                          label: launchOfferTimerLabel!,
                          color: colors.accent,
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        displayedPrice,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (displayedCompareAtPrice != null)
                        Text(
                          displayedCompareAtPrice,
                          key: ValueKey('billing-compare-${plan.productId}'),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: colors.secondaryText,
                                decoration: TextDecoration.lineThrough,
                                decorationThickness: 2,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.secondaryText,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ShadButton(
              key: ValueKey('billing-buy-${plan.productId}'),
              enabled:
                  !(active ||
                      offerBlocked ||
                      pending ||
                      !state.canPurchase ||
                      (productRequired && product == null)),
              onPressed:
                  active ||
                      offerBlocked ||
                      pending ||
                      !state.canPurchase ||
                      (productRequired && product == null)
                  ? null
                  : () async {
                      if (channel == BillingChannel.stripe && !signedIn) {
                        final prompt = ref.read(billingSignInPromptProvider);
                        if (prompt != null) {
                          await prompt(context);
                          return;
                        }
                      }
                      if (channel == BillingChannel.stripe) {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: Text(l10n.billingExternalBrowserTitle),
                            content: Text(l10n.billingExternalBrowserMessage),
                            actions: [
                              ShadButton.ghost(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(false),
                                child: Text(l10n.commonCancel),
                              ),
                              ShadButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(true),
                                child: Text(l10n.commonOpen),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true || !context.mounted) return;
                      }
                      await ref
                          .read(billingViewModelProvider.notifier)
                          .purchase(
                            plan.productId,
                            returnOfferId:
                                returning && channel == BillingChannel.storeKit
                                ? offer!.id
                                : null,
                          );
                    },
              child: pending
                  ? SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    )
                  : Text(
                      active
                          ? l10n.billingActiveShort
                          : trial
                          ? l10n.billingTryFree
                          : l10n.billingChoose,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color, super.key});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

String _planTitle(AppLocalizations l10n, BillingPlan plan) {
  return switch (plan.productId) {
    pomodoistMonthlyProductId => l10n.billingMonthlyTitle,
    pomodoistAnnualProductId => l10n.billingAnnualTitle,
    pomodoistLifetimeProductId => l10n.billingLifetimeTitle,
    pomodoistLifetimeLaunchProductId => l10n.billingLifetimeTitle,
    _ => plan.productId,
  };
}

String _regularPrice(
  AppLocalizations l10n,
  BillingPlan plan,
  BillingProduct? product,
  BillingChannel channel,
) {
  if (product == null) {
    if (channel == BillingChannel.storeKit) {
      return switch (plan.productId) {
        pomodoistMonthlyProductId => l10n.billingPricePerMonth(r'$4.99'),
        pomodoistAnnualProductId => l10n.billingPricePerYear(r'$29.99'),
        _ => plan.fallbackPrice,
      };
    }
    return plan.fallbackPrice;
  }
  if (product.price == plan.fallbackPrice) {
    return plan.fallbackPrice;
  }
  return _priceWithPeriod(l10n, plan, product.price);
}

String? _introductoryPrice(
  BuildContext context,
  AppLocalizations l10n,
  BillingPlan plan,
  BillingProduct? product,
) {
  if (product != null) {
    for (final offer in product.offers) {
      if (offer.type == BillingOfferType.introductory) {
        final price = intl.NumberFormat.simpleCurrency(
          name: product.currencyCode,
          locale: Localizations.localeOf(context).toLanguageTag(),
        ).format(offer.price);
        return _priceWithPeriod(l10n, plan, price);
      }
    }
    return null;
  }
  return plan.introductoryFallbackPrice;
}

String _priceWithPeriod(AppLocalizations l10n, BillingPlan plan, String price) {
  return switch (plan.productId) {
    pomodoistMonthlyProductId => l10n.billingPricePerMonth(price),
    pomodoistAnnualProductId => l10n.billingPricePerYear(price),
    _ => price,
  };
}

String _planSubtitle(
  AppLocalizations l10n,
  BillingPlan plan,
  String regularPrice, {
  required bool hasIntroductoryPrice,
}) {
  return switch (plan.productId) {
    pomodoistMonthlyProductId when hasIntroductoryPrice =>
      l10n.billingMonthlyIntroSubtitle(regularPrice),
    pomodoistAnnualProductId when hasIntroductoryPrice =>
      l10n.billingAnnualIntroSubtitle(regularPrice),
    pomodoistLifetimeProductId => l10n.billingLifetimeSubtitle,
    pomodoistLifetimeLaunchProductId => l10n.billingLifetimeSubtitle,
    _ => '',
  };
}

// Eligibility uses server-fetched Stripe history, including canceled trials.
export const stripeReturnCampaign = "return_2026_v1";
export type StripeOfferKind = "trial" | "return" | "standard" | "blocked";
export type StripeOfferHistory = {
  status: string;
  trialStart: number | null;
  endedAt: number | null;
  paid: boolean;
  campaign: string | null;
};

export function stripeOfferKind(
  history: StripeOfferHistory[],
  account: {
    hasActiveEntitlement: boolean;
    hasLifetimePurchase: boolean;
    firstSubscriptionPaidAt: string | null;
  },
  now: number,
): StripeOfferKind {
  if (
    account.hasActiveEntitlement || account.hasLifetimePurchase ||
    history.some((s) => !["canceled", "incomplete_expired"].includes(s.status))
  ) return "blocked";
  const accessed = history.filter((s) => s.trialStart != null || s.paid);
  if (accessed.length === 0) {
    return account.firstSubscriptionPaidAt == null ? "trial" : "standard";
  }
  if (history.some((s) => s.paid && s.campaign === stripeReturnCampaign)) {
    return "standard";
  }
  // ended_at is actual termination; current_period_end can be in the future
  // after immediate cancellation. Missing termination evidence fails closed.
  const ends = accessed.map((s) => s.endedAt);
  if (
    ends.some((end) => end == null || !Number.isSafeInteger(end) || end < 0)
  ) return "blocked";
  return now >= Math.max(...ends as number[]) + 7 * 86400
    ? "return"
    : "standard";
}

export function assertStripeTestOffersConfig(key: string, environment: string) {
  if (!/^(sk|rk)_test_/.test(key) || environment !== "develop") {
    throw new Error(
      "Subscription offers require Stripe test mode and develop.",
    );
  }
}

export function assertStripeOfferObjects(
  price: {
    livemode: boolean;
    active: boolean;
    currency: string;
    unit_amount: number | null;
    recurring:
      | { interval: string; interval_count: number; usage_type: string }
      | null;
    product: unknown;
  },
  coupon: {
    livemode: boolean;
    valid: boolean;
    currency: string | null;
    amount_off: number | null;
    percent_off: number | null;
    duration: string;
    duration_in_months?: number | null;
    applies_to?: { products?: string[] };
  },
  monthly: boolean,
) {
  if (
    price.livemode !== false || coupon.livemode !== false || !price.active ||
    !coupon.valid ||
    price.currency !== "usd" || price.unit_amount !== (monthly ? 499 : 2999) ||
    price.recurring?.interval !== (monthly ? "month" : "year") ||
    price.recurring.interval_count !== 1 ||
    price.recurring.usage_type !== "licensed" ||
    coupon.currency !== "usd" || coupon.amount_off !== (monthly ? 300 : 1500) ||
    coupon.percent_off != null ||
    coupon.duration !== (monthly ? "repeating" : "once") ||
    (monthly && coupon.duration_in_months !== 3) ||
    (coupon.applies_to?.products &&
      !coupon.applies_to.products.includes(String(price.product)))
  ) {
    throw new Error("Stripe offer terms do not match the campaign.");
  }
}

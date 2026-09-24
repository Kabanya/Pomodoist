import type Stripe from "npm:stripe@22.4.0";
import {
  assertStripeOfferObjects,
  type StripeOfferHistory,
  stripeOfferKind,
} from "./stripe_offers.ts";
import {
  type StripeBillingAccountContext,
  stripeCheckoutParams,
  type StripeCheckoutSessionInput,
} from "./pomodoist_stripe_billing.ts";

export async function loadStripeOffer(
  stripe: Stripe,
  context: StripeBillingAccountContext,
  priceIds: Record<string, string>,
  couponIds: Record<string, string>,
) {
  for (const product of ["pomodoist.pro.monthly", "pomodoist.pro.annual"]) {
    const [price, coupon] = await Promise.all([
      stripe.prices.retrieve(priceIds[product]),
      stripe.coupons.retrieve(couponIds[product]),
    ]);
    assertStripeOfferObjects(price, coupon, product.endsWith("monthly"));
  }
  const history: StripeOfferHistory[] = [];
  if (context.stripeCustomerId != null) {
    const customer = await stripe.customers.retrieve(context.stripeCustomerId);
    if (customer.deleted || customer.livemode !== false) {
      throw new Error("Invalid test customer.");
    }
    // Iterate every page. Canceled subscriptions remain in Stripe's history;
    // zero-amount trial invoices must not be mistaken for a paid return offer.
    for await (
      const subscription of stripe.subscriptions.list({
        customer: customer.id,
        status: "all",
        limit: 100,
      })
    ) {
      if (subscription.livemode !== false) {
        throw new Error("Live subscription in test history.");
      }
      let paid = false;
      for await (
        const invoice of stripe.invoices.list({
          customer: customer.id,
          subscription: subscription.id,
          status: "paid",
          limit: 100,
        })
      ) {
        if (invoice.livemode !== false) {
          throw new Error("Live invoice in test history.");
        }
        if (invoice.total > 0) paid = true;
      }
      history.push({
        status: subscription.status,
        trialStart: subscription.trial_start,
        endedAt: subscription.ended_at,
        paid,
        campaign: subscription.metadata.return_campaign ?? null,
      });
    }
  }
  return stripeOfferKind(history, context, Math.floor(Date.now() / 1000));
}

export type StripeCheckoutReservation = {
  id: string;
  expiresAt: number;
  input: StripeCheckoutSessionInput;
};

export async function createReservedStripeCheckout(
  stripe: Stripe,
  input: StripeCheckoutSessionInput,
  reserve: () => Promise<StripeCheckoutReservation>,
  release: (id: string) => Promise<void>,
  verify: () => Promise<boolean>,
  now = Math.floor(Date.now() / 1000),
): Promise<{ url: string | null }> {
  const reservation = await reserve();
  let existing: Stripe.Checkout.Session | null = null;
  // Also covers a process crash after Stripe creation but before returning URL.
  for await (
    const session of stripe.checkout.sessions.list({
      customer: input.customerId,
      limit: 100,
    })
  ) {
    if (session.livemode !== false) {
      throw new Error("Live Checkout in test history.");
    }
    if (session.metadata?.offer_reservation === reservation.id) {
      existing = session;
    } // Block legacy open/processing sessions too during the cutover. They can
    // otherwise purchase a second subscription after this check.
    else if (
      session.status === "open" ||
      (session.status === "complete" && session.payment_status === "unpaid")
    ) {
      throw new Error("offer_pending");
    }
  }
  if (existing != null && existing.status !== "open") {
    if (
      existing.status === "complete" && existing.payment_status === "unpaid"
    ) throw new Error("offer_pending");
    // Fresh history must be eligible again before releasing completed checkout.
    if (!await verify()) throw new Error("offer_pending");
    await release(reservation.id);
    throw new Error("offer_pending"); // Explicit retry; never choose a new offer silently.
  }
  if (existing == null && reservation.expiresAt <= now) {
    // The anchored expiry is in the past, so delayed create requests cannot
    // produce another payable session using this reservation.
    await release(reservation.id);
    throw new Error("offer_pending");
  }
  if (
    reservation.input.productId !== input.productId ||
    reservation.input.selectedOffer !== input.selectedOffer ||
    reservation.input.customerId !== input.customerId ||
    !await verify()
  ) throw new Error("offer_pending");
  if (existing != null) return { url: existing.url };
  const params = stripeCheckoutParams(
    reservation.input,
  ) as Stripe.Checkout.SessionCreateParams;
  params.expires_at = reservation.expiresAt;
  params.metadata = { ...params.metadata, offer_reservation: reservation.id };
  // Reuse the exact stored parameters even after a locale/surface change.
  const session = await stripe.checkout.sessions.create(params, {
    idempotencyKey: `pomodoist-test-offer:${reservation.id}`,
  });
  if (session.livemode !== false) {
    throw new Error("Live Checkout in test mode.");
  }
  return { url: session.url };
}

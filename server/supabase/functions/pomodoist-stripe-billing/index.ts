import { assertStripeTestOffersConfig } from "./stripe_offers.ts";
import {
  createReservedStripeCheckout,
  loadStripeOffer,
  type StripeCheckoutReservation,
} from "./stripe_offer_checkout.ts";
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { createClient } from "npm:@supabase/supabase-js@2";
import Stripe from "npm:stripe@22.4.0";

import {
  handlePomodoistStripeBilling,
  type StripeBillingAccountContext,
  stripeCheckoutParams,
} from "./pomodoist_stripe_billing.ts";

Deno.serve((req) => {
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const stripeSecretKey = Deno.env.get("STRIPE_SECRET_KEY") ?? "";
  const webhookSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET") ?? "";
  const priceIds = {
    "pomodoist.pro.monthly": Deno.env.get("STRIPE_PRICE_MONTHLY") ?? "",
    "pomodoist.pro.annual": Deno.env.get("STRIPE_PRICE_ANNUAL") ?? "",
    "pomodoist.pro.lifetime": Deno.env.get("STRIPE_PRICE_LIFETIME") ?? "",
    "pomodoist.pro.lifetime.launch":
      Deno.env.get("STRIPE_PRICE_LIFETIME_LAUNCH") ?? "",
  };
  const offersEnabled =
    Deno.env.get("STRIPE_TEST_SUBSCRIPTION_OFFERS_ENABLED") === "true";
  const couponIds = {
    "pomodoist.pro.monthly": Deno.env.get(
      offersEnabled
        ? "STRIPE_COUPON_MONTHLY_RETURN"
        : "STRIPE_COUPON_MONTHLY_INTRO",
    ) ?? "",
    "pomodoist.pro.annual": Deno.env.get(
      offersEnabled
        ? "STRIPE_COUPON_ANNUAL_RETURN"
        : "STRIPE_COUPON_ANNUAL_INTRO",
    ) ?? "",
  };
  const enabled = Deno.env.get("STRIPE_CHECKOUT_ENABLED") === "true" &&
    stripeSecretKey.length > 0 &&
    webhookSecret.length > 0 &&
    Object.values(priceIds).every((value) => value.length > 0) &&
    Object.values(couponIds).every((value) => value.length > 0);
  const admin = createClient(url, serviceRoleKey);
  const stripe = new Stripe(stripeSecretKey || "not-configured", {
    apiVersion: "2026-07-29.dahlia",
  });

  const validateTestMode = () =>
    assertStripeTestOffersConfig(
      stripeSecretKey,
      Deno.env.get("STRIPE_BILLING_ENVIRONMENT") ?? "",
    );
  const loadAccount = async (
    userId: string,
  ): Promise<StripeBillingAccountContext> => {
    const { data, error } = await admin.rpc(
      "pomodoist_stripe_checkout_context",
      { p_user_id: userId },
    );
    if (error || !isRecord(data)) {
      throw new Error("Could not load billing context.");
    }
    return data as StripeBillingAccountContext;
  };
  return handlePomodoistStripeBilling(req, {
    enabled,
    offersEnabled,
    loadOffer: async (context) => {
      validateTestMode();
      return await loadStripeOffer(stripe, context, priceIds, couponIds);
    },
    authenticate: async (authorization) => {
      const auth = createClient(url, anonKey, {
        global: { headers: { Authorization: authorization } },
      });
      const {
        data: { user },
        error,
      } = await auth.auth.getUser();
      return error == null && user != null
        ? { userId: user.id, email: user.email ?? null }
        : null;
    },
    loadAccount,
    createCustomer: async ({ userId, email }) => {
      if (offersEnabled) validateTestMode();
      const customer = await stripe.customers.create(
        {
          ...(email == null ? {} : { email }),
          metadata: { supabase_user_id: userId, app_id: "pomodoist" },
        },
        { idempotencyKey: `pomodoist-customer:${userId}` },
      );
      return customer.id;
    },
    linkCustomer: async (userId, customerId) => {
      const { data, error } = await admin.rpc(
        "link_pomodoist_stripe_customer",
        { p_user_id: userId, p_stripe_customer_id: customerId },
      );
      if (error || typeof data !== "string") {
        throw new Error("Could not link Stripe customer.");
      }
      return data;
    },
    createCheckoutSession: async (input) => {
      if (offersEnabled) {
        validateTestMode();
        return await createReservedStripeCheckout(stripe, input, async () => {
          const { data, error } = await admin.rpc(
            "reserve_pomodoist_stripe_checkout",
            { p_user_id: input.userId, p_input: input },
          );
          if (error || !isRecord(data)) {
            throw new Error("Could not reserve Checkout.");
          }
          return data as StripeCheckoutReservation;
        }, async (id) => {
          const { error } = await admin.rpc(
            "release_pomodoist_stripe_checkout",
            { p_user_id: input.userId, p_reservation_id: id },
          );
          if (error) throw new Error("Could not release Checkout.");
        }, async () => {
          const kind = await loadStripeOffer(
            stripe,
            await loadAccount(input.userId),
            priceIds,
            couponIds,
          );
          return kind !== "blocked" &&
            (input.mode !== "subscription" || kind === input.selectedOffer);
        });
      }
      const session = await stripe.checkout.sessions.create(
        stripeCheckoutParams(input) as Stripe.Checkout.SessionCreateParams,
      );
      return { url: session.url };
    },
    priceIds,
    couponIds,
    successUrl: Deno.env.get("STRIPE_SUCCESS_URL") ??
      "https://app.pomodoist.com/purchase-success?source=stripe",
    cancelUrl: Deno.env.get("STRIPE_CANCEL_URL") ??
      "https://app.pomodoist.com/settings",
  });
});

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

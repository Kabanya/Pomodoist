import { assertEquals, assertRejects } from "@std/assert";
import type Stripe from "npm:stripe@22.4.0";
import { createReservedStripeCheckout } from "./stripe_offer_checkout.ts";
import type { StripeCheckoutSessionInput } from "./pomodoist_stripe_billing.ts";
const input: StripeCheckoutSessionInput = {
  customerId: "cus_test",
  userId: "user",
  productId: "pomodoist.pro.monthly",
  priceId: "price_test",
  couponId: "coupon_return",
  selectedOffer: "return",
  mode: "subscription",
  surface: "web",
  successUrl: "http://localhost/success",
  cancelUrl: "http://localhost/cancel",
};
const reservation = { id: "reservation", expiresAt: 2500, input };
const url = "https://checkout.stripe.com/test";
Deno.test("concurrent requests share anchored parameters and Stripe idempotency key across retries", async () => {
  const params: unknown[] = [];
  const keys: string[] = [];
  const stripe = {
    checkout: {
      sessions: {
        list: async function* () {},
        create: async (p: unknown, options: { idempotencyKey: string }) => {
          params.push(p);
          keys.push(options.idempotencyKey);
          return { url, livemode: false };
        },
      },
    },
  } as unknown as Stripe;
  await Promise.all(
    [input, { ...input, locale: "fr" }].map((i) =>
      createReservedStripeCheckout(
        stripe,
        i,
        async () => reservation,
        async () => {},
        async () => true,
        100,
      )
    ),
  );
  assertEquals(params[0], params[1]);
  assertEquals(keys, [
    "pomodoist-test-offer:reservation",
    "pomodoist-test-offer:reservation",
  ]);
  await assertRejects(
    () =>
      createReservedStripeCheckout(
        stripe,
        { ...input, productId: "pomodoist.pro.annual" },
        async () => reservation,
        async () => {},
        async () => true,
        100,
      ),
    Error,
    "offer_pending",
  );
  assertEquals(keys.length, 2);
});
Deno.test("closed browser preserves open offer; expired cancellation releases without redemption; async processing stays locked", async () => {
  for (
    const [status, payment_status, releases, succeeds] of [
      ["open", "unpaid", 0, true],
      ["expired", "unpaid", 1, false],
      ["complete", "unpaid", 0, false],
      ["complete", "paid", 1, false],
    ] as const
  ) {
    let released = 0;
    const stripe = {
      checkout: {
        sessions: {
          list: async function* () {
            yield {
              status,
              payment_status,
              livemode: false,
              metadata: { offer_reservation: "reservation" },
              url,
            };
          },
          create: () => {
            throw new Error("must not create");
          },
        },
      },
    } as unknown as Stripe;
    const run = () =>
      createReservedStripeCheckout(
        stripe,
        input,
        async () => reservation,
        async () => {
          released++;
        },
        async () => true,
        100,
      );
    if (succeeds) assertEquals(await run(), { url });
    else await assertRejects(run, Error, "offer_pending");
    assertEquals(released, releases);
  }
});
Deno.test("fresh eligibility errors and legacy open sessions never create checkout", async () => {
  for (const legacy of [false, true]) {
    const stripe = {
      checkout: {
        sessions: {
          list: async function* () {
            if (legacy) yield { status: "open", livemode: false, metadata: {} };
          },
          create: () => {
            throw new Error("must not create");
          },
        },
      },
    } as unknown as Stripe;
    await assertRejects(
      () =>
        createReservedStripeCheckout(
          stripe,
          input,
          async () => reservation,
          async () => {},
          async () => {
            throw new Error("verification_failed");
          },
          100,
        ),
      Error,
      legacy ? "offer_pending" : "verification_failed",
    );
  }
});

Deno.test("full Stripe history distinguishes free trials, paid credits and consumed return campaign", async () => {
  const { loadStripeOffer } = await import("./stripe_offer_checkout.ts");
  for (const livemode of [false, true]) {
    const subscriptions = [
      {
        id: "sub_trial",
        status: "canceled",
        trial_start: 1,
        ended_at: 100,
        livemode,
        metadata: {},
      },
      {
        id: "sub_return",
        status: "canceled",
        trial_start: null,
        ended_at: 200,
        livemode,
        metadata: { return_campaign: "return_2026_v1" },
      },
    ];
    const seen: string[] = [];
    let fundedReturn = false;
    const stripe = {
      prices: {
        retrieve: async (id: string) => ({
          livemode,
          active: true,
          currency: "usd",
          unit_amount: id === "monthly" ? 499 : 2999,
          recurring: {
            interval: id === "monthly" ? "month" : "year",
            interval_count: 1,
            usage_type: "licensed",
          },
          product: "prod_test",
        }),
      },
      coupons: {
        retrieve: async (id: string) => ({
          livemode,
          valid: true,
          currency: "usd",
          amount_off: id === "monthly" ? 300 : 1500,
          percent_off: null,
          duration: id === "monthly" ? "repeating" : "once",
          duration_in_months: id === "monthly" ? 3 : null,
        }),
      },
      customers: { retrieve: async () => ({ id: "cus_test", livemode }) },
      subscriptions: {
        list: async function* () {
          for (const subscription of subscriptions) yield subscription;
        },
      },
      invoices: {
        list: async function* ({ subscription }: { subscription: string }) {
          seen.push(subscription);
          yield {
            livemode,
            total: fundedReturn && subscription === "sub_return" ? 199 : 0,
            amount_paid: 0,
          };
        },
      },
    } as unknown as Stripe;
    const context = {
      stripeCustomerId: "cus_test",
      profileCreatedAt: "2026-01-01",
      hasActiveEntitlement: false,
      hasLifetimePurchase: false,
      firstSubscriptionPaidAt: null,
    };
    const ids = {
      "pomodoist.pro.monthly": "monthly",
      "pomodoist.pro.annual": "annual",
    };
    assertEquals(
      await loadStripeOffer(stripe, context, ids, ids, livemode),
      "return",
    );
    assertEquals(seen, ["sub_trial", "sub_return"]);
    fundedReturn = true;
    assertEquals(
      await loadStripeOffer(stripe, context, ids, ids, livemode),
      "standard",
    );
  }
});

Deno.test("live Checkout rejects test sessions before reuse or creation", async () => {
  for (const livemode of [false, true]) {
    for (const existing of [false, true]) {
      const session = {
        url,
        livemode,
        status: "open",
        metadata: { offer_reservation: reservation.id },
      };
      const stripe = {
        checkout: {
          sessions: {
            list: async function* () {
              if (existing) yield session;
            },
            create: async () => session,
          },
        },
      } as unknown as Stripe;
      const checkout = () =>
        createReservedStripeCheckout(
          stripe,
          input,
          async () => reservation,
          async () => {},
          async () => true,
          100,
          true,
        );
      if (livemode) assertEquals(await checkout(), { url });
      else await assertRejects(checkout, Error, "mode mismatch");
    }
  }
});

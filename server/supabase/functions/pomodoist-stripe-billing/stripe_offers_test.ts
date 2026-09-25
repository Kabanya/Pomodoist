import { assertEquals, assertThrows } from "@std/assert";
import {
  assertStripeOfferObjects,
  assertStripeOffersConfig,
  type StripeOfferHistory,
  stripeOfferKind,
  stripeReturnCampaign,
} from "./stripe_offers.ts";
const account = {
  hasActiveEntitlement: false,
  hasLifetimePurchase: false,
  firstSubscriptionPaidAt: null,
};
const ended: StripeOfferHistory = {
  status: "canceled",
  trialStart: 1,
  endedAt: 100,
  paid: false,
  campaign: null,
};
Deno.test("trial history, exact seven-day boundary and campaign shared between plans", () => {
  assertEquals(stripeOfferKind([], account, 1), "trial");
  assertEquals(stripeOfferKind([ended], account, 100 + 604800 - 1), "standard");
  assertEquals(stripeOfferKind([ended], account, 100 + 604800), "return");
  assertEquals(
    stripeOfferKind(
      [{ ...ended, trialStart: null, paid: true }],
      account,
      604900,
    ),
    "return",
  );
  assertEquals(
    stripeOfferKind(
      [{ ...ended, paid: true, campaign: stripeReturnCampaign }],
      account,
      604900,
    ),
    "standard",
  );
  assertEquals(
    stripeOfferKind(
      [{
        ...ended,
        trialStart: null,
        paid: false,
        campaign: stripeReturnCampaign,
      }],
      account,
      604900,
    ),
    "trial",
  );
  assertEquals(
    stripeOfferKind([ended, { ...ended, endedAt: 200 }], account, 604900),
    "standard",
  );
});
Deno.test("active, lifetime, retry, paused and uncertain termination cannot receive offers", () => {
  for (
    const status of [
      "active",
      "trialing",
      "past_due",
      "unpaid",
      "paused",
      "incomplete",
      "future_status",
    ]
  ) {
    assertEquals(
      stripeOfferKind([{ ...ended, status }], account, 99999999),
      "blocked",
    );
  }
  assertEquals(
    stripeOfferKind([], { ...account, hasActiveEntitlement: true }, 9999999),
    "blocked",
  );
  assertEquals(
    stripeOfferKind([], { ...account, hasLifetimePurchase: true }, 9999999),
    "blocked",
  );
  assertEquals(
    stripeOfferKind([{ ...ended, endedAt: null }], account, 9999999),
    "blocked",
  );
});
Deno.test("environment guard and exact Stripe amounts/coupon durations", () => {
  assertStripeOffersConfig("sk_" + "test_fake", "develop");
  assertThrows(() => assertStripeOffersConfig("sk_" + "live_fake", "develop"));
  assertThrows(() =>
    assertStripeOffersConfig("sk_" + "test_fake", "production")
  );
  const price = {
    livemode: false,
    active: true,
    currency: "usd",
    unit_amount: 499,
    recurring: { interval: "month", interval_count: 1, usage_type: "licensed" },
    product: "prod_test",
  };
  const coupon = {
    livemode: false,
    valid: true,
    currency: "usd",
    amount_off: 300,
    percent_off: null,
    duration: "repeating",
    duration_in_months: 3,
  };
  assertStripeOfferObjects(price, coupon, true);
  assertStripeOfferObjects(
    { ...price, livemode: true },
    { ...coupon, livemode: true },
    true,
    true,
  );
  assertThrows(() => assertStripeOfferObjects(price, coupon, true, true));
  assertThrows(() =>
    assertStripeOfferObjects({ ...price, livemode: true }, coupon, true, true)
  );
  for (
    const wrong of [{ amount_off: 299 }, { duration_in_months: 2 }, {
      livemode: true,
    }, { applies_to: { products: ["wrong"] } }]
  ) {
    assertThrows(() =>
      assertStripeOfferObjects(price, { ...coupon, ...wrong }, true)
    );
  }
});

Deno.test("production offers accept only live keys in the production environment", () => {
  assertEquals(
    assertStripeOffersConfig("rk_" + "live_fake", "production"),
    true,
  );
  assertEquals(
    assertStripeOffersConfig("sk_" + "test_fake", "develop", true),
    false,
  );
  assertThrows(() =>
    assertStripeOffersConfig("sk_" + "live_fake", "production", true)
  );
  for (
    const [key, environment] of [
      ["rk_" + "test_fake", "production"],
      ["rk_" + "live_fake", "develop"],
      ["rk_" + "live_fake", ""],
    ]
  ) {
    assertThrows(() => assertStripeOffersConfig(key, environment));
  }
});

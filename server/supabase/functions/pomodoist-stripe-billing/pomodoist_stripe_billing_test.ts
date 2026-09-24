import { assertEquals } from "@std/assert";

import {
  handlePomodoistStripeBilling,
  type PomodoistStripeBillingDeps,
  stripeCatalogForAccount,
  stripeCheckoutLocale,
  stripeCheckoutParams,
} from "./pomodoist_stripe_billing.ts";

Deno.test("Checkout locale preserves Brazilian Portuguese and validates all new languages", () => {
  for (
    const [input, expected] of [
      ["pt", "pt-BR"],
      ["pt_BR", "pt-BR"],
      ["ja-JP", "ja"],
      ["ko-KR", "ko"],
      ["unknown", "auto"],
      ["ja<script>", "auto"],
    ]
  ) {
    assertEquals(stripeCheckoutLocale(input), expected);
  }
});

Deno.test("Stripe catalog derives the launch window from the server profile anchor", () => {
  const catalog = stripeCatalogForAccount({
    enabled: true,
    profileCreatedAt: "2026-08-01T00:00:00.000Z",
    firstSubscriptionPaidAt: null,
    hasActiveEntitlement: false,
    hasLifetimePurchase: false,
    now: new Date("2026-08-01T12:00:00.000Z"),
  });

  assertEquals(catalog, {
    enabled: true,
    introEligible: true,
    prices: {
      "pomodoist.pro.monthly": "$5.99",
      "pomodoist.pro.annual": "$39",
      "pomodoist.pro.lifetime": "$99.99",
      "pomodoist.pro.lifetime.launch": "$89.99",
    },
    launchOffer: {
      eligible: true,
      endsAt: "2026-08-02T00:00:00.000Z",
    },
  });
});

Deno.test("Stripe catalog hides the launch offer from active Pro accounts", () => {
  const catalog = stripeCatalogForAccount({
    enabled: true,
    profileCreatedAt: "2026-08-01T00:00:00.000Z",
    firstSubscriptionPaidAt: null,
    hasActiveEntitlement: true,
    hasLifetimePurchase: false,
    now: new Date("2026-08-01T12:00:00.000Z"),
  });

  assertEquals(catalog.launchOffer, { eligible: false, endsAt: null });
});

Deno.test("Stripe billing requires an authenticated Pomodoist account", async () => {
  let loaded = false;
  const deps = billingDeps({
    authenticate: () => Promise.resolve(null),
    loadAccount: () => {
      loaded = true;
      return Promise.reject(new Error("must not load"));
    },
  });

  const response = await handlePomodoistStripeBilling(
    new Request("https://functions.test/pomodoist-stripe-billing", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action: "catalog" }),
    }),
    deps,
  );

  assertEquals(response.status, 401);
  assertEquals(loaded, false);
  assertEquals(await response.json(), {
    code: "authentication_required",
    error: "Authentication required.",
  });
});

Deno.test("Stripe catalog returns server-owned promotion eligibility", async () => {
  const response = await handlePomodoistStripeBilling(
    billingRequest({ action: "catalog" }),
    billingDeps(),
  );

  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    enabled: true,
    introEligible: true,
    prices: {
      "pomodoist.pro.monthly": "$5.99",
      "pomodoist.pro.annual": "$39",
      "pomodoist.pro.lifetime": "$99.99",
      "pomodoist.pro.lifetime.launch": "$89.99",
    },
    launchOffer: {
      eligible: true,
      endsAt: "2026-08-02T00:00:00.000Z",
    },
  });
});

Deno.test("Stripe checkout maps the annual plan to a hosted subscription", async () => {
  const calls: Array<Record<string, unknown>> = [];
  const response = await handlePomodoistStripeBilling(
    billingRequest({
      action: "checkout",
      productId: "pomodoist.pro.annual",
      surface: "web",
    }),
    billingDeps({
      loadAccount: () =>
        Promise.resolve({
          profileCreatedAt: "2026-08-01T00:00:00.000Z",
          stripeCustomerId: "cus_existing",
          firstSubscriptionPaidAt: null,
          hasActiveEntitlement: false,
          hasLifetimePurchase: false,
        }),
      createCheckoutSession: (input) => {
        calls.push(input);
        return Promise.resolve({
          url: "https://checkout.stripe.com/c/pay/annual",
        });
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(calls, [{
    customerId: "cus_existing",
    userId: "11111111-1111-4111-8111-111111111111",
    productId: "pomodoist.pro.annual",
    priceId: "price_annual",
    couponId: "coupon_annual",
    mode: "subscription",
    surface: "web",
    successUrl: "https://app.pomodoist.com/purchase-success?source=stripe",
    cancelUrl: "https://app.pomodoist.com/settings",
  }]);
  assertEquals(await response.json(), {
    url: "https://checkout.stripe.com/c/pay/annual",
  });
});

Deno.test("native lifetime Checkout enables Managed Payments without exposing amounts", () => {
  assertEquals(
    stripeCheckoutParams({
      customerId: "cus_test",
      userId: "11111111-1111-4111-8111-111111111111",
      productId: "pomodoist.pro.lifetime.launch",
      priceId: "price_launch",
      couponId: null,
      mode: "payment",
      surface: "native",
      successUrl: "https://app.pomodoist.com/purchase-success?source=stripe",
      cancelUrl: "https://app.pomodoist.com/settings",
    }),
    {
      customer: "cus_test",
      client_reference_id: "11111111-1111-4111-8111-111111111111",
      line_items: [{ price: "price_launch", quantity: 1 }],
      mode: "payment",
      managed_payments: { enabled: true },
      integration_identifier: "pomodoist_checkout_kmfwqzrt",
      origin_context: "mobile_app",
      metadata: {
        supabase_user_id: "11111111-1111-4111-8111-111111111111",
        product_id: "pomodoist.pro.lifetime.launch",
      },
      payment_intent_data: {
        metadata: {
          supabase_user_id: "11111111-1111-4111-8111-111111111111",
          product_id: "pomodoist.pro.lifetime.launch",
        },
      },
      success_url: "https://app.pomodoist.com/purchase-success?source=stripe",
      cancel_url: "https://app.pomodoist.com/settings",
    },
  );
});

Deno.test("web Checkout enables Managed Payments without mobile origin context", () => {
  const params = stripeCheckoutParams({
    customerId: "cus_test",
    userId: "11111111-1111-4111-8111-111111111111",
    productId: "pomodoist.pro.monthly",
    priceId: "price_monthly",
    couponId: "coupon_monthly",
    mode: "subscription",
    surface: "web",
    successUrl: "https://app.pomodoist.com/purchase-success?source=stripe",
    cancelUrl: "https://app.pomodoist.com/settings",
  });

  assertEquals(params.managed_payments, { enabled: true });
  assertEquals(params.integration_identifier, "pomodoist_checkout_kmfwqzrt");
  assertEquals("origin_context" in params, false);
});

Deno.test("Stripe billing returns a stable Managed Payments availability error", async () => {
  const response = await handlePomodoistStripeBilling(
    billingRequest({
      action: "checkout",
      productId: "pomodoist.pro.lifetime",
      surface: "web",
    }),
    billingDeps({
      createCheckoutSession: () =>
        Promise.reject({
          type: "StripeInvalidRequestError",
          param: "managed_payments[enabled]",
        }),
    }),
  );

  assertEquals(response.status, 503);
  assertEquals(await response.json(), {
    code: "managed_payments_unavailable",
    error: "Stripe Managed Payments is unavailable.",
  });
});

function billingRequest(body: unknown) {
  return new Request("https://functions.test/pomodoist-stripe-billing", {
    method: "POST",
    headers: {
      Authorization: "Bearer session",
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
}

function billingDeps(
  overrides: Partial<PomodoistStripeBillingDeps> = {},
): PomodoistStripeBillingDeps {
  return {
    enabled: true,
    authenticate: () =>
      Promise.resolve({
        userId: "11111111-1111-4111-8111-111111111111",
        email: "buyer@example.com",
      }),
    loadAccount: () =>
      Promise.resolve({
        profileCreatedAt: "2026-08-01T00:00:00.000Z",
        stripeCustomerId: null,
        firstSubscriptionPaidAt: null,
        hasActiveEntitlement: false,
        hasLifetimePurchase: false,
      }),
    createCustomer: () => Promise.resolve("cus_test"),
    linkCustomer: (_userId, customerId) => Promise.resolve(customerId),
    createCheckoutSession: () =>
      Promise.resolve({ url: "https://checkout.stripe.com/c/pay/test" }),
    priceIds: {
      "pomodoist.pro.monthly": "price_monthly",
      "pomodoist.pro.annual": "price_annual",
      "pomodoist.pro.lifetime": "price_lifetime",
      "pomodoist.pro.lifetime.launch": "price_launch",
    },
    couponIds: {
      "pomodoist.pro.monthly": "coupon_monthly",
      "pomodoist.pro.annual": "coupon_annual",
    },
    successUrl: "https://app.pomodoist.com/purchase-success?source=stripe",
    cancelUrl: "https://app.pomodoist.com/settings",
    now: () => new Date("2026-08-01T12:00:00.000Z"),
    ...overrides,
  };
}

Deno.test("versioned test catalog replaces introductory discounts with trial and new prices", async () => {
  const deps = billingDeps({
    offersEnabled: true,
    loadOffer: async () => "trial",
  });
  const request = (body: unknown) =>
    new Request("https://functions.test/billing", {
      method: "POST",
      headers: {
        Authorization: "Bearer test",
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    });
  assertEquals(
    (await handlePomodoistStripeBilling(request({ action: "catalog" }), deps))
      .status,
    409,
  );
  const response = await handlePomodoistStripeBilling(
    request({ action: "catalog", offerVersion: 1 }),
    deps,
  );
  const catalog = await response.json();
  assertEquals(catalog.subscriptionOffer, "trial");
  assertEquals(catalog.introEligible, false);
  assertEquals(catalog.prices["pomodoist.pro.monthly"], "$4.99");
  assertEquals(catalog.prices["pomodoist.pro.annual"], "$29.99");
});

Deno.test("stale offer, verification error and blocked history never fall back to full-price checkout", async () => {
  for (
    const loadOffer of [
      async () => "standard" as const,
      async () => "blocked" as const,
      () => Promise.reject(new Error("Stripe unavailable")),
    ]
  ) {
    let calls = 0;
    const deps = billingDeps({
      offersEnabled: true,
      loadOffer,
      createCheckoutSession: async () => {
        calls++;
        return { url: "https://checkout.stripe.com/test" };
      },
    });
    const response = await handlePomodoistStripeBilling(
      new Request("https://functions.test/billing", {
        method: "POST",
        headers: {
          Authorization: "Bearer test",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          action: "checkout",
          offerVersion: 1,
          productId: "pomodoist.pro.annual",
          surface: "web",
          selectedOffer: "return",
        }),
      }),
      deps,
    );
    assertEquals(response.status >= 400, true);
    assertEquals(calls, 0);
  }
});

Deno.test("trial and return coupons are mutually exclusive native Checkout parameters", () => {
  const input = {
    customerId: "cus_test",
    userId: "user",
    productId: "pomodoist.pro.monthly",
    priceId: "price_test",
    couponId: null,
    mode: "subscription" as const,
    surface: "web" as const,
    successUrl: "http://localhost/success",
    cancelUrl: "http://localhost/cancel",
  };
  const trial = stripeCheckoutParams({ ...input, selectedOffer: "trial" });
  assertEquals(
    (trial.subscription_data as Record<string, unknown>).trial_period_days,
    7,
  );
  assertEquals(trial.discounts, undefined);
  const returning = stripeCheckoutParams({
    ...input,
    selectedOffer: "return",
    couponId: "coupon_return",
  });
  assertEquals(
    (returning.subscription_data as Record<string, unknown>).trial_period_days,
    undefined,
  );
  assertEquals(returning.discounts, [{ coupon: "coupon_return" }]);
});

Deno.test("disabling test offers after catalog selection cannot route a discounted purchase to legacy checkout", async () => {
  let calls = 0;
  const response = await handlePomodoistStripeBilling(
    new Request("https://functions.test/billing", {
      method: "POST",
      headers: {
        Authorization: "Bearer test",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        action: "checkout",
        offerVersion: 1,
        productId: "pomodoist.pro.annual",
        surface: "web",
        selectedOffer: "return",
      }),
    }),
    billingDeps({
      offersEnabled: false,
      createCheckoutSession: async () => {
        calls++;
        return { url: "https://checkout.stripe.com/test" };
      },
    }),
  );
  assertEquals(response.status, 409);
  assertEquals(calls, 0);
});

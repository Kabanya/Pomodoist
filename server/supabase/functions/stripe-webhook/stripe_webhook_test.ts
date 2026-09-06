import { assertEquals } from "@std/assert";

import {
  handleStripeWebhook,
  type StripeWebhookDeps,
} from "./stripe_webhook.ts";

Deno.test("Stripe webhook rejects a missing signature before any entitlement write", async () => {
  let verified = false;
  let recorded = false;
  const response = await handleStripeWebhook(
    new Request("https://functions.test/stripe-webhook", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id: "evt_unsigned" }),
    }),
    webhookDeps({
      verifyEvent: () => {
        verified = true;
        return Promise.reject(new Error("must not verify"));
      },
      recordEvent: () => {
        recorded = true;
        return Promise.reject(new Error("must not record"));
      },
    }),
  );

  assertEquals(response.status, 401);
  assertEquals(verified, false);
  assertEquals(recorded, false);
  assertEquals(await response.json(), {
    code: "invalid_signature",
    error: "Invalid Stripe signature.",
  });
});

Deno.test("Stripe webhook grants lifetime access only after a paid Checkout event", async () => {
  const records: Array<Record<string, unknown>> = [];
  const event = {
    id: "evt_lifetime_paid",
    type: "checkout.session.completed",
    created: 1785585600,
    data: {
      object: {
        id: "cs_test_lifetime",
        mode: "payment",
        payment_status: "paid",
        payment_intent: "pi_test_lifetime",
        customer: "cus_test",
        metadata: {
          supabase_user_id: "11111111-1111-4111-8111-111111111111",
          product_id: "pomodoist.pro.lifetime",
        },
      },
    },
  };
  const response = await handleStripeWebhook(
    signedRequest(event),
    webhookDeps({
      verifyEvent: (rawBody, signature) => {
        assertEquals(signature, "signed");
        assertEquals(rawBody, JSON.stringify(event));
        return Promise.resolve(event);
      },
      recordEvent: (record) => {
        records.push(record);
        return Promise.resolve({ applied: true });
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(records, [{
    eventId: "evt_lifetime_paid",
    eventType: "checkout.session.completed",
    eventCreatedAt: "2026-08-01T12:00:00.000Z",
    stripeObjectId: "pi_test_lifetime",
    customerId: "cus_test",
    userId: "11111111-1111-4111-8111-111111111111",
    productId: "pomodoist.pro.lifetime",
    purchaseType: "lifetime",
    status: "active",
    validFrom: "2026-08-01T12:00:00.000Z",
    validUntil: null,
    firstSubscriptionPaid: false,
    payload: {
      checkoutSessionId: "cs_test_lifetime",
      paymentStatus: "paid",
    },
  }]);
  assertEquals(await response.json(), { ok: true, applied: true });
});

Deno.test("Stripe webhook ignores declined or cancelled Checkout", async () => {
  let recorded = false;
  for (
    const event of [
      {
        id: "evt_unpaid",
        type: "checkout.session.completed",
        created: 1785585600,
        data: { object: { mode: "payment", payment_status: "unpaid" } },
      },
      {
        id: "evt_cancelled",
        type: "checkout.session.expired",
        created: 1785585600,
        data: { object: { mode: "payment" } },
      },
    ]
  ) {
    const response = await handleStripeWebhook(
      signedRequest(event),
      webhookDeps({
        verifyEvent: () => Promise.resolve(event),
        recordEvent: () => {
          recorded = true;
          return Promise.resolve({ applied: true });
        },
      }),
    );
    assertEquals(await response.json(), { ok: true, ignored: true });
  }
  assertEquals(recorded, false);
});

Deno.test("Stripe webhook refreshes subscription state from Stripe on invoice payment", async () => {
  const records: Array<Record<string, unknown>> = [];
  const event = {
    id: "evt_invoice_paid",
    type: "invoice.paid",
    created: 1785585600,
    data: {
      object: {
        id: "in_test",
        parent: {
          subscription_details: { subscription: "sub_test" },
        },
      },
    },
  };
  const response = await handleStripeWebhook(
    signedRequest(event),
    webhookDeps({
      verifyEvent: () => Promise.resolve(event),
      retrieveSubscription: (id) => {
        assertEquals(id, "sub_test");
        return Promise.resolve({
          id: "sub_test",
          customer: "cus_test",
          status: "active",
          metadata: {
            supabase_user_id: "11111111-1111-4111-8111-111111111111",
            product_id: "pomodoist.pro.annual",
          },
          items: {
            data: [{
              current_period_start: 1785582000,
              current_period_end: 1817118000,
            }],
          },
        });
      },
      recordEvent: (record) => {
        records.push(record);
        return Promise.resolve({ applied: true });
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(records, [{
    eventId: "evt_invoice_paid",
    eventType: "invoice.paid",
    eventCreatedAt: "2026-08-01T12:00:00.000Z",
    stripeObjectId: "sub_test",
    customerId: "cus_test",
    userId: "11111111-1111-4111-8111-111111111111",
    productId: "pomodoist.pro.annual",
    purchaseType: "subscription",
    status: "active",
    validFrom: "2026-08-01T11:00:00.000Z",
    validUntil: "2027-08-01T11:00:00.000Z",
    firstSubscriptionPaid: true,
    payload: { stripeStatus: "active" },
  }]);
});

Deno.test("Stripe webhook asks Stripe to retry when subscription refresh fails", async () => {
  const event = {
    id: "evt_invoice_retry",
    type: "invoice.payment_failed",
    created: 1785585600,
    data: {
      object: {
        id: "in_retry",
        subscription: "sub_retry",
      },
    },
  };
  const response = await handleStripeWebhook(
    signedRequest(event),
    webhookDeps({
      verifyEvent: () => Promise.resolve(event),
      retrieveSubscription: () => Promise.reject(new Error("Stripe timeout")),
    }),
  );

  assertEquals(response.status, 500);
  assertEquals(await response.json(), {
    code: "webhook_failed",
    error: "Could not process Stripe event.",
  });
});

Deno.test("Stripe webhook maps delayed payment, failure, and cancellation", async () => {
  const records: Array<Record<string, unknown>> = [];
  const scenarios = [
    {
      type: "checkout.session.async_payment_succeeded",
      object: { mode: "subscription", subscription: "sub_test" },
      stripeStatus: "active",
      expected: "active",
    },
    {
      type: "invoice.payment_failed",
      object: { subscription: "sub_test" },
      stripeStatus: "past_due",
      expected: "active",
    },
    {
      type: "customer.subscription.deleted",
      object: { id: "sub_test" },
      stripeStatus: "canceled",
      expected: "expired",
    },
  ];

  for (const scenario of scenarios) {
    const event = {
      id: `evt_${scenario.stripeStatus}`,
      type: scenario.type,
      created: 1785585600,
      data: { object: scenario.object },
    };
    const response = await handleStripeWebhook(
      signedRequest(event),
      webhookDeps({
        verifyEvent: () => Promise.resolve(event),
        retrieveSubscription: () =>
          Promise.resolve({
            id: "sub_test",
            customer: "cus_test",
            status: scenario.stripeStatus,
            metadata: {
              supabase_user_id: "11111111-1111-4111-8111-111111111111",
              product_id: "pomodoist.pro.monthly",
            },
            items: {
              data: [{
                current_period_start: 1785582000,
                current_period_end: 1788260400,
              }],
            },
          }),
        recordEvent: (record) => {
          records.push(record);
          return Promise.resolve({ applied: true });
        },
      }),
    );
    assertEquals(response.status, 200);
  }

  assertEquals(
    records.map(({ eventType, status, firstSubscriptionPaid }) => ({
      eventType,
      status,
      firstSubscriptionPaid,
    })),
    scenarios.map(({ type, expected }) => ({
      eventType: type,
      status: expected,
      firstSubscriptionPaid: false,
    })),
  );
});

Deno.test("Stripe webhook revokes lifetime access after a full refund", async () => {
  const records: Array<Record<string, unknown>> = [];
  const event = {
    id: "evt_refunded",
    type: "charge.refunded",
    created: 1785585600,
    data: {
      object: {
        id: "ch_test",
        amount: 20000,
        amount_refunded: 20000,
        payment_intent: "pi_test_lifetime",
        customer: "cus_test",
        metadata: {
          supabase_user_id: "11111111-1111-4111-8111-111111111111",
          product_id: "pomodoist.pro.lifetime",
        },
      },
    },
  };
  const response = await handleStripeWebhook(
    signedRequest(event),
    webhookDeps({
      verifyEvent: () => Promise.resolve(event),
      recordEvent: (record) => {
        records.push(record);
        return Promise.resolve({ applied: true });
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(records, [{
    eventId: "evt_refunded",
    eventType: "charge.refunded",
    eventCreatedAt: "2026-08-01T12:00:00.000Z",
    stripeObjectId: "pi_test_lifetime",
    customerId: "cus_test",
    userId: "11111111-1111-4111-8111-111111111111",
    productId: "pomodoist.pro.lifetime",
    purchaseType: "lifetime",
    status: "revoked",
    validFrom: null,
    validUntil: "2026-08-01T12:00:00.000Z",
    firstSubscriptionPaid: false,
    payload: {
      chargeId: "ch_test",
      amount: 20000,
      amountRefunded: 20000,
    },
  }]);
});

function signedRequest(event: unknown) {
  return new Request("https://functions.test/stripe-webhook", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Stripe-Signature": "signed",
    },
    body: JSON.stringify(event),
  });
}

function webhookDeps(
  overrides: Partial<StripeWebhookDeps> = {},
): StripeWebhookDeps {
  return {
    verifyEvent: () => Promise.reject(new Error("not configured")),
    retrieveSubscription: () => Promise.reject(new Error("not configured")),
    recordEvent: () => Promise.resolve({ applied: true }),
    now: () => new Date("2026-08-01T12:00:00.000Z"),
    ...overrides,
  };
}

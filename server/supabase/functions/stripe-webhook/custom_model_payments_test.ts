import { assertEquals } from "@std/assert";
import type Stripe from "npm:stripe@22.4.0";
import {
  modelInvoicePeriod,
  type StripeModelPayment,
  syncCustomModelInvoice,
  syncCustomModelStripeEvent,
} from "./custom_model_payments.ts";

const invoice = {
  id: "in_test",
  status: "paid",
  amount_paid: 2499,
  parent: {
    subscription_details: {
      subscription: "sub_annual",
      metadata: { product_id: "pomodoist.pro.annual" },
    },
  },
  lines: {
    has_more: false,
    data: [
      {
        amount: 2499,
        parent: { subscription_item_details: { subscription: "sub_annual" } },
        period: { end: 1800000000 },
      },
      {
        amount: 0,
        parent: { subscription_item_details: { subscription: "sub_annual" } },
        period: { end: 1900000000 },
      },
    ],
  },
} as unknown as Stripe.Invoice;

Deno.test("the paid invoice line sets the SKU and service period while zero or unrelated lines give no grant", () => {
  assertEquals(modelInvoicePeriod(invoice), {
    subscriptionId: "sub_annual",
    productId: "pomodoist.pro.annual",
    validUntil: "2027-01-15T08:00:00.000Z",
  });
  assertEquals(modelInvoicePeriod({ ...invoice, amount_paid: 0 }), null);
  assertEquals(
    modelInvoicePeriod({ ...invoice, lines: { ...invoice.lines, data: [] } }),
    null,
  );
  assertEquals(modelInvoicePeriod({ ...invoice, parent: null }), null);
});

Deno.test("reconciliation records distinct captured payments and their full refunds", async () => {
  const stripe = {
    invoicePayments: {
      list: () => [
        {
          id: "pay_live",
          amount_paid: 100,
          payment: {
            payment_intent: {
              latest_charge: {
                paid: true,
                captured: true,
                amount_captured: 100,
                amount_refunded: 50,
              },
            },
          },
        },
        {
          id: "pay_refund",
          amount_paid: 100,
          payment: {
            payment_intent: {
              latest_charge: {
                paid: true,
                captured: true,
                amount_captured: 100,
                amount_refunded: 100,
              },
            },
          },
        },
        { id: "pay_missing", amount_paid: 100, payment: {} },
      ],
    },
  } as unknown as Stripe;
  const saved: StripeModelPayment[] = [];
  await syncCustomModelInvoice(stripe, invoice, async (payment) => {
    saved.push(payment);
  });
  assertEquals(saved.map((p) => [p.p_payment_id, p.p_refunded]), [[
    "pay_live",
    false,
  ], ["pay_refund", true]]);
});

Deno.test("a subscription charge refund locates the original invoice and rechecks its payments", async () => {
  const refundedCharge = {
    paid: true,
    captured: true,
    amount_captured: 90,
    amount_refunded: 90,
  };
  const stripe = {
    invoices: {
      retrieve: async (id: string) => {
        assertEquals(id, invoice.id);
        return invoice;
      },
    },
    invoicePayments: {
      list: (query: { invoice?: string }) =>
        query.invoice
          ? [{
            id: "payment",
            amount_paid: 90,
            payment: { charge: refundedCharge },
          }]
          : [{ invoice: invoice.id }],
    },
  } as unknown as Stripe;
  const saved: StripeModelPayment[] = [];
  await syncCustomModelStripeEvent(stripe, {
    id: "evt",
    type: "charge.refunded",
    created: 1,
    data: { object: { payment_intent: "pi_test" } },
  }, async (p) => {
    saved.push(p);
  });
  assertEquals(saved.map((p) => p.p_refunded), [true]);
});

import type Stripe from "npm:stripe@22.4.0";
import type { StripeWebhookEvent } from "./stripe_webhook.ts";

export type StripeModelPayment = {
  p_subscription_id: string;
  p_payment_id: string;
  p_product_id: string;
  p_valid_until: string;
  p_refunded: boolean;
};

type SavePayment = (payment: StripeModelPayment) => Promise<void>;

// A subscription may have changed plans since the invoice was issued.
// Use the metadata snapshot at finalization and the billed line's period.
export function modelInvoicePeriod(invoice: Stripe.Invoice) {
  const details = invoice.parent?.subscription_details;
  const productId = details?.metadata?.product_id;
  if (
    invoice.status !== "paid" || invoice.amount_paid <= 0 || !details ||
    (productId !== "pomodoist.pro.monthly" &&
      productId !== "pomodoist.pro.annual")
  ) return null;
  const subscription = details.subscription;
  const subscriptionId = typeof subscription === "string"
    ? subscription
    : subscription.id;
  const ends = invoice.lines.data.flatMap((line) => {
    const item = line.parent?.subscription_item_details;
    const discounts = (line.discount_amounts ?? []).reduce(
      (sum, discount) => sum + discount.amount,
      0,
    );
    return line.amount > discounts && item?.subscription === subscriptionId &&
        line.period.end > 0
      ? [line.period.end]
      : [];
  });
  return ends.length
    ? {
      subscriptionId,
      productId,
      validUntil: new Date(Math.max(...ends) * 1000).toISOString(),
    }
    : null;
}

export async function syncCustomModelInvoice(
  stripe: Stripe,
  invoice: Stripe.Invoice,
  save: SavePayment,
) {
  if (invoice.lines.has_more) {
    invoice = {
      ...invoice,
      lines: {
        ...invoice.lines,
        data: await stripe.invoices
          .listLineItems(invoice.id, { limit: 100 }).autoPagingToArray({
            limit: 10000,
          }),
      },
    };
  }
  const period = modelInvoicePeriod(invoice);
  if (!period) return;
  for await (
    const payment of stripe.invoicePayments.list({
      invoice: invoice.id,
      status: "paid",
      limit: 100,
      expand: [
        "data.payment.payment_intent.latest_charge",
        "data.payment.charge",
      ],
    })
  ) {
    if (!payment.amount_paid || payment.amount_paid <= 0) continue;
    let intent = payment.payment.payment_intent;
    if (typeof intent === "string") {
      intent = await stripe.paymentIntents.retrieve(intent);
    }
    let charge = payment.payment.charge ?? intent?.latest_charge;
    if (typeof charge === "string") {
      charge = await stripe.charges.retrieve(charge);
    }
    if (!charge?.paid || !charge.captured || charge.amount_captured <= 0) {
      continue;
    }
    await save({
      p_subscription_id: period.subscriptionId,
      p_payment_id: payment.id,
      p_product_id: period.productId,
      p_valid_until: period.validUntil,
      p_refunded: charge.amount_refunded >= charge.amount_captured,
    });
  }
}

export async function syncCustomModelStripeEvent(
  stripe: Stripe,
  event: StripeWebhookEvent,
  save: SavePayment,
) {
  const object = event.data.object;
  if (
    event.type === "invoice.paid" && typeof object.id === "string" &&
    Number(object.amount_paid) > 0
  ) {
    await syncCustomModelInvoice(
      stripe,
      await stripe.invoices.retrieve(object.id),
      save,
    );
  } else if (
    event.type === "charge.refunded" &&
    typeof object.payment_intent === "string"
  ) {
    for await (
      const payment of stripe.invoicePayments.list({
        payment: {
          type: "payment_intent",
          payment_intent: object.payment_intent,
        },
        limit: 100,
      })
    ) {
      const invoice = payment.invoice;
      const id = typeof invoice === "string" ? invoice : invoice.id;
      await syncCustomModelInvoice(
        stripe,
        await stripe.invoices.retrieve(id),
        save,
      );
    }
  }
}

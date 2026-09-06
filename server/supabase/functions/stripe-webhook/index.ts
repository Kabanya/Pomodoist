import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { createClient } from "npm:@supabase/supabase-js@2";
import Stripe from "npm:stripe@22.4.0";

import {
  handleStripeWebhook,
  type StripeWebhookEvent,
} from "./stripe_webhook.ts";

Deno.serve((req) => {
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const stripeSecretKey = Deno.env.get("STRIPE_SECRET_KEY") ?? "";
  const webhookSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET") ?? "";
  const stripe = new Stripe(stripeSecretKey || "not-configured", {
    apiVersion: "2026-07-29.dahlia",
  });
  const admin = createClient(url, serviceRoleKey);

  return handleStripeWebhook(req, {
    verifyEvent: async (rawBody, signature) => {
      if (webhookSecret.length === 0) {
        throw new Error("Stripe webhook is not configured.");
      }
      const event = await stripe.webhooks.constructEventAsync(
        rawBody,
        signature,
        webhookSecret,
        undefined,
        Stripe.createSubtleCryptoProvider(),
      );
      return event as unknown as StripeWebhookEvent;
    },
    retrieveSubscription: async (id) => {
      const subscription = await stripe.subscriptions.retrieve(id);
      return subscription as unknown as Record<string, unknown>;
    },
    recordEvent: async (record) => {
      const { data, error } = await admin.rpc(
        "record_pomodoist_stripe_event",
        {
          p_event_id: record.eventId,
          p_event_type: record.eventType,
          p_event_created_at: record.eventCreatedAt,
          p_stripe_object_id: record.stripeObjectId,
          p_stripe_customer_id: record.customerId,
          p_user_id: record.userId,
          p_product_id: record.productId,
          p_purchase_type: record.purchaseType,
          p_status: record.status,
          p_valid_from: record.validFrom,
          p_valid_until: record.validUntil,
          p_first_subscription_paid: record.firstSubscriptionPaid,
          p_raw_payload: record.payload,
        },
      );
      if (error || !isRecord(data) || typeof data.applied !== "boolean") {
        throw new Error("Could not record Stripe event.");
      }
      return { applied: data.applied };
    },
  });
});

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

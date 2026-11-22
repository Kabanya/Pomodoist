// Run once per Stripe environment after installing the payment migration.
// Replaying the import is safe; general Pro entitlements are never rewritten.
import Stripe from "npm:stripe@22.4.0";
import { createClient } from "npm:@supabase/supabase-js@2";
import { syncCustomModelInvoice } from "../supabase/functions/stripe-webhook/custom_model_payments.ts";

function required(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing ${name}`);
  return value;
}

const stripe = new Stripe(required("STRIPE_SECRET_KEY"), {
  apiVersion: "2026-07-29.dahlia",
});
const admin = createClient(
  required("SUPABASE_URL"),
  required("SUPABASE_SERVICE_ROLE_KEY"),
);
let receipts = 0;
for await (
  const invoice of stripe.invoices.list({ status: "paid", limit: 100 })
) {
  await syncCustomModelInvoice(stripe, invoice, async (payment) => {
    const { error } = await admin.rpc(
      "record_pomodoist_custom_model_stripe_payment",
      payment,
    );
    if (error) {
      throw new Error(`Could not record invoice ${invoice.id}: ${error.code}`);
    }
    receipts++;
  });
}
console.log(`Processed ${receipts} Pomodoist payment receipts.`);

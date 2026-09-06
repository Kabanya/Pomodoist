export type StripeWebhookEvent = {
  id: string;
  type: string;
  created: number;
  data: { object: Record<string, unknown> };
};

export type StripeSubscriptionSnapshot = Record<string, unknown>;

export type StripeEventRecord = {
  eventId: string;
  eventType: string;
  eventCreatedAt: string;
  stripeObjectId: string;
  customerId: string;
  userId: string;
  productId: string;
  purchaseType: "lifetime" | "subscription";
  status: "active" | "inactive" | "expired" | "revoked";
  validFrom: string | null;
  validUntil: string | null;
  firstSubscriptionPaid: boolean;
  payload: Record<string, unknown>;
};

export type StripeWebhookDeps = {
  verifyEvent: (
    rawBody: string,
    signature: string,
  ) => Promise<StripeWebhookEvent>;
  retrieveSubscription: (id: string) => Promise<StripeSubscriptionSnapshot>;
  recordEvent: (
    record: StripeEventRecord,
  ) => Promise<{ applied: boolean }>;
  now?: () => Date;
};

export async function handleStripeWebhook(
  req: Request,
  deps: StripeWebhookDeps,
) {
  if (req.method !== "POST") {
    return json(
      { code: "method_not_allowed", error: "Method not allowed." },
      405,
    );
  }
  const signature = req.headers.get("Stripe-Signature");
  if (signature == null || signature.length === 0) {
    return json(
      { code: "invalid_signature", error: "Invalid Stripe signature." },
      401,
    );
  }
  const contentLength = Number(req.headers.get("Content-Length") ?? "0");
  if (Number.isFinite(contentLength) && contentLength > 1_048_576) {
    return json(
      { code: "payload_too_large", error: "Payload is too large." },
      413,
    );
  }
  const rawBody = await req.text();
  if (new TextEncoder().encode(rawBody).byteLength > 1_048_576) {
    return json(
      { code: "payload_too_large", error: "Payload is too large." },
      413,
    );
  }

  let event: StripeWebhookEvent;
  try {
    event = await deps.verifyEvent(rawBody, signature);
  } catch {
    return json(
      { code: "invalid_signature", error: "Invalid Stripe signature." },
      401,
    );
  }

  let record: StripeEventRecord | null;
  try {
    record = await stripeRecordForEvent(event, deps);
  } catch {
    return json(
      { code: "webhook_failed", error: "Could not process Stripe event." },
      500,
    );
  }
  if (record == null) {
    return json({ ok: true, ignored: true });
  }
  try {
    const result = await deps.recordEvent(record);
    return json({ ok: true, applied: result.applied });
  } catch {
    return json(
      { code: "webhook_failed", error: "Could not record Stripe event." },
      500,
    );
  }
}

async function stripeRecordForEvent(
  event: StripeWebhookEvent,
  deps: StripeWebhookDeps,
): Promise<StripeEventRecord | null> {
  if (event.type === "charge.refunded") {
    return lifetimeRefundRecord(event);
  }
  const sessionEvent = event.type === "checkout.session.completed" ||
    event.type === "checkout.session.async_payment_succeeded";
  const session = event.data.object;
  if (sessionEvent && session.mode === "payment") {
    return lifetimeRecordForCheckout(event);
  }

  const subscriptionId = subscriptionIdForEvent(event);
  if (subscriptionId == null) return null;
  let subscription: StripeSubscriptionSnapshot;
  try {
    subscription = await deps.retrieveSubscription(subscriptionId);
  } catch {
    throw new Error("Could not refresh Stripe subscription.");
  }
  return subscriptionRecordForEvent(
    event,
    subscription,
    deps.now?.() ?? new Date(),
  );
}

function lifetimeRefundRecord(
  event: StripeWebhookEvent,
): StripeEventRecord | null {
  const charge = event.data.object;
  const metadata = isRecord(charge.metadata) ? charge.metadata : null;
  const amount = integerValue(charge.amount);
  const amountRefunded = integerValue(charge.amount_refunded);
  const userId = metadata?.supabase_user_id;
  const productId = metadata?.product_id;
  const paymentIntentId = stringId(charge.payment_intent);
  const customerId = stringId(charge.customer);
  const chargeId = stringId(charge.id);
  const eventDate = stripeEventDate(event.created);
  if (
    amount == null ||
    amountRefunded == null ||
    amountRefunded < amount ||
    typeof userId !== "string" ||
    !uuidPattern.test(userId) ||
    (productId !== "pomodoist.pro.lifetime" &&
      productId !== "pomodoist.pro.lifetime.launch") ||
    paymentIntentId == null ||
    customerId == null ||
    chargeId == null ||
    eventDate == null
  ) {
    return null;
  }
  const eventCreatedAt = eventDate.toISOString();
  return {
    eventId: event.id,
    eventType: event.type,
    eventCreatedAt,
    stripeObjectId: paymentIntentId,
    customerId,
    userId,
    productId,
    purchaseType: "lifetime",
    status: "revoked",
    validFrom: null,
    validUntil: eventCreatedAt,
    firstSubscriptionPaid: false,
    payload: { chargeId, amount, amountRefunded },
  };
}

function lifetimeRecordForCheckout(
  event: StripeWebhookEvent,
): StripeEventRecord | null {
  const session = event.data.object;
  if (session.payment_status !== "paid") return null;
  const metadata = isRecord(session.metadata) ? session.metadata : null;
  const userId = metadata?.supabase_user_id;
  const productId = metadata?.product_id;
  const paymentIntentId = stringId(session.payment_intent);
  const customerId = stringId(session.customer);
  const sessionId = stringId(session.id);
  const eventDate = stripeEventDate(event.created);
  if (
    typeof userId !== "string" ||
    !uuidPattern.test(userId) ||
    (productId !== "pomodoist.pro.lifetime" &&
      productId !== "pomodoist.pro.lifetime.launch") ||
    paymentIntentId == null ||
    customerId == null ||
    sessionId == null ||
    eventDate == null
  ) {
    return null;
  }
  const eventCreatedAt = eventDate.toISOString();
  return {
    eventId: event.id,
    eventType: event.type,
    eventCreatedAt,
    stripeObjectId: paymentIntentId,
    customerId,
    userId,
    productId,
    purchaseType: "lifetime",
    status: "active",
    validFrom: eventCreatedAt,
    validUntil: null,
    firstSubscriptionPaid: false,
    payload: {
      checkoutSessionId: sessionId,
      paymentStatus: "paid",
    },
  };
}

function subscriptionIdForEvent(event: StripeWebhookEvent) {
  const object = event.data.object;
  if (
    event.type === "customer.subscription.created" ||
    event.type === "customer.subscription.updated" ||
    event.type === "customer.subscription.deleted"
  ) {
    return stringId(object.id);
  }
  if (
    event.type === "checkout.session.completed" ||
    event.type === "checkout.session.async_payment_succeeded"
  ) {
    return object.mode === "subscription"
      ? stringId(object.subscription)
      : null;
  }
  if (
    event.type === "invoice.paid" || event.type === "invoice.payment_failed"
  ) {
    const parent = isRecord(object.parent) ? object.parent : null;
    const details = parent != null && isRecord(parent.subscription_details)
      ? parent.subscription_details
      : null;
    return stringId(details?.subscription ?? object.subscription);
  }
  return null;
}

function subscriptionRecordForEvent(
  event: StripeWebhookEvent,
  subscription: StripeSubscriptionSnapshot,
  now: Date,
): StripeEventRecord | null {
  const metadata = isRecord(subscription.metadata)
    ? subscription.metadata
    : null;
  const userId = metadata?.supabase_user_id;
  const productId = metadata?.product_id;
  const subscriptionId = stringId(subscription.id);
  const customerId = stringId(subscription.customer);
  const stripeStatus = subscription.status;
  const item =
    isRecord(subscription.items) && Array.isArray(subscription.items.data)
      ? subscription.items.data.find(isRecord)
      : null;
  const periodStart = stripeEventDate(
    numberValue(
      item?.current_period_start ?? subscription.current_period_start,
    ),
  );
  const periodEnd = stripeEventDate(
    numberValue(item?.current_period_end ?? subscription.current_period_end),
  );
  const eventDate = stripeEventDate(event.created);
  if (
    typeof userId !== "string" ||
    !uuidPattern.test(userId) ||
    (productId !== "pomodoist.pro.monthly" &&
      productId !== "pomodoist.pro.annual") ||
    subscriptionId == null ||
    customerId == null ||
    typeof stripeStatus !== "string" ||
    periodStart == null ||
    periodEnd == null ||
    eventDate == null
  ) {
    return null;
  }

  const status = subscriptionEntitlementStatus(
    stripeStatus,
    periodEnd,
    now,
  );
  return {
    eventId: event.id,
    eventType: event.type,
    eventCreatedAt: eventDate.toISOString(),
    stripeObjectId: subscriptionId,
    customerId,
    userId,
    productId,
    purchaseType: "subscription",
    status,
    validFrom: periodStart.toISOString(),
    validUntil: periodEnd.toISOString(),
    firstSubscriptionPaid: event.type === "invoice.paid",
    payload: { stripeStatus },
  };
}

function subscriptionEntitlementStatus(
  stripeStatus: string,
  periodEnd: Date,
  now: Date,
): StripeEventRecord["status"] {
  if (
    (stripeStatus === "active" ||
      stripeStatus === "trialing" ||
      stripeStatus === "past_due") &&
    periodEnd > now
  ) {
    return "active";
  }
  if (stripeStatus === "incomplete" || stripeStatus === "paused") {
    return "inactive";
  }
  return "expired";
}

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function stripeEventDate(seconds: number) {
  if (!Number.isSafeInteger(seconds) || seconds < 0) return null;
  const value = new Date(seconds * 1000);
  return Number.isFinite(value.getTime()) ? value : null;
}

function numberValue(value: unknown) {
  return typeof value === "number" ? value : Number.NaN;
}

function integerValue(value: unknown) {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0
    ? value
    : null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function stringId(value: unknown) {
  if (typeof value === "string" && value.length > 0 && value.length <= 255) {
    return value;
  }
  if (isRecord(value) && typeof value.id === "string") return value.id;
  return null;
}

function json(value: unknown, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

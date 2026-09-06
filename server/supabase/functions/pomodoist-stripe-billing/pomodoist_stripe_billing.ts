export type StripeCatalogAccount = {
  enabled: boolean;
  profileCreatedAt: string;
  firstSubscriptionPaidAt: string | null;
  hasActiveEntitlement: boolean;
  hasLifetimePurchase: boolean;
  now: Date;
};

export type StripeBillingCatalog = {
  enabled: boolean;
  introEligible: boolean;
  prices: Record<string, string>;
  launchOffer: {
    eligible: boolean;
    endsAt: string | null;
  };
};

export type StripeBillingAccountContext = {
  profileCreatedAt: string;
  stripeCustomerId: string | null;
  firstSubscriptionPaidAt: string | null;
  hasActiveEntitlement: boolean;
  hasLifetimePurchase: boolean;
};

export type StripeCheckoutSessionInput = {
  customerId: string;
  userId: string;
  productId: string;
  priceId: string;
  couponId: string | null;
  mode: "payment" | "subscription";
  surface: "native" | "web";
  successUrl: string;
  cancelUrl: string;
};

export type PomodoistStripeBillingDeps = {
  enabled: boolean;
  authenticate: (
    authorization: string,
  ) => Promise<{ userId: string; email: string | null } | null>;
  loadAccount: (userId: string) => Promise<StripeBillingAccountContext>;
  createCustomer: (account: {
    userId: string;
    email: string | null;
  }) => Promise<string>;
  linkCustomer: (userId: string, customerId: string) => Promise<string>;
  createCheckoutSession: (
    input: StripeCheckoutSessionInput,
  ) => Promise<{ url: string | null }>;
  priceIds: Record<string, string>;
  couponIds: Record<string, string>;
  successUrl: string;
  cancelUrl: string;
  now?: () => Date;
};

export const pomodoistStripeBillingCorsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

export function stripeCheckoutParams(
  input: StripeCheckoutSessionInput,
): Record<string, unknown> {
  const metadata = {
    supabase_user_id: input.userId,
    product_id: input.productId,
  };
  return {
    customer: input.customerId,
    client_reference_id: input.userId,
    line_items: [{ price: input.priceId, quantity: 1 }],
    mode: input.mode,
    managed_payments: { enabled: true },
    integration_identifier: "pomodoist_checkout_kmfwqzrt",
    ...(input.surface === "native" ? { origin_context: "mobile_app" } : {}),
    metadata,
    ...(input.mode === "subscription"
      ? { subscription_data: { metadata } }
      : { payment_intent_data: { metadata } }),
    ...(input.couponId == null
      ? {}
      : { discounts: [{ coupon: input.couponId }] }),
    success_url: input.successUrl,
    cancel_url: input.cancelUrl,
  };
}

const launchCycleMs = 7 * 24 * 60 * 60 * 1000;
const launchWindowMs = 24 * 60 * 60 * 1000;
const subscriptionProductIds = new Set([
  "pomodoist.pro.monthly",
  "pomodoist.pro.annual",
]);
const lifetimeProductIds = new Set([
  "pomodoist.pro.lifetime",
  "pomodoist.pro.lifetime.launch",
]);

export function stripeCatalogForAccount(
  account: StripeCatalogAccount,
): StripeBillingCatalog {
  const anchorMs = Date.parse(account.profileCreatedAt);
  const nowMs = account.now.getTime();
  const elapsedMs = nowMs - anchorMs;
  const cyclePositionMs = elapsedMs >= 0 && Number.isFinite(anchorMs)
    ? elapsedMs % launchCycleMs
    : launchWindowMs;
  const launchEligible = account.enabled &&
    !account.hasActiveEntitlement &&
    !account.hasLifetimePurchase &&
    cyclePositionMs < launchWindowMs;

  return {
    enabled: account.enabled,
    introEligible: account.firstSubscriptionPaidAt == null,
    prices: {
      "pomodoist.pro.monthly": "$5.99",
      "pomodoist.pro.annual": "$39",
      "pomodoist.pro.lifetime": "$99.99",
      "pomodoist.pro.lifetime.launch": "$89.99",
    },
    launchOffer: {
      eligible: launchEligible,
      endsAt: launchEligible
        ? new Date(nowMs + launchWindowMs - cyclePositionMs).toISOString()
        : null,
    },
  };
}

export async function handlePomodoistStripeBilling(
  req: Request,
  deps: PomodoistStripeBillingDeps,
) {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: pomodoistStripeBillingCorsHeaders });
  }
  if (req.method !== "POST") {
    return json(
      { code: "method_not_allowed", error: "Method not allowed." },
      405,
    );
  }
  const authorization = req.headers.get("Authorization");
  if (!authorization) {
    return json(
      { code: "authentication_required", error: "Authentication required." },
      401,
    );
  }
  const account = await deps.authenticate(authorization);
  if (account == null) {
    return json(
      { code: "authentication_required", error: "Authentication required." },
      401,
    );
  }
  const parsed = await readLimitedJson(req, 4096);
  if (!parsed.ok) {
    return json(
      { code: "invalid_request", error: parsed.error },
      parsed.status,
    );
  }
  if (!isRecord(parsed.value) || typeof parsed.value.action !== "string") {
    return json(
      { code: "invalid_request", error: "A valid action is required." },
      400,
    );
  }
  if (parsed.value.action === "catalog") {
    const context = await deps.loadAccount(account.userId);
    return json(
      stripeCatalogForAccount({
        enabled: deps.enabled,
        profileCreatedAt: context.profileCreatedAt,
        firstSubscriptionPaidAt: context.firstSubscriptionPaidAt,
        hasActiveEntitlement: context.hasActiveEntitlement,
        hasLifetimePurchase: context.hasLifetimePurchase,
        now: deps.now?.() ?? new Date(),
      }),
    );
  }
  if (parsed.value.action !== "checkout") {
    return json(
      { code: "invalid_request", error: "Unknown billing action." },
      400,
    );
  }
  if (!deps.enabled) {
    return json(
      { code: "billing_disabled", error: "Stripe checkout is disabled." },
      503,
    );
  }
  const productId = parsed.value.productId;
  const surface = parsed.value.surface;
  if (
    typeof productId !== "string" ||
    (!subscriptionProductIds.has(productId) &&
      !lifetimeProductIds.has(productId)) ||
    typeof deps.priceIds[productId] !== "string"
  ) {
    return json(
      { code: "invalid_product", error: "Unknown Pomodoist product." },
      400,
    );
  }
  if (surface !== "web" && surface !== "native") {
    return json(
      { code: "invalid_request", error: "Unknown checkout surface." },
      400,
    );
  }
  const context = await deps.loadAccount(account.userId);
  if (context.hasActiveEntitlement) {
    return json(
      { code: "already_entitled", error: "Pomodoist Pro is already active." },
      409,
    );
  }
  const catalog = stripeCatalogForAccount({
    enabled: deps.enabled,
    profileCreatedAt: context.profileCreatedAt,
    firstSubscriptionPaidAt: context.firstSubscriptionPaidAt,
    hasActiveEntitlement: context.hasActiveEntitlement,
    hasLifetimePurchase: context.hasLifetimePurchase,
    now: deps.now?.() ?? new Date(),
  });
  if (
    productId === "pomodoist.pro.lifetime.launch" &&
    !catalog.launchOffer.eligible
  ) {
    return json(
      { code: "offer_expired", error: "The launch offer is not active." },
      409,
    );
  }

  try {
    let customerId = context.stripeCustomerId;
    if (customerId == null) {
      const createdCustomerId = await deps.createCustomer(account);
      customerId = await deps.linkCustomer(account.userId, createdCustomerId);
    }
    const subscription = subscriptionProductIds.has(productId);
    const session = await deps.createCheckoutSession({
      customerId,
      userId: account.userId,
      productId,
      priceId: deps.priceIds[productId],
      couponId: subscription && catalog.introEligible
        ? deps.couponIds[productId] ?? null
        : null,
      mode: subscription ? "subscription" : "payment",
      surface,
      successUrl: deps.successUrl,
      cancelUrl: deps.cancelUrl,
    });
    if (session.url == null || !isAllowedCheckoutUrl(session.url)) {
      throw new Error("Stripe returned an invalid Checkout URL.");
    }
    return json({ url: session.url });
  } catch (error) {
    if (
      isRecord(error) &&
      (String(error.param ?? "").startsWith("managed_payments") ||
        String(error.code ?? "").startsWith("managed_payments") ||
        String(error.message ?? "").toLowerCase().includes("managed payments"))
    ) {
      return json(
        {
          code: "managed_payments_unavailable",
          error: "Stripe Managed Payments is unavailable.",
        },
        503,
      );
    }
    return json(
      { code: "checkout_failed", error: "Could not start Stripe checkout." },
      502,
    );
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isAllowedCheckoutUrl(value: string) {
  try {
    const url = new URL(value);
    return url.protocol === "https:" && url.hostname === "checkout.stripe.com";
  } catch {
    return false;
  }
}

function json(value: unknown, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: {
      ...pomodoistStripeBillingCorsHeaders,
      "Content-Type": "application/json",
    },
  });
}
import { readLimitedJson } from "../_shared/limited_json.ts";

import { apiVersionError } from "../_shared/api_version.ts";
import type { AppleStoreTransaction } from "../_shared/apple_app_transaction.ts";
import { readLimitedJson } from "../_shared/limited_json.ts";
import {
  pomodoistAppleVerificationOptions,
  pomodoistPurchaseState,
} from "../_shared/pomodoist_storekit.ts";
import { type History, offerIds, record } from "./apple_server.ts";

export const campaignId = "return-2026-v1";
const waitingPeriod = 7 * 24 * 60 * 60 * 1000;
export type Signature = {
  nonce: string;
  timestamp: number;
  compactJws: string;
};
export type OfferDeps = {
  enabled: boolean;
  configured: boolean;
  signatureMaxAgeSeconds: number;
  environment: "Production" | "Sandbox";
  authenticate: (
    authorization: string | null,
  ) => Promise<{ userId: string; accountToken: string } | null>;
  verify: (
    jws: string,
    options: typeof pomodoistAppleVerificationOptions,
  ) => Promise<AppleStoreTransaction>;
  history: (seed: AppleStoreTransaction) => Promise<History>;
  state: (
    params: {
      p_environment: string;
      p_app_transaction_id: string;
      p_campaign_id: string;
      p_original_transaction_ids: string[];
      p_user_id: string | null;
      p_redeemed: boolean;
      p_product_id: string | null;
      p_nonce: string | null;
      p_timestamp: number | null;
      p_signature_max_age_seconds: number;
    },
  ) => Promise<{ code: string; retryAfter?: string }>;
  sign: (
    productId: string,
    transactionId: string,
    now: number,
  ) => Signature;
  now?: () => number;
};
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Cache-Control": "no-store",
};
const json = (body: unknown, status = 200) =>
  Response.json(body, { status, headers: cors });

export function evaluateHistory(
  seed: AppleStoreTransaction,
  history: History,
  now: number,
) {
  const all = [
    ...history.transactions,
    ...history.statuses.map((item) => item.transaction),
  ];
  const identities = new Set(
    all.map((item) => item.claims.appTransactionId).filter((id) =>
      typeof id === "string" && /^[0-9]{1,128}$/.test(id)
    ),
  );
  if (
    identities.size !== 1 ||
    all.some((item) =>
      item.environment !== seed.environment ||
      item.bundleId !== seed.bundleId ||
      (item.claims.appTransactionId != null &&
        !identities.has(item.claims.appTransactionId))
    )
  ) throw new Error("unsupported_identity");
  const appTransactionId = [...identities][0] as string;
  if (
    seed.claims.appTransactionId != null &&
    seed.claims.appTransactionId !== appTransactionId
  ) throw new Error("invalid_proof");
  if (
    !history.transactions.some((item) =>
      item.transactionId === seed.transactionId
    )
  ) throw new Error("invalid_history");
  const redeemed = all.some((item) =>
    Object.values(offerIds).includes(item.claims.offerIdentifier as string)
  );
  let lastExpiry = -Infinity;
  let eligible = history.statuses.length > 0;
  for (const item of all) {
    if (item.claims.inAppOwnershipType === "FAMILY_SHARED") eligible = false;
    const state = pomodoistPurchaseState(item, new Date(now));
    if (!state || state.status === "active") eligible = false;
    if (state?.purchaseType === "subscription" && state.status !== "revoked") {
      lastExpiry = Math.max(lastExpiry, Date.parse(item.expiresDate!));
    }
  }
  for (const item of history.statuses) {
    if (
      item.status !== 2 || item.renewal.isInBillingRetryPeriod === true ||
      (typeof item.renewal.gracePeriodExpiresDate === "number" &&
        item.renewal.gracePeriodExpiresDate > now)
    ) eligible = false;
  }
  eligible &&= Number.isFinite(lastExpiry) &&
    now >= lastExpiry + waitingPeriod && !redeemed;
  return {
    eligible,
    redeemed,
    appTransactionId,
    originalTransactionIds: [
      ...new Set(all.map((item) => item.originalTransactionId)),
    ],
  };
}

export async function handleSubscriptionOffer(
  req: Request,
  deps: OfferDeps,
): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ code: "method_not_allowed" }, 405);
  if (
    deps.enabled && (!deps.configured ||
      !Number.isInteger(deps.signatureMaxAgeSeconds) ||
      deps.signatureMaxAgeSeconds < 1 ||
      deps.signatureMaxAgeSeconds > 604800)
  ) {
    return json({ code: "offer_unavailable" }, 503);
  }
  const parsed = await readLimitedJson(req, 40_000);
  if (!parsed.ok) return json({ code: "invalid_request" }, parsed.status);
  const versionError = apiVersionError(parsed.value);
  if (versionError) return json(versionError, 400);
  const body = parsed.value;
  // Read only the action before the rollout gate; disabled eligibility must not
  // depend on a purchase proof, account, Apple request, or signing credentials.
  if (!deps.enabled) {
    return record(body) && body.action === "eligibility"
      ? json({ eligible: false, offerIds: {} })
      : json({ code: "offer_unavailable" }, 503);
  }
  if (
    !record(body) || !["eligibility", "sign"].includes(body.action as string) ||
    typeof body.transaction !== "string" || body.transaction.length < 1 ||
    body.transaction.length > 32_768 ||
    (body.action === "sign" &&
      (typeof body.productId !== "string" ||
        !Object.hasOwn(offerIds, body.productId))) ||
    (body.appAccountToken != null &&
      (typeof body.appAccountToken !== "string" ||
        !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
          body.appAccountToken,
        )))
  ) return json({ code: "invalid_request" }, 400);
  let account: Awaited<ReturnType<OfferDeps["authenticate"]>>;
  try {
    account = await deps.authenticate(req.headers.get("Authorization"));
  } catch {
    return json({ code: "authentication_failed" }, 401);
  }
  let seed: AppleStoreTransaction;
  try {
    seed = await deps.verify(
      body.transaction,
      {
        ...pomodoistAppleVerificationOptions,
        allowedEnvironments: [deps.environment],
      },
    );
  } catch {
    return json({ code: "invalid_proof" }, 401);
  }
  if (
    seed.environment !== deps.environment ||
    !Object.hasOwn(offerIds, seed.productId) ||
    !/^[0-9]{1,128}$/.test(seed.transactionId)
  ) return json({ code: "invalid_proof" }, 401);
  const accountToken = typeof body.appAccountToken === "string"
    ? body.appAccountToken.toLowerCase()
    : null;
  if (
    (accountToken != null &&
      accountToken !== account?.accountToken.toLowerCase()) ||
    (account != null && seed.appAccountToken != null &&
      seed.appAccountToken.toLowerCase() !==
        account.accountToken.toLowerCase()) ||
    (body.action === "sign" && account != null &&
      accountToken !== account.accountToken.toLowerCase())
  ) return json({ code: "purchase_already_linked" }, 403);
  try {
    const history = await deps.history(seed);
    const now = deps.now?.() ?? Date.now();
    const evaluated = evaluateHistory(seed, history, now);
    if (
      account &&
      [...history.transactions, ...history.statuses.map((s) => s.transaction)]
        .some((item) =>
          item.appAccountToken != null &&
          item.appAccountToken.toLowerCase() !==
            account.accountToken.toLowerCase()
        )
    ) return json({ code: "purchase_already_linked" }, 403);
    // Prepare privately first; DB must reserve successfully before any signature leaves the server.
    const signature = body.action === "sign" && evaluated.eligible
      ? deps.sign(body.productId as string, evaluated.appTransactionId, now)
      : null;
    const state = await deps.state({
      p_environment: seed.environment,
      p_app_transaction_id: evaluated.appTransactionId,
      p_campaign_id: campaignId,
      p_original_transaction_ids: evaluated.originalTransactionIds,
      p_user_id: account?.userId ?? null,
      p_redeemed: evaluated.redeemed,
      p_product_id: signature ? body.productId as string : null,
      p_nonce: signature?.nonce ?? null,
      p_timestamp: signature?.timestamp ?? null,
      p_signature_max_age_seconds: deps.signatureMaxAgeSeconds,
    });
    const eligible = evaluated.eligible && state.code === "eligible";
    if (body.action === "eligibility") {
      return json({
        eligible,
        offerIds: eligible ? offerIds : {},
        ...(state.code === "offer_pending" ? state : {}),
      });
    }
    if (!eligible || !signature) {
      return json({
        code: state.code === "eligible" ? "not_eligible" : state.code,
        ...(state.retryAfter ? { retryAfter: state.retryAfter } : {}),
      }, 409);
    }
    return json({
      offerId: offerIds[body.productId as string],
      compactJws: signature.compactJws,
    });
  } catch {
    return json({ code: "offer_unavailable" }, 503);
  }
}

import type {
  AppleAppStoreNotification,
  AppleStoreTransaction,
} from "../_shared/apple_app_transaction.ts";
import { readLimitedJson } from "../_shared/limited_json.ts";
import {
  pomodoistAppleVerificationOptions,
  pomodoistPurchaseState,
} from "../_shared/pomodoist_storekit.ts";
import type {
  PomodoistPurchaseRpcParams,
} from "../pomodoist-purchase/pomodoist_purchase.ts";

const maxBodyBytes = 262_144;
const maxSignedPayloadLength = 196_608;

export type PomodoistAppStoreNotificationDeps = {
  verifyNotification: (
    jws: string,
    options: typeof pomodoistAppleVerificationOptions,
  ) => Promise<AppleAppStoreNotification>;
  verifyTransaction: (
    jws: string,
    options: typeof pomodoistAppleVerificationOptions,
  ) => Promise<AppleStoreTransaction>;
  recordPurchase: (
    params: PomodoistPurchaseRpcParams,
  ) => Promise<{
    data: unknown;
    error: { message: string } | null;
  }>;
  now?: () => Date;
};

export async function handlePomodoistAppStoreNotification(
  req: Request,
  deps: PomodoistAppStoreNotificationDeps,
) {
  if (req.method === "OPTIONS") {
    return new Response("ok");
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed." }, 405);
  }

  const parsed = await readLimitedJson(req, maxBodyBytes);
  if (!parsed.ok) {
    return json({ error: parsed.error }, parsed.status);
  }
  if (!isRecord(parsed.value)) {
    return json({ error: "signedPayload is required." }, 400);
  }
  const signedPayload = parsed.value.signedPayload;
  if (
    typeof signedPayload !== "string" ||
    signedPayload.length < 1 ||
    signedPayload.length > maxSignedPayloadLength
  ) {
    return json({ error: "signedPayload is invalid." }, 400);
  }

  let notification: AppleAppStoreNotification;
  try {
    notification = await deps.verifyNotification(
      signedPayload,
      pomodoistAppleVerificationOptions,
    );
  } catch {
    return json({ error: "Could not verify App Store notification." }, 401);
  }
  if (notification.signedTransactionJws == null) {
    return json({ ok: true, ignored: true });
  }

  let transaction: AppleStoreTransaction;
  try {
    transaction = await deps.verifyTransaction(
      notification.signedTransactionJws,
      pomodoistAppleVerificationOptions,
    );
  } catch {
    return json({ error: "Could not verify App Store transaction." }, 401);
  }

  const state = pomodoistPurchaseState(
    transaction,
    deps.now?.() ?? new Date(),
  );
  if (
    state == null ||
    transaction.purchaseDate == null ||
    transaction.originalTransactionId.length > 128 ||
    transaction.transactionId.length > 128
  ) {
    return json({ ok: true, ignored: true });
  }

  const { data, error } = await deps.recordPurchase({
    p_original_transaction_id: transaction.originalTransactionId,
    p_latest_transaction_id: transaction.transactionId,
    p_product_id: transaction.productId,
    p_environment: transaction.environment,
    p_purchase_type: state.purchaseType,
    p_purchased_at: transaction.purchaseDate,
    p_expires_at: transaction.expiresDate ?? null,
    p_revoked_at: transaction.revocationDate ?? null,
    p_app_account_token: transaction.appAccountToken ?? null,
    p_signed_at: notification.signedDate,
    p_raw_claims: transaction.claims,
    p_user_id: null,
  });
  if (error) {
    return json({ error: "Could not save App Store notification." }, 500);
  }
  return json({ ok: true, entitlement: data });
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function json(value: unknown, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

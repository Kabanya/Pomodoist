import type { AppleStoreTransaction } from "../_shared/apple_app_transaction.ts";
import { readLimitedJson } from "../_shared/limited_json.ts";
import {
  pomodoistBundleId,
  pomodoistPurchaseState,
} from "../_shared/pomodoist_storekit.ts";

const maxBodyBytes = 3_300_000;
const maxTransactions = 100;
const maxJwsLength = 32_768;

export type PomodoistPurchaseRpcParams = {
  p_original_transaction_id: string;
  p_latest_transaction_id: string;
  p_product_id: string;
  p_environment: string;
  p_purchase_type: "subscription" | "lifetime";
  p_purchased_at: string;
  p_expires_at: string | null;
  p_revoked_at: string | null;
  p_app_account_token: string | null;
  p_signed_at: string;
  p_raw_claims: Record<string, unknown>;
  p_user_id: string | null;
};

export type PomodoistPurchaseDeps = {
  authenticate: (
    authorization: string,
  ) => Promise<{ userId: string; accountToken: string } | null>;
  verifyStoreTransaction: (
    jws: string,
    options: { bundleId: string },
  ) => Promise<AppleStoreTransaction>;
  recordPurchase: (
    params: PomodoistPurchaseRpcParams,
  ) => Promise<{
    data: unknown;
    error: { message: string } | null;
  }>;
  now?: () => Date;
};

export const pomodoistPurchaseCorsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

export async function handlePomodoistPurchase(
  req: Request,
  deps: PomodoistPurchaseDeps,
) {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: pomodoistPurchaseCorsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed." }, 405);
  }

  const authorization = req.headers.get("Authorization");
  if (!authorization) {
    return json({ error: "Authentication required." }, 401);
  }

  let account: { userId: string; accountToken: string } | null;
  try {
    account = await deps.authenticate(authorization);
  } catch {
    return json({ error: "Could not read account." }, 500);
  }
  if (!account) {
    return json({ error: "Authentication required." }, 401);
  }

  const parsed = await readLimitedJson(req, maxBodyBytes);
  if (!parsed.ok) {
    return json({ error: parsed.error }, parsed.status);
  }
  if (!isRecord(parsed.value) || !Array.isArray(parsed.value.transactions)) {
    return json({ error: "transactions must be an array." }, 400);
  }
  const candidates = parsed.value.transactions;
  if (candidates.length < 1 || candidates.length > maxTransactions) {
    return json({ error: "transactions must contain 1 to 100 items." }, 400);
  }
  if (
    candidates.some((candidate) =>
      typeof candidate !== "string" ||
      candidate.length < 1 ||
      candidate.length > maxJwsLength
    )
  ) {
    return json(
      { error: "Every transaction must be a valid compact JWS." },
      400,
    );
  }

  const accepted: Array<{
    transaction: AppleStoreTransaction;
    purchaseType: "subscription" | "lifetime";
  }> = [];
  for (const jws of candidates as string[]) {
    try {
      const transaction = await deps.verifyStoreTransaction(jws, {
        bundleId: pomodoistBundleId,
      });
      const state = pomodoistPurchaseState(
        transaction,
        deps.now?.() ?? new Date(),
      );
      if (
        state == null ||
        transaction.purchaseDate == null ||
        transaction.signedDate == null ||
        !Number.isFinite(Date.parse(transaction.signedDate)) ||
        transaction.originalTransactionId.length > 128 ||
        transaction.transactionId.length > 128
      ) {
        continue;
      }
      if (
        transaction.appAccountToken != null &&
        transaction.appAccountToken.toLowerCase() !==
          account.accountToken.toLowerCase()
      ) {
        return purchaseAlreadyLinked();
      }
      accepted.push({
        transaction,
        purchaseType: state.purchaseType,
      });
    } catch {
      // StoreKit may return obsolete or unverifiable history beside valid rows.
    }
  }

  if (accepted.length === 0) {
    return json({ error: "Could not verify App Store purchase." }, 401);
  }

  const entitlements: unknown[] = [];
  for (const { transaction, purchaseType } of accepted) {
    const { data, error } = await deps.recordPurchase({
      p_original_transaction_id: transaction.originalTransactionId,
      p_latest_transaction_id: transaction.transactionId,
      p_product_id: transaction.productId,
      p_environment: transaction.environment,
      p_purchase_type: purchaseType,
      p_purchased_at: transaction.purchaseDate!,
      p_expires_at: transaction.expiresDate ?? null,
      p_revoked_at: transaction.revocationDate ?? null,
      p_app_account_token: transaction.appAccountToken ?? null,
      p_signed_at: transaction.signedDate!,
      p_raw_claims: transaction.claims,
      p_user_id: account.userId,
    });
    if (error) {
      if (error.message.includes("pomodoist_purchase_already_linked")) {
        return purchaseAlreadyLinked();
      }
      return json({ error: "Could not save App Store purchase." }, 500);
    }
    entitlements.push(data);
  }

  return json({ ok: true, entitlements });
}

function purchaseAlreadyLinked() {
  return json({
    ok: false,
    code: "purchase_already_linked",
    error: "This App Store purchase is linked to another account.",
  });
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function json(value: unknown, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: {
      ...pomodoistPurchaseCorsHeaders,
      "Content-Type": "application/json",
    },
  });
}

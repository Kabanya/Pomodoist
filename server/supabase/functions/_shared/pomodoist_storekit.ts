import type { AppleStoreTransaction } from "./apple_app_transaction.ts";

export const pomodoistBundleId = "com.finchforge.pomodoist";

const productTypes = new Map<string, "subscription" | "lifetime">([
  ["pomodoist.pro.monthly", "subscription"],
  ["pomodoist.pro.annual", "subscription"],
  ["pomodoist.pro.lifetime", "lifetime"],
  ["pomodoist.pro.lifetime.launch", "lifetime"],
]);

export type PomodoistPurchaseState = {
  purchaseType: "subscription" | "lifetime";
  status: "active" | "expired" | "revoked";
  validUntil: string | null;
};

export function pomodoistPurchaseState(
  transaction: AppleStoreTransaction,
  now: Date,
): PomodoistPurchaseState | null {
  if (transaction.bundleId !== pomodoistBundleId) {
    return null;
  }
  const purchaseType = productTypes.get(transaction.productId);
  if (purchaseType == null) {
    return null;
  }
  if (transaction.revocationDate != null) {
    return {
      purchaseType,
      status: "revoked",
      validUntil: transaction.revocationDate,
    };
  }
  if (purchaseType === "lifetime") {
    return { purchaseType, status: "active", validUntil: null };
  }
  const expiresAt = transaction.expiresDate == null
    ? Number.NaN
    : Date.parse(transaction.expiresDate);
  if (!Number.isFinite(expiresAt)) {
    return null;
  }
  return {
    purchaseType,
    status: expiresAt > now.getTime() ? "active" : "expired",
    validUntil: new Date(expiresAt).toISOString(),
  };
}

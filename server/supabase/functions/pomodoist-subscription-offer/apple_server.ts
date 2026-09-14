import { createPrivateKey, sign } from "node:crypto";
import {
  type AppleStoreTransaction,
  verifyAppleRenewalInfoJws,
  verifyAppleStoreTransactionJws,
} from "../_shared/apple_app_transaction.ts";
import {
  pomodoistAppleVerificationOptions,
  pomodoistBundleId,
} from "../_shared/pomodoist_storekit.ts";

export const offerIds: Record<string, string> = {
  "pomodoist.pro.monthly": "return_monthly_2026_v1",
  "pomodoist.pro.annual": "return_annual_2026_v1",
};
export type AppleCredentials = {
  keyID: string;
  issuerId: string;
  privateKey: string;
};
export type History = {
  transactions: AppleStoreTransaction[];
  statuses: {
    status: number;
    transaction: AppleStoreTransaction;
    renewal: Record<string, unknown>;
  }[];
};
const encoder = new TextEncoder();
const b64url = (value: Uint8Array) =>
  btoa(String.fromCharCode(...value)).replace(/=/g, "").replace(/\+/g, "-")
    .replace(/\//g, "_");

export function promotionalSignature(
  credentials: AppleCredentials,
  productId: string,
  transactionId: string,
  now: number,
) {
  if (
    !/^[0-9]{1,128}$/.test(transactionId) || !Object.hasOwn(offerIds, productId)
  ) {
    throw new Error("invalid_offer_binding");
  }
  const nonce = crypto.randomUUID().toLowerCase();
  const compactJws = signedJws(credentials, {
    iss: credentials.issuerId,
    iat: Math.floor(now / 1000),
    aud: "promotional-offer",
    bid: pomodoistBundleId,
    nonce,
    productId,
    offerIdentifier: offerIds[productId],
    // Required here even though Apple makes it optional: prevents using a
    // copied authorization with a different App Store customer.
    transactionId,
  });
  // Apple calculates expiration from iat; an exp claim makes this request fail.
  return { nonce, timestamp: now, compactJws };
}

function serverToken(credentials: AppleCredentials, now: number) {
  return signedJws(credentials, {
    iss: credentials.issuerId,
    iat: Math.floor(now / 1000),
    exp: Math.floor(now / 1000) + 300,
    aud: "appstoreconnect-v1",
    bid: pomodoistBundleId,
  });
}

function signedJws(
  credentials: AppleCredentials,
  claims: Record<string, unknown>,
) {
  const header = b64url(encoder.encode(JSON.stringify({
    alg: "ES256",
    kid: credentials.keyID,
    typ: "JWT",
  })));
  const payload = b64url(encoder.encode(JSON.stringify(claims)));
  return `${header}.${payload}.${
    b64url(sign("sha256", encoder.encode(`${header}.${payload}`), {
      key: createPrivateKey(credentials.privateKey),
      dsaEncoding: "ieee-p1363",
    }))
  }`;
}

// Fetch every product and state; filtering to the seed subscription would hide lifetime or another chain.
export async function fetchAppleHistory(
  seed: AppleStoreTransaction,
  credentials: AppleCredentials,
  fetcher: typeof fetch = fetch,
  verifyTransaction = verifyAppleStoreTransactionJws,
  verifyRenewal = verifyAppleRenewalInfoJws,
): Promise<History> {
  if (
    !/^[0-9]{1,128}$/.test(seed.transactionId) ||
    !["Production", "Sandbox"].includes(seed.environment)
  ) throw new Error("invalid_seed");
  const host = seed.environment === "Production"
    ? "https://api.storekit.apple.com"
    : "https://api.storekit-sandbox.apple.com";
  const authorization = `Bearer ${serverToken(credentials, Date.now())}`;
  const options = {
    ...pomodoistAppleVerificationOptions,
    allowedEnvironments: [seed.environment],
  };
  const deadline = Date.now() + 60_000;
  async function get(path: string) {
    const remaining = deadline - Date.now();
    if (remaining <= 0) throw new Error("apple_timeout");
    const response = await fetcher(`${host}${path}`, {
      headers: { Authorization: authorization },
      signal: AbortSignal.timeout(Math.min(remaining, 10_000)),
      redirect: "error",
    });
    if (!response.ok) {
      await response.body?.cancel();
      throw new Error("apple_unavailable");
    }
    // Bound bodies before parsing, including chunked transfer responses.
    const { readLimitedJson } = await import("../_shared/limited_json.ts");
    const parsed = await readLimitedJson(
      new Request(
        host,
        { method: "POST", body: response.body, duplex: "half" } as RequestInit,
      ),
      4_000_000,
    );
    if (!parsed.ok || !record(parsed.value)) {
      throw new Error("invalid_apple_response");
    }
    if (
      parsed.value.bundleId !== pomodoistBundleId ||
      parsed.value.environment !== seed.environment
    ) throw new Error("invalid_apple_response");
    return parsed.value;
  }
  async function transaction(jws: unknown) {
    if (typeof jws !== "string" || jws.length > 32_768) {
      throw new Error("invalid_apple_response");
    }
    return await verifyTransaction(jws, options);
  }
  const transactions = new Map<string, AppleStoreTransaction>();
  const revisions = new Set<string>();
  let revision = "";
  for (let page = 0;; page++) {
    if (page >= 100) throw new Error("apple_history_limit");
    const data = await get(
      `/inApps/v2/history/${seed.transactionId}${
        revision ? `?revision=${encodeURIComponent(revision)}` : ""
      }`,
    );
    if (
      !Array.isArray(data.signedTransactions) ||
      data.signedTransactions.length > 20 || typeof data.hasMore !== "boolean"
    ) throw new Error("invalid_apple_response");
    for (const jws of data.signedTransactions) {
      const item = await transaction(jws);
      const previous = transactions.get(item.transactionId);
      if (
        !previous ||
        Date.parse(item.signedDate!) >= Date.parse(previous.signedDate!)
      ) transactions.set(item.transactionId, item);
    }
    if (!data.hasMore) break;
    if (
      typeof data.revision !== "string" || !data.revision ||
      data.revision.length > 4096 || revisions.has(data.revision)
    ) throw new Error("invalid_apple_pagination");
    revision = data.revision;
    revisions.add(revision);
  }
  if (!transactions.has(seed.transactionId)) {
    throw new Error("seed_missing_from_history");
  }
  const response = await get(`/inApps/v1/subscriptions/${seed.transactionId}`);
  if (!Array.isArray(response.data) || response.data.length > 100) {
    throw new Error("invalid_apple_status");
  }
  const statuses: History["statuses"] = [];
  for (const group of response.data) {
    if (
      !record(group) || !Array.isArray(group.lastTransactions) ||
      group.lastTransactions.length > 100
    ) throw new Error("invalid_apple_status");
    for (const row of group.lastTransactions) {
      if (
        !record(row) || ![1, 2, 3, 4, 5].includes(row.status as number) ||
        typeof row.signedRenewalInfo !== "string" ||
        row.signedRenewalInfo.length > 32_768
      ) throw new Error("invalid_apple_status");
      const item = await transaction(row.signedTransactionInfo);
      const renewal = await verifyRenewal(row.signedRenewalInfo, options);
      if (
        renewal.originalTransactionId !== item.originalTransactionId ||
        row.originalTransactionId !== item.originalTransactionId
      ) throw new Error("invalid_apple_status");
      statuses.push({
        status: row.status as number,
        transaction: item,
        renewal,
      });
    }
  }
  return { transactions: [...transactions.values()], statuses };
}

export function record(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

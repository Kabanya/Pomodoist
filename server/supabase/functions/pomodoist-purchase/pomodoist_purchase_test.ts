import { assertEquals } from "@std/assert";

import type { AppleStoreTransaction } from "../_shared/apple_app_transaction.ts";
import { pomodoistBundleId } from "../_shared/pomodoist_storekit.ts";
import {
  handlePomodoistPurchase,
  type PomodoistPurchaseDeps,
} from "./pomodoist_purchase.ts";

const userId = "11111111-1111-1111-1111-111111111111";
const accountToken = "22222222-2222-4222-8222-222222222222";
const now = new Date("2026-07-27T12:00:00.000Z");

Deno.test("links verified StoreKit transactions to the signed-in user", async () => {
  const calls: Array<Record<string, unknown>> = [];
  const response = await handlePomodoistPurchase(
    request(["signed-lifetime", "signed-expired"]),
    deps({
      calls,
      transactions: {
        "signed-lifetime": transaction(),
        "signed-expired": transaction({
          transactionId: "transaction-2",
          originalTransactionId: "original-2",
          productId: "pomodoist.pro.monthly",
          expiresDate: "2026-06-27T10:00:00.000Z",
        }),
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(calls.length, 2);
  assertEquals(calls[0].p_user_id, userId);
  assertEquals(calls[0].p_purchase_type, "lifetime");
  assertEquals(calls[0].p_signed_at, "2026-07-27T10:00:01.000Z");
  assertEquals(calls[1].p_purchase_type, "subscription");
  assertEquals(calls[1].p_expires_at, "2026-06-27T10:00:00.000Z");
  assertEquals(await response.json(), {
    ok: true,
    entitlements: [
      {
        applied: true,
        originalTransactionId: "original-1",
        status: "active",
      },
      {
        applied: true,
        originalTransactionId: "original-2",
        status: "expired",
      },
    ],
  });
});

Deno.test("requires a signed-in account before reading purchase proofs", async () => {
  let authenticated = false;
  const response = await handlePomodoistPurchase(
    request(["signed-lifetime"], null),
    deps({
      authenticate: () => {
        authenticated = true;
        return Promise.resolve({ userId, accountToken });
      },
    }),
  );

  assertEquals(response.status, 401);
  assertEquals(authenticated, false);
});

Deno.test("rejects malformed and oversized transaction collections", async (t) => {
  const cases: Array<[string, Request, number]> = [
    [
      "non-array",
      rawRequest(JSON.stringify({ transactions: "signed" })),
      400,
    ],
    [
      "empty",
      rawRequest(JSON.stringify({ transactions: [] })),
      400,
    ],
    [
      "over 100",
      request(Array.from({ length: 101 }, () => "signed")),
      400,
    ],
    ["oversized JWS", request(["x".repeat(32_769)]), 400],
    ["oversized body", rawRequest("x".repeat(3_300_001)), 413],
  ];

  for (const [name, candidate, expectedStatus] of cases) {
    await t.step(name, async () => {
      const calls: Array<Record<string, unknown>> = [];
      const response = await handlePomodoistPurchase(
        candidate,
        deps({ calls }),
      );
      assertEquals(response.status, expectedStatus);
      assertEquals(calls, []);
    });
  }
});

Deno.test("does not write unverified, unsupported, or incomplete proofs", async (t) => {
  const candidates: Record<string, AppleStoreTransaction | Error> = {
    invalid: new Error("bad signature"),
    unknown: transaction({ productId: "other.product" }),
    unsigned: transaction({ signedDate: undefined }),
  };

  for (const candidate of Object.keys(candidates)) {
    await t.step(candidate, async () => {
      const calls: Array<Record<string, unknown>> = [];
      const response = await handlePomodoistPurchase(
        request([candidate]),
        deps({
          calls,
          verifyStoreTransaction: (jws) => {
            const value = candidates[jws];
            return value instanceof Error
              ? Promise.reject(value)
              : Promise.resolve(value);
          },
        }),
      );
      assertEquals(response.status, 401);
      assertEquals(calls, []);
    });
  }
});

Deno.test("maps an App Account Token mismatch to permanent ownership conflict", async () => {
  const calls: Array<Record<string, unknown>> = [];
  const response = await handlePomodoistPurchase(
    request(["other-account"]),
    deps({
      calls,
      transactions: {
        "other-account": transaction({
          appAccountToken: "33333333-3333-4333-8333-333333333333",
        }),
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(calls, []);
  assertEquals(await response.json(), {
    ok: false,
    code: "purchase_already_linked",
    error: "This App Store purchase is linked to another account.",
  });
});

Deno.test("accepts matching App Account Tokens case-insensitively", async () => {
  const calls: Array<Record<string, unknown>> = [];
  const response = await handlePomodoistPurchase(
    request(["matching"]),
    deps({
      calls,
      accountToken: accountToken.toUpperCase(),
      transactions: {
        matching: transaction({ appAccountToken: accountToken }),
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(calls.length, 1);
});

Deno.test("maps the atomic RPC ownership conflict to a stable business result", async () => {
  const response = await handlePomodoistPurchase(
    request(["signed-lifetime"]),
    deps({ rpcError: "pomodoist_purchase_already_linked" }),
  );

  assertEquals(response.status, 200);
  assertEquals((await response.json()).code, "purchase_already_linked");
});

Deno.test("keeps same-account replay idempotent", async () => {
  const response = await handlePomodoistPurchase(
    request(["signed-lifetime"]),
    deps({
      rpcData: {
        applied: false,
        originalTransactionId: "original-1",
        status: "active",
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    ok: true,
    entitlements: [
      {
        applied: false,
        originalTransactionId: "original-1",
        status: "active",
      },
    ],
  });
});

function request(
  transactions: unknown[],
  authorization: string | null = "Bearer session",
) {
  return rawRequest(JSON.stringify({ transactions }), authorization);
}

function rawRequest(
  body: string,
  authorization: string | null = "Bearer session",
) {
  const headers = new Headers({ "Content-Type": "application/json" });
  if (authorization != null) {
    headers.set("Authorization", authorization);
  }
  return new Request("https://functions.test/pomodoist-purchase", {
    method: "POST",
    headers,
    body,
  });
}

function deps(
  options: {
    calls?: Array<Record<string, unknown>>;
    transactions?: Record<string, AppleStoreTransaction>;
    accountToken?: string;
    authenticate?: PomodoistPurchaseDeps["authenticate"];
    verifyStoreTransaction?: PomodoistPurchaseDeps["verifyStoreTransaction"];
    rpcData?: Record<string, unknown>;
    rpcError?: string;
  } = {},
): PomodoistPurchaseDeps {
  const calls = options.calls ?? [];
  const transactions = options.transactions ?? {
    "signed-lifetime": transaction(),
  };
  return {
    authenticate: options.authenticate ??
      (() =>
        Promise.resolve({
          userId,
          accountToken: options.accountToken ?? accountToken,
        })),
    verifyStoreTransaction: options.verifyStoreTransaction ??
      ((jws) => Promise.resolve(transactions[jws]!)),
    recordPurchase: (params) => {
      calls.push(params);
      return Promise.resolve({
        data: options.rpcData ?? {
          applied: true,
          originalTransactionId: params.p_original_transaction_id,
          status: params.p_purchase_type === "lifetime" ? "active" : "expired",
        },
        error: options.rpcError == null ? null : { message: options.rpcError },
      });
    },
    now: () => now,
  };
}

function transaction(
  overrides: Partial<AppleStoreTransaction> = {},
): AppleStoreTransaction {
  return {
    purchaseId: "original-1",
    originalTransactionId: "original-1",
    transactionId: "transaction-1",
    productId: "pomodoist.pro.lifetime",
    bundleId: pomodoistBundleId,
    environment: "Sandbox",
    appAccountToken: accountToken,
    purchaseDate: "2026-07-27T10:00:00.000Z",
    signedDate: "2026-07-27T10:00:01.000Z",
    claims: {},
    ...overrides,
  };
}

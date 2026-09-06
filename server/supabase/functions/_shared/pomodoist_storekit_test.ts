import { assertEquals } from "jsr:@std/assert@1";

import type { AppleStoreTransaction } from "./apple_app_transaction.ts";
import { pomodoistPurchaseState } from "./pomodoist_storekit.ts";

const now = new Date("2026-07-27T12:00:00.000Z");

Deno.test("Pomodoist StoreKit policy derives lifetime and subscription state", () => {
  assertEquals(
    pomodoistPurchaseState(
      transaction({ productId: "pomodoist.pro.lifetime" }),
      now,
    ),
    { purchaseType: "lifetime", status: "active", validUntil: null },
  );
  assertEquals(
    pomodoistPurchaseState(
      transaction({
        productId: "pomodoist.pro.monthly",
        expiresDate: "2026-08-27T12:00:00.000Z",
      }),
      now,
    ),
    {
      purchaseType: "subscription",
      status: "active",
      validUntil: "2026-08-27T12:00:00.000Z",
    },
  );
  assertEquals(
    pomodoistPurchaseState(
      transaction({
        productId: "pomodoist.pro.annual",
        expiresDate: "2026-06-27T12:00:00.000Z",
      }),
      now,
    ),
    {
      purchaseType: "subscription",
      status: "expired",
      validUntil: "2026-06-27T12:00:00.000Z",
    },
  );
  assertEquals(
    pomodoistPurchaseState(
      transaction({
        productId: "pomodoist.pro.lifetime.launch",
        revocationDate: "2026-07-01T00:00:00.000Z",
      }),
      now,
    ),
    {
      purchaseType: "lifetime",
      status: "revoked",
      validUntil: "2026-07-01T00:00:00.000Z",
    },
  );
});

Deno.test("Pomodoist StoreKit policy rejects unrelated or incomplete transactions", () => {
  assertEquals(
    pomodoistPurchaseState(transaction({ productId: "other.product" }), now),
    null,
  );
  assertEquals(
    pomodoistPurchaseState(
      transaction({
        productId: "pomodoist.pro.lifetime",
        bundleId: "com.example.other",
      }),
      now,
    ),
    null,
  );
  assertEquals(
    pomodoistPurchaseState(
      transaction({ productId: "pomodoist.pro.monthly" }),
      now,
    ),
    null,
  );
});

function transaction(
  overrides: Partial<AppleStoreTransaction>,
): AppleStoreTransaction {
  return {
    purchaseId: "original-1",
    transactionId: "transaction-1",
    originalTransactionId: "original-1",
    productId: "pomodoist.pro.lifetime",
    bundleId: "com.finchforge.pomodoist",
    environment: "Sandbox",
    claims: {},
    ...overrides,
  };
}

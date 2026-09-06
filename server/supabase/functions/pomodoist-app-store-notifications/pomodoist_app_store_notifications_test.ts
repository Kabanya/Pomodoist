import { assertEquals } from "@std/assert";

import type {
  AppleAppStoreNotification,
  AppleStoreTransaction,
} from "../_shared/apple_app_transaction.ts";
import { pomodoistBundleId } from "../_shared/pomodoist_storekit.ts";
import type { PomodoistPurchaseRpcParams } from "../pomodoist-purchase/pomodoist_purchase.ts";
import {
  handlePomodoistAppStoreNotification,
  type PomodoistAppStoreNotificationDeps,
} from "./pomodoist_app_store_notifications.ts";

const signedDate = "2026-07-27T12:00:00.000Z";
const now = new Date(signedDate);

Deno.test("records renewal, expiry, and revocation lifecycle updates", async (t) => {
  const cases: Array<{
    name: string;
    transaction: AppleStoreTransaction;
    expectedStatus: string;
    expectedExpiresAt: string | null;
    expectedRevokedAt: string | null;
  }> = [
    {
      name: "renewal",
      transaction: transaction({
        productId: "pomodoist.pro.monthly",
        expiresDate: "2026-08-27T12:00:00.000Z",
      }),
      expectedStatus: "active",
      expectedExpiresAt: "2026-08-27T12:00:00.000Z",
      expectedRevokedAt: null,
    },
    {
      name: "expiry",
      transaction: transaction({
        productId: "pomodoist.pro.monthly",
        expiresDate: "2026-06-27T12:00:00.000Z",
      }),
      expectedStatus: "expired",
      expectedExpiresAt: "2026-06-27T12:00:00.000Z",
      expectedRevokedAt: null,
    },
    {
      name: "revocation",
      transaction: transaction({
        revocationDate: "2026-07-26T12:00:00.000Z",
      }),
      expectedStatus: "revoked",
      expectedExpiresAt: null,
      expectedRevokedAt: "2026-07-26T12:00:00.000Z",
    },
  ];

  for (const fixture of cases) {
    await t.step(fixture.name, async () => {
      const calls: PomodoistPurchaseRpcParams[] = [];
      const response = await handlePomodoistAppStoreNotification(
        request("outer"),
        deps({ calls, transaction: fixture.transaction }),
      );

      assertEquals(response.status, 200);
      assertEquals(calls.length, 1);
      assertEquals(calls[0].p_expires_at, fixture.expectedExpiresAt);
      assertEquals(calls[0].p_revoked_at, fixture.expectedRevokedAt);
      assertEquals(calls[0].p_signed_at, signedDate);
      assertEquals(calls[0].p_user_id, null);
      assertEquals(
        (await response.json()).entitlement.status,
        fixture.expectedStatus,
      );
    });
  }
});

Deno.test("acknowledges replay and control notifications", async (t) => {
  await t.step("replay", async () => {
    const response = await handlePomodoistAppStoreNotification(
      request("outer"),
      deps({
        rpcData: {
          applied: false,
          originalTransactionId: "original-1",
          status: "active",
        },
      }),
    );
    assertEquals(response.status, 200);
    assertEquals((await response.json()).entitlement.applied, false);
  });

  await t.step("control", async () => {
    const calls: PomodoistPurchaseRpcParams[] = [];
    const response = await handlePomodoistAppStoreNotification(
      request("control"),
      deps({
        calls,
        notification: notification({ signedTransactionJws: undefined }),
      }),
    );
    assertEquals(response.status, 200);
    assertEquals(await response.json(), { ok: true, ignored: true });
    assertEquals(calls, []);
  });
});

Deno.test("rejects untrusted payloads without a database write", async (t) => {
  const cases: Array<{
    name: string;
    request: Request;
    options?: Parameters<typeof deps>[0];
    status: number;
  }> = [
    {
      name: "malformed JSON",
      request: rawRequest("{"),
      status: 400,
    },
    {
      name: "oversized request",
      request: rawRequest("x".repeat(262_145)),
      status: 413,
    },
    {
      name: "invalid outer signature",
      request: request("invalid-outer"),
      options: { outerError: true },
      status: 401,
    },
    {
      name: "invalid nested signature",
      request: request("outer"),
      options: { transactionError: true },
      status: 401,
    },
    {
      name: "wrong bundle",
      request: request("wrong-bundle"),
      options: { outerError: true },
      status: 401,
    },
    {
      name: "unknown product",
      request: request("outer"),
      options: {
        transaction: transaction({ productId: "other.product" }),
      },
      status: 200,
    },
  ];

  for (const fixture of cases) {
    await t.step(fixture.name, async () => {
      const calls: PomodoistPurchaseRpcParams[] = [];
      const response = await handlePomodoistAppStoreNotification(
        fixture.request,
        deps({ ...fixture.options, calls }),
      );
      assertEquals(response.status, fixture.status);
      assertEquals(calls, []);
    });
  }
});

Deno.test("App Store notification endpoint is the public Apple-signed exception", async () => {
  const config = await Deno.readTextFile(
    new URL("../../config.toml", import.meta.url),
  );
  const matches = config.matchAll(
    /\[functions\.pomodoist-app-store-notifications\]\s+verify_jwt = false/g,
  );
  assertEquals([...matches].length, 1);
});

function request(signedPayload: string) {
  return rawRequest(JSON.stringify({ signedPayload }));
}

function rawRequest(body: string) {
  return new Request(
    "https://functions.test/pomodoist-app-store-notifications",
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body,
    },
  );
}

function deps(
  options: {
    calls?: PomodoistPurchaseRpcParams[];
    notification?: AppleAppStoreNotification;
    transaction?: AppleStoreTransaction;
    outerError?: boolean;
    transactionError?: boolean;
    rpcData?: Record<string, unknown>;
  } = {},
): PomodoistAppStoreNotificationDeps {
  const calls = options.calls ?? [];
  return {
    verifyNotification: () =>
      options.outerError
        ? Promise.reject(new Error("invalid outer"))
        : Promise.resolve(options.notification ?? notification()),
    verifyTransaction: () =>
      options.transactionError
        ? Promise.reject(new Error("invalid transaction"))
        : Promise.resolve(options.transaction ?? transaction()),
    recordPurchase: (params) => {
      calls.push(params);
      return Promise.resolve({
        data: options.rpcData ?? {
          applied: true,
          originalTransactionId: params.p_original_transaction_id,
          status: params.p_revoked_at != null
            ? "revoked"
            : params.p_expires_at != null &&
                Date.parse(params.p_expires_at) <= now.getTime()
            ? "expired"
            : "active",
        },
        error: null,
      });
    },
    now: () => now,
  };
}

function notification(
  overrides: Partial<AppleAppStoreNotification> = {},
): AppleAppStoreNotification {
  return {
    notificationType: "DID_RENEW",
    notificationUuid: "notification-1",
    signedDate,
    environment: "Sandbox",
    signedTransactionJws: "nested",
    claims: {},
    ...overrides,
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
    purchaseDate: "2026-01-01T00:00:00.000Z",
    signedDate,
    claims: {},
    ...overrides,
  };
}

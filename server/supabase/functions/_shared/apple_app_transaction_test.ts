import { assertEquals, assertRejects } from "jsr:@std/assert@1";

import {
  verifyAppleAppStoreNotificationJws,
  verifyAppleAppTransactionJws,
  verifyAppleStoreTransactionJws,
} from "./apple_app_transaction.ts";

Deno.test("Apple AppTransaction verifier accepts a valid ES256 fixture", async () => {
  const jws = await fixtureJws({
    bundleId: "dev.nottica.notticaApp",
    environment: "Sandbox",
    appTransactionId: "app-tx-1",
  });

  const transaction = await verifyAppleAppTransactionJws(jws, {
    bundleId: "dev.nottica.notticaApp",
    allowJwkFixtures: true,
  });

  assertEquals(transaction.purchaseId, "app-tx-1");
  assertEquals(transaction.bundleId, "dev.nottica.notticaApp");
  assertEquals(transaction.environment, "Sandbox");
});

Deno.test("Apple AppTransaction verifier rejects wrong bundle and signature", async () => {
  const jws = await fixtureJws({
    bundleId: "com.example.Other",
    environment: "Sandbox",
    appTransactionId: "app-tx-1",
  });

  await assertRejects(
    () =>
      verifyAppleAppTransactionJws(jws, {
        bundleId: "dev.nottica.notticaApp",
        allowJwkFixtures: true,
      }),
    Error,
    "bundle id",
  );

  const valid = await fixtureJws({
    bundleId: "dev.nottica.notticaApp",
    environment: "Sandbox",
    appTransactionId: "app-tx-1",
  });
  const tampered = tamperSignature(valid);
  await assertRejects(
    () =>
      verifyAppleAppTransactionJws(tampered, {
        bundleId: "dev.nottica.notticaApp",
        allowJwkFixtures: true,
      }),
    Error,
    "signature",
  );
});

Deno.test("Apple AppTransaction verifier rejects JWK fixtures unless explicitly allowed", async () => {
  const jws = await fixtureJws({
    bundleId: "dev.nottica.notticaApp",
    environment: "Sandbox",
    appTransactionId: "app-tx-1",
  });

  await assertRejects(
    () =>
      verifyAppleAppTransactionJws(jws, { bundleId: "dev.nottica.notticaApp" }),
    Error,
    "x5c",
  );
});

Deno.test("Apple StoreKit verifier exposes the signed timestamp", async () => {
  const jws = await fixtureJws({
    bundleId: "com.finchforge.pomodoist",
    environment: "Sandbox",
    transactionId: "transaction-1",
    originalTransactionId: "original-1",
    productId: "pomodoist.pro.lifetime",
    signedDate: Date.parse("2026-07-27T12:00:00.000Z"),
  });

  const transaction = await verifyAppleStoreTransactionJws(jws, {
    bundleId: "com.finchforge.pomodoist",
    allowJwkFixtures: true,
  });

  assertEquals(transaction.signedDate, "2026-07-27T12:00:00.000Z");
});

Deno.test("Apple notification verifier exposes the nested transaction", async () => {
  const jws = await fixtureJws(notificationPayload());

  const notification = await verifyAppleAppStoreNotificationJws(jws, {
    bundleId: "com.finchforge.pomodoist",
    allowJwkFixtures: true,
  });

  assertEquals(notification.notificationType, "DID_RENEW");
  assertEquals(notification.notificationUuid, "notification-1");
  assertEquals(notification.signedDate, "2026-07-27T12:00:00.000Z");
  assertEquals(notification.environment, "Sandbox");
  assertEquals(notification.signedTransactionJws, "nested-transaction-jws");
});

Deno.test("Apple notification verifier rejects untrusted or incomplete envelopes", async (t) => {
  const jws = await fixtureJws(notificationPayload());
  await t.step("fixture key in production", async () => {
    await assertRejects(
      () =>
        verifyAppleAppStoreNotificationJws(jws, {
          bundleId: "com.finchforge.pomodoist",
        }),
      Error,
      "x5c",
    );
  });
  await t.step("wrong bundle", async () => {
    const wrong = await fixtureJws(notificationPayload({
      data: {
        bundleId: "com.example.Other",
        environment: "Sandbox",
        signedTransactionInfo: "nested-transaction-jws",
      },
    }));
    await assertRejects(
      () =>
        verifyAppleAppStoreNotificationJws(wrong, {
          bundleId: "com.finchforge.pomodoist",
          allowJwkFixtures: true,
        }),
      Error,
      "bundle id",
    );
  });
  await t.step("tampered signature", async () => {
    const tampered = tamperSignature(jws);
    await assertRejects(
      () =>
        verifyAppleAppStoreNotificationJws(tampered, {
          bundleId: "com.finchforge.pomodoist",
          allowJwkFixtures: true,
        }),
      Error,
      "signature",
    );
  });
  await t.step("missing data", async () => {
    const missing = await fixtureJws(notificationPayload({ data: undefined }));
    await assertRejects(
      () =>
        verifyAppleAppStoreNotificationJws(missing, {
          bundleId: "com.finchforge.pomodoist",
          allowJwkFixtures: true,
        }),
      Error,
      "data",
    );
  });
});

function notificationPayload(
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    notificationType: "DID_RENEW",
    notificationUUID: "notification-1",
    version: "2.0",
    signedDate: Date.parse("2026-07-27T12:00:00.000Z"),
    data: {
      bundleId: "com.finchforge.pomodoist",
      environment: "Sandbox",
      signedTransactionInfo: "nested-transaction-jws",
    },
    ...overrides,
  };
}

async function fixtureJws(payload: Record<string, unknown>) {
  const keyPair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const jwk = await crypto.subtle.exportKey("jwk", keyPair.publicKey);
  const header = base64UrlEncodeJson({ alg: "ES256", typ: "JWT", jwk });
  const encodedPayload = base64UrlEncodeJson({
    originalAppVersion: "1.0",
    originalPurchaseDate: "2026-05-01T00:00:00.000Z",
    ...payload,
  });
  const signingInput = `${header}.${encodedPayload}`;
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      keyPair.privateKey,
      new TextEncoder().encode(signingInput),
    ),
  );
  return `${signingInput}.${base64UrlEncode(signature)}`;
}

function base64UrlEncodeJson(value: unknown) {
  return base64UrlEncode(new TextEncoder().encode(JSON.stringify(value)));
}

function base64UrlEncode(bytes: Uint8Array) {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(
    /=+$/g,
    "",
  );
}

function tamperSignature(jws: string) {
  const [header, payload, signature] = jws.split(".");
  const first = signature[0] === "A" ? "B" : "A";
  return `${header}.${payload}.${first}${signature.slice(1)}`;
}

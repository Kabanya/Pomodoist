import { assertEquals, assertRejects } from "jsr:@std/assert@1";

import {
  verifyAppleAppStoreNotificationJws,
  verifyAppleAppTransactionJws,
  verifyAppleStoreTransactionJws,
} from "./apple_app_transaction.ts";
import { pomodoistPurchaseState } from "./pomodoist_storekit.ts";
import { handlePomodoistPurchase } from "../pomodoist-purchase/pomodoist_purchase.ts";
import { handlePomodoistAppStoreNotification } from "../pomodoist-app-store-notifications/pomodoist_app_store_notifications.ts";
import { handlePomodoistWatch } from "../pomodoist-watch/pomodoist_watch.ts";

Deno.test("Apple identity and receipt timestamps are checked on each envelope", async (t) => {
  const options = {
    bundleId: "com.finchforge.pomodoist",
    appAppleId: 6794391064,
    allowJwkFixtures: true,
  };
  for (const environment of ["Production", "Sandbox"]) {
    await t.step(environment, async () => {
      const app = {
        bundleId: options.bundleId,
        environment,
        appAppleId: 6794391064,
        appTransactionId: "app-tx-1",
        signedDate: undefined,
      };
      assertEquals(
        (await verifyAppleAppTransactionJws(await fixtureJws(app), options))
          .purchaseId,
        "app-tx-1",
      );
      await assertRejects(
        async () =>
          verifyAppleAppTransactionJws(
            await fixtureJws({ ...app, receiptCreationDate: undefined }),
            options,
          ),
        Error,
        "receiptCreationDate",
      );
      if (environment === "Production") {
        await assertRejects(
          async () =>
            verifyAppleAppTransactionJws(
              await fixtureJws({ ...app, appAppleId: 123 }),
              options,
            ),
          Error,
          "appAppleId",
        );
      }
      const notification = notificationPayload({
        data: {
          bundleId: options.bundleId,
          environment,
          appAppleId: 6794391064,
        },
      });
      assertEquals(
        (await verifyAppleAppStoreNotificationJws(
          await fixtureJws(notification),
          options,
        )).environment,
        environment,
      );
    });
  }
  for (
    const verify of [
      verifyAppleAppTransactionJws,
      verifyAppleAppStoreNotificationJws,
    ]
  ) {
    const jws = await fixtureJws({
      ...notificationPayload(),
      bundleId: options.bundleId,
      appTransactionId: "tx",
      environment: "Xcode",
      data: { bundleId: options.bundleId, environment: "Xcode" },
    });
    await assertRejects(() => verify(jws, options), Error, "environment");
  }
  for (const signedDate of [undefined, "2026-07-27T12:00:00Z", 1e100]) {
    await assertRejects(
      async () =>
        verifyAppleStoreTransactionJws(
          await fixtureJws({ signedDate }),
          options,
        ),
      Error,
      "signedDate",
    );
  }
});

Deno.test("Historical lifetime proof stays active while subscription expiry uses current time", async () => {
  const base = {
    bundleId: "com.finchforge.pomodoist",
    environment: "Sandbox",
    transactionId: "old-tx",
    signedDate: Date.parse("2023-01-01"),
    purchaseDate: Date.parse("2023-01-01"),
  };
  const options = { bundleId: base.bundleId, allowJwkFixtures: true };
  const lifetime = await verifyAppleStoreTransactionJws(
    await fixtureJws({ ...base, productId: "pomodoist.pro.lifetime" }),
    options,
  );
  const subscription = await verifyAppleStoreTransactionJws(
    await fixtureJws({
      ...base,
      productId: "pomodoist.pro.monthly",
      expiresDate: Date.parse("2023-02-01"),
    }),
    options,
  );
  assertEquals(
    pomodoistPurchaseState(lifetime, new Date("2026-09-09"))?.status,
    "active",
  );
  assertEquals(
    pomodoistPurchaseState(subscription, new Date("2026-09-09"))?.status,
    "expired",
  );
});

Deno.test("Production handlers never accept request-controlled fixture options", async () => {
  const transaction = await fixtureJws({
    bundleId: "com.finchforge.pomodoist",
    environment: "Sandbox",
    transactionId: "tx",
    productId: "pomodoist.pro.lifetime",
    purchaseDate: Date.parse("2026-01-01"),
  });
  const notification = await fixtureJws(notificationPayload());
  const body = {
    transactions: [transaction],
    storeTransactions: [transaction],
    signedPayload: notification,
    allowJwkFixtures: true,
    allowedEnvironments: ["Xcode"],
    trustedRoots: ["test-root"],
    localStoreKit: true,
    command: { type: "task.decomposeTranscript", transcript: "Buy milk" },
  };
  const request = (authenticated = false) =>
    new Request("https://functions.test", {
      method: "POST",
      headers: authenticated ? { Authorization: "Bearer user" } : {},
      body: JSON.stringify(body),
    });
  let writes = 0;
  const recordPurchase = () => {
    writes++;
    return Promise.resolve({ data: {}, error: null });
  };
  const purchase = await handlePomodoistPurchase(request(true), {
    authenticate: () =>
      Promise.resolve({ userId: "user", accountToken: "token" }),
    verifyStoreTransaction: verifyAppleStoreTransactionJws,
    recordPurchase,
  });
  assertEquals(purchase.status, 401);
  const notice = await handlePomodoistAppStoreNotification(request(), {
    verifyNotification: verifyAppleAppStoreNotificationJws,
    verifyTransaction: verifyAppleStoreTransactionJws,
    recordPurchase,
  });
  assertEquals(notice.status, 401);
  const watch = await handlePomodoistWatch(request(), {
    env: { get: () => "true" },
    fetch: () => {
      throw new Error("Must not reach provider");
    },
    createClient: () => {
      throw new Error("Must not need account");
    },
  });
  assertEquals(watch.status, 403);
  assertEquals(writes, 0);
});

Deno.test("Apple verifier rejects testJWK headers and malformed JSON objects", async () => {
  const jws = await fixtureJws({
    bundleId: "com.finchforge.pomodoist",
    environment: "Sandbox",
    transactionId: "tx",
    productId: "pomodoist.pro.lifetime",
  });
  const [header, payload, signature] = jws.split(".");
  const jwkHeader = JSON.parse(
    atob(header.replace(/-/g, "+").replace(/_/g, "/")),
  );
  await assertRejects(
    () =>
      verifyAppleStoreTransactionJws(
        `${
          base64UrlEncodeJson({ alg: "ES256", testJWK: jwkHeader.jwk })
        }.${payload}.${signature}`,
        { bundleId: "com.finchforge.pomodoist" },
      ),
    Error,
    "verification key",
  );
  for (const malformed of [null, [], "payload"]) {
    await assertRejects(
      () =>
        verifyAppleStoreTransactionJws(
          `${header}.${base64UrlEncodeJson(malformed)}.${signature}`,
          { bundleId: "com.finchforge.pomodoist" },
        ),
      Error,
      "JSON objects",
    );
  }
});

Deno.test("Apple production verification rejects local environments and wrong app identity", async (t) => {
  for (const environment of ["Xcode", "LocalTesting", "Unknown"]) {
    await t.step(environment, async () => {
      const jws = await fixtureJws({
        bundleId: "com.finchforge.pomodoist",
        environment,
        transactionId: "tx",
        productId: "pomodoist.pro.lifetime",
      });
      await assertRejects(
        () =>
          verifyAppleStoreTransactionJws(jws, {
            bundleId: "com.finchforge.pomodoist",
            allowJwkFixtures: true,
          }),
        Error,
        "environment",
      );
    });
  }
  for (const appAppleId of [undefined, 123]) {
    await t.step(`app identity ${appAppleId}`, async () => {
      const jws = await fixtureJws({
        ...notificationPayload(),
        data: {
          bundleId: "com.finchforge.pomodoist",
          environment: "Production",
          appAppleId,
        },
      });
      await assertRejects(
        () =>
          verifyAppleAppStoreNotificationJws(jws, {
            bundleId: "com.finchforge.pomodoist",
            appAppleId: 6794391064,
            allowJwkFixtures: true,
          }),
        Error,
        "appAppleId",
      );
    });
  }
});

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

Deno.test("Apple service notification envelopes are verified and acknowledged without writes", async (t) => {
  for (
    const envelope of ["data", "summary", "externalPurchaseToken", "appData"]
  ) {
    for (const environment of ["Production", "Sandbox"]) {
      await t.step(`${envelope} ${environment}`, async () => {
        const jws = await fixtureJws(notificationPayload({
          data: undefined,
          [envelope]: {
            bundleId: "com.finchforge.pomodoist",
            appAppleId: 6794391064,
            ...(envelope === "externalPurchaseToken"
              ? {
                externalPurchaseId: environment === "Sandbox"
                  ? "SANDBOX-token"
                  : "production-token",
              }
              : { environment }),
          },
        }));
        const result = await handlePomodoistAppStoreNotification(
          new Request("https://functions.test", {
            method: "POST",
            body: JSON.stringify({ signedPayload: jws }),
          }),
          {
            verifyNotification: async (value, options) => {
              const notification = await verifyAppleAppStoreNotificationJws(
                value,
                { ...options, allowJwkFixtures: true },
              );
              assertEquals(notification.environment, environment);
              return notification;
            },
            verifyTransaction: () => {
              throw new Error("Service notifications have no transaction");
            },
            recordPurchase: () => {
              throw new Error("Service notifications must not write purchases");
            },
          },
        );
        assertEquals(result.status, 200);
        assertEquals(await result.json(), { ok: true, ignored: true });
      });
    }
  }
});

Deno.test("Apple service notifications reject wrong identities, environments and signatures", async (t) => {
  const options = {
    bundleId: "com.finchforge.pomodoist",
    appAppleId: 6794391064,
    allowedEnvironments: ["Production"],
    allowJwkFixtures: true,
  };
  for (const envelope of ["summary", "externalPurchaseToken", "appData"]) {
    for (
      const invalid of ["bundle", "appAppleId", "environment", "signature"]
    ) {
      await t.step(`${envelope} ${invalid}`, async () => {
        const claims = {
          bundleId: invalid === "bundle"
            ? "com.example.other"
            : options.bundleId,
          appAppleId: invalid === "appAppleId" ? 123 : options.appAppleId,
          environment: invalid === "environment" ? "Xcode" : "Production",
          externalPurchaseId: invalid === "environment"
            ? "SANDBOX-token"
            : "production-token",
        };
        const jws = await fixtureJws(
          notificationPayload({ data: undefined, [envelope]: claims }),
        );
        await assertRejects(
          () =>
            verifyAppleAppStoreNotificationJws(
              invalid === "signature" ? tamperSignature(jws) : jws,
              options,
            ),
          Error,
          invalid === "bundle" ? "bundle id" : invalid,
        );
      });
    }
  }
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
    signedDate: Date.parse("2026-07-27T12:00:00.000Z"),
    receiptCreationDate: Date.parse("2026-07-27T12:00:00.000Z"),
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

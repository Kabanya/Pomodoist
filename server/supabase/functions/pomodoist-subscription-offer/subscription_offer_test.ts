import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import { generateKeyPairSync, verify as verifySignature } from "node:crypto";
import { Buffer } from "node:buffer";
import {
  type AppleStoreTransaction,
  verifyAppleRenewalInfoJws,
  verifyAppleStoreTransactionJws,
} from "../_shared/apple_app_transaction.ts";
import { pomodoistBundleId } from "../_shared/pomodoist_storekit.ts";
import {
  fetchAppleHistory,
  type History,
  offerIds,
  promotionalSignature,
} from "./apple_server.ts";
import {
  evaluateHistory,
  handleSubscriptionOffer,
  type OfferDeps,
} from "./pomodoist_subscription_offer.ts";

const now = Date.parse("2026-09-13T12:00:00Z");
const week = 7 * 86_400_000;
const token = "11111111-1111-4111-8111-111111111111";
const key = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
const credentials = {
  keyID: "TESTKEY",
  issuerId: "test-issuer",
  privateKey: key.privateKey.export({ format: "pem", type: "pkcs8" })
    .toString(),
};
function transaction(
  overrides: Partial<AppleStoreTransaction> = {},
): AppleStoreTransaction {
  return {
    purchaseId: "100",
    originalTransactionId: "100",
    transactionId: "101",
    productId: "pomodoist.pro.monthly",
    environment: "Sandbox",
    bundleId: pomodoistBundleId,
    purchaseDate: new Date(now - week - 86_400_000).toISOString(),
    expiresDate: new Date(now - week).toISOString(),
    signedDate: new Date(now).toISOString(),
    claims: { appTransactionId: "12345" },
    ...overrides,
  };
}
function history(item = transaction()): History {
  return {
    transactions: [item],
    statuses: [{
      status: 2,
      transaction: item,
      renewal: {
        originalTransactionId: item.originalTransactionId,
        environment: item.environment,
        isInBillingRetryPeriod: false,
      },
    }],
  };
}
function request(body: Record<string, unknown> = {}) {
  return new Request("https://example.test", {
    method: "POST",
    body: JSON.stringify({
      action: "eligibility",
      transaction: "seed",
      ...body,
    }),
  });
}
function deps(overrides: Partial<OfferDeps> = {}): OfferDeps {
  return {
    enabled: true,
    configured: true,
    signatureMaxAgeSeconds: 86400, // Fixture only; not an Apple V2 expiry claim.
    environment: "Sandbox",
    authenticate: async () => null,
    verify: async () => transaction(),
    history: async () => history(),
    state: async () => ({ code: "eligible" }),
    sign: (p, a, n) => promotionalSignature(credentials, p, a, n),
    now: () => now,
    ...overrides,
  };
}

Deno.test("7-day eligibility boundary includes a previous trial and uses last actual expiry", () => {
  const item = transaction({
    claims: {
      appTransactionId: "12345",
      offerType: 1,
      offerDiscountType: "FREE_TRIAL",
    },
  });
  assertEquals(evaluateHistory(item, history(item), now - 1).eligible, false);
  assertEquals(evaluateHistory(item, history(item), now).eligible, true);
  assertEquals(evaluateHistory(item, history(item), now + 1).eligible, true);
  const newer = transaction({
    transactionId: "102",
    expiresDate: new Date(now - week + 1).toISOString(),
  });
  assertEquals(
    evaluateHistory(item, { ...history(), transactions: [item, newer] }, now)
      .eligible,
    false,
  );
});

Deno.test("active, lifetime, grace, retry, revocation, family sharing and either redeemed SKU exclude", () => {
  for (
    const patch of [
      { expiresDate: new Date(now + 1).toISOString() },
      { productId: "pomodoist.pro.lifetime", expiresDate: undefined },
      { productId: "pomodoist.pro.lifetime.launch", expiresDate: undefined },
      { revocationDate: new Date(now - week).toISOString() },
      {
        claims: {
          appTransactionId: "12345",
          inAppOwnershipType: "FAMILY_SHARED",
        },
      },
      ...Object.values(offerIds).map((offerIdentifier) => ({
        claims: { appTransactionId: "12345", offerIdentifier },
      })),
    ]
  ) {
    const item = transaction(patch);
    assertEquals(evaluateHistory(item, history(item), now).eligible, false);
  }
  for (const status of [1, 3, 4, 5]) {
    const h = history();
    h.statuses[0].status = status;
    assertEquals(evaluateHistory(transaction(), h, now).eligible, false);
  }
  for (
    const patch of [{ isInBillingRetryPeriod: true }, {
      gracePeriodExpiresDate: now + 1,
    }]
  ) {
    const h = history();
    Object.assign(h.statuses[0].renewal, patch);
    assertEquals(evaluateHistory(transaction(), h, now).eligible, false);
  }
});

Deno.test("older proof uses fresh authoritative app identity; missing/mismatched identity fails closed", () => {
  assertEquals(
    evaluateHistory(transaction({ claims: {} }), history(), now)
      .appTransactionId,
    "12345",
  );
  assertThrows(() =>
    evaluateHistory(transaction(), history(transaction({ claims: {} })), now)
  );
  assertThrows(() =>
    evaluateHistory(
      transaction({ claims: { appTransactionId: "9" } }),
      history(),
      now,
    )
  );
  assertThrows(() =>
    evaluateHistory(transaction(), {
      transactions: [],
      statuses: history().statuses,
    }, now)
  );
  assertEquals(
    evaluateHistory(transaction(), {
      transactions: [transaction()],
      statuses: [],
    }, now).eligible,
    false,
  );
});

Deno.test("V2 promotional JWS binds the Apple customer and SKU with correct claims and no exp", () => {
  for (const productId of Object.keys(offerIds)) {
    const authorization = promotionalSignature(
      credentials,
      productId,
      "12345",
      now,
    );
    const [headerPart, payloadPart, signaturePart] = authorization.compactJws
      .split(".");
    assertEquals(JSON.parse(Buffer.from(headerPart, "base64url").toString()), {
      alg: "ES256",
      kid: credentials.keyID,
      typ: "JWT",
    });
    const payload = JSON.parse(
      Buffer.from(payloadPart, "base64url").toString(),
    );
    assertEquals(payload, {
      iss: credentials.issuerId,
      iat: Math.floor(now / 1000),
      aud: "promotional-offer",
      bid: pomodoistBundleId,
      nonce: authorization.nonce,
      productId,
      offerIdentifier: offerIds[productId],
      transactionId: "12345",
    });
    assertEquals(Object.hasOwn(payload, "exp"), false);
    const publicKey = {
      key: key.publicKey,
      dsaEncoding: "ieee-p1363" as const,
    };
    const signature = Buffer.from(signaturePart, "base64url");
    assertEquals(signature.length, 64);
    assert(
      verifySignature(
        "sha256",
        Buffer.from(`${headerPart}.${payloadPart}`),
        publicKey,
        signature,
      ),
    );
    for (
      const patch of [{ transactionId: "67890" }, { productId: "wrong.sku" }]
    ) {
      const tampered = Buffer.from(JSON.stringify({ ...payload, ...patch }))
        .toString("base64url");
      assert(
        !verifySignature(
          "sha256",
          Buffer.from(`${headerPart}.${tampered}`),
          publicKey,
          signature,
        ),
      );
    }
    assertEquals(authorization.timestamp, now);
  }
  assertThrows(() =>
    promotionalSignature(credentials, "pomodoist.pro.monthly", "", now)
  );
  assertThrows(() =>
    promotionalSignature(credentials, "unknown.sku", "12345", now)
  );
});

Deno.test("sign response exposes only customer-bound compact JWS and uses authoritative appTransactionId", async () => {
  const response = await handleSubscriptionOffer(
    request({
      action: "sign",
      productId: "pomodoist.pro.monthly",
      transactionId: "attacker-controlled",
    }),
    deps({ verify: async () => transaction({ claims: {} }) }),
  );
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(Object.keys(body).sort(), ["compactJws", "offerId"]);
  const payload = JSON.parse(
    Buffer.from(body.compactJws.split(".")[1], "base64url").toString(),
  );
  assertEquals(payload.transactionId, "12345");
});

Deno.test("disabled eligibility is quiet without proof/auth while disabled signing and missing config fail closed", async () => {
  const disabled = deps({
    enabled: false,
    configured: false,
    authenticate: () => {
      throw Error("must not authenticate");
    },
    verify: () => {
      throw Error("must not verify");
    },
  });
  const eligibility = await handleSubscriptionOffer(
    request({ transaction: null }),
    disabled,
  );
  assertEquals(eligibility.status, 200);
  assertEquals(await eligibility.json(), { eligible: false, offerIds: {} });
  const signing = await handleSubscriptionOffer(
    request({ action: "sign" }),
    disabled,
  );
  assertEquals(signing.status, 503);
  assertEquals(await signing.json(), { code: "offer_unavailable" });
  const missingConfig = await handleSubscriptionOffer(
    request(),
    deps({ configured: false }),
  );
  assertEquals(missingConfig.status, 503);
  assertEquals(await missingConfig.json(), { code: "offer_unavailable" });
});

Deno.test("handler verifies proof, ignores client history subset and fails closed on upstream/DB errors", async () => {
  for (
    const override of [
      { verify: verifyAppleStoreTransactionJws },
      {
        history: async () => {
          throw new Error("Apple down");
        },
      },
      {
        state: async () => {
          throw new Error("DB down");
        },
      },
    ]
  ) {
    const response = await handleSubscriptionOffer(
      request({ action: "sign", productId: "pomodoist.pro.monthly" }),
      deps(override),
    );
    assert([401, 503].includes(response.status));
    assertEquals((await response.json()).compactJws, undefined);
  }
  const active = transaction({
    transactionId: "102",
    productId: "pomodoist.pro.annual",
    expiresDate: new Date(now + week).toISOString(),
  });
  const response = await handleSubscriptionOffer(
    request({ transactions: ["expired-only"] }),
    deps({
      history: async () => ({
        ...history(),
        transactions: [transaction(), active],
      }),
    }),
  );
  assertEquals((await response.json()).eligible, false);
});

Deno.test("pending lease is surfaced; cancellation cannot release or consume; retry after expiry", async () => {
  let leaseUntil = 0;
  let currentNow = now;
  const d = deps({
    now: () => currentNow,
    state: async (p) => {
      if (leaseUntil > currentNow) {
        return {
          code: "offer_pending",
          retryAfter: new Date(leaseUntil).toISOString(),
        };
      }
      if (p.p_product_id) {
        leaseUntil = currentNow + (p.p_signature_max_age_seconds + 300) * 1000;
      }
      return { code: "eligible" };
    },
  });
  const responses = await Promise.all(
    ["pomodoist.pro.monthly", "pomodoist.pro.annual"].map((productId) =>
      handleSubscriptionOffer(request({ action: "sign", productId }), d)
    ),
  );
  assertEquals(responses.map((r) => r.status).sort(), [200, 409]);
  const pending = await (await handleSubscriptionOffer(request(), d)).json();
  assertEquals(pending.code, "offer_pending");
  assertEquals(pending.eligible, false);
  assertEquals(pending.retryAfter, new Date(leaseUntil).toISOString());
  assertEquals(
    (await handleSubscriptionOffer(request({ action: "cancel" }), d)).status,
    400,
  );
  currentNow = leaseUntil;
  assertEquals(
    (await handleSubscriptionOffer(
      request({ action: "sign", productId: "pomodoist.pro.annual" }),
      d,
    )).status,
    200,
  );
});

Deno.test("signing errors leave no lease; mismatched ownership and account tokens are rejected", async () => {
  let calls = 0;
  assertEquals(
    (await handleSubscriptionOffer(
      request({ action: "sign", productId: "pomodoist.pro.monthly" }),
      deps({
        sign: () => {
          throw Error("bad key");
        },
        state: async () => {
          calls++;
          return { code: "eligible" };
        },
      }),
    )).status,
    503,
  );
  assertEquals(calls, 0);
  const authenticated = deps({
    authenticate: async () => ({ userId: token, accountToken: token }),
  });
  assertEquals(
    (await handleSubscriptionOffer(
      request({ action: "sign", productId: "pomodoist.pro.monthly" }),
      authenticated,
    )).status,
    403,
  );
  assertEquals(
    (await handleSubscriptionOffer(
      request({
        action: "sign",
        productId: "pomodoist.pro.monthly",
        appAccountToken: token,
      }),
      authenticated,
    )).status,
    200,
  );
  assertEquals(
    (await handleSubscriptionOffer(request({ appAccountToken: token }), deps()))
      .status,
    403,
  );
  assertEquals(
    (await handleSubscriptionOffer(request(), deps({ enabled: false }))).status,
    200,
  );
});

Deno.test("history reader paginates all products, verifies both signed payloads, separates environments", async () => {
  for (const environment of ["Production", "Sandbox"]) {
    const seed = transaction({ environment, claims: {} });
    const paths: string[] = [];
    const verifyOptions: string[][] = [];
    const h = await fetchAppleHistory(
      seed,
      credentials,
      (async (url: string | URL | Request, init?: RequestInit) => {
        paths.push(String(url));
        assert(init?.signal);
        assert(init?.headers);
        const response = paths.length === 1
          ? { hasMore: true, revision: "next", signedTransactions: ["old"] }
          : paths.length === 2
          ? { hasMore: false, signedTransactions: ["latest"] }
          : {
            data: [{
              lastTransactions: [{
                status: 2,
                originalTransactionId: "100",
                signedTransactionInfo: "latest",
                signedRenewalInfo: "renewal",
              }],
            }],
          };
        return Response.json({
          bundleId: pomodoistBundleId,
          environment,
          ...response,
        });
      }) as typeof fetch,
      async (jws, options) => {
        verifyOptions.push([...(options.allowedEnvironments ?? [])]);
        return transaction({
          environment,
          transactionId: jws === "old" ? "101" : "102",
        });
      },
      async (_jws, options) => {
        verifyOptions.push([...(options.allowedEnvironments ?? [])]);
        return { originalTransactionId: "100", environment };
      },
    );
    assertEquals(h.transactions.length, 2);
    assertEquals(h.statuses.length, 1);
    assert(
      paths[0].includes(
        environment === "Production"
          ? "api.storekit.apple.com"
          : "api.storekit-sandbox.apple.com",
      ),
    );
    assert(paths[1].endsWith("?revision=next"));
    assert(!paths.some((path) => path.includes("productId=")));
    assert(
      verifyOptions.every((options) =>
        options.length === 1 && options[0] === environment
      ),
    );
  }
});

Deno.test("history reader rejects unavailable, mismatched, untrusted or incomplete Apple results", async () => {
  for (
    const response of [
      new Response("unavailable", { status: 500 }),
      Response.json({
        bundleId: pomodoistBundleId,
        environment: "Production",
        hasMore: false,
        signedTransactions: [],
      }),
      Response.json({
        bundleId: pomodoistBundleId,
        environment: "Sandbox",
        hasMore: false,
        signedTransactions: [],
      }),
      Response.json({
        bundleId: pomodoistBundleId,
        environment: "Sandbox",
        hasMore: false,
        signedTransactions: ["untrusted"],
      }),
    ]
  ) {
    await assertRejects(() =>
      fetchAppleHistory(
        transaction(),
        credentials,
        (async () => response.clone()) as typeof fetch,
      )
    );
  }
  await assertRejects(() =>
    verifyAppleRenewalInfoJws("untrusted", { bundleId: pomodoistBundleId })
  );
});

Deno.test("production signer rejects sandbox seeds before querying history", async () => {
  let readHistory = false;
  const response = await handleSubscriptionOffer(
    request(),
    deps({
      environment: "Production",
      verify: async (_jws, options) => {
        assertEquals(options.allowedEnvironments, ["Production"]);
        return transaction();
      },
      history: async () => {
        readHistory = true;
        return history();
      },
    }),
  );
  assertEquals(response.status, 401);
  assertEquals(readHistory, false);
});

Deno.test("activation requires an explicit valid V2 lifetime bound and passes it to the lease RPC", async () => {
  for (const signatureMaxAgeSeconds of [NaN, 0, -1, 1.5, 604801, Infinity]) {
    for (const action of ["eligibility", "sign"]) {
      const response = await handleSubscriptionOffer(
        request({ action }),
        deps({
          signatureMaxAgeSeconds,
          authenticate: () => {
            throw Error("must not authenticate");
          },
        }),
      );
      assertEquals(response.status, 503);
      assertEquals(await response.json(), { code: "offer_unavailable" });
    }
  }
  assertEquals(
    (await handleSubscriptionOffer(
      request(),
      deps({
        enabled: false,
        signatureMaxAgeSeconds: NaN,
      }),
    )).status,
    200,
  );
  for (const signatureMaxAgeSeconds of [1, 3600, 604800]) {
    let recorded = 0;
    const response = await handleSubscriptionOffer(
      request({ action: "sign", productId: "pomodoist.pro.monthly" }),
      deps({
        signatureMaxAgeSeconds,
        state: async (params) => {
          recorded = params.p_signature_max_age_seconds;
          return { code: "eligible" };
        },
      }),
    );
    assertEquals(response.status, 200);
    assertEquals(recorded, signatureMaxAgeSeconds);
  }
});

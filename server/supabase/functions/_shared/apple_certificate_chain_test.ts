import "npm:reflect-metadata@0.2.2";
import {
  BasicConstraintsExtension,
  Extension,
  KeyUsageFlags,
  KeyUsagesExtension,
  X509Certificate,
  X509CertificateGenerator,
} from "npm:@peculiar/x509@2.1.0";
import { assertRejects } from "jsr:@std/assert@1";
import {
  validateAppleCertificateChain,
  verifyAppleStoreTransactionJws,
} from "./apple_app_transaction.ts";
// Apple MIT fixtures: https://github.com/apple/app-store-server-library-node/blob/main/tests/unit-tests/jws_verification.test.ts
// The accompanying APPLE_LICENSE applies to these public certificates.
import fixtures from "./test_fixtures/apple_certificates.json" with {
  type: "json",
};

const signedAt = Date.parse("2026-09-09T12:00:00Z");
const realChain = [
  fixtures.REAL_APPLE_SIGNING_CERTIFICATE_BASE64_ENCODED,
  fixtures.REAL_APPLE_INTERMEDIATE_BASE64_ENCODED,
  fixtures.REAL_APPLE_ROOT_BASE64_ENCODED,
].map(decode);
const publicTestChain = [
  fixtures.LEAF_CERT_BASE64_ENCODED,
  fixtures.INTERMEDIATE_CA_BASE64_ENCODED,
  fixtures.ROOT_CA_BASE64_ENCODED,
].map(decode);

Deno.test("Apple certificate validity uses the signed date instead of today's date", async () => {
  await validateAppleCertificateChain(realChain, signedAt);
  await assertRejects(
    () => validateAppleCertificateChain(realChain, Date.parse("2040-01-01")),
    Error,
    "validity",
  );
  await assertRejects(
    () => validateAppleCertificateChain(realChain, Date.parse("2020-01-01")),
    Error,
    "validity",
  );
});

Deno.test("Apple public test chain validates without trusting its root in production", async () => {
  const roots = await trustedRoots(publicTestChain);
  await validateAppleCertificateChain(publicTestChain, signedAt, roots);
  await assertRejects(
    () => validateAppleCertificateChain(publicTestChain, signedAt),
    Error,
    "rooted at Apple",
  );
});

Deno.test("Apple chain rejects wrong purpose, signature, root and chain length", async (t) => {
  const roots = await trustedRoots(publicTestChain);
  const invalidSignature = publicTestChain[0].slice();
  invalidSignature[invalidSignature.length - 1] ^= 1;
  const cases = [
    {
      name: "leaf purpose",
      chain: [
        decode(fixtures.LEAF_CERT_INVALID_OID_BASE64_ENCODED),
        ...publicTestChain.slice(1),
      ],
      error: "purpose",
    },
    {
      name: "intermediate purpose",
      chain: [
        decode(
          fixtures.LEAF_CERT_FOR_INTERMEDIATE_CA_INVALID_OID_BASE64_ENCODED,
        ),
        decode(fixtures.INTERMEDIATE_CA_INVALID_OID_BASE64_ENCODED),
        publicTestChain[2],
      ],
      error: "purpose",
    },
    {
      name: "signature",
      chain: [invalidSignature, ...publicTestChain.slice(1)],
      error: "signature",
    },
    {
      name: "wrong root",
      chain: [publicTestChain[0], publicTestChain[1], realChain[2]],
      error: "rooted at Apple",
    },
    { name: "short chain", chain: publicTestChain.slice(1), error: "three" },
    {
      name: "extra certificate",
      chain: [...publicTestChain, publicTestChain[2]],
      error: "three",
    },
  ];
  for (const test of cases) {
    await t.step(test.name, async () => {
      await assertRejects(
        () => validateAppleCertificateChain(test.chain, signedAt, roots),
        Error,
        test.error,
      );
    });
  }
});

Deno.test("Apple chain enforces CA, path length, key usages and issuer names", async (t) => {
  const cases: Array<
    { name: string; overrides: ChainOverrides; error: string }
  > = [
    { name: "leaf CA", overrides: { leafCa: true }, error: "CA" },
    {
      name: "leaf critical extension",
      overrides: { criticalIndex: 2 },
      error: "critical extension",
    },
    {
      name: "intermediate critical extension",
      overrides: { criticalIndex: 1 },
      error: "critical extension",
    },
    {
      name: "root critical extension",
      overrides: { criticalIndex: 0 },
      error: "critical extension",
    },
    {
      name: "intermediate not CA",
      overrides: { intermediateCa: false },
      error: "CA",
    },
    { name: "root not CA", overrides: { rootCa: false }, error: "CA" },
    {
      name: "root path length",
      overrides: { rootPathLength: 0 },
      error: "path length",
    },
    {
      name: "leaf key usage",
      overrides: { leafUsage: KeyUsageFlags.keyEncipherment },
      error: "key usage",
    },
    {
      name: "leaf signs certificates",
      overrides: {
        leafUsage: KeyUsageFlags.digitalSignature | KeyUsageFlags.keyCertSign,
      },
      error: "key usage",
    },
    {
      name: "intermediate key usage",
      overrides: { intermediateUsage: KeyUsageFlags.digitalSignature },
      error: "key usage",
    },
    {
      name: "root key usage",
      overrides: { rootUsage: KeyUsageFlags.digitalSignature },
      error: "key usage",
    },
    {
      name: "issuer name",
      overrides: { leafIssuer: "CN=Different issuer" },
      error: "issuer",
    },
    {
      name: "non ES256 leaf",
      overrides: { leafCurve: "P-384" },
      error: "P-256",
    },
  ];
  for (const test of cases) {
    await t.step(test.name, async () => {
      const chain = await generateChain(test.overrides);
      await assertRejects(
        async () =>
          validateAppleCertificateChain(
            chain,
            signedAt,
            await trustedRoots(chain),
          ),
        Error,
        test.error,
      );
    });
  }
});

Deno.test("Historical certificate validity allows 60 seconds of clock skew only", async () => {
  const chain = await generateChain({ leafNotAfter: "2024-01-01" });
  const roots = await trustedRoots(chain);
  // This leaf is expired today, but lifetime purchases signed during its validity stay verifiable.
  const expiredLeaf = new X509Certificate(Uint8Array.from(chain[0]));
  const end = expiredLeaf.notAfter.getTime();
  const start = expiredLeaf.notBefore.getTime();
  await validateAppleCertificateChain(chain, end + 60_000, roots);
  await validateAppleCertificateChain(chain, start - 60_000, roots);
  for (const date of [end + 60_001, start - 60_001, NaN]) {
    await assertRejects(
      () => validateAppleCertificateChain(chain, date, roots),
      Error,
      "validity",
    );
  }
});

Deno.test("Production JWS path trusts only Apple roots and verifies the actual JWS signature", async () => {
  const payload = {
    bundleId: "com.finchforge.pomodoist",
    environment: "Production",
    transactionId: "tx",
    productId: "pomodoist.pro.lifetime",
    signedDate: signedAt,
  };
  const options = { bundleId: "com.finchforge.pomodoist" };
  const untrusted = makeJws(publicTestChain, payload);
  await assertRejects(
    () => verifyAppleStoreTransactionJws(untrusted, options),
    Error,
    "rooted at Apple",
  );
  const trusted = makeJws(realChain, payload);
  await assertRejects(
    () => verifyAppleStoreTransactionJws(trusted, options),
    Error,
    "signature",
  );
  const absentDate = makeJws(realChain, { ...payload, signedDate: undefined });
  await assertRejects(
    () => verifyAppleStoreTransactionJws(absentDate, options),
    Error,
    "signedDate",
  );
});

type ChainOverrides = {
  criticalIndex?: number;
  rootCa?: boolean;
  intermediateCa?: boolean;
  leafCa?: boolean;
  rootPathLength?: number;
  rootUsage?: KeyUsageFlags;
  intermediateUsage?: KeyUsageFlags;
  leafUsage?: KeyUsageFlags;
  leafIssuer?: string;
  leafCurve?: string;
  leafNotAfter?: string;
};

async function generateChain(overrides: ChainOverrides = {}) {
  const keys = await Promise.all(
    ["P-256", "P-256", overrides.leafCurve ?? "P-256"].map(
      (namedCurve) =>
        crypto.subtle.generateKey({ name: "ECDSA", namedCurve }, true, [
          "sign",
          "verify",
        ]),
    ),
  );
  const names = ["CN=Test root", "CN=Test intermediate", "CN=Test leaf"];
  const certificates: Uint8Array[] = [];
  for (let index = 0; index < 3; index++) {
    const ca = [
      overrides.rootCa ?? true,
      overrides.intermediateCa ?? true,
      overrides.leafCa ?? false,
    ][index];
    const usage = [
      overrides.rootUsage ?? KeyUsageFlags.keyCertSign,
      overrides.intermediateUsage ?? KeyUsageFlags.keyCertSign,
      overrides.leafUsage ?? KeyUsageFlags.digitalSignature,
    ][index];
    const cert = await X509CertificateGenerator.create({
      serialNumber: String(index + 1),
      subject: names[index],
      issuer: index === 2
        ? overrides.leafIssuer ?? names[1]
        : names[Math.max(index - 1, 0)],
      publicKey: keys[index].publicKey,
      signingKey: keys[Math.max(index - 1, 0)].privateKey,
      signingAlgorithm: { name: "ECDSA", hash: "SHA-256" },
      notBefore: new Date("2020-01-01"),
      notAfter: new Date(
        index === 2 ? overrides.leafNotAfter ?? "2030-01-01" : "2035-01-01",
      ),
      extensions: [
        ...(overrides.criticalIndex === index
          ? [new Extension("1.2.3.4.5.6", true, new Uint8Array([5, 0]))]
          : []),
        new BasicConstraintsExtension(
          ca,
          index === 0
            ? overrides.rootPathLength ?? 1
            : index === 1
            ? 0
            : undefined,
          true,
        ),
        new KeyUsagesExtension(usage, true),
        ...(index === 0 ? [] : [
          new Extension(
            index === 1
              ? "1.2.840.113635.100.6.2.1"
              : "1.2.840.113635.100.6.11.1",
            false,
            new Uint8Array([5, 0]),
          ),
        ]),
      ],
    }, crypto);
    certificates.unshift(new Uint8Array(cert.rawData));
  }
  return certificates;
}

async function trustedRoots(chain: Uint8Array[]) {
  const fingerprint = new Uint8Array(
    await crypto.subtle.digest("SHA-256", Uint8Array.from(chain[2])),
  );
  return new Set([
    Array.from(fingerprint, (value) => value.toString(16).padStart(2, "0"))
      .join(""),
  ]);
}

function decode(value: string) {
  return Uint8Array.from(atob(value), (char) => char.charCodeAt(0));
}

function makeJws(chain: Uint8Array[], payload: Record<string, unknown>) {
  const encode = (value: unknown) =>
    btoa(JSON.stringify(value)).replace(/\+/g, "-").replace(/\//g, "_").replace(
      /=+$/g,
      "",
    );
  const x5c = chain.map((cert) => btoa(String.fromCharCode(...cert)));
  return `${encode({ alg: "ES256", x5c })}.${encode(payload)}.${
    "A".repeat(86)
  }`;
}

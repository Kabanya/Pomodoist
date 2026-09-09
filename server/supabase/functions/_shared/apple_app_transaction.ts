import "npm:reflect-metadata@0.2.2";
import {
  BasicConstraintsExtension,
  KeyUsageFlags,
  KeyUsagesExtension,
  X509Certificate,
} from "npm:@peculiar/x509@2.1.0";

const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder();

export type AppleAppTransaction = {
  purchaseId: string;
  appTransactionId: string;
  bundleId: string;
  environment: string;
  originalAppVersion?: string;
  originalPurchaseDate?: string;
  claims: Record<string, unknown>;
};

export type AppleStoreTransaction = {
  purchaseId: string;
  transactionId: string;
  originalTransactionId: string;
  productId: string;
  bundleId: string;
  environment: string;
  appAccountToken?: string;
  purchaseDate?: string;
  expiresDate?: string;
  revocationDate?: string;
  signedDate?: string;
  claims: Record<string, unknown>;
};

export type AppleAppStoreNotification = {
  notificationType: string;
  subtype?: string;
  notificationUuid: string;
  signedDate: string;
  environment: string;
  signedTransactionJws?: string;
  claims: Record<string, unknown>;
};

type VerifyOptions = {
  bundleId: string;
  appAppleId?: number;
  allowedEnvironments?: readonly string[];
  allowJwkFixtures?: boolean;
};

const appleRootSha256Fingerprints = new Set([
  "63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179",
  "c2b9b042dd57830e7d117dac55ac8ae19407d38e41d88f3215bc3a890444a050",
  "b0b1730ecbc7ff4505142c49f1295e6eda6bcaed7e2c68c5be91b5a11001f024",
]);

export async function verifyAppleAppTransactionJws(
  jws: string,
  options: VerifyOptions,
): Promise<AppleAppTransaction> {
  const payload = await verifyAppleJwsPayload(
    jws,
    options,
    "AppTransaction",
    "receiptCreationDate",
  );

  const bundleId = stringClaim(payload.bundleId);
  if (bundleId !== options.bundleId) {
    throw new Error("AppTransaction bundle id does not match Nottica.");
  }

  const environment = stringClaim(payload.environment ?? payload.receiptType);
  const allowed = options.allowedEnvironments ??
    ["Production", "Sandbox"];
  if (!allowed.includes(environment)) {
    throw new Error("AppTransaction environment is not allowed.");
  }

  verifyAppAppleId(payload, environment, options);

  const appTransactionId = stringClaim(
    payload.appTransactionId ?? payload.originalTransactionId ??
      payload.transactionId,
  );
  const purchaseId = appTransactionId.trim();
  if (!purchaseId) {
    throw new Error("AppTransaction is missing appTransactionId.");
  }

  return {
    purchaseId,
    appTransactionId,
    bundleId,
    environment,
    originalAppVersion: optionalString(
      payload.originalAppVersion ?? payload.originalApplicationVersion,
    ),
    originalPurchaseDate: optionalAppleDate(payload.originalPurchaseDate),
    claims: payload,
  };
}

export async function verifyAppleStoreTransactionJws(
  jws: string,
  options: VerifyOptions,
): Promise<AppleStoreTransaction> {
  const payload = await verifyAppleJwsPayload(
    jws,
    options,
    "StoreKit transaction",
  );

  const bundleId = stringClaim(payload.bundleId);
  if (bundleId !== options.bundleId) {
    throw new Error("StoreKit transaction bundle id does not match Nottica.");
  }

  const environment = stringClaim(payload.environment ?? payload.receiptType);
  const allowed = options.allowedEnvironments ??
    ["Production", "Sandbox"];
  if (!allowed.includes(environment)) {
    throw new Error("StoreKit transaction environment is not allowed.");
  }

  // StoreKit transaction claims do not normally include appAppleId.
  if (payload.appAppleId != null) {
    verifyAppAppleId(payload, environment, options);
  }
  const transactionId = stringClaim(payload.transactionId);
  const originalTransactionId = stringClaim(
    payload.originalTransactionId ?? payload.transactionId,
  );
  const productId = stringClaim(payload.productId);

  return {
    purchaseId: originalTransactionId,
    transactionId,
    originalTransactionId,
    productId,
    bundleId,
    environment,
    appAccountToken: optionalString(payload.appAccountToken),
    purchaseDate: optionalAppleDate(payload.purchaseDate),
    expiresDate: optionalAppleDate(payload.expiresDate),
    revocationDate: optionalAppleDate(payload.revocationDate),
    signedDate: optionalAppleDate(payload.signedDate),
    claims: payload,
  };
}

export async function verifyAppleAppStoreNotificationJws(
  jws: string,
  options: VerifyOptions,
): Promise<AppleAppStoreNotification> {
  const payload = await verifyAppleJwsPayload(
    jws,
    options,
    "App Store notification",
  );
  const envelope = ["data", "summary", "externalPurchaseToken", "appData"]
    .find((name) => payload[name] != null);
  const data = envelope == null ? undefined : payload[envelope];
  if (typeof data !== "object" || data === null || Array.isArray(data)) {
    throw new Error("App Store notification is missing data.");
  }
  const claims = data as Record<string, unknown>;
  const bundleId = stringClaim(claims.bundleId);
  if (bundleId !== options.bundleId) {
    throw new Error("App Store notification bundle id does not match.");
  }
  const environment = envelope === "externalPurchaseToken"
    ? optionalString(claims.externalPurchaseId)?.startsWith("SANDBOX")
      ? "Sandbox"
      : "Production"
    : stringClaim(claims.environment);
  const allowed = options.allowedEnvironments ??
    ["Production", "Sandbox"];
  if (!allowed.includes(environment)) {
    throw new Error("App Store notification environment is not allowed.");
  }
  verifyAppAppleId(claims, environment, options);
  const signedDate = optionalAppleDate(payload.signedDate);
  if (signedDate == null) {
    throw new Error("App Store notification is missing signedDate.");
  }

  return {
    notificationType: stringClaim(payload.notificationType),
    subtype: optionalString(payload.subtype),
    notificationUuid: stringClaim(payload.notificationUUID),
    signedDate,
    environment,
    signedTransactionJws: envelope === "data"
      ? optionalString(claims.signedTransactionInfo)
      : undefined,
    claims: payload,
  };
}

async function verifyAppleJwsPayload(
  jws: string,
  options: VerifyOptions,
  label: string,
  dateClaim = "signedDate",
) {
  const parts = jws.split(".");
  if (parts.length !== 3) {
    throw new Error(`${label} must be a compact JWS.`);
  }
  const [encodedHeader, encodedPayload, encodedSignature] = parts;
  const header = parseJsonPart(encodedHeader) as Record<string, unknown>;
  const payload = parseJsonPart(encodedPayload) as Record<string, unknown>;

  if (header.alg !== "ES256") {
    throw new Error(`Unsupported ${label} algorithm.`);
  }

  const signedAt = payload[dateClaim];
  if (
    typeof signedAt !== "number" ||
    !Number.isFinite(new Date(signedAt).getTime())
  ) {
    throw new Error(`${label} is missing a valid ${dateClaim}.`);
  }
  const key = await verificationKey(header, options, signedAt);
  const verified = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    base64UrlDecode(encodedSignature),
    textEncoder.encode(`${encodedHeader}.${encodedPayload}`),
  );
  if (!verified) {
    throw new Error(`Invalid ${label} signature.`);
  }
  return payload;
}

async function verificationKey(
  header: Record<string, unknown>,
  options: VerifyOptions,
  signedAt: number,
) {
  const jwk = header.jwk;
  if (jwk && typeof jwk === "object") {
    if (!options.allowJwkFixtures) {
      throw new Error("AppTransaction production JWS must use Apple x5c.");
    }
    return crypto.subtle.importKey(
      "jwk",
      jwk as JsonWebKey,
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      ["verify"],
    );
  }

  const x5c = header.x5c;
  if (
    Array.isArray(x5c) && typeof x5c[0] === "string" &&
    x5c[0].trim().length > 0
  ) {
    const certificates = x5c.map((value) => {
      if (typeof value !== "string" || value.trim().length === 0) {
        throw new Error("Invalid AppTransaction certificate chain.");
      }
      return base64Decode(value);
    });
    // Root trust is fixed here; neither request claims nor verifier options can override it.
    return validateAppleCertificateChain(certificates, signedAt);
  }

  throw new Error("AppTransaction JWS is missing verification key.");
}

// The explicit trust argument lets certificate tests exercise the same validation
// with generated chains. Production callers always use the private Apple roots.
export async function validateAppleCertificateChain(
  certificates: Uint8Array[],
  signedAt: number,
  trustedRoots: ReadonlySet<string> = appleRootSha256Fingerprints,
): Promise<CryptoKey> {
  if (certificates.length !== 3) {
    throw new Error(
      "AppTransaction certificate chain must contain three certificates.",
    );
  }
  if (!trustedRoots.has(await sha256Hex(certificates[2]))) {
    throw new Error("AppTransaction certificate chain is not rooted at Apple.");
  }
  const chain = certificates.map((certificate) =>
    new X509Certificate(arrayBufferFrom(certificate))
  );
  if (
    !chain[0].getExtension("1.2.840.113635.100.6.11.1") ||
    !chain[1].getExtension("1.2.840.113635.100.6.2.1")
  ) {
    throw new Error("Invalid AppTransaction certificate purpose.");
  }
  for (let index = 0; index < chain.length; index++) {
    const certificate = chain[index];
    const issuer = chain[Math.min(index + 1, 2)];
    if (
      certificate.extensions.some((extension) =>
        extension.critical &&
        !(extension instanceof BasicConstraintsExtension) &&
        !(extension instanceof KeyUsagesExtension)
      )
    ) {
      throw new Error(
        "Unsupported AppTransaction certificate critical extension.",
      );
    }
    const constraints = certificate.getExtension(BasicConstraintsExtension);
    const usages = certificate.getExtension(KeyUsagesExtension)?.usages ?? 0;
    if (!constraints || constraints.ca !== (index > 0)) {
      throw new Error("Invalid AppTransaction certificate CA constraints.");
    }
    if (
      index > 0 && constraints.pathLength != null &&
      constraints.pathLength < index - 1
    ) {
      throw new Error("Invalid AppTransaction certificate path length.");
    }
    if (
      index === 0
        ? !(usages & KeyUsageFlags.digitalSignature) ||
          !!(usages & KeyUsageFlags.keyCertSign)
        : !(usages & KeyUsageFlags.keyCertSign)
    ) {
      throw new Error("Invalid AppTransaction certificate key usage.");
    }
    // Historical lifetime proofs remain valid after their signing certificate
    // expires. Subscription expiry is evaluated separately against the current time.
    if (
      !Number.isFinite(signedAt) ||
      signedAt < certificate.notBefore.getTime() - 60_000 ||
      signedAt > certificate.notAfter.getTime() + 60_000
    ) {
      throw new Error(
        "AppTransaction certificate is outside its validity period.",
      );
    }
    if (certificate.issuer !== issuer.subject) {
      throw new Error("Invalid AppTransaction certificate issuer.");
    }
    if (
      !(await certificate.verify({
        publicKey: issuer.publicKey,
        signatureOnly: true,
      }, crypto))
    ) {
      throw new Error("Invalid AppTransaction certificate chain signature.");
    }
  }
  const algorithm = chain[0].publicKey.algorithm as EcKeyAlgorithm;
  if (algorithm.name !== "ECDSA" || algorithm.namedCurve !== "P-256") {
    throw new Error("AppTransaction signing certificate must use P-256.");
  }
  return chain[0].publicKey.export(
    { name: "ECDSA", namedCurve: "P-256" },
    ["verify"],
    crypto,
  );
}

function verifyAppAppleId(
  claims: Record<string, unknown>,
  environment: string,
  options: VerifyOptions,
) {
  if (
    environment === "Production" &&
    (options.appAppleId == null || claims.appAppleId !== options.appAppleId)
  ) {
    throw new Error("App Store appAppleId does not match.");
  }
}

function parseJsonPart(value: string) {
  const parsed = JSON.parse(textDecoder.decode(base64UrlDecode(value)));
  if (typeof parsed !== "object" || parsed == null || Array.isArray(parsed)) {
    throw new Error("AppTransaction JWS must contain JSON objects.");
  }
  return parsed as Record<string, unknown>;
}

function stringClaim(value: unknown) {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error("AppTransaction is missing a required claim.");
  }
  return value;
}

function optionalString(value: unknown) {
  return typeof value === "string" && value.trim().length > 0
    ? value
    : undefined;
}

function optionalAppleDate(value: unknown) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return new Date(value).toISOString();
  }
  if (typeof value === "string" && value.trim().length > 0) {
    const parsed = new Date(value);
    if (Number.isFinite(parsed.valueOf())) {
      return parsed.toISOString();
    }
  }
  return undefined;
}

function base64UrlDecode(value: string) {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/").padEnd(
    Math.ceil(value.length / 4) * 4,
    "=",
  );
  return base64Decode(padded);
}

function base64Decode(value: string) {
  return Uint8Array.from(atob(value), (char) => char.charCodeAt(0));
}

async function sha256Hex(bytes: Uint8Array) {
  const digest = new Uint8Array(
    await crypto.subtle.digest("SHA-256", arrayBufferFrom(bytes)),
  );
  return [...digest].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function arrayBufferFrom(bytes: Uint8Array) {
  return bytes.buffer.slice(
    bytes.byteOffset,
    bytes.byteOffset + bytes.byteLength,
  ) as ArrayBuffer;
}

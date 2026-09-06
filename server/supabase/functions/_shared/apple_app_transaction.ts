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
  allowedEnvironments?: string[];
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
  );

  const bundleId = stringClaim(payload.bundleId);
  if (bundleId !== options.bundleId) {
    throw new Error("AppTransaction bundle id does not match Nottica.");
  }

  const environment = stringClaim(payload.environment ?? payload.receiptType);
  const allowed = options.allowedEnvironments ??
    ["Production", "Sandbox", "Xcode", "LocalTesting"];
  if (!allowed.includes(environment)) {
    throw new Error("AppTransaction environment is not allowed.");
  }

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
    ["Production", "Sandbox", "Xcode", "LocalTesting"];
  if (!allowed.includes(environment)) {
    throw new Error("StoreKit transaction environment is not allowed.");
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
  const data = payload.data;
  if (typeof data !== "object" || data === null || Array.isArray(data)) {
    throw new Error("App Store notification is missing data.");
  }
  const claims = data as Record<string, unknown>;
  const bundleId = stringClaim(claims.bundleId);
  if (bundleId !== options.bundleId) {
    throw new Error("App Store notification bundle id does not match.");
  }
  const environment = stringClaim(claims.environment);
  const allowed = options.allowedEnvironments ??
    ["Production", "Sandbox", "Xcode", "LocalTesting"];
  if (!allowed.includes(environment)) {
    throw new Error("App Store notification environment is not allowed.");
  }
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
    signedTransactionJws: optionalString(claims.signedTransactionInfo),
    claims: payload,
  };
}

async function verifyAppleJwsPayload(
  jws: string,
  options: VerifyOptions,
  label: string,
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

  const key = await verificationKey(header, options);
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
    await validateAppleCertificateChain(certificates);
    const spki = extractSubjectPublicKeyInfo(certificates[0]);
    return crypto.subtle.importKey(
      "spki",
      arrayBufferFrom(spki),
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      ["verify"],
    );
  }

  throw new Error("AppTransaction JWS is missing verification key.");
}

async function validateAppleCertificateChain(certificates: Uint8Array[]) {
  if (certificates.length < 2) {
    throw new Error("AppTransaction certificate chain is incomplete.");
  }
  const rootFingerprint = await sha256Hex(
    certificates[certificates.length - 1],
  );
  if (!appleRootSha256Fingerprints.has(rootFingerprint)) {
    throw new Error("AppTransaction certificate chain is not rooted at Apple.");
  }
  for (let index = 0; index < certificates.length - 1; index += 1) {
    const child = parseCertificateForVerification(certificates[index]);
    const issuerSpki = extractSubjectPublicKeyInfo(certificates[index + 1]);
    const verified = await verifyCertificateSignature(child, issuerSpki);
    if (!verified) {
      throw new Error("Invalid AppTransaction certificate chain signature.");
    }
  }
}

type CertificateVerificationParts = {
  tbs: Uint8Array;
  algorithmOid: string;
  signature: Uint8Array;
};

function parseCertificateForVerification(
  certificate: Uint8Array,
): CertificateVerificationParts {
  const certificateNode = readDerNode(certificate, 0);
  const children = readDerChildren(certificate, certificateNode);
  const tbs = children[0];
  const algorithm = children[1];
  const signature = children[2];
  if (!tbs || !algorithm || !signature || signature.tag !== 0x03) {
    throw new Error("Invalid AppTransaction certificate.");
  }
  return {
    tbs: certificate.slice(tbs.start, tbs.next),
    algorithmOid: oidFromAlgorithmIdentifier(certificate, algorithm),
    signature: certificate.slice(
      signature.contentStart + 1,
      signature.contentEnd,
    ),
  };
}

async function verifyCertificateSignature(
  child: CertificateVerificationParts,
  issuerSpki: Uint8Array,
) {
  if (child.algorithmOid === "1.2.840.10045.4.3.2") {
    return verifyEcdsaCertificate(child, issuerSpki, "SHA-256");
  }
  if (child.algorithmOid === "1.2.840.10045.4.3.3") {
    return verifyEcdsaCertificate(child, issuerSpki, "SHA-384");
  }
  if (child.algorithmOid === "1.2.840.113549.1.1.11") {
    return verifyRsaCertificate(child, issuerSpki, "SHA-256");
  }
  if (child.algorithmOid === "1.2.840.113549.1.1.12") {
    return verifyRsaCertificate(child, issuerSpki, "SHA-384");
  }
  throw new Error(
    "Unsupported AppTransaction certificate signature algorithm.",
  );
}

async function verifyEcdsaCertificate(
  child: CertificateVerificationParts,
  issuerSpki: Uint8Array,
  hash: "SHA-256" | "SHA-384",
) {
  for (const curve of ["P-256", "P-384"] as const) {
    try {
      const key = await crypto.subtle.importKey(
        "spki",
        arrayBufferFrom(issuerSpki),
        { name: "ECDSA", namedCurve: curve },
        false,
        ["verify"],
      );
      const rawSignature = derEcdsaSignatureToRaw(
        child.signature,
        curve === "P-256" ? 32 : 48,
      );
      return crypto.subtle.verify(
        { name: "ECDSA", hash },
        key,
        arrayBufferFrom(rawSignature),
        arrayBufferFrom(child.tbs),
      );
    } catch {
      // Try the other Apple root/intermediate curve.
    }
  }
  return false;
}

async function verifyRsaCertificate(
  child: CertificateVerificationParts,
  issuerSpki: Uint8Array,
  hash: "SHA-256" | "SHA-384",
) {
  const key = await crypto.subtle.importKey(
    "spki",
    arrayBufferFrom(issuerSpki),
    { name: "RSASSA-PKCS1-v1_5", hash },
    false,
    ["verify"],
  );
  return crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    key,
    arrayBufferFrom(child.signature),
    arrayBufferFrom(child.tbs),
  );
}

function extractSubjectPublicKeyInfo(certificate: Uint8Array): Uint8Array {
  const certificateNode = readDerNode(certificate, 0);
  if (certificateNode.tag !== 0x30) {
    throw new Error("Invalid AppTransaction certificate.");
  }
  const certificateChildren = readDerChildren(certificate, certificateNode);
  const tbsCertificate = certificateChildren[0];
  if (!tbsCertificate || tbsCertificate.tag !== 0x30) {
    throw new Error("Invalid AppTransaction certificate body.");
  }
  const tbsChildren = readDerChildren(certificate, tbsCertificate);
  const hasVersion = tbsChildren[0]?.tag === 0xa0;
  const spki = tbsChildren[hasVersion ? 6 : 5];
  if (!spki || spki.tag !== 0x30) {
    throw new Error("AppTransaction certificate is missing public key.");
  }
  return certificate.slice(spki.start, spki.next);
}

type DerNode = {
  tag: number;
  start: number;
  contentStart: number;
  contentEnd: number;
  next: number;
};

function readDerChildren(data: Uint8Array, node: DerNode) {
  const children: DerNode[] = [];
  let offset = node.contentStart;
  while (offset < node.contentEnd) {
    const child = readDerNode(data, offset);
    children.push(child);
    offset = child.next;
  }
  return children;
}

function readDerNode(data: Uint8Array, start: number): DerNode {
  const tag = data[start];
  let offset = start + 1;
  const lengthByte = data[offset++];
  let length = lengthByte;
  if ((lengthByte & 0x80) !== 0) {
    const lengthBytes = lengthByte & 0x7f;
    if (lengthBytes === 0 || lengthBytes > 4) {
      throw new Error("Unsupported DER length.");
    }
    length = 0;
    for (let index = 0; index < lengthBytes; index += 1) {
      length = (length << 8) | data[offset++];
    }
  }
  const contentStart = offset;
  const contentEnd = contentStart + length;
  if (contentEnd > data.length) {
    throw new Error("Invalid DER node length.");
  }
  return {
    tag,
    start,
    contentStart,
    contentEnd,
    next: contentEnd,
  };
}

function oidFromAlgorithmIdentifier(data: Uint8Array, node: DerNode) {
  const children = readDerChildren(data, node);
  const oid = children[0];
  if (!oid || oid.tag !== 0x06) {
    throw new Error("Invalid certificate algorithm identifier.");
  }
  return decodeOid(data.slice(oid.contentStart, oid.contentEnd));
}

function decodeOid(bytes: Uint8Array) {
  if (bytes.length === 0) {
    throw new Error("Invalid OID.");
  }
  const values = [Math.floor(bytes[0] / 40), bytes[0] % 40];
  let value = 0;
  for (let index = 1; index < bytes.length; index += 1) {
    value = (value << 7) | (bytes[index] & 0x7f);
    if ((bytes[index] & 0x80) === 0) {
      values.push(value);
      value = 0;
    }
  }
  return values.join(".");
}

function derEcdsaSignatureToRaw(
  signature: Uint8Array,
  componentLength: number,
) {
  const sequence = readDerNode(signature, 0);
  if (sequence.tag !== 0x30) {
    throw new Error("Invalid ECDSA signature.");
  }
  const integers = readDerChildren(signature, sequence);
  if (
    integers.length !== 2 || integers[0].tag !== 0x02 ||
    integers[1].tag !== 0x02
  ) {
    throw new Error("Invalid ECDSA signature integers.");
  }
  const raw = new Uint8Array(componentLength * 2);
  raw.set(
    trimAndPadInteger(
      signature.slice(integers[0].contentStart, integers[0].contentEnd),
      componentLength,
    ),
    0,
  );
  raw.set(
    trimAndPadInteger(
      signature.slice(integers[1].contentStart, integers[1].contentEnd),
      componentLength,
    ),
    componentLength,
  );
  return raw;
}

function trimAndPadInteger(value: Uint8Array, length: number) {
  let start = 0;
  while (start < value.length - 1 && value[start] === 0) {
    start += 1;
  }
  const trimmed = value.slice(start);
  if (trimmed.length > length) {
    throw new Error("ECDSA signature integer is too large.");
  }
  const output = new Uint8Array(length);
  output.set(trimmed, length - trimmed.length);
  return output;
}

function parseJsonPart(value: string) {
  return JSON.parse(textDecoder.decode(base64UrlDecode(value)));
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

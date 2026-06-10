import { importX509, jwtVerify } from "jose";
import { X509Certificate } from "@peculiar/x509";

export type DecodedAppleTransaction = {
  bundleId?: string;
  environment?: string;
  productId?: string;
  transactionId?: string;
  originalTransactionId?: string;
  expiresDate?: number;
  purchaseDate?: number;
  price?: number;
  currency?: string;
};

function base64DecodeToString(base64Url: string): string {
  const normalized = base64Url.replace(/-/g, "+").replace(/_/g, "/");
  const padding = normalized.length % 4 === 0 ? "" : "=".repeat(4 - (normalized.length % 4));
  return atob(normalized + padding);
}

function derFromBase64(base64: string): Uint8Array {
  const binary = base64DecodeToString(base64);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}

function pemFromBase64(base64: string): string {
  const normalized = base64.replace(/\s+/g, "");
  const lines = normalized.match(/.{1,64}/g) ?? [normalized];
  return `-----BEGIN CERTIFICATE-----\n${lines.join("\n")}\n-----END CERTIFICATE-----`;
}

function extractX5C(jws: string): string[] {
  const parts = jws.split(".");
  if (parts.length !== 3) {
    throw new Error("Invalid JWS format");
  }

  const header = JSON.parse(base64DecodeToString(parts[0])) as { x5c?: unknown; alg?: string };
  if (header.alg && header.alg !== "ES256") {
    throw new Error(`Unsupported JWS algorithm: ${header.alg}`);
  }

  if (!Array.isArray(header.x5c)) {
    throw new Error("Invalid x5c certificate chain (missing)");
  }

  const certificates = header.x5c.filter((entry): entry is string => typeof entry === "string");
  if (certificates.length !== header.x5c.length) {
    throw new Error("Invalid x5c certificate chain (non-string entries)");
  }

  return certificates;
}

export function normalizeAppleEnvironment(value?: string): "production" | "sandbox" | "xcode" {
  const lowered = value?.toLowerCase() ?? "";
  if (lowered === "xcode" || lowered === "localtesting") return "xcode";
  if (lowered === "sandbox") return "sandbox";
  return "production";
}

export function isLocalStoreKitEnvironment(value?: string): boolean {
  const normalized = normalizeAppleEnvironment(value);
  return normalized === "xcode";
}

async function verifyWithLeafCertificate(
  jws: string,
  leafCertificateBase64: string,
): Promise<DecodedAppleTransaction> {
  const publicKey = await importX509(pemFromBase64(leafCertificateBase64), "ES256");
  const { payload } = await jwtVerify(jws, publicKey, { algorithms: ["ES256"] });
  return payload as DecodedAppleTransaction;
}

async function verifyCertificateChain(
  trustedAppleRootCAsDer: Uint8Array[],
  leaf: X509Certificate,
  intermediate: X509Certificate,
): Promise<void> {
  let chainTrusted = false;

  for (const rootDer of trustedAppleRootCAsDer) {
    const root = new X509Certificate(rootDer);
    const intermediateSignedByRoot = await intermediate.verify({ publicKey: root.publicKey });
    if (intermediateSignedByRoot && intermediate.issuer === root.subject) {
      chainTrusted = true;
      break;
    }
  }

  if (!chainTrusted) {
    throw new Error("Untrusted Apple certificate chain");
  }

  const leafSignedByIntermediate = await leaf.verify({ publicKey: intermediate.publicKey });
  if (!leafSignedByIntermediate || leaf.issuer !== intermediate.subject) {
    throw new Error("Invalid App Store leaf certificate");
  }
}

export async function verifyAppleTransactionJws(
  jws: string,
  trustedAppleRootCAsDer: Uint8Array[],
): Promise<DecodedAppleTransaction> {
  const x5c = extractX5C(jws);

  if (x5c.length === 1) {
    const decoded = await verifyWithLeafCertificate(jws, x5c[0]);
    if (!isLocalStoreKitEnvironment(decoded.environment)) {
      throw new Error("Single-certificate JWS is only valid for Xcode StoreKit testing");
    }
    return decoded;
  }

  if (x5c.length < 2) {
    throw new Error(`Invalid x5c certificate chain (length=${x5c.length})`);
  }

  const leaf = new X509Certificate(derFromBase64(x5c[0]));
  const intermediate = new X509Certificate(derFromBase64(x5c[1]));
  await verifyCertificateChain(trustedAppleRootCAsDer, leaf, intermediate);

  return await verifyWithLeafCertificate(jws, x5c[0]);
}

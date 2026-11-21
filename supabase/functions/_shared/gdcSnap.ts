const encoder = new TextEncoder();
export const GDC_API_BASE = (Deno.env.get("GDC_API_BASE_URL") || "https://neo-sandbox-api.gdc.co.id/snap").replace(/\/$/, "");

export interface GdcCredentials {
  clientKey: string;
  clientSecret: string;
  privateKeyPem: string;
  partnerId: string;
  channelId: string;
  deviceId: string;
}

export interface GdcResponse {
  responseCode?: string;
  responseMessage?: string;
  accessToken?: string;
  expiresIn?: string;
  partnerReferenceNo?: string;
  referenceNo?: string;
  qrContent?: string;
  originalReferenceNo?: string;
  originalPartnerReferenceNo?: string;
  originalExternalId?: string;
  serviceCode?: string;
  latestTransactionStatus?: string;
  transactionStatusDesc?: string;
  paidTime?: string;
  amount?: { value?: string; currency?: string };
}

let tokenCache: { token: string; expiresAt: number } | null = null;
function base64(bytes: Uint8Array) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}
function pemBytes(pem: string) {
  const normalized = pem.replace(/\\n/g, "\n");
  const match = normalized.match(/-----BEGIN PRIVATE KEY-----([\s\S]+?)-----END PRIVATE KEY-----/);
  if (!match) throw new Error("GDC private key must be PKCS#8 PEM");
  const binary = atob(match[1].replace(/\s/g, ""));
  return Uint8Array.from(binary, (char) => char.charCodeAt(0));
}
async function sha256(value: string) {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
function timestamp() { return new Date().toISOString(); }
export function getGdcCredentials(): GdcCredentials {
  const credentials = {
    clientKey: Deno.env.get("GDC_CLIENT_KEY") || "",
    clientSecret: Deno.env.get("GDC_CLIENT_SECRET") || "",
    privateKeyPem: Deno.env.get("GDC_PRIVATE_KEY_PEM") || "",
    partnerId: Deno.env.get("GDC_PARTNER_ID") || "",
    channelId: Deno.env.get("GDC_CHANNEL_ID") || "",
    deviceId: Deno.env.get("GDC_DEVICE_ID") || "",
  };
  if (Object.values(credentials).some((value) => !value)) throw new Error("Konfigurasi pembayaran GDC belum lengkap.");
  if (!/^[0-9a-f-]{36}$/i.test(credentials.partnerId)) throw new Error("Konfigurasi partner GDC tidak valid.");
  if (!GDC_API_BASE.startsWith("https://")) throw new Error("Base URL GDC harus menggunakan HTTPS.");
  return credentials;
}
async function getAccessToken(credentials: GdcCredentials) {
  if (tokenCache && tokenCache.expiresAt > Date.now() + 30_000) return tokenCache.token;
  const now = timestamp();
  const keyBytes = pemBytes(credentials.privateKeyPem);
  const keyBuffer = new ArrayBuffer(keyBytes.byteLength);
  new Uint8Array(keyBuffer).set(keyBytes);
  const key = await crypto.subtle.importKey("pkcs8", keyBuffer, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, encoder.encode(`${credentials.clientKey}|${now}`));
  const result = await fetch(`${GDC_API_BASE}/v1.0/access-token/b2b`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Timestamp": now, "Client-Key": credentials.clientKey, "X-Signature": base64(new Uint8Array(signature)) },
    body: JSON.stringify({ grantType: "client_credentials" }),
  });
  const data = await result.json().catch(() => ({})) as GdcResponse;
  if (!result.ok || data.responseCode !== "2007300" || !data.accessToken) throw new Error("Gagal menghubungkan ke layanan QRIS.");
  tokenCache = { token: data.accessToken, expiresAt: Date.now() + Math.max(60, Number(data.expiresIn || 900)) * 1000 };
  return data.accessToken;
}
export async function gdcPost(credentials: GdcCredentials, path: string, body: Record<string, unknown>, externalId?: string): Promise<GdcResponse> {
  const token = await getAccessToken(credentials);
  const now = timestamp();
  const payloadHash = await sha256(JSON.stringify(body));
  const signingKey = await crypto.subtle.importKey("raw", encoder.encode(credentials.clientSecret), { name: "HMAC", hash: "SHA-512" }, false, ["sign"]);
  const signature = await crypto.subtle.sign("HMAC", signingKey, encoder.encode(`POST:${path}:${token}:${payloadHash}:${now}`));
  const result = await fetch(`${GDC_API_BASE}${path}`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json", "X-TIMESTAMP": now, "X-PARTNER-ID": credentials.partnerId, "X-EXTERNAL-ID": externalId || crypto.randomUUID(), "X-DEVICE-ID": credentials.deviceId, "CHANNEL-ID": credentials.channelId, "X-Signature": base64(new Uint8Array(signature)) },
    body: JSON.stringify(body),
  });
  const data = await result.json().catch(() => ({})) as GdcResponse;
  if (!result.ok) throw new Error("Layanan QRIS belum dapat memproses pembayaran.");
  return data;
}

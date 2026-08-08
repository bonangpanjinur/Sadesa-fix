// Generate a VAPID (ECDSA P-256) key pair in the browser using WebCrypto.
// Public key: uncompressed point, base64url. Private key: raw `d`, base64url.

function base64UrlEncode(bytes: Uint8Array): string {
  let binary = '';
  bytes.forEach((b) => { binary += String.fromCharCode(b); });
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function base64UrlToBytes(value: string): Uint8Array {
  const normalized = value.replace(/-/g, '+').replace(/_/g, '/');
  const padded = normalized + '='.repeat((4 - (normalized.length % 4)) % 4);
  const binary = atob(padded);
  return Uint8Array.from(binary, (c) => c.charCodeAt(0));
}

export async function generateVapidKeyPair(): Promise<{ publicKey: string; privateKey: string }> {
  const keyPair = await crypto.subtle.generateKey(
    { name: 'ECDSA', namedCurve: 'P-256' },
    true,
    ['sign', 'verify'],
  );

  const rawPublic = await crypto.subtle.exportKey('raw', keyPair.publicKey);
  const jwkPrivate = await crypto.subtle.exportKey('jwk', keyPair.privateKey);

  if (!jwkPrivate.d) throw new Error('Gagal mengekspor private key VAPID');

  return {
    publicKey: base64UrlEncode(new Uint8Array(rawPublic)),
    // `d` sudah dalam format base64url sesuai spesifikasi JWK
    privateKey: base64UrlEncode(base64UrlToBytes(jwkPrivate.d)),
  };
}

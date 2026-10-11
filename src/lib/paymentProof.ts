import { supabase } from '@/integrations/supabase/client';

function decodeStoragePath(value: string): string {
  let path = value.split(/[?#]/, 1)[0].replace(/^\/+/, '').replace(/^payment-proofs\//, '');
  // Support old rows that stored an encoded path (including paths encoded twice).
  for (let i = 0; i < 2; i += 1) {
    const decoded = decodeURIComponent(path);
    if (decoded === path) break;
    path = decoded;
  }
  return path;
}

function extractPaymentProofPath(value: string): string | null {
  try {
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      const path = decodeStoragePath(value);
      return path.startsWith('services/') || path.startsWith('orders/') ? path : null;
    }
    const parsed = new URL(value);
    const marker = '/payment-proofs/';
    const idx = parsed.pathname.indexOf(marker);
    if (idx === -1) return null;
    const path = decodeStoragePath(parsed.pathname.slice(idx + marker.length));
    return path.startsWith('services/') || path.startsWith('orders/') ? path : null;
  } catch {
    return null;
  }
}

export async function uploadServicePaymentProof(
  requestId: string,
  uploaderId: string,
  file: File,
): Promise<{ path: string | null; error: string | null }> {
  const extension = file.name.split('.').pop()?.toLowerCase() || 'jpg';
  const path = `services/${requestId}/${uploaderId}/${crypto.randomUUID()}.${extension}`;
  const { error } = await supabase.storage.from('payment-proofs').upload(path, file, {
    cacheControl: '3600',
    upsert: false,
  });
  return error ? { path: null, error: error.message } : { path, error: null };
}

export async function deleteServicePaymentProof(path: string): Promise<boolean> {
  if (!path.startsWith('services/')) return false;
  const { error } = await supabase.storage.from('payment-proofs').remove([path]);
  return !error;
}

async function findOrderProofCandidates(
  storage: ReturnType<typeof supabase.storage.from>,
  path: string,
): Promise<string[]> {
  const list = storage.list;
  if (typeof list !== 'function' || !path.startsWith('orders/')) return [];

  const orderFolder = path.split('/').slice(0, 2).join('/');
  const requestedPath = path.split('/').slice(2).join('/');
  const pendingFolders = [orderFolder];
  const candidates: string[] = [];
  const visited = new Set<string>();

  // Guest uploads use orders/{orderId}/{tokenHash}/{file}; authenticated
  // uploads use orders/{orderId}/{file}. Walk only this order's folder.
  while (pendingFolders.length && visited.size < 20) {
    const folder = pendingFolders.shift()!;
    if (visited.has(folder)) continue;
    visited.add(folder);

    const { data: objects, error } = await list.call(storage, folder, {
      limit: 100,
      sortBy: { column: 'created_at', order: 'desc' },
    });
    if (error || !objects) continue;

    for (const object of objects) {
      const objectPath = `${folder}/${object.name}`;
      // Storage may return either a folder marker or a file. Metadata/id are
      // more reliable than relying on a filename extension alone.
      const looksLikeFile = Boolean(object.id || object.metadata || /\.[a-z0-9]{2,8}$/i.test(object.name));
      if (looksLikeFile) {
        candidates.push(objectPath);
      } else if (visited.size < 20) {
        pendingFolders.push(objectPath);
      }
    }
  }

  const matching = candidates.filter((candidate) => candidate.slice(orderFolder.length + 1) === requestedPath);
  return [...matching, ...candidates.filter((candidate) => !matching.includes(candidate))];
}

export async function getPaymentProofSignedUrl(
  storedPath: string | null | undefined,
  expiresInSeconds = 3600,
): Promise<string | null> {
  if (!storedPath) return null;
  const path = extractPaymentProofPath(storedPath);
  if (!path) return null;

  const storage = supabase.storage.from('payment-proofs');
  let { data, error } = await storage.createSignedUrl(path, expiresInSeconds);

  // Storage can briefly return 400 immediately after an upload while its
  // object index catches up. Retry once so the order screen recovers from
  // that transient race instead of showing a permanent load error.
  if ((error || !data?.signedUrl) && typeof window !== 'undefined') {
    await new Promise((resolve) => window.setTimeout(resolve, 250));
    const retry = await storage.createSignedUrl(path, expiresInSeconds);
    data = retry.data;
    error = retry.error;
  }

  // Rows from older upload flows can point to a stale name, while the object
  // still exists under the same order (including guest token subfolders).
  // Try every candidate: one stale object must not prevent a valid proof from
  // being displayed.
  if (error || !data?.signedUrl) {
    const candidates = await findOrderProofCandidates(storage, path);
    for (const candidatePath of candidates) {
      if (candidatePath === path) continue;
      const fallback = await storage.createSignedUrl(candidatePath, expiresInSeconds);
      if (fallback.data?.signedUrl && !fallback.error) {
        data = fallback.data;
        error = null;
        break;
      }
      data = fallback.data;
      error = fallback.error;
    }
  }

  if (error || !data?.signedUrl) {
    console.warn('Failed to sign payment proof path:', error?.message);
    return null;
  }
  return data.signedUrl;
}

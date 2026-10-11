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

  // Older uploads can leave the order row pointing at an object that was
  // renamed/replaced. Storage reports this as the same 400/Object not found
  // response as a transient failure. Look for an existing proof in the
  // order's private folder and sign the newest candidate as a safe fallback.
  if ((error || !data?.signedUrl) && path.startsWith('orders/') && 'list' in storage) {
    const orderFolder = path.split('/').slice(0, 2).join('/');
    const requestedName = path.split('/').at(-1);
    const { data: objects, error: listError } = await storage.list(orderFolder, {
      limit: 100,
      sortBy: { column: 'created_at', order: 'desc' },
    });
    if (!listError && objects?.length) {
      const candidate = objects.find((object) => object.name === requestedName) ?? objects[0];
      const candidatePath = `${orderFolder}/${candidate.name}`;
      const fallback = await storage.createSignedUrl(candidatePath, expiresInSeconds);
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

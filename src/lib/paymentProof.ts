import { supabase } from '@/integrations/supabase/client';

function extractPaymentProofPath(value: string): string | null {
  try {
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      const path = decodeURIComponent(value).replace(/^\/+/, '').replace(/^payment-proofs\//, '');
      return path.startsWith('services/') || path.startsWith('orders/') ? path : null;
    }
    const parsed = new URL(value);
    const marker = '/payment-proofs/';
    const idx = parsed.pathname.indexOf(marker);
    if (idx === -1) return null;
    const path = decodeURIComponent(parsed.pathname.slice(idx + marker.length));
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

  const { data, error } = await supabase.storage
    .from('payment-proofs')
    .createSignedUrl(path, expiresInSeconds);

  if (error || !data?.signedUrl) {
    console.warn('Failed to sign payment proof path:', error?.message);
    return null;
  }
  return data.signedUrl;
}

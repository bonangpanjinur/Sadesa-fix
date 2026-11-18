import { supabase } from '@/integrations/supabase/client';

const BUCKET = 'qris-merchant-static';

/** Convert a stored public URL or bucket-relative QRIS path to a display URL. */
export function getStaticQrisPublicUrl(value: string | null | undefined): string | null {
  if (!value?.trim()) return null;
  const normalized = value.trim();
  if (/^https?:\/\//i.test(normalized)) return normalized;
  const path = normalized
    .replace(/^\/+/, '')
    .replace(new RegExp(`^${BUCKET}/`), '')
    .replace(/^storage\/v1\/object\/public\/[^/]+\//, '');
  if (!path || path.includes('..')) return null;
  return supabase.storage.from(BUCKET).getPublicUrl(path).data.publicUrl;
}

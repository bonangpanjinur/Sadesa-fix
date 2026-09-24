import { supabase } from '@/integrations/supabase/client';

export const COURIER_DOCUMENT_BUCKET = 'courier-documents';
type DocumentKind = 'ktp' | 'photo' | 'vehicle';

/**
 * The database should store a storage object path, but older registrations may
 * contain a Supabase public/signed URL or only a legacy filename/UUID.
 */
export function normalizeCourierDocumentPath(value: string | null | undefined): string | null {
  if (!value) return null;
  const trimmed = value.trim();
  if (!trimmed) return null;
  if (!trimmed.startsWith('http')) return trimmed;

  try {
    const url = new URL(trimmed);
    const markerIndex = url.pathname.indexOf('/storage/v1/object/');
    if (markerIndex < 0) return trimmed;
    const segments = url.pathname.slice(markerIndex + '/storage/v1/object/'.length).split('/');
    const bucketIndex = segments.findIndex((segment) => segment === COURIER_DOCUMENT_BUCKET);
    if (bucketIndex < 0 || bucketIndex === segments.length - 1) return trimmed;
    return segments.slice(bucketIndex + 1).map(decodeURIComponent).join('/');
  } catch {
    return trimmed;
  }
}

function documentPathCandidates(
  value: string | null | undefined,
  userId?: string | null,
  kind?: DocumentKind,
): string[] {
  const normalized = normalizeCourierDocumentPath(value);
  if (!normalized) return [];

  const candidates = [normalized];
  // A few early registrations stored only the generated filename/UUID. Try the
  // current namespace and the two historical folder layouts before giving up.
  if (userId && kind && !normalized.includes('/')) {
    candidates.unshift(`${userId}/${kind}/${normalized}`, `${kind}/${normalized}`);
  }
  return [...new Set(candidates)];
}

export async function createCourierDocumentSignedUrl(
  value: string | null | undefined,
  userId?: string | null,
  kind?: DocumentKind,
): Promise<string | null> {
  const normalized = normalizeCourierDocumentPath(value);
  if (!normalized) return null;
  if (normalized.startsWith('http')) return normalized;

  for (const path of documentPathCandidates(value, userId, kind)) {
    const { data, error } = await supabase.storage
      .from(COURIER_DOCUMENT_BUCKET)
      .createSignedUrl(path, 10 * 60);
    if (!error && data?.signedUrl) return data.signedUrl;
    if (error) console.warn('Unable to create courier document signed URL', { path, message: error.message });
  }
  return null;
}

export async function removeCourierDocuments(paths: Array<string | null | undefined>): Promise<void> {
  const normalized = paths
    .map(normalizeCourierDocumentPath)
    .filter((path): path is string => Boolean(path) && !path.startsWith('http'));
  if (!normalized.length) return;
  const { error } = await supabase.storage.from(COURIER_DOCUMENT_BUCKET).remove(normalized);
  if (error) console.warn('Unable to clean up courier registration documents', error.message);
}

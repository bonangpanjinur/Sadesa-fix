import { supabase } from '@/integrations/supabase/client';

export const COURIER_DOCUMENT_BUCKET = 'courier-documents';

/**
 * The database should store a storage object path, but older registrations may
 * contain a Supabase public/signed URL. Convert both formats to a bucket path
 * before asking Storage for a new signed URL.
 */
export function normalizeCourierDocumentPath(value: string | null | undefined): string | null {
  if (!value) return null;
  const trimmed = value.trim();
  if (!trimmed) return null;
  if (!trimmed.startsWith('http')) return trimmed;

  try {
    const url = new URL(trimmed);
    const marker = `/storage/v1/object/`;
    const markerIndex = url.pathname.indexOf(marker);
    if (markerIndex < 0) return trimmed;

    const objectPath = url.pathname.slice(markerIndex + marker.length);
    const segments = objectPath.split('/');
    const bucketIndex = segments.findIndex((segment) => segment === COURIER_DOCUMENT_BUCKET);
    if (bucketIndex < 0 || bucketIndex === segments.length - 1) return trimmed;
    return segments.slice(bucketIndex + 1).map(decodeURIComponent).join('/');
  } catch {
    return trimmed;
  }
}

export async function createCourierDocumentSignedUrl(value: string | null | undefined): Promise<string | null> {
  const path = normalizeCourierDocumentPath(value);
  if (!path) return null;
  if (path.startsWith('http')) return path;

  const { data, error } = await supabase.storage
    .from(COURIER_DOCUMENT_BUCKET)
    .createSignedUrl(path, 10 * 60);
  if (error) {
    console.warn('Unable to create courier document signed URL', { path, message: error.message });
    return null;
  }
  return data?.signedUrl || null;
}

export async function removeCourierDocuments(paths: Array<string | null | undefined>): Promise<void> {
  const normalized = paths
    .map(normalizeCourierDocumentPath)
    .filter((path): path is string => Boolean(path) && !path.startsWith('http'));
  if (!normalized.length) return;
  const { error } = await supabase.storage.from(COURIER_DOCUMENT_BUCKET).remove(normalized);
  if (error) console.warn('Unable to clean up courier registration documents', error.message);
}

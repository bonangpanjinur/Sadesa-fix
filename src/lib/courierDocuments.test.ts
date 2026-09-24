import { describe, expect, it, vi } from 'vitest';

vi.mock('@/integrations/supabase/client', () => ({
  supabase: { storage: { from: vi.fn() } },
}));

import { normalizeCourierDocumentPath } from './courierDocuments';

describe('normalizeCourierDocumentPath', () => {
  it('keeps the canonical storage path unchanged', () => {
    expect(normalizeCourierDocumentPath('user-1/ktp/ktp.jpg')).toBe('user-1/ktp/ktp.jpg');
  });

  it('extracts a path from a public storage URL', () => {
    expect(normalizeCourierDocumentPath('https://project.supabase.co/storage/v1/object/public/courier-documents/user-1/ktp/ktp.jpg'))
      .toBe('user-1/ktp/ktp.jpg');
  });

  it('extracts a path from a signed storage URL', () => {
    expect(normalizeCourierDocumentPath('https://project.supabase.co/storage/v1/object/sign/courier-documents/user-1/photo/selfie.jpg?token=abc'))
      .toBe('user-1/photo/selfie.jpg');
  });

  it('returns null for blank values and preserves unrelated URLs for diagnostics', () => {
    expect(normalizeCourierDocumentPath('  ')).toBeNull();
    expect(normalizeCourierDocumentPath('https://example.com/document.jpg')).toBe('https://example.com/document.jpg');
  });
});

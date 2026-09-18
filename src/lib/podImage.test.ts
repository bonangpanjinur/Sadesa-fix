import { beforeEach, describe, expect, it, vi } from 'vitest';

const createSignedUrl = vi.fn();
vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    storage: {
      from: vi.fn(() => ({ createSignedUrl })),
    },
  },
}));

import { getPodImageSignedUrl } from './podImage';

describe('getPodImageSignedUrl', () => {
  beforeEach(() => {
    createSignedUrl.mockReset();
    createSignedUrl.mockResolvedValue({ data: { signedUrl: 'https://signed.example/pod.jpg' }, error: null });
  });

  it('signs the relative storage path returned by the delivery RPC', async () => {
    await expect(getPodImageSignedUrl('order-1/photo.jpg')).resolves.toBe('https://signed.example/pod.jpg');
    expect(createSignedUrl).toHaveBeenCalledWith('order-1/photo.jpg', 3600);
  });

  it('extracts paths from Supabase storage URLs', async () => {
    await getPodImageSignedUrl('https://project.supabase.co/storage/v1/object/public/pod-images/order-1/photo.jpg');
    expect(createSignedUrl).toHaveBeenCalledWith('order-1/photo.jpg', 3600);
  });

  it('returns null for an unrelated URL instead of rendering a broken image', async () => {
    await expect(getPodImageSignedUrl('https://example.com/photo.jpg')).resolves.toBeNull();
    expect(createSignedUrl).not.toHaveBeenCalled();
  });
});

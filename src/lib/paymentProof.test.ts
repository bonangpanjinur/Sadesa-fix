import { beforeEach, describe, expect, it, vi } from 'vitest';

const createSignedUrl = vi.fn();
vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    storage: {
      from: vi.fn(() => ({ createSignedUrl })),
    },
  },
}));

import { getPaymentProofSignedUrl } from './paymentProof';

describe('getPaymentProofSignedUrl', () => {
  beforeEach(() => createSignedUrl.mockReset());

  it('returns null when no proof is stored', async () => {
    await expect(getPaymentProofSignedUrl(null)).resolves.toBeNull();
    expect(createSignedUrl).not.toHaveBeenCalled();
  });

  it('creates a signed URL from a stored payment-proof path', async () => {
    createSignedUrl.mockResolvedValue({ data: { signedUrl: 'https://signed.example/proof' }, error: null });
    await expect(getPaymentProofSignedUrl('https://storage.example/payment-proofs/order%2Fproof.jpg?download=1', 900)).resolves.toBe('https://signed.example/proof');
    expect(createSignedUrl).toHaveBeenCalledWith('order/proof.jpg', 900);
  });

  it('keeps the original URL when signing fails or URL is external', async () => {
    createSignedUrl.mockResolvedValue({ data: null, error: { message: 'missing object' } });
    await expect(getPaymentProofSignedUrl('https://storage.example/payment-proofs/missing.jpg')).resolves.toBe('https://storage.example/payment-proofs/missing.jpg');
    await expect(getPaymentProofSignedUrl('https://cdn.example/proof.jpg')).resolves.toBe('https://cdn.example/proof.jpg');
  });
});

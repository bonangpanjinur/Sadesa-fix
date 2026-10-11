import { beforeEach, describe, expect, it, vi } from 'vitest';

const createSignedUrl = vi.fn();
const upload = vi.fn();
const remove = vi.fn();
const list = vi.fn();
vi.mock('@/integrations/supabase/client', () => ({
  SUPABASE_URL: 'https://xqdbnlcvboelvkdotilj.supabase.co',
  supabase: {
    storage: {
      from: vi.fn(() => ({ createSignedUrl, upload, remove, list })),
    },
  },
}));

import { deleteServicePaymentProof, getPaymentProofSignedUrl, uploadServicePaymentProof } from './paymentProof';

describe('service payment proof storage', () => {
  beforeEach(() => {
    createSignedUrl.mockReset();
    upload.mockReset();
    remove.mockReset();
    list.mockReset();
  });

  it('returns null when there is no stored path', async () => {
    await expect(getPaymentProofSignedUrl(null)).resolves.toBeNull();
    expect(createSignedUrl).not.toHaveBeenCalled();
  });

  it('creates a signed URL from a stored private service path', async () => {
    createSignedUrl.mockResolvedValue({ data: { signedUrl: 'https://signed.example/proof' }, error: null });
    await expect(getPaymentProofSignedUrl('services/request/uploader/proof.jpg', 900)).resolves.toBe('https://signed.example/proof');
    expect(createSignedUrl).toHaveBeenCalledWith('services/request/uploader/proof.jpg', 900);
  });

  it('creates a signed URL from the canonical marketplace order path', async () => {
    createSignedUrl.mockResolvedValue({ data: { signedUrl: 'https://signed.example/order-proof' }, error: null });
    await expect(getPaymentProofSignedUrl('orders/order-id/receipt.jpg')).resolves.toBe('https://signed.example/order-proof');
    expect(createSignedUrl).toHaveBeenCalledWith('orders/order-id/receipt.jpg', 3600);
  });

  it('signs legacy payment-proofs URLs but rejects arbitrary URLs and signing failures', async () => {
    createSignedUrl.mockResolvedValueOnce({ data: { signedUrl: 'https://signed.example/legacy' }, error: null });
    createSignedUrl.mockResolvedValueOnce({ data: null, error: { message: 'missing object' } });
    await expect(getPaymentProofSignedUrl('https://xqdbnlcvboelvkdotilj.supabase.co/storage/v1/object/public/payment-proofs/orders%2Fproof.jpg?download=1')).resolves.toBe('https://signed.example/legacy');
    await expect(getPaymentProofSignedUrl('https://xqdbnlcvboelvkdotilj.supabase.co/storage/v1/object/public/payment-proofs/missing.jpg')).resolves.toBeNull();
    await expect(getPaymentProofSignedUrl('https://cdn.example/proof.jpg')).resolves.toBeNull();
  });

  it('recovers a proof from a nested guest folder when the stored name is stale', async () => {
    createSignedUrl
      .mockResolvedValueOnce({ data: null, error: { message: 'Object not found' } })
      .mockResolvedValueOnce({ data: null, error: { message: 'Object not found' } })
      .mockResolvedValueOnce({ data: { signedUrl: 'https://signed.example/nested-proof' }, error: null });
    list
      .mockResolvedValueOnce({
        data: [{ name: 'guest-token-hash' }],
        error: null,
      })
      .mockResolvedValueOnce({
        data: [{ name: 'actual-proof.png', id: 'object-id', metadata: { mimetype: 'image/png' } }],
        error: null,
      });

    await expect(getPaymentProofSignedUrl('orders/order-id/stale-proof.png')).resolves.toBe('https://signed.example/nested-proof');
    expect(list).toHaveBeenNthCalledWith(1, 'orders/order-id', expect.any(Object));
    expect(list).toHaveBeenNthCalledWith(2, 'orders/order-id/guest-token-hash', expect.any(Object));
    expect(createSignedUrl).toHaveBeenLastCalledWith('orders/order-id/guest-token-hash/actual-proof.png', 3600);
  });

  it('uploads proofs to a request/uploader-scoped private path', async () => {
    upload.mockResolvedValue({ error: null });
    const file = new File(['proof'], 'receipt.png', { type: 'image/png' });
    const result = await uploadServicePaymentProof('request-id', 'user-id', file);
    expect(result.path).toMatch(/^services\/request-id\/user-id\/[0-9a-f-]+\.png$/i);
    expect(upload).toHaveBeenCalledWith(expect.stringMatching(/^services\/request-id\/user-id\//), file, { cacheControl: '3600', upsert: false });
  });

  it('only cleans up service proof paths', async () => {
    remove.mockResolvedValue({ error: null });
    await expect(deleteServicePaymentProof('orders/other/proof.jpg')).resolves.toBe(false);
    expect(remove).not.toHaveBeenCalled();
    await expect(deleteServicePaymentProof('services/request/user/proof.jpg')).resolves.toBe(true);
    expect(remove).toHaveBeenCalledWith(['services/request/user/proof.jpg']);
  });
});

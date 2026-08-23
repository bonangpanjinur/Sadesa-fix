import { beforeEach, describe, expect, it, vi } from 'vitest';

const { rpc } = vi.hoisted(() => ({ rpc: vi.fn() }));
vi.mock('@/integrations/supabase/client', () => ({
  supabase: { rpc },
}));

import { processAtomicPOSSale } from './posCheckout';

describe('processAtomicPOSSale', () => {
  beforeEach(() => rpc.mockReset());

  it('calls the atomic RPC with the complete transaction contract', async () => {
    rpc.mockResolvedValue({
      data: { sale_id: 'sale-1', sale_number: 'TRX-1', total: 12500, payment_method: 'cash', duplicate: false },
      error: null,
    });
    const sale = {
      sale_number: 'TRX-1', subtotal: 10000, discount_amount: 0, tax_amount: 2500, total: 12500,
      payment_method: 'cash', payment_amount: 15000, change_amount: 2500,
      promotion_discount: 0, voucher_discount: 0, loyalty_points_earned: 1,
      loyalty_points_redeemed: 0, loyalty_discount: 0,
    };
    const items = [{ product_id: 'product-1', name: 'Kopi', qty: 1, price: 12500, subtotal: 12500 }];

    await expect(processAtomicPOSSale('request-123456789', 'tenant-1', 'outlet-1', 'cashier-1', sale, items))
      .resolves.toMatchObject({ sale_id: 'sale-1', duplicate: false });
    expect(rpc).toHaveBeenCalledWith('process_pos_sale', {
      p_request_key: 'request-123456789',
      p_tenant_id: 'tenant-1',
      p_outlet_id: 'outlet-1',
      p_cashier_id: 'cashier-1',
      p_sale: sale,
      p_items: items,
    });
  });

  it('propagates the RPC error so the caller can retry with the same key', async () => {
    const error = new Error('stock unavailable');
    rpc.mockResolvedValue({ data: null, error });
    await expect(processAtomicPOSSale('request-123456789', 'tenant-1', 'outlet-1', 'cashier-1', {
      sale_number: 'TRX-1', subtotal: 1, discount_amount: 0, tax_amount: 0, total: 1,
      payment_method: 'cash', payment_amount: 1, change_amount: 0,
      promotion_discount: 0, voucher_discount: 0, loyalty_points_earned: 0,
      loyalty_points_redeemed: 0, loyalty_discount: 0,
    }, [{ product_id: 'product-1', name: 'Kopi', qty: 1, price: 1, subtotal: 1 }]))
      .rejects.toThrow('stock unavailable');
  });
});

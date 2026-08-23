import { beforeEach, describe, expect, it, vi } from 'vitest';

const { rpc } = vi.hoisted(() => ({ rpc: vi.fn() }));
vi.mock('@/integrations/supabase/client', () => ({
  supabase: { rpc },
}));

import { adjustPOSStock, closeCashSession, openCashSession, recordCashMutation } from './posOperations';

describe('POS operation RPC wrappers', () => {
  beforeEach(() => rpc.mockReset());

  it('opens a cash session with tenant and cashier identity', async () => {
    rpc.mockResolvedValue({ data: { session_id: 'session-1', status: 'open' }, error: null });
    await expect(openCashSession({
      tenantId: 'tenant-1', outletId: 'outlet-1', cashierId: 'cashier-1', cashierName: 'Kasir', openingBalance: 100000,
    })).resolves.toMatchObject({ session_id: 'session-1' });
    expect(rpc).toHaveBeenCalledWith('open_cash_session', {
      p_tenant_id: 'tenant-1', p_outlet_id: 'outlet-1', p_cashier_id: 'cashier-1',
      p_cashier_name: 'Kasir', p_opening_balance: 100000, p_notes: null,
    });
  });

  it('records mutation and closes a session through RPC', async () => {
    rpc
      .mockResolvedValueOnce({ data: { mutation_id: 'mutation-1', session_id: 'session-1' }, error: null })
      .mockResolvedValueOnce({ data: { session_id: 'session-1', expected_balance: 110000, difference: 0 }, error: null });
    await recordCashMutation({
      sessionId: 'session-1', tenantId: 'tenant-1', outletId: 'outlet-1', type: 'in',
      category: 'modal', amount: 10000, description: 'Setoran', reference: 'ref-1',
    });
    await closeCashSession({ sessionId: 'session-1', closingBalance: 110000, notes: 'Closing normal' });
    expect(rpc).toHaveBeenNthCalledWith(1, 'record_cash_mutation', expect.objectContaining({ p_amount: 10000, p_type: 'in' }));
    expect(rpc).toHaveBeenNthCalledWith(2, 'close_cash_session', {
      p_session_id: 'session-1', p_closing_balance: 110000, p_notes: 'Closing normal',
    });
  });

  it('uses the atomic stock adjustment contract and propagates errors', async () => {
    const error = new Error('Insufficient stock');
    rpc.mockResolvedValue({ data: null, error });
    await expect(adjustPOSStock({
      stockId: 'stock-1', tenantId: 'tenant-1', outletId: 'outlet-1', type: 'transfer_out', quantity: 2,
    })).rejects.toThrow('Insufficient stock');
    expect(rpc).toHaveBeenCalledWith('adjust_pos_stock', expect.objectContaining({
      p_stock_id: 'stock-1', p_quantity: 2, p_type: 'transfer_out',
    }));
  });
});

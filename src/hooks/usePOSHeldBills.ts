import { useCallback, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import type { CartItem, HeldBill } from '@/components/pos/kasir/types';

interface UsePOSHeldBillsArgs {
  tenantId: string | null;
  outletId: string | null;
  cashierId: string | null;
}

export function usePOSHeldBills({ tenantId, outletId, cashierId }: UsePOSHeldBillsArgs) {
  const [heldBills, setHeldBills] = useState<HeldBill[]>([]);
  const [isLoading, setIsLoading] = useState(false);

  const fetchHeldBills = useCallback(async () => {
    if (!tenantId || !outletId || !cashierId) {
      setHeldBills([]);
      return [];
    }
    setIsLoading(true);
    try {
      const { data, error } = await supabase.from('pos_held_bills' as never).select('*')
        .eq('tenant_id', tenantId).eq('outlet_id', outletId).eq('cashier_id', cashierId).order('created_at');
      if (error) throw error;
      const bills = (data || []).map((bill) => ({ ...bill, items: bill.items || [] })) as unknown as HeldBill[];
      setHeldBills(bills);
      return bills;
    } finally {
      setIsLoading(false);
    }
  }, [tenantId, outletId, cashierId]);

  const holdBill = useCallback(async (input: {
    items: CartItem[];
    discountAmount: number;
    notes: string;
    customerName?: string | null;
    customerId?: string | null;
  }) => {
    if (!tenantId || !outletId || !cashierId || input.items.length === 0) return false;
    const { error } = await supabase.from('pos_held_bills' as never).insert({
      tenant_id: tenantId,
      outlet_id: outletId,
      cashier_id: cashierId,
      label: `Bill ${heldBills.length + 1}`,
      customer_name: input.customerName || null,
      customer_id: input.customerId || null,
      items: input.items,
      discount_amount: input.discountAmount,
      notes: input.notes,
    });
    if (error) throw error;
    await fetchHeldBills();
    return true;
  }, [tenantId, outletId, cashierId, heldBills.length, fetchHeldBills]);

  const resumeBill = useCallback(async (bill: HeldBill) => {
    const { error } = await supabase.from('pos_held_bills' as never).delete()
      .eq('id', bill.id).eq('tenant_id', tenantId || '').eq('outlet_id', outletId || '').eq('cashier_id', cashierId || '');
    if (error) throw error;
    await fetchHeldBills();
    return bill;
  }, [tenantId, outletId, cashierId, fetchHeldBills]);

  return { heldBills, isLoading, fetchHeldBills, holdBill, resumeBill };
}

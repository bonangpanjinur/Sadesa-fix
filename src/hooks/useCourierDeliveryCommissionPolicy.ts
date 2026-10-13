import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import type { CourierDeliveryCommissionPolicy } from '@/lib/courierDeliveryEarnings';

type CommissionSettingsRow = {
  fee_percent: number;
  is_enabled: boolean;
  charge_courier_delivery: boolean;
};

export function useCourierDeliveryCommissionPolicy(enabled: boolean) {
  return useQuery<CourierDeliveryCommissionPolicy>({
    queryKey: ['courier-delivery-commission-policy'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('commission_fee_settings' as never)
        .select('fee_percent,is_enabled,charge_courier_delivery' as never)
        .eq('owner_type' as never, 'COURIER' as never)
        .maybeSingle();

      if (error) throw error;

      const settings = data as unknown as CommissionSettingsRow | null;
      if (!settings) {
        return { feePercent: 0, enabled: false, chargeCourierDelivery: false };
      }

      return {
        feePercent: Number(settings.fee_percent),
        enabled: settings.is_enabled,
        chargeCourierDelivery: settings.charge_courier_delivery,
      };
    },
    enabled,
    staleTime: 60_000,
  });
}

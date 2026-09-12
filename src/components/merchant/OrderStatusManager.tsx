import { MerchantOrdersWorkspace } from '@/pages/merchant/MerchantOrdersPage';

interface OrderStatusManagerProps {
  merchantId: string;
}

/**
 * Compatibility wrapper for the dashboard Orders tab.
 * All merchant order behavior now lives in MerchantOrdersWorkspace so the
 * dashboard and /merchant/orders route share the same query, actions, dialogs,
 * realtime behavior, and status contract.
 */
export function OrderStatusManager({ merchantId }: OrderStatusManagerProps) {
  return <MerchantOrdersWorkspace embedded merchantIdOverride={merchantId} />;
}

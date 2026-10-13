import { getCourierDeliveryEarningBreakdown, type CourierDeliveryCommissionPolicy } from '@/lib/courierDeliveryEarnings';
import { formatPrice } from '@/lib/utils';

interface Props {
  shippingCost: number | null | undefined;
  earningEstimate: number | null | undefined;
  policy: CourierDeliveryCommissionPolicy | null | undefined;
  policyLoading?: boolean;
  policyError?: boolean;
}

export function CourierDeliveryEarnings({
  shippingCost,
  earningEstimate,
  policy,
  policyLoading = false,
  policyError = false,
}: Props) {
  const breakdown = getCourierDeliveryEarningBreakdown({ shippingCost, earningEstimate, policy: policyError ? null : policy });
  const commissionLabel = breakdown.platformFee == null
    ? policyError
      ? 'Tidak tersedia'
      : policyLoading
        ? 'Memuat…'
        : 'Tidak tersedia'
    : `−${formatPrice(breakdown.platformFee)}`;

  return (
    <div className="space-y-1 text-xs" data-testid="courier-delivery-earnings">
      <div className="flex justify-between gap-3">
        <span className="text-muted-foreground">Ongkir kurir (gross)</span>
        <span>{formatPrice(breakdown.gross)}</span>
      </div>
      <div className="flex justify-between gap-3">
        <span className="text-muted-foreground">Fee platform</span>
        <span>{commissionLabel}</span>
      </div>
      <div className="flex justify-between gap-3 border-t pt-1 font-semibold">
        <span>Estimasi bersih</span>
        <span data-testid="courier-estimated-net">{breakdown.net == null ? '—' : formatPrice(breakdown.net)}</span>
      </div>
      <p className="pt-1 text-[10px] leading-relaxed text-muted-foreground">
        Estimasi memakai tarif komisi aktif. Fee final dicatat saat pengiriman selesai dan ditagihkan lewat wallet komisi.
      </p>
    </div>
  );
}

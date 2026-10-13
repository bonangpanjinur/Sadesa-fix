import { useEffect, useState } from 'react';
import { CheckCircle, Clock3, MapPin, Navigation, X } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { NavigationButton } from '@/components/courier/NavigationButton';
import { formatPrice } from '@/lib/utils';
import { formatRemainingTime } from '@/lib/courierOrderStatus';
import { getDeliveryEstimate } from '@/lib/etaCalculation';
import { CourierDeliveryEarnings } from '@/components/courier/CourierDeliveryEarnings';
import type { CourierDeliveryCommissionPolicy } from '@/lib/courierDeliveryEarnings';

export interface DeliveryOfferCardData {
  id: string;
  order_id: string;
  expires_at: string;
  order: {
    total: number;
    shipping_cost?: number | null;
    courier_earning_estimate?: number | null;
    courier_platform_fee?: number | null;
    pickup_address?: string | null;
    pickup_lat?: number | null;
    pickup_lng?: number | null;
    delivery_name?: string | null;
    delivery_address?: string | null;
    delivery_lat?: number | null;
    delivery_lng?: number | null;
    notes?: string | null;
    merchants?: { name: string; address?: string | null } | null;
  } | null;
}

interface Props {
  offer: DeliveryOfferCardData;
  busy?: boolean;
  onRespond: (id: string, accept: boolean) => void;
  commissionPolicy?: CourierDeliveryCommissionPolicy | null;
  commissionPolicyLoading?: boolean;
  commissionPolicyError?: boolean;
}

export function DeliveryOfferCard({
  offer,
  busy,
  onRespond,
  commissionPolicy,
  commissionPolicyLoading,
  commissionPolicyError,
}: Props) {
  const [now, setNow] = useState(Date.now());
  useEffect(() => { const timer = window.setInterval(() => setNow(Date.now()), 1000); return () => window.clearInterval(timer); }, []);
  const remaining = Math.max(0, new Date(offer.expires_at).getTime() - now);
  const expired = remaining === 0;
  const order = offer.order;
  const pickupAddress = order?.pickup_address || order?.merchants?.address;
  const estimate = order?.pickup_lat != null && order?.pickup_lng != null && order?.delivery_lat != null && order?.delivery_lng != null
    ? getDeliveryEstimate(
      { lat: Number(order.pickup_lat), lng: Number(order.pickup_lng) },
      { lat: Number(order.delivery_lat), lng: Number(order.delivery_lng) },
      'motor',
    )
    : null;
  return (
    <Card className={`space-y-3 p-4 ${expired ? 'opacity-70' : 'border-primary/30 border-2'}`}>
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="font-semibold">#{offer.order_id.slice(0, 8).toUpperCase()}</p>
          <p className="text-xs text-muted-foreground">Kirim barang langsung · {order?.delivery_name || 'Penerima'}</p>
        </div>
        <div className={`flex shrink-0 items-center gap-1 text-sm font-semibold ${expired ? 'text-destructive' : 'text-warning'}`}>
          <Clock3 className="h-4 w-4" /> {expired ? 'Kedaluwarsa' : formatRemainingTime(offer.expires_at, now)}
        </div>
      </div>
      <div className="grid gap-2 text-sm">
        <div className="flex items-start gap-2"><MapPin className="h-4 w-4 text-primary mt-0.5" /><div><b>Pickup pengirim</b><p className="text-muted-foreground">{pickupAddress || 'Lokasi pickup belum tersedia'}</p></div></div>
        <div className="flex items-start gap-2"><Navigation className="h-4 w-4 text-destructive mt-0.5" /><div><b>Penerima</b><p className="text-muted-foreground">{order?.delivery_address || 'Alamat tujuan belum tersedia'}</p></div></div>
      </div>
      {order?.notes && <p className="text-xs bg-secondary rounded p-2">Catatan: {order.notes}</p>}
      <div className="flex flex-col gap-3 border-t pt-3 sm:flex-row sm:items-center sm:justify-between">
        <div className="min-w-0 flex-1 space-y-2">
          <CourierDeliveryEarnings
            shippingCost={order?.shipping_cost}
            earningEstimate={order?.courier_earning_estimate}
            policy={commissionPolicy}
            policyLoading={commissionPolicyLoading}
            policyError={commissionPolicyError}
          />
          <p className="text-[11px] text-muted-foreground">Total pesanan: {formatPrice(order?.total || 0)}</p>
          {estimate && <p className="text-[11px] text-muted-foreground">{estimate.distanceFormatted} · ETA {estimate.etaFormatted}</p>}
        </div>
        {!expired && <div className="grid grid-cols-2 gap-2 sm:flex"><Button className="min-h-11 sm:min-h-9" size="sm" onClick={() => onRespond(offer.id, true)} disabled={busy}><CheckCircle className="h-4 w-4 mr-1" /> Terima</Button><Button className="min-h-11 sm:min-h-9" size="sm" variant="outline" onClick={() => onRespond(offer.id, false)} disabled={busy}><X className="h-4 w-4 mr-1" /> Tolak</Button></div>}
      </div>
      {!expired && order?.pickup_lat != null && order?.pickup_lng != null && <NavigationButton lat={order.pickup_lat} lng={order.pickup_lng} address={pickupAddress || undefined} variant="outline" size="sm" className="w-full"><span>Navigasi ke pickup</span></NavigationButton>}
    </Card>
  );
}

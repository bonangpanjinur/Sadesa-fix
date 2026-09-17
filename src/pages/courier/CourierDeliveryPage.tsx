import { useEffect, useState } from 'react';
import { Package, RefreshCw, Truck, Clock3 } from 'lucide-react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { CourierLayout } from '@/components/courier/CourierLayout';
import { DeliveryOfferCard, type DeliveryOfferCardData } from '@/components/courier/DeliveryOfferCard';
import { Card } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { toast } from '@/hooks/use-toast';
import { getRpcErrorMessage } from '@/lib/courierOrderStatus';
import { formatPrice } from '@/lib/utils';

interface CourierInfo { id: string; registration_status: string; }
interface DeliveryOffer { id: string; order_id: string; expires_at: string; orders?: DeliveryOfferCardData['order']; }
interface ActiveDelivery {
  id: string;
  status: string;
  delivery_name: string | null;
  delivery_address: string | null;
  pickup_address: string | null;
  courier_earning_estimate: number | null;
  merchants: { name: string } | null;
}

const OFFER_SELECT = 'id, order_id, expires_at, orders(total, shipping_cost, courier_earning_estimate, courier_platform_fee, pickup_address, pickup_lat, pickup_lng, delivery_name, delivery_address, delivery_lat, delivery_lng, notes, merchants(name, address))';

export default function CourierDeliveryPage() {
  const { user } = useAuth();
  const queryClient = useQueryClient();
  const [responding, setResponding] = useState<string | null>(null);

  const { data: courier, isLoading: courierLoading } = useQuery<CourierInfo | null>({
    queryKey: ['courier-delivery-profile', user?.id],
    queryFn: async () => {
      if (!user) return null;
      const { data, error } = await supabase.from('couriers').select('id, registration_status').eq('user_id', user.id).maybeSingle();
      if (error) throw error;
      return data as CourierInfo | null;
    },
    enabled: !!user,
  });

  const courierId = courier?.registration_status === 'APPROVED' ? courier.id : null;
  const { data: offers = [], isLoading: offersLoading, refetch } = useQuery<DeliveryOffer[]>({
    queryKey: ['courier-delivery-page-offers', courierId],
    queryFn: async () => {
      const { data, error } = await supabase.from('delivery_assignments')
        .select(OFFER_SELECT)
        .eq('courier_id', courierId!)
        .eq('status', 'OFFERED')
        .gt('expires_at', new Date().toISOString())
        .order('offered_at', { ascending: false });
      if (error) throw error;
      return (data || []) as unknown as DeliveryOffer[];
    },
    enabled: !!courierId,
    refetchInterval: 15_000,
  });

  const { data: activeDeliveries = [] } = useQuery<ActiveDelivery[]>({
    queryKey: ['courier-delivery-page-active', courierId],
    queryFn: async () => {
      const { data, error } = await supabase.from('orders')
        .select('id, status, delivery_name, delivery_address, pickup_address, courier_earning_estimate, merchants(name)')
        .eq('courier_id', courierId!)
        .in('status', ['COURIER_ACCEPTED', 'PICKED_UP', 'SENT', 'DELIVERING'])
        .order('created_at', { ascending: false });
      if (error) throw error;
      return (data || []) as unknown as ActiveDelivery[];
    },
    enabled: !!courierId,
    refetchInterval: 15_000,
  });

  useEffect(() => {
    if (!courierId) return;
    const channel = supabase.channel(`courier-delivery-page-${courierId}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'delivery_assignments', filter: `courier_id=eq.${courierId}` }, () => {
        queryClient.invalidateQueries({ queryKey: ['courier-delivery-page-offers', courierId] });
      })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'orders', filter: `courier_id=eq.${courierId}` }, () => {
        queryClient.invalidateQueries({ queryKey: ['courier-delivery-page-active', courierId] });
      })
      .subscribe();
    return () => { supabase.removeChannel(channel); };
  }, [courierId, queryClient]);

  const respond = async (assignmentId: string, accept: boolean) => {
    setResponding(assignmentId);
    try {
      const { error } = await supabase.rpc('respond_delivery_offer' as never, {
        p_assignment_id: assignmentId,
        p_accept: accept,
        p_reason: accept ? null : 'Kurir menolak tawaran',
      } as never);
      if (error) throw error;
      await Promise.all([refetch(), queryClient.invalidateQueries({ queryKey: ['courier-delivery-page-active', courierId] })]);
      toast({ title: accept ? 'Pengiriman diterima' : 'Tawaran ditolak', description: accept ? 'Pesanan masuk ke daftar aktif.' : undefined });
    } catch (error) {
      toast({ title: 'Tawaran tidak dapat diproses', description: getRpcErrorMessage(error), variant: 'destructive' });
    } finally {
      setResponding(null);
    }
  };

  if (courierLoading) return <div className="min-h-screen flex items-center justify-center"><RefreshCw className="h-6 w-6 animate-spin" /></div>;

  if (!courierId) return (
    <CourierLayout title="Pengiriman Barang" subtitle="Kelola tawaran pengantaran barang">
      <Card className="p-8 text-center"><Package className="mx-auto mb-3 h-10 w-10 text-muted-foreground" /><p className="font-semibold">Akun kurir belum disetujui</p><p className="mt-1 text-sm text-muted-foreground">Halaman pengiriman tersedia setelah pendaftaran kurir disetujui.</p></Card>
    </CourierLayout>
  );

  return (
    <CourierLayout title="Pengiriman Barang" subtitle="Terima atau tolak tawaran pengantaran barang">
      <div className="space-y-5">
        <div className="flex items-center justify-between gap-3">
          <div><h2 className="text-xl font-bold">Tawaran Pengiriman</h2><p className="text-sm text-muted-foreground">Pesanan baru akan muncul di sini dan tidak otomatis diterima.</p></div>
          <Button variant="outline" size="sm" onClick={() => { void refetch(); queryClient.invalidateQueries({ queryKey: ['courier-delivery-page-active', courierId] }); }}><RefreshCw className="mr-1.5 h-4 w-4" /> Muat ulang</Button>
        </div>

        {offersLoading ? <Card className="p-8 text-center"><RefreshCw className="mx-auto h-6 w-6 animate-spin" /></Card> : offers.length === 0 ? (
          <Card className="p-8 text-center"><Clock3 className="mx-auto mb-3 h-10 w-10 text-muted-foreground" /><p className="font-semibold">Belum ada tawaran pengiriman</p><p className="mt-1 text-sm text-muted-foreground">Tawaran dari pemesan akan muncul di halaman ini.</p></Card>
        ) : <div className="space-y-3">{offers.map((offer) => <DeliveryOfferCard key={offer.id} offer={{ id: offer.id, order_id: offer.order_id, expires_at: offer.expires_at, order: offer.orders || null }} busy={responding === offer.id} onRespond={respond} />)}</div>}

        <div className="flex items-center gap-2 pt-3"><Truck className="h-5 w-5 text-primary" /><h2 className="text-xl font-bold">Pengiriman Aktif</h2><Badge>{activeDeliveries.length}</Badge></div>
        {activeDeliveries.length === 0 ? <Card className="p-6 text-center text-sm text-muted-foreground">Belum ada pengiriman yang diterima.</Card> : <div className="grid gap-3">{activeDeliveries.map((delivery) => <Card key={delivery.id} className="p-4"><div className="flex items-start justify-between gap-3"><div><p className="font-semibold">#{delivery.id.slice(0, 8).toUpperCase()} · {delivery.merchants?.name || 'Toko'}</p><p className="text-sm text-muted-foreground">{delivery.pickup_address || 'Lokasi toko'} → {delivery.delivery_address || 'Alamat pelanggan'}</p><p className="mt-2 text-xs text-muted-foreground">Status: {delivery.status} · Pendapatan: {formatPrice(delivery.courier_earning_estimate || 0)}</p></div><Badge>{delivery.status === 'COURIER_ACCEPTED' ? 'Menuju toko' : delivery.status}</Badge></div></Card>)}</div>}
      </div>
    </CourierLayout>
  );
}

import { useEffect, useState } from 'react';
import { Package, RefreshCw, Truck, Clock3, MapPinned, Play, CheckCircle, MessageCircle } from 'lucide-react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { CourierLayout } from '@/components/courier/CourierLayout';
import { DeliveryOfferCard, type DeliveryOfferCardData } from '@/components/courier/DeliveryOfferCard';
import { DeliveryProofDialog } from '@/components/courier/DeliveryProofDialog';
import { OrderChat } from '@/components/chat/OrderChat';
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
  id: string; status: string; buyer_id: string; delivery_name: string | null; delivery_address: string | null;
  delivery_lat: number | null; delivery_lng: number | null; pickup_address: string | null;
  pickup_lat: number | null; pickup_lng: number | null; courier_earning_estimate: number | null;
}

const statusLabel: Record<string, string> = { COURIER_ACCEPTED: 'Menuju pickup pengirim', PICKED_UP: 'Barang sudah diambil', DELIVERING: 'Sedang mengantar' };

export default function CourierDeliveryPage() {
  const { user } = useAuth(); const queryClient = useQueryClient();
  const [responding, setResponding] = useState<string | null>(null); const [transitioning, setTransitioning] = useState<string | null>(null);
  const [proofOrder, setProofOrder] = useState<ActiveDelivery | null>(null);
  const [chatOrder, setChatOrder] = useState<ActiveDelivery | null>(null);
  const { data: courier, isLoading: courierLoading } = useQuery<CourierInfo | null>({
    queryKey: ['courier-delivery-profile', user?.id], queryFn: async () => {
      if (!user) return null; const { data, error } = await supabase.from('couriers').select('id, registration_status').eq('user_id', user.id).maybeSingle();
      if (error) throw error; return data as CourierInfo | null;
    }, enabled: !!user,
  });
  const courierId = courier?.registration_status === 'APPROVED' ? courier.id : null;
  const { data: offers = [], isLoading: offersLoading, isError: offersError, error: offersQueryError, refetch } = useQuery<DeliveryOffer[]>({
    queryKey: ['courier-delivery-page-offers', courierId], queryFn: async () => { const { data, error } = await supabase.rpc('get_courier_delivery_offers' as never); if (error) throw error; return (data || []) as unknown as DeliveryOffer[]; }, enabled: !!courierId, refetchInterval: 15_000,
  });
  const { data: activeDeliveries = [] } = useQuery<ActiveDelivery[]>({
    queryKey: ['courier-delivery-page-active', courierId], queryFn: async () => {
      const { data, error } = await supabase.from('orders').select('id,status,buyer_id,delivery_name,delivery_address,delivery_lat,delivery_lng,pickup_address,pickup_lat,pickup_lng,courier_earning_estimate').eq('courier_id', courierId!).eq('service_type', 'COURIER_DELIVERY').in('status', ['COURIER_ACCEPTED', 'PICKED_UP', 'DELIVERING']).order('created_at', { ascending: false });
      if (error) throw error; return (data || []) as unknown as ActiveDelivery[];
    }, enabled: !!courierId, refetchInterval: 15_000,
  });
  useEffect(() => { if (!courierId) return; const channel = supabase.channel(`courier-delivery-page-${courierId}`).on('postgres_changes', { event: '*', schema: 'public', table: 'delivery_assignments', filter: `courier_id=eq.${courierId}` }, () => { queryClient.invalidateQueries({ queryKey: ['courier-delivery-page-offers', courierId] }); queryClient.invalidateQueries({ queryKey: ['courier-delivery-page-active', courierId] }); }).on('postgres_changes', { event: '*', schema: 'public', table: 'orders', filter: `courier_id=eq.${courierId}` }, () => { queryClient.invalidateQueries({ queryKey: ['courier-delivery-page-active', courierId] }); }).subscribe(); return () => { supabase.removeChannel(channel); }; }, [courierId, queryClient]);
  const refresh = () => { void refetch(); void queryClient.invalidateQueries({ queryKey: ['courier-delivery-page-active', courierId] }); };
  const respond = async (assignmentId: string, accept: boolean) => { setResponding(assignmentId); try { const { error } = await supabase.rpc('respond_delivery_offer' as never, { p_assignment_id: assignmentId, p_accept: accept, p_reason: accept ? null : 'Kurir menolak tawaran' } as never); if (error) throw error; refresh(); toast({ title: accept ? 'Pengiriman diterima' : 'Tawaran ditolak', description: accept ? 'Pesanan masuk ke daftar aktif.' : undefined }); } catch (error) { toast({ title: 'Tawaran tidak dapat diproses', description: getRpcErrorMessage(error), variant: 'destructive' }); } finally { setResponding(null); } };
  const transition = async (order: ActiveDelivery, rpc: string) => { setTransitioning(order.id); try { const { error } = await supabase.rpc(rpc as never, { p_order_id: order.id } as never); if (error) throw error; refresh(); toast({ title: rpc === 'courier_pickup_order' ? 'Barang ditandai sudah diambil' : 'Pengantaran dimulai' }); } catch (error) { toast({ title: 'Status belum dapat diperbarui', description: getRpcErrorMessage(error), variant: 'destructive' }); } finally { setTransitioning(null); } };
  const navigate = (lat: number | null, lng: number | null) => { if (lat == null || lng == null) return toast({ title: 'Lokasi belum tersedia', variant: 'destructive' }); window.open(`https://www.google.com/maps/dir/?api=1&destination=${lat},${lng}`, '_blank', 'noopener,noreferrer'); };
  if (courierLoading) return <div className="min-h-screen flex items-center justify-center"><RefreshCw className="h-6 w-6 animate-spin" /></div>;
  if (!courierId) return <CourierLayout title="Pengiriman Barang" subtitle="Kelola kirim barang langsung"><Card className="p-8 text-center"><Package className="mx-auto mb-3 h-10 w-10 text-muted-foreground" /><p className="font-semibold">Akun kurir belum disetujui</p><p className="mt-1 text-sm text-muted-foreground">Halaman tersedia setelah pendaftaran kurir disetujui.</p></Card></CourierLayout>;
  return <CourierLayout title="Kirim Barang Langsung" subtitle="Terima tawaran dan selesaikan pengantaran dari pickup ke penerima"><div className="space-y-5">
    <div className="flex items-center justify-between gap-3"><div><h2 className="text-xl font-bold">Tawaran Pengiriman</h2><p className="text-sm text-muted-foreground">Tawaran tidak otomatis diterima dan memiliki batas waktu.</p></div><Button variant="outline" size="sm" onClick={refresh}><RefreshCw className="mr-1.5 h-4 w-4" /> Muat ulang</Button></div>
    {offersLoading ? <Card className="p-8 text-center"><RefreshCw className="mx-auto h-6 w-6 animate-spin" /></Card> : offersError ? <Card className="p-8 text-center"><p className="font-semibold">Tawaran belum dapat dimuat</p><p className="mt-1 text-sm text-muted-foreground">{getRpcErrorMessage(offersQueryError, 'Periksa koneksi lalu muat ulang.')}</p></Card> : offers.length === 0 ? <Card className="p-8 text-center"><Clock3 className="mx-auto mb-3 h-10 w-10 text-muted-foreground" /><p className="font-semibold">Belum ada tawaran pengiriman</p><p className="mt-1 text-sm text-muted-foreground">Tawaran kirim barang langsung akan muncul di sini.</p></Card> : <div className="space-y-3">{offers.map(offer => <DeliveryOfferCard key={offer.id} offer={{ id: offer.id, order_id: offer.order_id, expires_at: offer.expires_at, order: offer.orders || null }} busy={responding === offer.id} onRespond={respond} />)}</div>}
    <div className="flex items-center gap-2 pt-3"><Truck className="h-5 w-5 text-primary" /><h2 className="text-xl font-bold">Pengiriman Aktif</h2><Badge>{activeDeliveries.length}</Badge></div>
    {activeDeliveries.length === 0 ? <Card className="p-6 text-center text-sm text-muted-foreground">Belum ada pengiriman yang diterima.</Card> : <div className="grid gap-3">{activeDeliveries.map(delivery => <Card key={delivery.id} className="p-4"><div className="flex items-start justify-between gap-3"><div className="min-w-0"><p className="font-semibold">Kirim barang langsung · #{delivery.id.slice(0, 8).toUpperCase()}</p><p className="text-sm text-muted-foreground">Pickup pengirim: {delivery.pickup_address || 'Alamat pickup belum tersedia'}</p><p className="text-sm text-muted-foreground">Penerima: {delivery.delivery_name || 'Penerima'} · {delivery.delivery_address || 'Alamat tujuan belum tersedia'}</p><p className="mt-2 text-xs text-muted-foreground">{statusLabel[delivery.status] || delivery.status} · Pendapatan: {formatPrice(delivery.courier_earning_estimate || 0)}</p></div><Badge>{statusLabel[delivery.status] || delivery.status}</Badge></div><div className="mt-4 flex flex-wrap gap-2"><Button size="sm" variant="outline" onClick={() => setChatOrder(delivery)}><MessageCircle className="mr-1.5 h-4 w-4" />Chat pembeli</Button>{delivery.status === 'COURIER_ACCEPTED' && <><Button size="sm" variant="outline" onClick={() => navigate(delivery.pickup_lat, delivery.pickup_lng)}><MapPinned className="mr-1.5 h-4 w-4" />Navigasi pickup</Button><Button size="sm" onClick={() => transition(delivery, 'courier_pickup_order')} disabled={transitioning === delivery.id}><Package className="mr-1.5 h-4 w-4" />Ambil barang</Button></>}{delivery.status === 'PICKED_UP' && <><Button size="sm" variant="outline" onClick={() => navigate(delivery.delivery_lat, delivery.delivery_lng)}><MapPinned className="mr-1.5 h-4 w-4" />Navigasi penerima</Button><Button size="sm" onClick={() => transition(delivery, 'courier_start_delivery')} disabled={transitioning === delivery.id}><Play className="mr-1.5 h-4 w-4" />Mulai antar</Button></>}{delivery.status === 'DELIVERING' && <Button size="sm" onClick={() => setProofOrder(delivery)}><CheckCircle className="mr-1.5 h-4 w-4" />Selesaikan + bukti</Button>}</div></Card>)}</div>}
  </div>{proofOrder && <DeliveryProofDialog open={!!proofOrder} onClose={() => setProofOrder(null)} orderId={proofOrder.id} orderNumber={proofOrder.id.slice(0, 8).toUpperCase()} onConfirmed={() => { setProofOrder(null); refresh(); }} />}{chatOrder && <OrderChat orderId={chatOrder.id} otherUserId={chatOrder.buyer_id} otherUserName={chatOrder.delivery_name || 'Pembeli'} chatType="buyer_courier" isOpen={!!chatOrder} onClose={() => setChatOrder(null)} />}</CourierLayout>;
}

import { useCallback, useEffect, useState } from 'react';
import { PackageCheck, Truck, RefreshCw } from 'lucide-react';
import { MerchantLayout } from '@/components/merchant/MerchantLayout';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { supabase } from '@/integrations/supabase/client';
import { useMerchantGuard } from '@/hooks/useMerchantGuard';
import { toast } from 'sonner';

interface Order { id: string; created_at: string; status: string; }
interface OrderItem { id: string; order_id: string; product_id: string | null; product_name: string; quantity: number; }
interface Shipment { id: string; order_id: string; shipment_number: string; status: string; tracking_number: string | null; created_at: string; }

const SHIPMENT_STATUSES = ['pending', 'processing', 'packed', 'shipped', 'delivered', 'cancelled'];

export default function MerchantFulfillmentPage() {
  const { merchantId, loading: guardLoading } = useMerchantGuard();
  const [orders, setOrders] = useState<Order[]>([]);
  const [items, setItems] = useState<OrderItem[]>([]);
  const [shipments, setShipments] = useState<Shipment[]>([]);
  const [selectedOrder, setSelectedOrder] = useState('');
  const [quantities, setQuantities] = useState<Record<string, string>>({});
  const [tracking, setTracking] = useState('');
  const [loading, setLoading] = useState(false);

  const loadData = useCallback(async () => {
    if (!merchantId) return;
    setLoading(true);
    const { data: orderData } = await supabase.from('orders').select('id, created_at, status').eq('merchant_id', merchantId).not('status', 'in', '(CANCELED,COMPLETED,DONE)').order('created_at', { ascending: false }).limit(50);
    const nextOrders = (orderData ?? []) as Order[];
    setOrders(nextOrders);
    const orderIds = nextOrders.map((order) => order.id);
    if (orderIds.length) {
      const [{ data: itemData }, { data: shipmentData }] = await Promise.all([
        supabase.from('order_items').select('id, order_id, product_id, product_name, quantity').in('order_id', orderIds),
        supabase.from('marketplace_shipments').select('id, order_id, shipment_number, status, tracking_number, created_at').in('order_id', orderIds).order('created_at', { ascending: false }),
      ]);
      setItems((itemData ?? []) as OrderItem[]);
      setShipments((shipmentData ?? []) as Shipment[]);
    } else { setItems([]); setShipments([]); }
    setLoading(false);
  }, [merchantId]);

  useEffect(() => { void loadData(); }, [loadData]);

  const createShipment = async () => {
    if (!selectedOrder) return;
    const orderItems = items.filter((item) => item.order_id === selectedOrder);
    const shipmentItems = orderItems.map((item) => ({ order_item_id: item.id, quantity: Math.trunc(Number(quantities[item.id] ?? 0)) })).filter((item) => item.quantity > 0);
    if (!shipmentItems.length) { toast.error('Masukkan minimal satu quantity item'); return; }
    setLoading(true);
    try {
      const { error } = await supabase.rpc('create_marketplace_shipment' as never, { p_order_id: selectedOrder, p_items: shipmentItems, p_tracking_number: tracking || null } as never);
      if (error) throw error;
      toast.success('Shipment parsial berhasil dibuat'); setQuantities({}); setTracking(''); await loadData();
    } catch (error) { toast.error(error instanceof Error ? error.message : 'Gagal membuat shipment'); } finally { setLoading(false); }
  };

  const updateStatus = async (shipment: Shipment, status: string) => {
    try {
      const { error } = await supabase.rpc('update_marketplace_shipment_status' as never, { p_shipment_id: shipment.id, p_status: status, p_tracking_number: shipment.tracking_number } as never);
      if (error) throw error;
      toast.success('Status shipment diperbarui'); await loadData();
    } catch (error) { toast.error(error instanceof Error ? error.message : 'Gagal memperbarui shipment'); }
  };

  if (guardLoading) return <MerchantLayout title="Fulfillment"><div className="p-6">Memuat...</div></MerchantLayout>;
  return <MerchantLayout title="Fulfillment Parsial" subtitle="Kelola shipment parsial dan tracking order"><div className="space-y-6"><Card><CardHeader><CardTitle className="flex items-center gap-2"><PackageCheck className="h-5 w-5" />Buat Shipment Parsial</CardTitle></CardHeader><CardContent className="space-y-4"><div><Label>Order</Label><Select value={selectedOrder} onValueChange={(value) => { setSelectedOrder(value); setQuantities({}); }}><SelectTrigger className="mt-1"><SelectValue placeholder="Pilih order" /></SelectTrigger><SelectContent>{orders.map((order) => <SelectItem key={order.id} value={order.id}>#{order.id.slice(0, 8).toUpperCase()} · {order.status}</SelectItem>)}</SelectContent></Select></div>{selectedOrder && <div className="space-y-2">{items.filter((item) => item.order_id === selectedOrder).map((item) => <div key={item.id} className="grid grid-cols-[1fr_100px] items-center gap-3 border rounded-lg p-3"><div><p className="text-sm font-medium">{item.product_name}</p><p className="text-xs text-muted-foreground">Maksimal {item.quantity}</p></div><Input type="number" min="0" max={item.quantity} step="1" placeholder="Qty" value={quantities[item.id] ?? ''} onChange={(event) => setQuantities((current) => ({ ...current, [item.id]: event.target.value }))} /></div>)}</div>}<div><Label>Nomor tracking (opsional)</Label><Input className="mt-1" value={tracking} onChange={(event) => setTracking(event.target.value)} maxLength={100} /></div><Button onClick={() => void createShipment()} disabled={loading || !selectedOrder}><PackageCheck className="h-4 w-4 mr-2" />Buat Shipment</Button></CardContent></Card><Card><CardHeader><CardTitle className="flex items-center gap-2"><Truck className="h-5 w-5" />Shipment Berjalan</CardTitle></CardHeader><CardContent className="space-y-3">{shipments.length === 0 ? <p className="text-sm text-muted-foreground">Belum ada shipment.</p> : shipments.map((shipment) => <div key={shipment.id} className="flex flex-wrap items-center gap-3 border rounded-lg p-3"><div className="flex-1"><p className="font-mono text-sm">{shipment.shipment_number}</p><p className="text-xs text-muted-foreground">Order #{shipment.order_id.slice(0, 8).toUpperCase()} {shipment.tracking_number ? `· ${shipment.tracking_number}` : ''}</p></div><Badge variant="outline">{shipment.status}</Badge><Select value={shipment.status} onValueChange={(value) => void updateStatus(shipment, value)}><SelectTrigger className="w-36"><SelectValue /></SelectTrigger><SelectContent>{SHIPMENT_STATUSES.map((status) => <SelectItem key={status} value={status}>{status}</SelectItem>)}</SelectContent></Select><RefreshCw className="h-4 w-4 text-muted-foreground" /></div>)}</CardContent></Card></div></MerchantLayout>;
}

import { useCallback, useEffect, useState } from 'react';
import { Clock3, LockKeyhole, Plus, RefreshCw, UnlockKeyhole } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { supabase } from '@/integrations/supabase/client';
import { usePOS } from '@/contexts/POSContext';
import { toast } from 'sonner';

type StockOption = { id: string; product_id: string; quantity: number; reserved_quantity: number; product?: { name?: string | null; sku?: string | null } | null };
type Reservation = { id: string; order_id: string | null; status: string; expires_at: string | null; created_at: string; pos_stock_reservation_items?: Array<{ quantity: number; pos_stock?: { pos_products?: { name?: string | null } | null } | null }> };

export function StockReservationPanel() {
  const { tenant, activeOutlet } = usePOS();
  const [stocks, setStocks] = useState<StockOption[]>([]);
  const [reservations, setReservations] = useState<Reservation[]>([]);
  const [loading, setLoading] = useState(false);
  const [form, setForm] = useState({ stockId: '', quantity: '', orderId: '', minutes: '30' });

  const load = useCallback(async () => {
    if (!tenant || !activeOutlet) return;
    setLoading(true);
    const [stockResult, reservationResult] = await Promise.all([
      supabase.from('pos_stock').select('id, product_id, quantity, reserved_quantity, pos_products(name, sku)').eq('tenant_id', tenant.id).eq('outlet_id', activeOutlet.id).order('updated_at', { ascending: false }),
      supabase.from('pos_stock_reservations').select('id, order_id, status, expires_at, created_at, pos_stock_reservation_items(quantity, pos_stock(pos_products(name)))').eq('tenant_id', tenant.id).eq('outlet_id', activeOutlet.id).order('created_at', { ascending: false }).limit(50),
    ]);
    if (stockResult.error || reservationResult.error) toast.error('Gagal memuat reservation stok');
    setStocks((stockResult.data ?? []) as unknown as StockOption[]);
    setReservations((reservationResult.data ?? []) as unknown as Reservation[]);
    setLoading(false);
  }, [tenant, activeOutlet]);

  useEffect(() => { void load(); }, [load]);

  const reserve = async () => {
    if (!tenant || !activeOutlet || !form.stockId) { toast.error('Pilih stok terlebih dahulu'); return; }
    const quantity = Number(form.quantity);
    const selected = stocks.find((stock) => stock.id === form.stockId);
    if (!selected || !Number.isFinite(quantity) || quantity <= 0 || quantity > selected.quantity - selected.reserved_quantity) { toast.error('Jumlah melebihi stok tersedia'); return; }
    if (form.orderId && !/^[0-9a-f-]{36}$/i.test(form.orderId)) { toast.error('Order ID harus berupa UUID'); return; }
    setLoading(true);
    const { error } = await supabase.rpc('reserve_pos_stock', { p_tenant_id: tenant.id, p_outlet_id: activeOutlet.id, p_order_id: form.orderId || null, p_items: [{ stock_id: form.stockId, quantity }], p_expires_at: new Date(Date.now() + Math.max(5, Number(form.minutes) || 30) * 60_000).toISOString() });
    if (error) toast.error(error.message); else { toast.success('Stok berhasil di-reserve'); setForm({ stockId: '', quantity: '', orderId: '', minutes: '30' }); await load(); }
    setLoading(false);
  };

  const release = async (id: string) => {
    setLoading(true);
    const { error } = await supabase.rpc('release_pos_stock_reservation', { p_reservation_id: id });
    if (error) toast.error(error.message); else { toast.success('Reservation dilepas'); await load(); }
    setLoading(false);
  };

  return <Card className="mt-5"><CardHeader className="flex flex-row items-center justify-between"><CardTitle className="flex items-center gap-2"><LockKeyhole className="h-5 w-5" />Stock Reservation</CardTitle><Button size="sm" variant="outline" onClick={() => void load()} disabled={loading}><RefreshCw className="h-4 w-4" /></Button></CardHeader><CardContent className="space-y-5"><div className="grid gap-3 md:grid-cols-4"><div className="md:col-span-2"><Label>Stok produk</Label><Select value={form.stockId} onValueChange={(value) => setForm((prev) => ({ ...prev, stockId: value }))}><SelectTrigger className="mt-1"><SelectValue placeholder="Pilih stok yang tersedia" /></SelectTrigger><SelectContent>{stocks.filter((stock) => stock.quantity - stock.reserved_quantity > 0).map((stock) => <SelectItem key={stock.id} value={stock.id}>{stock.product?.name ?? stock.product_id} · tersedia {stock.quantity - stock.reserved_quantity}</SelectItem>)}</SelectContent></Select></div><div><Label>Jumlah</Label><Input className="mt-1" type="number" min="0.001" step="0.001" value={form.quantity} onChange={(event) => setForm((prev) => ({ ...prev, quantity: event.target.value }))} /></div><div><Label>Durasi (menit)</Label><Input className="mt-1" type="number" min="5" value={form.minutes} onChange={(event) => setForm((prev) => ({ ...prev, minutes: event.target.value }))} /></div><div className="md:col-span-3"><Label>Order marketplace (opsional UUID)</Label><Input className="mt-1" value={form.orderId} onChange={(event) => setForm((prev) => ({ ...prev, orderId: event.target.value }))} placeholder="Hubungkan ke order marketplace" /></div><div className="flex items-end"><Button className="w-full" onClick={() => void reserve()} disabled={loading}><Plus className="mr-2 h-4 w-4" />Reserve Atomic</Button></div></div><div className="space-y-2">{reservations.length === 0 ? <p className="text-sm text-muted-foreground">Belum ada reservation pada outlet ini.</p> : reservations.map((reservation) => <div key={reservation.id} className="flex flex-wrap items-center gap-3 rounded-lg border p-3"><div className="flex-1"><p className="font-medium">{reservation.pos_stock_reservation_items?.map((item) => item.pos_stock?.pos_products?.name ?? 'Produk').join(', ') || 'Reservation stok'}</p><p className="text-xs text-muted-foreground">{reservation.order_id ? `Order ${reservation.order_id}` : 'Tanpa order'} · {new Date(reservation.created_at).toLocaleString('id-ID')}</p></div><Badge variant={reservation.status === 'active' ? 'default' : 'secondary'}>{reservation.status}</Badge>{reservation.expires_at && <span className="flex items-center gap-1 text-xs text-muted-foreground"><Clock3 className="h-3 w-3" />{new Date(reservation.expires_at).toLocaleString('id-ID')}</span>}{reservation.status === 'active' && <Button size="sm" variant="outline" onClick={() => void release(reservation.id)} disabled={loading}><UnlockKeyhole className="mr-1 h-3 w-3" />Release</Button>}</div>)}</div></CardContent></Card>;
}

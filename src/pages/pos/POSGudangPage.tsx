import { useCallback, useEffect, useMemo, useState } from 'react';
import { ArrowRightLeft, Boxes, Building2, Plus, RefreshCw, Search, Warehouse } from 'lucide-react';
import { POSLayout } from '@/components/pos/POSLayout';
import { usePOS } from '@/contexts/POSContext';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Badge } from '@/components/ui/badge';
import { Textarea } from '@/components/ui/textarea';
import { toast } from 'sonner';
import { StockReservationPanel } from '@/components/pos/StockReservationPanel';

interface WarehouseRow { id: string; name: string; code: string; warehouse_type: 'warehouse' | 'outlet' | 'vehicle' | 'transit'; outlet_id: string | null; is_active: boolean; }
interface StockRow { id: string; product_id: string; variant_id: string | null; warehouse_id: string | null; quantity: number; reserved_quantity: number; pos_products: { name: string; sku: string | null; unit: string } | null; }
interface GenericQuery<T> extends PromiseLike<{ data: T[] | null; error: { message: string } | null }> { select(columns: string): GenericQuery<T>; eq(column: string, value: string): GenericQuery<T>; order(column: string, options?: { ascending?: boolean }): GenericQuery<T>; }
interface GenericClient { from<T extends Record<string, unknown>>(table: string): GenericQuery<T>; rpc(name: string, params: Record<string, unknown>): Promise<{ data: unknown; error: { message: string } | null }>; }
const db = supabase as unknown as GenericClient;
const typeLabel: Record<WarehouseRow['warehouse_type'], string> = { warehouse: 'Gudang pusat', outlet: 'Outlet', vehicle: 'Kendaraan', transit: 'Transit' };
const n = (value: unknown) => typeof value === 'number' ? value : Number(value ?? 0);

export default function POSGudangPage() {
  const { tenant, outlets, activeOutlet, formatCurrency } = usePOS();
  const [warehouses, setWarehouses] = useState<WarehouseRow[]>([]);
  const [stocks, setStocks] = useState<StockRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [warehouseDialog, setWarehouseDialog] = useState(false);
  const [transferDialog, setTransferDialog] = useState(false);
  const [form, setForm] = useState({ name: '', code: '', type: 'warehouse' as WarehouseRow['warehouse_type'], outletId: '' });
  const [transfer, setTransfer] = useState({ fromWarehouseId: '', toWarehouseId: '', stockId: '', quantity: '', notes: '' });
  const [actionLoading, setActionLoading] = useState(false);

  const load = useCallback(async () => {
    if (!tenant) return;
    setLoading(true);
    try {
      const [warehouseResult, stockResult] = await Promise.all([
        db.from<Record<string, unknown>>('pos_warehouses').select('*').eq('tenant_id', tenant.id).order('name'),
        db.from<Record<string, unknown>>('pos_stock').select('*, pos_products(name, sku, unit)').eq('tenant_id', tenant.id).order('created_at', { ascending: false }),
      ]);
      if (warehouseResult.error) throw new Error(warehouseResult.error.message);
      if (stockResult.error) throw new Error(stockResult.error.message);
      setWarehouses((warehouseResult.data ?? []).map((row) => ({ id: String(row.id), name: String(row.name), code: String(row.code), warehouse_type: String(row.warehouse_type ?? 'warehouse') as WarehouseRow['warehouse_type'], outlet_id: typeof row.outlet_id === 'string' ? row.outlet_id : null, is_active: row.is_active !== false })));
      setStocks((stockResult.data ?? []).map((row) => ({ id: String(row.id), product_id: String(row.product_id), variant_id: typeof row.variant_id === 'string' ? row.variant_id : null, warehouse_id: typeof row.warehouse_id === 'string' ? row.warehouse_id : null, quantity: n(row.quantity), reserved_quantity: n(row.reserved_quantity), pos_products: row.pos_products as StockRow['pos_products'] })));
    } catch (error) { console.error('Failed to load warehouses:', error); toast.error('Gagal memuat data gudang'); } finally { setLoading(false); }
  }, [tenant]);
  useEffect(() => { void load(); }, [load]);

  const visibleWarehouses = useMemo(() => warehouses.filter((warehouse) => `${warehouse.name} ${warehouse.code} ${typeLabel[warehouse.warehouse_type]}`.toLowerCase().includes(search.toLowerCase())), [warehouses, search]);
  const sourceStocks = useMemo(() => stocks.filter((stock) => stock.warehouse_id === transfer.fromWarehouseId && stock.quantity - stock.reserved_quantity > 0), [stocks, transfer.fromWarehouseId]);
  const selectedStock = stocks.find((stock) => stock.id === transfer.stockId);

  const createWarehouse = async () => {
    if (!tenant || !form.name.trim() || !form.code.trim() || !form.outletId) { toast.error('Nama, kode, dan outlet wajib diisi'); return; }
    setActionLoading(true);
    try {
      const { error } = await supabase.from('pos_warehouses' as never).insert({ tenant_id: tenant.id, name: form.name.trim(), code: form.code.trim().toUpperCase(), warehouse_type: form.type, outlet_id: form.outletId, is_active: true });
      if (error) throw error;
      toast.success('Gudang berhasil ditambahkan'); setWarehouseDialog(false); setForm({ name: '', code: '', type: 'warehouse', outletId: activeOutlet?.id ?? '' }); await load();
    } catch (error) { toast.error(error instanceof Error ? error.message : 'Gagal menambahkan gudang'); } finally { setActionLoading(false); }
  };

  const executeTransfer = async () => {
    if (!tenant || !selectedStock || !transfer.fromWarehouseId || !transfer.toWarehouseId) return;
    const quantity = Number(transfer.quantity);
    const available = selectedStock.quantity - selectedStock.reserved_quantity;
    if (transfer.fromWarehouseId === transfer.toWarehouseId || !Number.isFinite(quantity) || quantity <= 0 || quantity > available) { toast.error('Gudang sumber/tujuan atau jumlah transfer tidak valid'); return; }
    setActionLoading(true);
    try {
      const { error } = await db.rpc('transfer_stock_between_warehouses', { p_tenant_id: tenant.id, p_from_warehouse_id: transfer.fromWarehouseId, p_to_warehouse_id: transfer.toWarehouseId, p_items: [{ product_id: selectedStock.product_id, variant_id: selectedStock.variant_id, quantity }], p_notes: transfer.notes || null });
      if (error) throw new Error(error.message);
      toast.success('Transfer stok antar gudang berhasil'); setTransferDialog(false); setTransfer({ fromWarehouseId: '', toWarehouseId: '', stockId: '', quantity: '', notes: '' }); await load();
    } catch (error) { toast.error(error instanceof Error ? error.message : 'Gagal mentransfer stok'); } finally { setActionLoading(false); }
  };

  return <POSLayout title="Multi-Gudang" subtitle="Kelola lokasi stok dan transfer antar gudang secara atomic" actions={<div className="flex gap-2"><Button variant="outline" size="sm" onClick={() => setTransferDialog(true)}><ArrowRightLeft className="h-4 w-4 mr-1" />Transfer Stok</Button><Button size="sm" onClick={() => { setForm({ name: '', code: '', type: 'warehouse', outletId: activeOutlet?.id ?? '' }); setWarehouseDialog(true); }}><Plus className="h-4 w-4 mr-1" />Tambah Gudang</Button></div>}>
    <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-5"><Card><CardContent className="p-4"><Warehouse className="h-4 w-4 text-primary mb-2" /><p className="text-xs text-muted-foreground">Lokasi aktif</p><p className="text-xl font-bold">{warehouses.filter((item) => item.is_active).length}</p></CardContent></Card><Card><CardContent className="p-4"><Boxes className="h-4 w-4 text-emerald-600 mb-2" /><p className="text-xs text-muted-foreground">Stok terlacak</p><p className="text-xl font-bold">{stocks.length}</p></CardContent></Card><Card><CardContent className="p-4"><Building2 className="h-4 w-4 text-muted-foreground mb-2" /><p className="text-xs text-muted-foreground">Outlet</p><p className="text-xl font-bold">{outlets.length}</p></CardContent></Card><Card><CardContent className="p-4"><ArrowRightLeft className="h-4 w-4 text-warning mb-2" /><p className="text-xs text-muted-foreground">Stok reserved</p><p className="text-xl font-bold">{stocks.reduce((sum, stock) => sum + stock.reserved_quantity, 0)}</p></CardContent></Card></div>
    <Card><CardHeader className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3"><CardTitle>Lokasi Gudang</CardTitle><div className="flex gap-2"><div className="relative"><Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" /><Input className="pl-9 w-64" placeholder="Cari gudang atau kode" value={search} onChange={(event) => setSearch(event.target.value)} /></div><Button variant="outline" size="icon" onClick={() => void load()} aria-label="Refresh"><RefreshCw className="h-4 w-4" /></Button></div></CardHeader><CardContent>{loading ? <div className="flex justify-center py-12"><RefreshCw className="h-7 w-7 animate-spin text-primary" /></div> : visibleWarehouses.length === 0 ? <p className="text-center py-12 text-muted-foreground">Belum ada gudang. Tambahkan lokasi pertama untuk mengaktifkan transfer.</p> : <div className="grid grid-cols-1 md:grid-cols-2 gap-3">{visibleWarehouses.map((warehouse) => <div key={warehouse.id} className="border rounded-lg p-4"><div className="flex items-start justify-between gap-3"><div><p className="font-semibold">{warehouse.name}</p><p className="text-xs text-muted-foreground">Kode {warehouse.code}</p></div><Badge variant={warehouse.is_active ? 'success' : 'secondary'}>{typeLabel[warehouse.warehouse_type]}</Badge></div><p className="text-xs text-muted-foreground mt-3">{warehouse.outlet_id ? `Outlet: ${outlets.find((outlet) => outlet.id === warehouse.outlet_id)?.name ?? warehouse.outlet_id}` : 'Belum terhubung outlet'}</p></div>)}</div>}</CardContent></Card>
    <Dialog open={warehouseDialog} onOpenChange={setWarehouseDialog}><DialogContent><DialogHeader><DialogTitle>Tambah Lokasi Gudang</DialogTitle></DialogHeader><div className="space-y-3"><div><Label>Nama lokasi</Label><Input className="mt-1" value={form.name} onChange={(event) => setForm((prev) => ({ ...prev, name: event.target.value }))} placeholder="Gudang Pusat" /></div><div className="grid grid-cols-2 gap-3"><div><Label>Kode</Label><Input className="mt-1" value={form.code} onChange={(event) => setForm((prev) => ({ ...prev, code: event.target.value }))} placeholder="GDG-01" /></div><div><Label>Tipe</Label><Select value={form.type} onValueChange={(value) => setForm((prev) => ({ ...prev, type: value as WarehouseRow['warehouse_type'] }))}><SelectTrigger className="mt-1"><SelectValue /></SelectTrigger><SelectContent><SelectItem value="warehouse">Gudang pusat</SelectItem><SelectItem value="outlet">Outlet</SelectItem><SelectItem value="vehicle">Kendaraan</SelectItem><SelectItem value="transit">Transit</SelectItem></SelectContent></Select></div></div><div><Label>Outlet terkait</Label><Select value={form.outletId} onValueChange={(value) => setForm((prev) => ({ ...prev, outletId: value }))}><SelectTrigger className="mt-1"><SelectValue placeholder="Pilih outlet" /></SelectTrigger><SelectContent>{outlets.map((outlet) => <SelectItem key={outlet.id} value={outlet.id}>{outlet.name}</SelectItem>)}</SelectContent></Select></div></div><DialogFooter><Button variant="outline" onClick={() => setWarehouseDialog(false)}>Batal</Button><Button onClick={() => void createWarehouse()} disabled={actionLoading}>{actionLoading ? 'Menyimpan...' : 'Simpan'}</Button></DialogFooter></DialogContent></Dialog>
    <Dialog open={transferDialog} onOpenChange={setTransferDialog}><DialogContent><DialogHeader><DialogTitle>Transfer Stok Antar Gudang</DialogTitle></DialogHeader><div className="space-y-3"><div className="grid grid-cols-2 gap-3"><div><Label>Gudang sumber</Label><Select value={transfer.fromWarehouseId} onValueChange={(value) => setTransfer((prev) => ({ ...prev, fromWarehouseId: value, stockId: '' }))}><SelectTrigger className="mt-1"><SelectValue placeholder="Sumber" /></SelectTrigger><SelectContent>{warehouses.filter((warehouse) => warehouse.is_active).map((warehouse) => <SelectItem key={warehouse.id} value={warehouse.id}>{warehouse.name}</SelectItem>)}</SelectContent></Select></div><div><Label>Gudang tujuan</Label><Select value={transfer.toWarehouseId} onValueChange={(value) => setTransfer((prev) => ({ ...prev, toWarehouseId: value }))}><SelectTrigger className="mt-1"><SelectValue placeholder="Tujuan" /></SelectTrigger><SelectContent>{warehouses.filter((warehouse) => warehouse.is_active && warehouse.id !== transfer.fromWarehouseId).map((warehouse) => <SelectItem key={warehouse.id} value={warehouse.id}>{warehouse.name}</SelectItem>)}</SelectContent></Select></div></div><div><Label>Produk</Label><Select value={transfer.stockId} onValueChange={(value) => setTransfer((prev) => ({ ...prev, stockId: value }))}><SelectTrigger className="mt-1"><SelectValue placeholder="Pilih stok sumber" /></SelectTrigger><SelectContent>{sourceStocks.map((stock) => <SelectItem key={stock.id} value={stock.id}>{stock.pos_products?.name ?? stock.product_id} · tersedia {stock.quantity - stock.reserved_quantity} {stock.pos_products?.unit ?? 'unit'}</SelectItem>)}</SelectContent></Select></div><div><Label>Jumlah</Label><Input className="mt-1" type="number" min="0.001" step="0.001" value={transfer.quantity} onChange={(event) => setTransfer((prev) => ({ ...prev, quantity: event.target.value }))} /></div><div><Label>Catatan</Label><Textarea className="mt-1" value={transfer.notes} onChange={(event) => setTransfer((prev) => ({ ...prev, notes: event.target.value }))} maxLength={500} /></div></div><DialogFooter><Button variant="outline" onClick={() => setTransferDialog(false)}>Batal</Button><Button onClick={() => void executeTransfer()} disabled={actionLoading}>{actionLoading ? 'Memproses...' : 'Transfer Atomic'}</Button></DialogFooter></DialogContent></Dialog>
    <StockReservationPanel />
  </POSLayout>;
}

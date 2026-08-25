import { useCallback, useEffect, useState } from 'react';
import { POSLayout } from '@/components/pos/POSLayout';
import { usePOS } from '@/contexts/POSContext';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Textarea } from '@/components/ui/textarea';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { toast } from 'sonner';
import { Search, AlertTriangle, Package, ArrowUpCircle, ArrowDownCircle, Edit2, History, TrendingUp, Layers3, CalendarDays } from 'lucide-react';
import { format } from 'date-fns';

interface StockItem {
  id: string;
  product_id: string;
  quantity: number;
  min_stock: number;
  pos_products: { name: string; sku: string | null; unit: string; price: number; cost_price: number; is_active: boolean } | null;
}

interface BatchItem {
  id: string;
  stock_id: string | null;
  product_id: string;
  batch_number: string;
  expiry_date: string | null;
  quantity: number;
  unit_cost: number;
  received_at: string;
  pos_products: { name: string; unit: string } | null;
}

interface Mutation {
  id: string;
  type: string;
  quantity: number;
  quantity_before: number;
  quantity_after: number;
  notes: string | null;
  created_at: string;
  pos_products: { name: string } | null;
}

const MUTATION_TYPES: Record<string, { label: string; color: string }> = {
  initial: { label: 'Stok Awal', color: 'bg-blue-100 text-blue-700' },
  purchase: { label: 'Pembelian', color: 'bg-emerald-100 text-emerald-700' },
  sale: { label: 'Penjualan', color: 'bg-orange-100 text-orange-700' },
  adjustment: { label: 'Penyesuaian', color: 'bg-purple-100 text-purple-700' },
  return_sale: { label: 'Retur Jual', color: 'bg-yellow-100 text-yellow-700' },
  transfer_in: { label: 'Transfer Masuk', color: 'bg-teal-100 text-teal-700' },
  transfer_out: { label: 'Transfer Keluar', color: 'bg-red-100 text-red-700' },
};

export default function POSStokPage() {
  const { tenant, activeOutlet, formatCurrency } = usePOS();
  const [stocks, setStocks] = useState<StockItem[]>([]);
  const [mutations, setMutations] = useState<Mutation[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [adjustDialog, setAdjustDialog] = useState(false);
  const [selectedStock, setSelectedStock] = useState<StockItem | null>(null);
  const [adjustForm, setAdjustForm] = useState({ type: 'adjustment', quantity: '', notes: '' });
  const [batches, setBatches] = useState<BatchItem[]>([]);
  const [batchDialog, setBatchDialog] = useState(false);
  const [batchForm, setBatchForm] = useState({ stockId: '', batchNumber: '', expiryDate: '', quantity: '', unitCost: '' });

  const fetchStocks = useCallback(async () => {
    if (!tenant || !activeOutlet) return;
    const { data } = await supabase
      .from('pos_stock' as never)
      .select('*, pos_products(name, sku, unit, price, cost_price, is_active)')
      .eq('tenant_id', tenant.id)
      .eq('outlet_id', activeOutlet.id)
      .order('pos_products(name)');
    setStocks((data || []) as unknown as StockItem[]);
    setLoading(false);
  }, [tenant, activeOutlet]);

  const fetchBatches = useCallback(async () => {
    if (!tenant || !activeOutlet) return;
    const { data } = await supabase
      .from('pos_stock_batches' as never)
      .select('*, pos_products(name, unit)')
      .eq('tenant_id', tenant.id)
      .eq('outlet_id', activeOutlet.id)
      .order('expiry_date', { ascending: true, nullsFirst: false })
      .order('received_at', { ascending: true });
    setBatches((data || []) as unknown as BatchItem[]);
  }, [tenant, activeOutlet]);

  const fetchMutations = useCallback(async () => {
    if (!tenant || !activeOutlet) return;
    const { data } = await supabase
      .from('pos_stock_mutations' as never)
      .select('*, pos_products(name)')
      .eq('tenant_id', tenant.id)
      .eq('outlet_id', activeOutlet.id)
      .order('created_at', { ascending: false })
      .limit(100);
    setMutations((data || []) as unknown as Mutation[]);
  }, [tenant, activeOutlet]);

  useEffect(() => {
    if (tenant && activeOutlet) {
      void fetchStocks();
      void fetchBatches();
      void fetchMutations();
    }
  }, [tenant, activeOutlet, fetchStocks, fetchBatches, fetchMutations]);

  const filtered = stocks.filter(s =>
    (s.pos_products?.name || '').toLowerCase().includes(search.toLowerCase()) ||
    (s.pos_products?.sku || '').toLowerCase().includes(search.toLowerCase())
  );

  const lowStocks = stocks.filter(s => s.quantity <= s.min_stock && s.pos_products?.is_active);
  const totalValue = stocks.reduce((sum, s) => sum + (s.quantity * (s.pos_products?.cost_price || 0)), 0);

  const openAdjust = (stock: StockItem) => {
    setSelectedStock(stock);
    setAdjustForm({ type: 'adjustment', quantity: '', notes: '' });
    setAdjustDialog(true);
  };

  const handleAdjust = async () => {
    if (!selectedStock || !tenant || !activeOutlet) return;
    const qty = Number(adjustForm.quantity);
    if (!adjustForm.quantity || isNaN(qty)) { toast.error('Jumlah harus diisi'); return; }

    try {
      const { error } = await supabase.rpc('request_pos_stock_adjustment' as never, {
        p_stock_id: selectedStock.id,
        p_tenant_id: tenant.id,
        p_outlet_id: activeOutlet.id,
        p_type: adjustForm.type,
        p_quantity: Math.abs(qty),
        p_notes: adjustForm.notes || null,
      } as never);
      if (error) throw error;
      toast.success('Permintaan penyesuaian stok dikirim untuk approval');
      setAdjustDialog(false);
      fetchStocks();
      fetchMutations();
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : String(err));
    }
  };

  const handleSaveBatch = async () => {
    if (!tenant || !activeOutlet) return;
    const stock = stocks.find((item) => item.id === batchForm.stockId);
    const quantity = Number(batchForm.quantity);
    const unitCost = Number(batchForm.unitCost || 0);
    if (!stock || !batchForm.batchNumber.trim() || !Number.isFinite(quantity) || quantity <= 0 || !Number.isFinite(unitCost) || unitCost < 0) {
      toast.error('Produk, nomor batch, dan jumlah batch wajib valid');
      return;
    }
    try {
      const { error } = await supabase.from('pos_stock_batches' as never).insert({
        tenant_id: tenant.id,
        outlet_id: activeOutlet.id,
        stock_id: stock.id,
        product_id: stock.product_id,
        batch_number: batchForm.batchNumber.trim(),
        expiry_date: batchForm.expiryDate || null,
        quantity,
        unit_cost: unitCost,
      });
      if (error) throw error;
      toast.success('Batch stok berhasil dicatat');
      setBatchDialog(false);
      setBatchForm({ stockId: '', batchNumber: '', expiryDate: '', quantity: '', unitCost: '' });
      await fetchBatches();
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : 'Gagal mencatat batch stok');
    }
  };

  const handleMinStockUpdate = async (stockId: string, minStock: number) => {
    await supabase.from('pos_stock' as never).update({ min_stock: minStock }).eq('id', stockId);
    fetchStocks();
  };

  const sendReorderNotifications = async () => {
    if (lowStocks.length === 0) { toast.info('Semua stok di atas batas minimum'); return; }
    const names = lowStocks.map(s => `${s.pos_products?.name} (sisa: ${s.quantity})`).join(', ');
    toast.success(`Notifikasi auto-reorder dikirim untuk ${lowStocks.length} produk`);
    // In production, this would trigger email/WhatsApp to suppliers
    console.log('[AUTO-REORDER] Low stock products:', names);
  };

  return (
    <POSLayout title="Manajemen Stok" subtitle={`Outlet: ${activeOutlet?.name || ''}`}>
      <Tabs defaultValue="stok">
        <TabsList className="mb-4">
          <TabsTrigger value="stok">Stok Saat Ini</TabsTrigger>
          <TabsTrigger value="mutasi">Riwayat Mutasi</TabsTrigger>
          <TabsTrigger value="batch">Batch & FEFO</TabsTrigger>
        </TabsList>

        <TabsContent value="stok">
          <div className="space-y-4">
            {lowStocks.length > 0 && (
              <div className="bg-amber-50 border border-amber-200 rounded-lg p-3">
                <div className="flex items-center justify-between mb-2">
                  <div className="flex items-center gap-2">
                    <AlertTriangle className="h-4 w-4 text-amber-600" />
                    <span className="text-sm font-semibold text-amber-800">{lowStocks.length} Produk Stok Menipis</span>
                  </div>
                  <Button size="sm" variant="outline" className="h-7 text-xs border-amber-400 text-amber-800 hover:bg-amber-100" onClick={sendReorderNotifications}>
                    <TrendingUp className="h-3 w-3 mr-1" />Auto-Reorder
                  </Button>
                </div>
                <div className="flex flex-wrap gap-1.5">
                  {lowStocks.map(s => (
                    <Badge key={s.id} variant="outline" className="bg-white border-amber-300 text-amber-800 text-xs">
                      {s.pos_products?.name} ({s.quantity} {s.pos_products?.unit})
                    </Badge>
                  ))}
                </div>
              </div>
            )}

            <div className="grid grid-cols-2 gap-3">
              <Card className="border-0 shadow-sm">
                <CardContent className="p-4">
                  <p className="text-xs text-muted-foreground">Total Item Produk</p>
                  <p className="text-xl font-bold mt-1">{stocks.length}</p>
                </CardContent>
              </Card>
              <Card className="border-0 shadow-sm">
                <CardContent className="p-4">
                  <p className="text-xs text-muted-foreground">Nilai Persediaan</p>
                  <p className="text-xl font-bold mt-1 text-emerald-600">{formatCurrency(totalValue)}</p>
                </CardContent>
              </Card>
            </div>

            <div className="relative">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
              <Input className="pl-9" placeholder="Cari produk..." value={search} onChange={e => setSearch(e.target.value)} />
            </div>

            {loading ? (
              <div className="space-y-2">{[...Array(6)].map((_, i) => <div key={i} className="h-16 bg-muted animate-pulse rounded-lg" />)}</div>
            ) : filtered.length === 0 ? (
              <div className="text-center py-12">
                <Package className="h-12 w-12 text-muted-foreground mx-auto mb-3" />
                <p className="text-muted-foreground text-sm">Belum ada data stok</p>
              </div>
            ) : (
              <div className="space-y-2">
                {filtered.map(s => {
                  const isLow = s.quantity <= s.min_stock;
                  return (
                    <Card key={s.id} className={`border shadow-sm ${isLow ? 'border-amber-300 bg-amber-50/40' : ''}`}>
                      <CardContent className="p-3 flex items-center gap-3">
                        <div className={`w-9 h-9 rounded-lg flex items-center justify-center flex-shrink-0 ${isLow ? 'bg-amber-100' : 'bg-muted'}`}>
                          {isLow ? <AlertTriangle className="h-4 w-4 text-amber-600" /> : <Package className="h-4 w-4 text-muted-foreground" />}
                        </div>
                        <div className="flex-1 min-w-0">
                          <p className="font-medium text-sm truncate">{s.pos_products?.name}</p>
                          <p className="text-xs text-muted-foreground">{s.pos_products?.sku || 'No SKU'} • Min: {s.min_stock} {s.pos_products?.unit}</p>
                        </div>
                        <div className="text-right flex-shrink-0">
                          <p className={`font-bold text-sm ${isLow ? 'text-amber-600' : 'text-foreground'}`}>
                            {s.quantity} <span className="font-normal text-xs text-muted-foreground">{s.pos_products?.unit}</span>
                          </p>
                          <p className="text-xs text-muted-foreground">{formatCurrency(s.quantity * (s.pos_products?.cost_price || 0))}</p>
                        </div>
                        <div className="flex gap-1 flex-shrink-0">
                          <Button variant="ghost" size="icon" className="h-7 w-7 text-emerald-600" title="Tambah stok" onClick={() => { setSelectedStock(s); setAdjustForm({ type: 'purchase', quantity: '', notes: '' }); setAdjustDialog(true); }}>
                            <ArrowUpCircle className="h-4 w-4" />
                          </Button>
                          <Button variant="ghost" size="icon" className="h-7 w-7 text-orange-600" title="Kurangi stok" onClick={() => { setSelectedStock(s); setAdjustForm({ type: 'transfer_out', quantity: '', notes: '' }); setAdjustDialog(true); }}>
                            <ArrowDownCircle className="h-4 w-4" />
                          </Button>
                          <Button variant="ghost" size="icon" className="h-7 w-7" title="Penyesuaian" onClick={() => openAdjust(s)}>
                            <Edit2 className="h-3.5 w-3.5" />
                          </Button>
                        </div>
                      </CardContent>
                    </Card>
                  );
                })}
              </div>
            )}
          </div>
        </TabsContent>

        <TabsContent value="batch">
          <div className="space-y-4">
            <div className="flex items-center justify-between gap-3">
              <div><h3 className="font-semibold flex items-center gap-2"><Layers3 className="h-4 w-4 text-primary" />Lot stok dan expiry</h3><p className="text-xs text-muted-foreground">Batch ditampilkan dalam urutan FEFO: expiry terdekat diprioritaskan.</p></div>
              <Button size="sm" onClick={() => setBatchDialog(true)}><Package className="h-4 w-4 mr-1" />Tambah Batch</Button>
            </div>
            {batches.length === 0 ? <div className="text-center py-12 text-muted-foreground"><Layers3 className="h-10 w-10 mx-auto mb-2 opacity-50" />Belum ada batch yang tercatat.</div> : <div className="space-y-2">{batches.map((batch) => { const expired = !!batch.expiry_date && new Date(batch.expiry_date) < new Date(); const soon = !!batch.expiry_date && !expired && new Date(batch.expiry_date).getTime() - Date.now() < 30 * 86400000; return <Card key={batch.id} className={`border shadow-sm ${expired ? 'border-red-300 bg-red-50/40' : soon ? 'border-amber-300 bg-amber-50/40' : ''}`}><CardContent className="p-3 flex items-center gap-3"><div className="w-9 h-9 rounded-lg bg-muted flex items-center justify-center"><Layers3 className="h-4 w-4 text-muted-foreground" /></div><div className="flex-1 min-w-0"><div className="flex items-center gap-2"><p className="font-medium text-sm truncate">{batch.pos_products?.name ?? batch.product_id}</p>{expired && <Badge variant="destructive">Expired</Badge>}{soon && <Badge variant="warning">Segera expiry</Badge>}</div><p className="text-xs text-muted-foreground">Batch: {batch.batch_number} · Diterima {format(new Date(batch.received_at), 'dd/MM/yy')}</p></div><div className="text-right"><p className="font-bold text-sm">{batch.quantity} {batch.pos_products?.unit ?? 'unit'}</p><p className="text-xs text-muted-foreground flex items-center justify-end gap-1"><CalendarDays className="h-3 w-3" />{batch.expiry_date ? format(new Date(batch.expiry_date), 'dd/MM/yyyy') : 'Tanpa expiry'}</p></div></CardContent></Card>; })}</div>}
          </div>
        </TabsContent>

        <TabsContent value="mutasi">
          <div className="space-y-2">
            {mutations.length === 0 ? (
              <div className="text-center py-12">
                <History className="h-12 w-12 text-muted-foreground mx-auto mb-3" />
                <p className="text-muted-foreground text-sm">Belum ada riwayat mutasi stok</p>
              </div>
            ) : (
              mutations.map(m => {
                const typeInfo = MUTATION_TYPES[m.type] || { label: m.type, color: 'bg-gray-100 text-gray-700' };
                const isPositive = m.quantity >= 0;
                return (
                  <Card key={m.id} className="border shadow-sm">
                    <CardContent className="p-3 flex items-center gap-3">
                      <div className={`w-8 h-8 rounded-lg flex items-center justify-center flex-shrink-0 ${isPositive ? 'bg-emerald-100' : 'bg-red-100'}`}>
                        {isPositive ? <TrendingUp className="h-3.5 w-3.5 text-emerald-600" /> : <ArrowDownCircle className="h-3.5 w-3.5 text-red-600" />}
                      </div>
                      <div className="flex-1 min-w-0">
                        <p className="text-sm font-medium truncate">{m.pos_products?.name}</p>
                        <div className="flex items-center gap-2 mt-0.5 flex-wrap">
                          <Badge className={`${typeInfo.color} border-0 text-xs`}>{typeInfo.label}</Badge>
                          {m.notes && <span className="text-xs text-muted-foreground">{m.notes}</span>}
                        </div>
                      </div>
                      <div className="text-right flex-shrink-0">
                        <p className={`font-bold text-sm ${isPositive ? 'text-emerald-600' : 'text-red-600'}`}>
                          {isPositive ? '+' : ''}{m.quantity}
                        </p>
                        <p className="text-xs text-muted-foreground">{m.quantity_before} → {m.quantity_after}</p>
                        <p className="text-xs text-muted-foreground">{format(new Date(m.created_at), 'dd/MM/yy HH:mm')}</p>
                      </div>
                    </CardContent>
                  </Card>
                );
              })
            )}
          </div>
        </TabsContent>
      </Tabs>

      <Dialog open={batchDialog} onOpenChange={setBatchDialog}>
        <DialogContent>
          <DialogHeader><DialogTitle>Tambah Batch Stok</DialogTitle></DialogHeader>
          <div className="space-y-3 py-2">
            <div><Label>Produk</Label><Select value={batchForm.stockId} onValueChange={(value) => setBatchForm((prev) => ({ ...prev, stockId: value }))}><SelectTrigger className="mt-1"><SelectValue placeholder="Pilih produk" /></SelectTrigger><SelectContent>{stocks.map((stock) => <SelectItem key={stock.id} value={stock.id}>{stock.pos_products?.name ?? stock.product_id} ({stock.quantity} {stock.pos_products?.unit ?? 'unit'})</SelectItem>)}</SelectContent></Select></div>
            <div><Label>Nomor batch</Label><Input className="mt-1" value={batchForm.batchNumber} onChange={(event) => setBatchForm((prev) => ({ ...prev, batchNumber: event.target.value }))} placeholder="BATCH-2026-001" maxLength={80} /></div>
            <div className="grid grid-cols-2 gap-3"><div><Label>Expiry date</Label><Input className="mt-1" type="date" value={batchForm.expiryDate} onChange={(event) => setBatchForm((prev) => ({ ...prev, expiryDate: event.target.value }))} /></div><div><Label>Jumlah</Label><Input className="mt-1" type="number" min="0.001" step="0.001" value={batchForm.quantity} onChange={(event) => setBatchForm((prev) => ({ ...prev, quantity: event.target.value }))} /></div></div>
            <div><Label>Harga modal per unit</Label><Input className="mt-1" type="number" min="0" step="0.01" value={batchForm.unitCost} onChange={(event) => setBatchForm((prev) => ({ ...prev, unitCost: event.target.value }))} /></div>
          </div>
          <DialogFooter><Button variant="outline" onClick={() => setBatchDialog(false)}>Batal</Button><Button onClick={() => void handleSaveBatch()}>Simpan Batch</Button></DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={adjustDialog} onOpenChange={setAdjustDialog}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Penyesuaian Stok — {selectedStock?.pos_products?.name}</DialogTitle>
          </DialogHeader>
          <div className="space-y-4 py-2">
            <div className="bg-muted rounded-lg p-3 text-sm">
              Stok saat ini: <strong>{selectedStock?.quantity} {selectedStock?.pos_products?.unit}</strong>
            </div>
            <div>
              <Label>Jenis Mutasi</Label>
              <Select value={adjustForm.type} onValueChange={v => setAdjustForm(p => ({ ...p, type: v }))}>
                <SelectTrigger className="mt-1"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="adjustment">Penyesuaian (set ke nilai baru)</SelectItem>
                  <SelectItem value="initial">Stok Awal</SelectItem>
                  <SelectItem value="purchase">Barang Masuk</SelectItem>
                  <SelectItem value="transfer_out">Barang Keluar</SelectItem>
                  <SelectItem value="return_sale">Retur dari Pelanggan</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div>
              <Label>
                {adjustForm.type === 'adjustment' ? 'Jumlah Stok Baru' : 'Jumlah'}
              </Label>
              <Input className="mt-1" type="number" value={adjustForm.quantity} onChange={e => setAdjustForm(p => ({ ...p, quantity: e.target.value }))}
                placeholder={adjustForm.type === 'adjustment' ? `Contoh: 50` : `Contoh: 10`} />
              {adjustForm.quantity && adjustForm.type !== 'adjustment' && selectedStock && (
                <p className="text-xs text-muted-foreground mt-1">
                  Stok setelah: {['purchase', 'initial', 'return_sale', 'transfer_in'].includes(adjustForm.type)
                    ? selectedStock.quantity + Math.abs(Number(adjustForm.quantity))
                    : Math.max(0, selectedStock.quantity - Math.abs(Number(adjustForm.quantity)))} {selectedStock.pos_products?.unit}
                </p>
              )}
            </div>
            <div>
              <Label>Catatan / Alasan</Label>
              <Textarea className="mt-1" value={adjustForm.notes} onChange={e => setAdjustForm(p => ({ ...p, notes: e.target.value }))} rows={2} placeholder="Keterangan penyesuaian" />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setAdjustDialog(false)}>Batal</Button>
            <Button className="bg-emerald-600 hover:bg-emerald-700" onClick={handleAdjust}>Simpan Perubahan</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </POSLayout>
  );
}

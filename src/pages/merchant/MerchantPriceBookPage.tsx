import { useCallback, useEffect, useState } from 'react';
import { BookOpen, Plus, RefreshCw } from 'lucide-react';
import { MerchantLayout } from '@/components/merchant/MerchantLayout';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { supabase } from '@/integrations/supabase/client';
import { usePOS } from '@/contexts/POSContext';
import { toast } from 'sonner';

interface PriceBook { id: string; name: string; customer_segment: string; outlet_id: string | null; starts_at: string | null; ends_at: string | null; is_active: boolean; priority: number; }
interface Product { id: string; name: string; price: number; }
const SEGMENTS = ['retail', 'wholesale', 'reseller', 'member', 'outlet'];

export default function MerchantPriceBookPage() {
  const { tenant, outlets, loading: posLoading, formatCurrency } = usePOS();
  const [books, setBooks] = useState<PriceBook[]>([]);
  const [products, setProducts] = useState<Product[]>([]);
  const [loading, setLoading] = useState(false);
  const [form, setForm] = useState({ name: '', segment: 'retail', outletId: 'all', productId: '', price: '', startsAt: '', endsAt: '', priority: '0' });

  const load = useCallback(async () => {
    if (!tenant) return;
    setLoading(true);
    const [{ data: bookData, error: bookError }, { data: productData }] = await Promise.all([
      supabase.from('pos_price_books').select('id, name, customer_segment, outlet_id, starts_at, ends_at, is_active, priority').eq('tenant_id', tenant.id).order('created_at', { ascending: false }),
      supabase.from('pos_products').select('id, name, price').eq('tenant_id', tenant.id).eq('is_active', true).order('name').limit(500),
    ]);
    if (bookError) toast.error('Gagal memuat price book');
    setBooks((bookData ?? []) as PriceBook[]); setProducts((productData ?? []) as Product[]); setLoading(false);
  }, [tenant]);
  useEffect(() => { void load(); }, [load]);

  const create = async () => {
    if (!tenant || !form.name.trim() || !form.productId || Number(form.price) < 0 || Number(form.priority) < 0) { toast.error('Lengkapi nama, produk, prioritas, dan harga'); return; }
    if (form.startsAt && form.endsAt && new Date(form.endsAt) < new Date(form.startsAt)) { toast.error('Tanggal berakhir harus setelah tanggal mulai'); return; }
    setLoading(true);
    try {
      const { error } = await supabase.rpc('create_pos_price_book', { p_tenant_id: tenant.id, p_name: form.name.trim(), p_customer_segment: form.segment, p_outlet_id: form.outletId === 'all' ? null : form.outletId, p_starts_at: form.startsAt ? new Date(form.startsAt).toISOString() : null, p_ends_at: form.endsAt ? new Date(form.endsAt).toISOString() : null, p_priority: Number(form.priority) || 0, p_product_id: form.productId, p_variant_id: null, p_price: Number(form.price) });
      if (error) throw error;
      toast.success('Price book berhasil dibuat'); setForm({ name: '', segment: 'retail', outletId: 'all', productId: '', price: '', startsAt: '', endsAt: '', priority: '0' }); await load();
    } catch (error) { toast.error(error instanceof Error ? error.message : 'Gagal membuat price book'); } finally { setLoading(false); }
  };

  const toggleActive = async (book: PriceBook) => {
    const { error } = await supabase.from('pos_price_books').update({ is_active: !book.is_active }).eq('id', book.id).eq('tenant_id', tenant?.id || '');
    if (error) toast.error('Gagal mengubah status price book'); else { toast.success(book.is_active ? 'Price book dinonaktifkan' : 'Price book diaktifkan'); await load(); }
  };

  if (posLoading) return <MerchantLayout title="Price Book"><div className="p-6">Memuat...</div></MerchantLayout>;
  return <MerchantLayout title="Price Book" subtitle="Kelola harga retail, grosir, reseller, member, dan outlet"><div className="space-y-6"><Card><CardHeader><CardTitle className="flex items-center gap-2"><Plus className="h-5 w-5" />Buat Price Book</CardTitle></CardHeader><CardContent className="grid gap-4 md:grid-cols-2"><div><Label>Nama</Label><Input className="mt-1" value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} placeholder="Harga Member Ramadan" /></div><div><Label>Segmen</Label><Select value={form.segment} onValueChange={(v) => setForm({ ...form, segment: v })}><SelectTrigger className="mt-1"><SelectValue /></SelectTrigger><SelectContent>{SEGMENTS.map((segment) => <SelectItem key={segment} value={segment}>{segment}</SelectItem>)}</SelectContent></Select></div><div><Label>Outlet</Label><Select value={form.outletId} onValueChange={(v) => setForm({ ...form, outletId: v })}><SelectTrigger className="mt-1"><SelectValue /></SelectTrigger><SelectContent><SelectItem value="all">Semua outlet</SelectItem>{outlets.map((outlet) => <SelectItem key={outlet.id} value={outlet.id}>{outlet.name}</SelectItem>)}</SelectContent></Select></div><div><Label>Produk</Label><Select value={form.productId} onValueChange={(v) => { const product = products.find((item) => item.id === v); setForm({ ...form, productId: v, price: product ? String(product.price) : form.price }); }}><SelectTrigger className="mt-1"><SelectValue placeholder="Pilih produk" /></SelectTrigger><SelectContent>{products.map((product) => <SelectItem key={product.id} value={product.id}>{product.name}</SelectItem>)}</SelectContent></Select></div><div><Label>Harga</Label><Input className="mt-1" type="number" min="0" value={form.price} onChange={(e) => setForm({ ...form, price: e.target.value })} /></div><div className="flex items-end"><Button onClick={() => void create()} disabled={loading} className="w-full"><Plus className="h-4 w-4 mr-2" />Simpan Price Book</Button></div><div><Label>Mulai berlaku</Label><Input className="mt-1" type="datetime-local" value={form.startsAt} onChange={(e) => setForm({ ...form, startsAt: e.target.value })} /></div><div><Label>Berakhir</Label><Input className="mt-1" type="datetime-local" value={form.endsAt} onChange={(e) => setForm({ ...form, endsAt: e.target.value })} /></div><div><Label>Prioritas</Label><Input className="mt-1" type="number" min="0" value={form.priority} onChange={(e) => setForm({ ...form, priority: e.target.value })} /></div></CardContent></Card><Card><CardHeader><CardTitle className="flex items-center justify-between"><span className="flex items-center gap-2"><BookOpen className="h-5 w-5" />Price Book Aktif</span><Button size="sm" variant="outline" onClick={() => void load()}><RefreshCw className="h-4 w-4" /></Button></CardTitle></CardHeader><CardContent>{books.length === 0 ? <p className="text-sm text-muted-foreground">Belum ada price book.</p> : <div className="space-y-2">{books.map((book) => <div key={book.id} className="flex flex-wrap items-center gap-3 border rounded-lg p-3"><div className="flex-1"><p className="font-medium">{book.name}</p><p className="text-xs text-muted-foreground">{book.starts_at ? new Date(book.starts_at).toLocaleString('id-ID') : 'Sekarang'} – {book.ends_at ? new Date(book.ends_at).toLocaleString('id-ID') : 'Tidak berakhir'}</p></div><Badge variant="outline">{book.customer_segment}</Badge><Badge variant={book.is_active ? 'default' : 'secondary'}>{book.is_active ? 'Aktif' : 'Nonaktif'}</Badge><Badge variant="outline">Prioritas {book.priority}</Badge><span className="text-xs">{book.outlet_id ? outlets.find((outlet) => outlet.id === book.outlet_id)?.name ?? 'Outlet' : 'Semua outlet'}</span><Button size="sm" variant="outline" onClick={() => void toggleActive(book)}>{book.is_active ? 'Nonaktifkan' : 'Aktifkan'}</Button></div>)}</div>}</CardContent></Card></div></MerchantLayout>;
}

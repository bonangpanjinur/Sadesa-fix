import { useEffect, useState } from 'react';
import { Save, Plus, PackageCheck, Percent, ShoppingBag } from 'lucide-react';
import { AdminLayout } from '@/components/admin/AdminLayout';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

type Rule = { id: string; source_type: string; label: string; commission_percent: number; is_active: boolean };
type Product = { id: string; name: string; sku: string | null; target_role: string; price: number; stock: number; is_active: boolean };
type StoreOrder = { id: string; buyer_role: string; total_amount: number; status: string; payment_status: string; referral_verifikator_id: string | null; created_at: string };
const money = (value: number) => new Intl.NumberFormat('id-ID', { style: 'currency', currency: 'IDR', maximumFractionDigits: 0 }).format(value);

export default function AdminVerifierCommercePage() {
  const [rules, setRules] = useState<Rule[]>([]);
  const [products, setProducts] = useState<Product[]>([]);
  const [orders, setOrders] = useState<StoreOrder[]>([]);
  const [form, setForm] = useState({ name: '', sku: '', target_role: 'ALL', price: '', stock: '', description: '' });
  const [loading, setLoading] = useState(true);

  const load = async () => {
    setLoading(true);
    const [{ data: ruleData, error: ruleError }, { data: productData, error: productError }, { data: orderData, error: orderError }] = await Promise.all([
      supabase.from('verifikator_commission_rules').select('*').order('source_type'),
      supabase.from('admin_store_products').select('*').order('created_at', { ascending: false }),
      supabase.from('admin_store_orders').select('*').order('created_at', { ascending: false }).limit(50),
    ]);
    if (ruleError || productError || orderError) toast.error('Sebagian data komisi/toko gagal dimuat');
    setRules((ruleData || []) as Rule[]);
    setProducts((productData || []) as Product[]);
    setOrders((orderData || []) as StoreOrder[]);
    setLoading(false);
  };
  useEffect(() => { void load(); }, []);

  const saveRule = async (rule: Rule) => {
    const percent = Number(rule.commission_percent);
    if (!Number.isFinite(percent) || percent < 0 || percent > 100) { toast.error('Komisi harus 0–100%'); return; }
    const { error } = await supabase.from('verifikator_commission_rules').update({ commission_percent: percent, updated_at: new Date().toISOString() }).eq('id', rule.id);
    if (error) toast.error('Komisi gagal disimpan'); else toast.success(`${rule.label} diperbarui`);
  };
  const addProduct = async () => {
    const price = Number(form.price); const stock = Number(form.stock);
    if (!form.name.trim() || !Number.isInteger(price) || price < 0 || !Number.isInteger(stock) || stock < 0) { toast.error('Lengkapi nama, harga, dan stok dengan angka valid'); return; }
    const { error } = await supabase.from('admin_store_products').insert({ name: form.name.trim(), sku: form.sku.trim() || null, target_role: form.target_role, price, stock, description: form.description.trim() || null });
    if (error) toast.error(error.message || 'Produk gagal ditambahkan'); else { toast.success('Produk admin ditambahkan'); setForm({ name: '', sku: '', target_role: 'ALL', price: '', stock: '', description: '' }); void load(); }
  };
  const toggleProduct = async (product: Product) => {
    const { error } = await supabase.from('admin_store_products').update({ is_active: !product.is_active, updated_at: new Date().toISOString() }).eq('id', product.id);
    if (error) toast.error('Status produk gagal diubah'); else void load();
  };
  const markPaid = async (orderId: string) => {
    const { error } = await supabase.rpc('admin_mark_store_order_paid', { p_order_id: orderId });
    if (error) toast.error(error.message || 'Pembayaran gagal dikonfirmasi'); else { toast.success('Pembayaran dikonfirmasi; komisi referral dicatat server'); void load(); }
  };

  return <AdminLayout title="Toko & Komisi Verifikator" subtitle="Atur komisi dinamis dan penjualan produk milik admin">
    <div className="space-y-6">
      <Card><CardHeader><CardTitle className="flex items-center gap-2"><Percent className="h-5 w-5" />Aturan komisi dinamis</CardTitle><p className="text-sm text-muted-foreground">Nilai tersimpan sebagai snapshot pada earning. Perubahan hanya berlaku untuk transaksi baru.</p></CardHeader><CardContent className="space-y-3">
        {rules.map(rule => <div key={rule.id} className="flex flex-col gap-2 rounded-lg border p-3 sm:flex-row sm:items-center sm:justify-between"><div><p className="font-medium">{rule.label}</p><p className="text-xs text-muted-foreground">Sumber: {rule.source_type}</p></div><div className="flex items-center gap-2"><Input className="w-28" type="number" min="0" max="100" step="0.01" value={rule.commission_percent} onChange={e => setRules(current => current.map(item => item.id === rule.id ? { ...item, commission_percent: Number(e.target.value) } : item))} /><span className="text-sm">%</span><Button size="sm" onClick={() => void saveRule(rule)}><Save className="mr-1 h-4 w-4" />Simpan</Button></div></div>)}
      </CardContent></Card>
      <Card><CardHeader><CardTitle className="flex items-center gap-2"><ShoppingBag className="h-5 w-5" />Katalog jualan admin</CardTitle><p className="text-sm text-muted-foreground">Driver dapat membeli jaket/box dan mengambilnya di verifikator. Merchant dapat membeli barang lain melalui katalog yang sama.</p></CardHeader><CardContent><div className="grid gap-3 md:grid-cols-3"><div><Label>Nama produk</Label><Input value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} placeholder="Jaket driver" /></div><div><Label>SKU</Label><Input value={form.sku} onChange={e => setForm({ ...form, sku: e.target.value })} placeholder="JKT-001" /></div><div><Label>Target</Label><select className="h-10 w-full rounded-md border bg-background px-3 text-sm" value={form.target_role} onChange={e => setForm({ ...form, target_role: e.target.value })}><option value="ALL">Driver & Merchant</option><option value="DRIVER">Driver</option><option value="MERCHANT">Merchant</option></select></div><div><Label>Harga (IDR)</Label><Input type="number" min="0" value={form.price} onChange={e => setForm({ ...form, price: e.target.value })} /></div><div><Label>Stok</Label><Input type="number" min="0" value={form.stock} onChange={e => setForm({ ...form, stock: e.target.value })} /></div><div><Label>Deskripsi</Label><Input value={form.description} onChange={e => setForm({ ...form, description: e.target.value })} /></div></div><Button className="mt-4" onClick={() => void addProduct()}><Plus className="mr-2 h-4 w-4" />Tambah produk</Button><div className="mt-5 space-y-2">{products.map(product => <div key={product.id} className="flex flex-col gap-2 rounded-lg border p-3 sm:flex-row sm:items-center sm:justify-between"><div><p className="font-medium">{product.name} <span className="text-xs text-muted-foreground">({product.target_role})</span></p><p className="text-sm text-muted-foreground">{money(product.price)} · stok {product.stock} · {product.is_active ? 'Aktif' : 'Nonaktif'}</p></div><Button variant="outline" size="sm" onClick={() => void toggleProduct(product)}>{product.is_active ? 'Nonaktifkan' : 'Aktifkan'}</Button></div>)}{!loading && products.length === 0 && <p className="py-3 text-sm text-muted-foreground">Belum ada produk.</p>}</div></CardContent></Card>
      <Card><CardHeader><CardTitle className="flex items-center gap-2"><PackageCheck className="h-5 w-5" />Pesanan menunggu pembayaran</CardTitle></CardHeader><CardContent className="space-y-2">{orders.map(order => <div key={order.id} className="flex flex-col gap-2 rounded-lg border p-3 sm:flex-row sm:items-center sm:justify-between"><div><p className="font-medium">{order.buyer_role} · {money(order.total_amount)}</p><p className="text-xs text-muted-foreground">{new Date(order.created_at).toLocaleString('id-ID')} · referral {order.referral_verifikator_id ? 'terhubung' : 'tidak ada'}</p></div>{order.payment_status === 'UNPAID' ? <Button size="sm" onClick={() => void markPaid(order.id)}>Konfirmasi lunas</Button> : <span className="text-sm text-emerald-600">Siap diambil</span>}</div>)}{!loading && orders.length === 0 && <p className="py-3 text-sm text-muted-foreground">Belum ada order toko.</p>}</CardContent></Card>
    </div>
  </AdminLayout>;
}

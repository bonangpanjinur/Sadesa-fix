import { useCallback, useEffect, useState } from 'react';
import { Package, ShoppingCart } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { useAuth } from '@/contexts/AuthContext';
import { CourierLayout } from '@/components/courier/CourierLayout';
import { MerchantLayout } from '@/components/merchant/MerchantLayout';

type Product = { id: string; name: string; description: string | null; target_role: string; price: number; stock: number };
type Order = { id: string; total_amount: number; status: string; payment_status: string; created_at: string };
const money = (v: number) => new Intl.NumberFormat('id-ID', { style: 'currency', currency: 'IDR', maximumFractionDigits: 0 }).format(v);

export function StorePage({ role }: { role: 'DRIVER' | 'MERCHANT' }) {
  const { user } = useAuth();
  const [products, setProducts] = useState<Product[]>([]); const [orders, setOrders] = useState<Order[]>([]); const [quantities, setQuantities] = useState<Record<string, number>>({});
  const load = useCallback(async () => { const [{ data: p }, { data: o }] = await Promise.all([supabase.from('admin_store_products').select('*').eq('is_active', true).in('target_role', ['ALL', role]), supabase.from('admin_store_orders').select('*').eq('buyer_user_id', user?.id || '').order('created_at', { ascending: false })]); setProducts((p || []) as Product[]); setOrders((o || []) as Order[]); }, [role, user?.id]);
  useEffect(() => { if (user?.id) void load(); }, [load, user?.id]);
  const buy = async (product: Product) => { const quantity = quantities[product.id] || 1; const { data, error } = await supabase.rpc('create_admin_store_order', { p_product_id: product.id, p_quantity: quantity, p_pickup_verifikator_id: null }); if (error) toast.error(error.message || 'Order gagal dibuat'); else { toast.success(`Order dibuat: ${String(data).slice(0, 8)}. Silakan lakukan pembayaran ke admin.`); void load(); } };
  const content = <div className="space-y-6"><Card><CardHeader><CardTitle className="flex items-center gap-2"><ShoppingCart className="h-5 w-5" />Toko perlengkapan {role === 'DRIVER' ? 'driver' : 'merchant'}</CardTitle><p className="text-sm text-muted-foreground">Gunakan kode referral verifikator saat pendaftaran agar pembelian ini menghasilkan komisi untuk verifikator Anda.</p></CardHeader><CardContent className="grid gap-4 sm:grid-cols-2">{products.map(product => <div key={product.id} className="rounded-xl border p-4"><div className="flex items-start justify-between gap-3"><div><p className="font-semibold">{product.name}</p><p className="text-sm text-muted-foreground">{product.description || 'Produk resmi admin'}</p></div><Package className="h-5 w-5 text-primary" /></div><p className="mt-3 text-lg font-bold">{money(product.price)}</p><p className="text-xs text-muted-foreground">Stok tersedia: {product.stock}</p><div className="mt-3 flex gap-2"><Input className="w-20" type="number" min="1" max={product.stock} value={quantities[product.id] || 1} onChange={e => setQuantities({ ...quantities, [product.id]: Math.max(1, Number(e.target.value)) })} /><Button disabled={product.stock < 1} onClick={() => void buy(product)}>Beli</Button></div></div>)}{products.length === 0 && <p className="text-sm text-muted-foreground">Belum ada produk aktif.</p>}</CardContent></Card><Card><CardHeader><CardTitle>Pesanan saya</CardTitle></CardHeader><CardContent className="space-y-2">{orders.map(order => <div key={order.id} className="flex items-center justify-between rounded-lg border p-3"><div><p className="font-medium">{money(order.total_amount)}</p><p className="text-xs text-muted-foreground">{new Date(order.created_at).toLocaleString('id-ID')}</p></div><span className="text-sm">{order.payment_status === 'PAID' ? 'Siap diambil' : 'Menunggu pembayaran'}</span></div>)}{orders.length === 0 && <p className="text-sm text-muted-foreground">Belum ada pesanan.</p>}</CardContent></Card></div>;
  return role === 'DRIVER' ? <CourierLayout title="Toko Admin" subtitle="Beli perlengkapan dan ambil di verifikator">{content}</CourierLayout> : <MerchantLayout title="Toko Admin" subtitle="Beli barang operasional dari admin">{content}</MerchantLayout>;
}
export function DriverStorePage() { return <StorePage role="DRIVER" />; }
export function MerchantStorePage() { return <StorePage role="MERCHANT" />; }
export default StorePage;

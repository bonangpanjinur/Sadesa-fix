import { useEffect, useState } from 'react';
import { Check, Loader2, Plus } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

type Candidate = { id: string; name: string; price: number; stock: number };

export function ProductToppingManager({ productId, merchantId }: { productId: string; merchantId: string }) {
  const [candidates, setCandidates] = useState<Candidate[]>([]);
  const [selected, setSelected] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    let active = true;
    (async () => {
      const [{ data: products, error: productsError }, { data: links, error: linksError }] = await Promise.all([
        (supabase as any).from('products').select('id, name, price, stock').eq('merchant_id', merchantId).eq('is_active', true).neq('id', productId).order('name'),
        (supabase as any).from('product_toppings').select('topping_product_id').eq('product_id', productId).order('sort_order'),
      ]);
      if (!active) return;
      if (productsError || linksError) toast.error('Gagal memuat pengaturan topping');
      setCandidates((products || []).map((item: any) => ({ id: item.id, name: item.name, price: Number(item.price) || 0, stock: Number(item.stock) || 0 })));
      setSelected((links || []).map((item: any) => item.topping_product_id));
      setLoading(false);
    })();
    return () => { active = false; };
  }, [merchantId, productId]);

  const save = async () => {
    setSaving(true);
    const db = supabase as any;
    const { error: deleteError } = await db.from('product_toppings').delete().eq('product_id', productId);
    if (!deleteError && selected.length > 0) {
      const { error } = await db.from('product_toppings').insert(selected.map((toppingProductId, index) => ({ product_id: productId, topping_product_id: toppingProductId, sort_order: index })));
      if (error) toast.error('Gagal menyimpan topping');
      else toast.success('Topping produk disimpan');
    } else if (deleteError) toast.error('Gagal menyimpan topping');
    else toast.success('Topping produk disimpan');
    setSaving(false);
  };

  if (loading) return <div className="flex items-center gap-2 text-sm text-muted-foreground"><Loader2 className="h-4 w-4 animate-spin" /> Memuat topping...</div>;
  return (
    <Card>
      <CardHeader className="pb-3"><CardTitle className="text-base flex items-center gap-2"><Plus className="h-4 w-4" /> Topping dari produk lain</CardTitle><p className="text-xs text-muted-foreground">Pilih produk aktif dari toko ini. Harga dan stok topping mengikuti produk sumber.</p></CardHeader>
      <CardContent className="space-y-3">
        {candidates.length === 0 ? <p className="text-sm text-muted-foreground">Belum ada produk lain yang aktif untuk dijadikan topping.</p> : <div className="grid gap-2 sm:grid-cols-2">{candidates.map((candidate) => { const isSelected = selected.includes(candidate.id); return <button type="button" key={candidate.id} onClick={() => setSelected((current) => isSelected ? current.filter((id) => id !== candidate.id) : [...current, candidate.id])} className={`flex items-center justify-between rounded-lg border p-3 text-left ${isSelected ? 'border-primary bg-primary/5' : 'border-border'}`}><span><span className="block text-sm font-medium">{candidate.name}</span><span className="text-xs text-muted-foreground">Rp {candidate.price.toLocaleString('id-ID')} · stok {candidate.stock}</span></span>{isSelected && <Check className="h-4 w-4 text-primary" />}</button>; })}</div>}
        <Button type="button" onClick={save} disabled={saving} size="sm">{saving ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : null}{saving ? 'Menyimpan...' : 'Simpan Topping'}</Button>
      </CardContent>
    </Card>
  );
}

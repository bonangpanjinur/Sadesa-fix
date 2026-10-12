import { useEffect, useMemo, useState } from 'react';
import { Edit, Save, Trash2 } from 'lucide-react';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { getCategoryBySlug, getCategoryChildren, getCategoryDisplayLabel, getCategoryParent, sortProductCategories, type ProductCategory } from '@/lib/productCategories';

export interface AdminProductInput {
  id: string;
  name: string;
  description?: string | null;
  price: number;
  stock: number;
  shipping_weight_kg?: number | null;
  category?: string | null;
  image_url?: string | null;
  is_active: boolean;
  min_stock_alert?: number | null;
}

interface Props { open: boolean; onOpenChange: (open: boolean) => void; product: AdminProductInput | null; onSuccess: () => void; }

export function AdminEditProductDialog({ open, onOpenChange, product, onSuccess }: Props) {
  const [form, setForm] = useState({ name: '', description: '', price: '', stock: '', shipping_weight_kg: '1', category: '', is_active: true, min_stock_alert: '5' });
  const [categories, setCategories] = useState<ProductCategory[]>([]);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!open) return;
    void (async () => {
      const { data, error } = await supabase.from('categories').select('id, name, slug, parent_id, icon, description, sort_order, is_active').order('sort_order', { ascending: true });
      if (error) toast.error('Kategori produk gagal dimuat');
      setCategories((data || []) as ProductCategory[]);
    })();
  }, [open]);

  useEffect(() => {
    if (!product) return;
    setForm({ name: product.name, description: product.description || '', price: String(product.price), stock: String(product.stock), shipping_weight_kg: String(product.shipping_weight_kg ?? 1), category: product.category || '', is_active: product.is_active, min_stock_alert: String(product.min_stock_alert ?? 5) });
  }, [product]);

  const selectedCategory = getCategoryBySlug(categories, form.category);
  const selectedParent = getCategoryParent(categories, selectedCategory);
  const parentCategory = selectedParent || selectedCategory;
  const parents = useMemo(() => sortProductCategories(categories.filter(category => !category.parent_id)), [categories]);
  const children = getCategoryChildren(categories, parentCategory?.id);

  const handleParentChange = (slug: string) => {
    const parent = getCategoryBySlug(categories, slug);
    const nextChildren = getCategoryChildren(categories, parent?.id);
    setForm(current => ({ ...current, category: nextChildren[0]?.slug || slug }));
  };

  const save = async () => {
    if (!product || !form.name.trim() || Number(form.price) <= 0 || !form.category) {
      toast.error('Nama, harga, dan kategori produk wajib diisi dengan benar');
      return;
    }
    const shippingWeightKg = Number(form.shipping_weight_kg);
    if (!Number.isFinite(shippingWeightKg) || shippingWeightKg <= 0 || shippingWeightKg > 1000) {
      toast.error('Berat harus lebih dari 0 dan maksimal 1.000 kg');
      return;
    }
    if (selectedCategory && children.length > 0) {
      toast.error('Pilih subkategori produk');
      return;
    }
    setSaving(true);
    const { error } = await supabase.from('products').update({ name: form.name.trim(), description: form.description.trim() || null, price: Number(form.price), stock: Math.max(0, Number(form.stock) || 0), shipping_weight_kg: shippingWeightKg, category: form.category, category_id: selectedCategory?.id || null, is_active: form.is_active, min_stock_alert: Math.max(0, Number(form.min_stock_alert) || 0), updated_at: new Date().toISOString() }).eq('id', product.id);
    setSaving(false);
    if (error) { toast.error(error.message || 'Gagal memperbarui produk'); return; }
    toast.success('Produk/menu berhasil diperbarui'); onSuccess(); onOpenChange(false);
  };

  const remove = async () => {
    if (!product || !confirm(`Hapus menu “${product.name}”?`)) return;
    setSaving(true);
    const { error } = await supabase.from('products').delete().eq('id', product.id);
    setSaving(false);
    if (error) { toast.error('Gagal menghapus produk'); return; }
    toast.success('Produk/menu berhasil dihapus'); onSuccess(); onOpenChange(false);
  };

  return <Dialog open={open} onOpenChange={onOpenChange}>
    <DialogContent className="max-h-[90vh] max-w-lg overflow-y-auto">
      <DialogHeader><DialogTitle className="flex items-center gap-2"><Edit className="h-4 w-4" />Edit produk / buku menu</DialogTitle><DialogDescription>Perbaiki data produk merchant tanpa mengubah kepemilikan akun.</DialogDescription></DialogHeader>
      <div className="space-y-5 py-2">
        <div className="space-y-2"><Label>Nama menu *</Label><Input value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} /></div>
        <div className="grid grid-cols-2 gap-3"><div className="space-y-2"><Label>Harga (Rp) *</Label><Input type="number" min="1" value={form.price} onChange={e => setForm({ ...form, price: e.target.value })} /></div><div className="space-y-2"><Label>Stok</Label><Input type="number" min="0" value={form.stock} onChange={e => setForm({ ...form, stock: e.target.value })} /></div></div>
        <div className="space-y-2"><Label>Berat pengiriman (kg) *</Label><Input type="number" min="0.001" max="1000" step="0.001" value={form.shipping_weight_kg} onChange={e => setForm({ ...form, shipping_weight_kg: e.target.value })} /><p className="text-xs text-muted-foreground">Dipakai untuk tarif ekspedisi berbasis berat.</p></div>
        <div className="space-y-2"><Label>Kategori produk *</Label><div className="grid gap-3 sm:grid-cols-2"><Select value={parentCategory?.slug || ''} onValueChange={handleParentChange}><SelectTrigger><SelectValue placeholder="Kategori utama" /></SelectTrigger><SelectContent>{parents.map(category => <SelectItem key={category.id} value={category.slug}>{getCategoryDisplayLabel(categories, category)}{!category.is_active && ' (nonaktif)'}</SelectItem>)}</SelectContent></Select><Select value={selectedCategory?.parent_id ? form.category : ''} onValueChange={value => setForm({ ...form, category: value })} disabled={!children.length}><SelectTrigger><SelectValue placeholder={children.length ? 'Subkategori' : 'Tidak ada subkategori'} /></SelectTrigger><SelectContent>{children.map(category => <SelectItem key={category.id} value={category.slug}>{category.icon ? `${category.icon} ` : ''}{category.name}{!category.is_active && ' (nonaktif)'}</SelectItem>)}</SelectContent></Select></div><p className="text-xs text-muted-foreground">Tersimpan sebagai: <span className="font-medium text-foreground">{selectedCategory ? getCategoryDisplayLabel(categories, selectedCategory) : form.category || 'belum dipilih'}</span></p></div>
        <div className="grid grid-cols-2 gap-3"><div className="space-y-2"><Label>Ambang stok</Label><Input type="number" min="0" value={form.min_stock_alert} onChange={e => setForm({ ...form, min_stock_alert: e.target.value })} /></div><div className="flex items-end gap-2 pb-2"><Switch checked={form.is_active} onCheckedChange={is_active => setForm({ ...form, is_active })} /><Label>Menu aktif dan tampil di toko</Label></div></div>
        <div><Label>Deskripsi</Label><Textarea rows={3} value={form.description} onChange={e => setForm({ ...form, description: e.target.value })} /></div>
      </div>
      <DialogFooter className="justify-between"><Button variant="destructive" onClick={remove} disabled={saving}><Trash2 className="mr-1 h-4 w-4" />Hapus</Button><div className="flex gap-2"><Button variant="outline" onClick={() => onOpenChange(false)} disabled={saving}>Batal</Button><Button onClick={save} disabled={saving}><Save className="mr-1 h-4 w-4" />{saving ? 'Menyimpan...' : 'Simpan'}</Button></div></DialogFooter>
    </DialogContent>
  </Dialog>;
}

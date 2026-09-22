import { useEffect, useState } from 'react';
import { Edit, Save, Trash2 } from 'lucide-react';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';

export interface AdminProductInput {
  id: string;
  name: string;
  description?: string | null;
  price: number;
  stock: number;
  category?: string | null;
  image_url?: string | null;
  is_active: boolean;
  min_stock_alert?: number | null;
}

interface Props {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  product: AdminProductInput | null;
  onSuccess: () => void;
}

export function AdminEditProductDialog({ open, onOpenChange, product, onSuccess }: Props) {
  const [form, setForm] = useState({ name: '', description: '', price: '', stock: '', category: '', is_active: true, min_stock_alert: '5' });
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!product) return;
    setForm({
      name: product.name,
      description: product.description || '',
      price: String(product.price),
      stock: String(product.stock),
      category: product.category || 'umum',
      is_active: product.is_active,
      min_stock_alert: String(product.min_stock_alert ?? 5),
    });
  }, [product]);

  const save = async () => {
    if (!product || !form.name.trim() || Number(form.price) < 0) {
      toast.error('Nama dan harga produk wajib diisi dengan benar');
      return;
    }
    setSaving(true);
    const { error } = await supabase.from('products').update({
      name: form.name.trim(), description: form.description.trim() || null,
      price: Number(form.price), stock: Math.max(0, Number(form.stock) || 0),
      category: form.category.trim() || 'umum', is_active: form.is_active,
      min_stock_alert: Math.max(0, Number(form.min_stock_alert) || 0), updated_at: new Date().toISOString(),
    }).eq('id', product.id);
    setSaving(false);
    if (error) { toast.error('Gagal memperbarui produk'); return; }
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
    <DialogContent className="max-w-lg">
      <DialogHeader><DialogTitle className="flex items-center gap-2"><Edit className="h-4 w-4" />Edit produk / buku menu</DialogTitle><DialogDescription>Admin dapat memperbaiki isi menu merchant tanpa mengambil alih akun pemilik.</DialogDescription></DialogHeader>
      <div className="space-y-4">
        <div><Label>Nama menu *</Label><Input value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} /></div>
        <div className="grid grid-cols-2 gap-3"><div><Label>Harga (Rp) *</Label><Input type="number" min="0" value={form.price} onChange={e => setForm({ ...form, price: e.target.value })} /></div><div><Label>Stok</Label><Input type="number" min="0" value={form.stock} onChange={e => setForm({ ...form, stock: e.target.value })} /></div></div>
        <div className="grid grid-cols-2 gap-3"><div><Label>Kategori</Label><Input value={form.category} onChange={e => setForm({ ...form, category: e.target.value })} /></div><div><Label>Ambang stok</Label><Input type="number" min="0" value={form.min_stock_alert} onChange={e => setForm({ ...form, min_stock_alert: e.target.value })} /></div></div>
        <div><Label>Deskripsi</Label><Textarea rows={3} value={form.description} onChange={e => setForm({ ...form, description: e.target.value })} /></div>
        <div className="flex items-center gap-2"><Switch checked={form.is_active} onCheckedChange={is_active => setForm({ ...form, is_active })} /><Label>Menu aktif dan tampil di toko</Label></div>
      </div>
      <DialogFooter className="justify-between"><Button variant="destructive" onClick={remove} disabled={saving}><Trash2 className="h-4 w-4 mr-1" />Hapus</Button><div className="flex gap-2"><Button variant="outline" onClick={() => onOpenChange(false)}>Batal</Button><Button onClick={save} disabled={saving}><Save className="h-4 w-4 mr-1" />Simpan</Button></div></DialogFooter>
    </DialogContent>
  </Dialog>;
}

import { useEffect, useMemo, useState } from 'react';
import { Plus, Save } from 'lucide-react';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { ImageUpload } from '@/components/ui/ImageUpload';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { getCategoryBySlug, getCategoryChildren, getCategoryDisplayLabel, getCategoryParent, getInitialProductCategory, sortProductCategories, type ProductCategory } from '@/lib/productCategories';

interface AdminAddProductDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  merchantId: string;
  merchantName: string;
  onSuccess: () => void;
}

export function AdminAddProductDialog({ open, onOpenChange, merchantId, merchantName, onSuccess }: AdminAddProductDialogProps) {
  const [loading, setLoading] = useState(false);
  const [categories, setCategories] = useState<ProductCategory[]>([]);
  const [formData, setFormData] = useState({ name: '', description: '', price: '', stock: '', category: '', image_url: null as string | null, is_active: true, min_stock_alert: '5' });

  useEffect(() => {
    if (!open) return;
    void fetchCategories();
    setFormData({ name: '', description: '', price: '', stock: '', category: '', image_url: null, is_active: true, min_stock_alert: '5' });
  }, [open]);

  const fetchCategories = async () => {
    const { data, error } = await supabase.from('categories').select('id, name, slug, parent_id, icon, description, sort_order').eq('is_active', true).order('sort_order', { ascending: true });
    if (error) toast.error('Kategori produk gagal dimuat');
    const nextCategories = (data || []) as ProductCategory[];
    setCategories(nextCategories);
    setFormData((current) => ({ ...current, category: current.category || getInitialProductCategory(nextCategories) }));
  };

  const selectedCategory = getCategoryBySlug(categories, formData.category);
  const selectedParent = getCategoryParent(categories, selectedCategory);
  const parentCategory = selectedParent || selectedCategory;
  const parents = useMemo(() => sortProductCategories(categories.filter(category => !category.parent_id)), [categories]);
  const children = getCategoryChildren(categories, parentCategory?.id);

  const handleParentChange = (slug: string) => {
    const parent = getCategoryBySlug(categories, slug);
    const nextChildren = getCategoryChildren(categories, parent?.id);
    setFormData(current => ({ ...current, category: nextChildren[0]?.slug || slug }));
  };

  const handleSubmit = async () => {
    if (!formData.name.trim()) return void toast.error('Nama produk wajib diisi');
    if (!formData.price || Number(formData.price) <= 0) return void toast.error('Harga harus lebih dari 0');
    if (!formData.category) return void toast.error('Pilih kategori produk');
    if (selectedCategory && children.length > 0) return void toast.error('Pilih subkategori produk');
    setLoading(true);
    try {
      const { error } = await supabase.from('products').insert({ merchant_id: merchantId, name: formData.name.trim(), description: formData.description.trim() || null, price: Number(formData.price), stock: Number(formData.stock) || 0, category: formData.category, image_url: formData.image_url, is_active: formData.is_active, min_stock_alert: Number(formData.min_stock_alert) || 5 });
      if (error) throw error;
      toast.success('Produk berhasil ditambahkan');
      onSuccess();
      onOpenChange(false);
    } catch (error) {
      console.error('Error adding product:', error);
      toast.error(error instanceof Error ? error.message : 'Gagal menambahkan produk');
    } finally {
      setLoading(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[90vh] max-w-lg overflow-y-auto">
        <DialogHeader><DialogTitle className="flex items-center gap-2"><Plus className="h-5 w-5" />Tambah Produk</DialogTitle><DialogDescription>Tambahkan produk baru untuk <strong>{merchantName}</strong>.</DialogDescription></DialogHeader>
        <div className="space-y-5 py-2">
          <div className="space-y-2"><Label>Gambar Produk</Label><ImageUpload bucket="product-images" path={`admin/${merchantId}`} value={formData.image_url} onChange={(url) => setFormData({ ...formData, image_url: url })} aspectRatio="square" placeholder="Upload gambar produk" /></div>
          <div className="space-y-2"><Label htmlFor="admin-product-name">Nama Produk *</Label><Input id="admin-product-name" value={formData.name} onChange={(e) => setFormData({ ...formData, name: e.target.value })} placeholder="Contoh: Nasi Goreng Spesial" /></div>
          <div className="grid grid-cols-2 gap-4"><div className="space-y-2"><Label>Harga (Rp) *</Label><Input type="number" value={formData.price} onChange={(e) => setFormData({ ...formData, price: e.target.value })} min="1" placeholder="15000" /></div><div className="space-y-2"><Label>Stok</Label><Input type="number" value={formData.stock} onChange={(e) => setFormData({ ...formData, stock: e.target.value })} min="0" placeholder="100" /></div></div>
          <div className="space-y-2"><Label>Kategori produk *</Label><div className="grid gap-3 sm:grid-cols-2"><Select value={parentCategory?.slug || ''} onValueChange={handleParentChange}><SelectTrigger><SelectValue placeholder="Kategori utama" /></SelectTrigger><SelectContent>{parents.map(category => <SelectItem key={category.id} value={category.slug}>{getCategoryDisplayLabel(categories, category)}</SelectItem>)}</SelectContent></Select><Select value={selectedCategory?.parent_id ? formData.category : ''} onValueChange={(value) => setFormData({ ...formData, category: value })} disabled={!children.length}><SelectTrigger><SelectValue placeholder={children.length ? 'Subkategori' : 'Tidak ada subkategori'} /></SelectTrigger><SelectContent>{children.map(category => <SelectItem key={category.id} value={category.slug}>{category.icon ? `${category.icon} ` : ''}{category.name}</SelectItem>)}</SelectContent></Select></div><p className="text-xs text-muted-foreground">Tersimpan sebagai: <span className="font-medium text-foreground">{selectedCategory ? getCategoryDisplayLabel(categories, selectedCategory) : 'belum dipilih'}</span></p></div>
          <div className="grid grid-cols-2 gap-4"><div className="space-y-2"><Label>Peringatan Stok Min.</Label><Input type="number" value={formData.min_stock_alert} onChange={(e) => setFormData({ ...formData, min_stock_alert: e.target.value })} min="0" placeholder="5" /></div><div className="flex items-end gap-2 pb-2"><Switch checked={formData.is_active} onCheckedChange={(value) => setFormData({ ...formData, is_active: value })} /><Label>Produk aktif</Label></div></div>
          <div className="space-y-2"><Label>Deskripsi</Label><Textarea value={formData.description} onChange={(e) => setFormData({ ...formData, description: e.target.value })} placeholder="Deskripsi produk" rows={3} /></div>
        </div>
        <DialogFooter><Button variant="outline" onClick={() => onOpenChange(false)} disabled={loading}>Batal</Button><Button onClick={handleSubmit} disabled={loading} className="gap-2"><Save className="h-4 w-4" />{loading ? 'Menyimpan...' : 'Simpan Produk'}</Button></DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Package, Plus, Edit, Trash2, MoreHorizontal, ImageIcon, Images, Eye, ShoppingCart, AlertCircle } from 'lucide-react';
import { MerchantLayout } from '@/components/merchant/MerchantLayout';
import { DataTable } from '@/components/admin/DataTable';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Switch } from '@/components/ui/switch';
import { ImageUpload } from '@/components/ui/ImageUpload';
import { ProductVariantManager } from '@/components/merchant/ProductVariantManager';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from 'sonner';
import { useMerchantGuard } from '@/hooks/useMerchantGuard';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { z } from 'zod';
import { getCategoryTemplate } from '@/lib/categoryContracts';
import { productFormSchema } from '@/lib/commerceSchemas';
import { getCategoryBySlug, getCategoryChildren, getCategoryDisplayLabel, getCategoryParent, getInitialProductCategory, sortProductCategories, type ProductCategory } from '@/lib/productCategories';

interface ProductRow {
  id: string;
  name: string;
  description: string | null;
  price: number;
  stock: number;
  category: string;
  image_url: string | null;
  is_active: boolean;
  is_promo: boolean;
  view_count: number | null;
  order_count: number | null;
  pos_linked?: boolean;
}

interface ProductForm {
  name: string;
  description: string;
  price: string;
  stock: string;
  category: string;
  image_url: string | null;
  is_active: boolean;
  is_promo: boolean;
}

interface Category {
  id: string;
  name: string;
  slug: string;
  parent_id: string | null;
  icon: string | null;
}

const defaultForm: ProductForm = {
  name: '', description: '', price: '', stock: '0', category: '', image_url: null, is_active: true, is_promo: false,
};


export default function MerchantProductsPage() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const { merchantId: guardMerchantId, loading: guardLoading } = useMerchantGuard();
  const queryClient = useQueryClient();
  const [dialogOpen, setDialogOpen] = useState(false);
  const [editingProduct, setEditingProduct] = useState<ProductRow | null>(null);
  const [form, setForm] = useState<ProductForm>(defaultForm);
  const [formErrors, setFormErrors] = useState<Record<string, string>>({});

  const merchantId = guardMerchantId;

  // Fetch categories
  const { data: categories = [] } = useQuery<Category[]>({
    queryKey: ['product-categories'],
    queryFn: async () => {
      const { data } = await supabase.from('categories').select('id, name, slug, parent_id, icon, description, sort_order').eq('is_active', true).order('sort_order');
      return (data || []) as unknown as Category[];
    },
    staleTime: 300_000,
  });

  // Fetch products
  const { data: products = [], isLoading: productsLoading } = useQuery<ProductRow[]>({
    queryKey: ['merchant-products', merchantId],
    queryFn: async () => {
      const [{ data, error }, { data: posProducts, error: posError }] = await Promise.all([
        supabase.from('products').select('*').eq('merchant_id', merchantId!).order('created_at', { ascending: false }),
        supabase.from('pos_products' as never).select('merchant_product_id').not('merchant_product_id', 'is', null),
      ]);
      if (error) throw error;
      if (posError) throw posError;
      const linkedProductIds = new Set(
        ((posProducts || []) as unknown as Array<{ merchant_product_id: string | null }>)
          .map((row) => row.merchant_product_id)
          .filter((id): id is string => Boolean(id)),
      );
      return (data || []).map((product) => ({
        ...product,
        pos_linked: linkedProductIds.has(product.id),
      }));
    },
    enabled: !!merchantId && !guardLoading,
    staleTime: 60_000,
  });

  const loading = guardLoading || productsLoading;

  const saveMutation = useMutation({
    mutationFn: async () => {
      if (!merchantId) return;
      const parsed = productFormSchema.safeParse(form);
      if (!parsed.success) {
        const nextErrors: Record<string, string> = {};
        parsed.error.errors.forEach((issue) => {
          const field = issue.path[0];
          if (typeof field === 'string' && !nextErrors[field]) nextErrors[field] = issue.message;
        });
        setFormErrors(nextErrors);
        throw new Error('Periksa kembali data produk');
      }
      const selectedProductCategory = getCategoryBySlug(categories as ProductCategory[], parsed.data.category);
      if (selectedProductCategory && getCategoryChildren(categories as ProductCategory[], selectedProductCategory.id).length > 0) {
        setFormErrors({ category: 'Pilih subkategori agar produk ditempatkan lebih spesifik.' });
        throw new Error('Pilih subkategori produk');
      }
      setFormErrors({});

      const productData = {
        name: parsed.data.name,
        description: parsed.data.description || null,
        price: parsed.data.price,
        stock: parsed.data.stock,
        category: parsed.data.category,
        image_url: form.image_url,
        is_active: form.is_active,
        is_promo: form.is_promo,
        merchant_id: merchantId,
        updated_at: new Date().toISOString(),
      };

      if (editingProduct) {
        if (editingProduct.pos_linked && (
          parsed.data.name !== editingProduct.name
          || parsed.data.price !== editingProduct.price
          || parsed.data.description !== (editingProduct.description || '')
          || form.image_url !== editingProduct.image_url
          || form.is_active !== editingProduct.is_active
        )) {
          throw new Error('Produk tertaut POS hanya dapat mengubah data inti dari POS');
        }
        if (editingProduct.pos_linked && parsed.data.stock !== editingProduct.stock) {
          throw new Error('Stok produk tertaut POS hanya dapat diubah dari halaman stok POS');
        }
        const { error } = await supabase.from('products').update(productData).eq('id', editingProduct.id);
        if (error) throw error;
      } else {
        const { error } = await supabase.from('products').insert({ ...productData, created_at: new Date().toISOString() });
        if (error) throw error;
      }
    },
    onSuccess: () => {
      toast.success(editingProduct ? 'Produk berhasil diperbarui' : 'Produk berhasil ditambahkan');
      setDialogOpen(false);
      queryClient.invalidateQueries({ queryKey: ['merchant-products', merchantId] });
      queryClient.invalidateQueries({ queryKey: ['pos-products'] });
    },
    onError: (err: unknown) => {
      const errorMessage = err instanceof Error ? err.message : 'Gagal menyimpan produk';
      if (errorMessage.includes('Bucket not found')) {
        toast.error('Error: Bucket storage "products" tidak ditemukan. Silakan jalankan migrasi SQL.');
      } else {
        toast.error(errorMessage);
      }
    },
  });

  const deleteMutation = useMutation({
    mutationFn: async (id: string) => {
      if (!confirm('Yakin ingin menghapus produk ini?')) throw new Error('cancelled');
      const { error } = await supabase.from('products').delete().eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => {
      toast.success('Produk dihapus');
      queryClient.invalidateQueries({ queryKey: ['merchant-products', merchantId] });
    },
    onError: (err: unknown) => {
      if (err instanceof Error && err.message !== 'cancelled') toast.error('Gagal menghapus produk');
    },
  });

  const toggleActiveMutation = useMutation({
    mutationFn: async ({ id, currentActive }: { id: string; currentActive: boolean }) => {
      const { error } = await supabase.from('products').update({ is_active: !currentActive }).eq('id', id);
      if (error) throw error;
      return !currentActive;
    },
    onSuccess: (newActive) => {
      toast.success(newActive ? 'Produk diaktifkan' : 'Produk dinonaktifkan');
      queryClient.invalidateQueries({ queryKey: ['merchant-products', merchantId] });
    },
    onError: () => toast.error('Gagal mengubah status'),
  });

  const openCreateDialog = () => {
    setEditingProduct(null);
    setFormErrors({});
    setForm({ ...defaultForm, category: getInitialProductCategory(categories as ProductCategory[]) });
    setDialogOpen(true);
  };

  const openEditDialog = (product: ProductRow) => {
    setEditingProduct(product);
    setFormErrors({});
    setForm({
      name: product.name,
      description: product.description || '',
      price: product.price.toString(),
      stock: product.stock.toString(),
      category: product.category,
      image_url: product.image_url,
      is_active: product.is_active,
      is_promo: product.is_promo,
    });
    setDialogOpen(true);
  };

  const columns = [
    {
      key: 'product',
      header: 'Produk',
      render: (item: ProductRow) => (
        <div className="flex items-center gap-3">
          {item.image_url ? (
            <img src={item.image_url} alt={item.name} className="w-10 h-10 rounded-lg object-cover" />
          ) : (
            <div className="w-10 h-10 rounded-lg bg-secondary flex items-center justify-center">
              <ImageIcon className="h-5 w-5 text-muted-foreground" />
            </div>
          )}
          <div>
            <p className="font-medium">{item.name}</p>
            <p className="text-xs text-muted-foreground">{getCategoryDisplayLabel(categories as ProductCategory[], getCategoryBySlug(categories as ProductCategory[], item.category) || { id: '', name: item.category, slug: item.category, parent_id: null, icon: null })}</p>
          </div>
        </div>
      ),
    },
    { key: 'price', header: 'Harga', render: (item: ProductRow) => `Rp ${item.price.toLocaleString('id-ID')}` },
    {
      key: 'stock',
      header: 'Stok',
      render: (item: ProductRow) => {
        const isOutOfStock = item.stock === 0;
        const isLowStock = !isOutOfStock && item.stock <= 5;
        return (
          <div className="flex items-center gap-1.5">
            <span className={isOutOfStock ? 'text-destructive font-medium' : isLowStock ? 'text-warning font-medium' : ''}>{item.stock}</span>
            {isLowStock && <Badge variant="outline" className="text-[10px] px-1 py-0 h-4 border-warning/50 text-warning">Rendah</Badge>}
            {isOutOfStock && <Badge variant="outline" className="text-[10px] px-1 py-0 h-4 border-destructive/50 text-destructive">Habis</Badge>}
            {item.pos_linked && <Badge variant="outline" className="text-[10px] px-1 py-0 h-4 border-primary/50 text-primary">POS</Badge>}
          </div>
        );
      },
    },
    {
      key: 'stats',
      header: 'Statistik',
      render: (item: ProductRow) => (
        <div className="flex items-center gap-3 text-xs text-muted-foreground">
          <span className="flex items-center gap-1"><Eye className="h-3 w-3" />{(item.view_count || 0).toLocaleString()}</span>
          <span className="flex items-center gap-1"><ShoppingCart className="h-3 w-3" />{(item.order_count || 0).toLocaleString()}</span>
        </div>
      ),
    },
    {
      key: 'status',
      header: 'Status',
      render: (item: ProductRow) => (
        <div className="flex items-center gap-2">
          {item.is_active ? <Badge className="bg-primary/10 text-primary">Aktif</Badge> : <Badge variant="outline">Nonaktif</Badge>}
          {item.is_promo && <Badge variant="secondary">Promo</Badge>}
        </div>
      ),
    },
    {
      key: 'actions',
      header: '',
      render: (item: ProductRow) => (
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="ghost" size="icon"><MoreHorizontal className="h-4 w-4" /></Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuItem onClick={() => openEditDialog(item)}><Edit className="h-4 w-4 mr-2" />Edit</DropdownMenuItem>
            <DropdownMenuItem onClick={() => navigate(`/merchant/products/${item.id}`)}><Images className="h-4 w-4 mr-2" />Gambar & Varian</DropdownMenuItem>
            <DropdownMenuItem onClick={() => toggleActiveMutation.mutate({ id: item.id, currentActive: item.is_active })}>
              {item.is_active ? 'Nonaktifkan' : 'Aktifkan'}
            </DropdownMenuItem>
            <DropdownMenuItem onClick={() => deleteMutation.mutate(item.id)} className="text-destructive">
              <Trash2 className="h-4 w-4 mr-2" />Hapus
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      ),
    },
  ];

  const filters = [{ key: 'category', label: 'Kategori', options: categories.map(cat => ({ value: cat.slug, label: getCategoryDisplayLabel(categories as ProductCategory[], cat) })) }];
  const selectedCategoryTemplate = getCategoryTemplate(form.category);
  const selectedCategory = getCategoryBySlug(categories as ProductCategory[], form.category);
  const selectedParent = getCategoryParent(categories as ProductCategory[], selectedCategory);
  const parentCategory = selectedParent || selectedCategory;
  const categoryParents = sortProductCategories((categories as ProductCategory[]).filter(category => !category.parent_id));
  const categoryChildren = getCategoryChildren(categories as ProductCategory[], parentCategory?.id);

  const handleParentChange = (parentSlug: string) => {
    const parent = getCategoryBySlug(categories as ProductCategory[], parentSlug);
    const children = getCategoryChildren(categories as ProductCategory[], parent?.id);
    setForm(previous => ({ ...previous, category: children[0]?.slug || parentSlug }));
    setFormErrors(previous => ({ ...previous, category: '' }));
  };

  return (
    <MerchantLayout title="Katalog Produk" subtitle="Sumber katalog untuk marketplace dan POS">
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-2">
          <Package className="h-5 w-5 text-primary" />
          <span className="text-muted-foreground text-sm">{products.length} produk</span>
        </div>
        <Button onClick={openCreateDialog}><Plus className="h-4 w-4 mr-2" />Tambah Produk</Button>
      </div>

      <DataTable columns={columns} data={products} loading={loading} searchKeys={['name']} filters={filters} />

      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>{editingProduct ? 'Edit Produk' : 'Tambah Produk Baru'}</DialogTitle>
            <DialogDescription>Lengkapi informasi produk di bawah ini. Tanda (*) wajib diisi.</DialogDescription>
          </DialogHeader>
          <div className="grid gap-6 py-4">
            <div className="space-y-3">
              <Label className="text-base font-semibold">Gambar Produk</Label>
              <div className="space-y-2">
                <ImageUpload bucket="product-images" path={`merchants/${merchantId}/products`} value={form.image_url}
                  onChange={url => setForm(p => ({ ...p, image_url: url }))} aspectRatio="square" maxSizeMB={5} placeholder="Upload gambar produk" />
                <div className="flex items-start gap-2 p-2 bg-muted/50 rounded-md">
                  <AlertCircle className="h-3.5 w-3.5 text-muted-foreground mt-0.5" />
                  <p className="text-[10px] text-muted-foreground leading-tight">Gunakan gambar berkualitas tinggi (1:1). Jika upload gagal, pastikan bucket 'products' sudah dibuat di Supabase Storage.</p>
                </div>
              </div>
            </div>
            <div className="space-y-4">
              <Label className="text-base font-semibold">Informasi Dasar</Label>
              <div className="space-y-2">
                <Label htmlFor="prod-name">Nama Produk *</Label>
                <Input id="prod-name" value={form.name} onChange={e => { setForm(p => ({ ...p, name: e.target.value })); setFormErrors(p => ({ ...p, name: '' })); }} placeholder="Contoh: Nasi Goreng Spesial" required minLength={2} maxLength={150} aria-invalid={Boolean(formErrors.name)} aria-describedby={formErrors.name ? 'prod-name-error' : undefined} />
                {formErrors.name && <p id="prod-name-error" role="alert" className="text-xs text-destructive">{formErrors.name}</p>}
              </div>
              <div className="space-y-2">
                <Label>Kategori produk *</Label>
                <div className="grid gap-3 sm:grid-cols-2">
                  <Select value={parentCategory?.slug || ''} onValueChange={handleParentChange}>
                    <SelectTrigger><SelectValue placeholder="Pilih kategori utama" /></SelectTrigger>
                    <SelectContent>{categoryParents.map(category => <SelectItem key={category.id} value={category.slug}>{getCategoryDisplayLabel(categories as ProductCategory[], category)}</SelectItem>)}</SelectContent>
                  </Select>
                  <Select value={selectedCategory?.parent_id ? form.category : ''} onValueChange={v => { setForm(p => ({ ...p, category: v })); setFormErrors(p => ({ ...p, category: '' })); }} disabled={!categoryChildren.length}>
                    <SelectTrigger aria-invalid={Boolean(formErrors.category)} aria-describedby={formErrors.category ? 'prod-category-error' : undefined}><SelectValue placeholder={categoryChildren.length ? 'Pilih subkategori' : 'Tidak ada subkategori'} /></SelectTrigger>
                    <SelectContent>{categoryChildren.map(category => <SelectItem key={category.id} value={category.slug}>{category.icon ? `${category.icon} ` : ''}{category.name}</SelectItem>)}</SelectContent>
                  </Select>
                </div>
                {formErrors.category && <p id="prod-category-error" role="alert" className="text-xs text-destructive">{formErrors.category}</p>}
                <p className="text-xs text-muted-foreground">Pilihan tersimpan: <span className="font-medium text-foreground">{selectedCategory ? getCategoryDisplayLabel(categories as ProductCategory[], selectedCategory) : 'belum dipilih'}</span></p>
                <p className="text-xs text-muted-foreground">
                  Template {selectedCategoryTemplate.label} · alur {selectedCategoryTemplate.workflow.replace('_', ' ')} · atribut: {selectedCategoryTemplate.listingFields.join(', ')}.
                </p>
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label>Harga (Rp) *</Label>
                  <Input type="number" min={1} max={1000000000} step={1} value={form.price} onChange={e => { setForm(p => ({ ...p, price: e.target.value })); setFormErrors(p => ({ ...p, price: '' })); }} placeholder="15000" required aria-invalid={Boolean(formErrors.price)} aria-describedby={formErrors.price ? 'prod-price-error' : undefined} />
                  {formErrors.price && <p id="prod-price-error" role="alert" className="text-xs text-destructive">{formErrors.price}</p>}
                </div>
                <div className="space-y-2">
                  <Label>Stok</Label>
                   <Input type="number" min={0} max={1000000} step={1} value={form.stock} disabled={Boolean(editingProduct?.pos_linked)} onChange={e => { setForm(p => ({ ...p, stock: e.target.value })); setFormErrors(p => ({ ...p, stock: '' })); }} placeholder="0" aria-invalid={Boolean(formErrors.stock)} aria-describedby={formErrors.stock ? 'prod-stock-error' : undefined} />
                   {editingProduct?.pos_linked && <p className="text-xs text-muted-foreground">Stok dikelola dari outlet POS.</p>}
                  {formErrors.stock && <p id="prod-stock-error" role="alert" className="text-xs text-destructive">{formErrors.stock}</p>}
                </div>
              </div>
              <div className="space-y-2">
                <Label>Deskripsi</Label>
                <Textarea value={form.description} onChange={e => { setForm(p => ({ ...p, description: e.target.value })); setFormErrors(p => ({ ...p, description: '' })); }} placeholder="Jelaskan detail produk Anda..." rows={3} maxLength={2000} aria-invalid={Boolean(formErrors.description)} aria-describedby={formErrors.description ? 'prod-description-error' : undefined} />
                <p className="text-xs text-muted-foreground">{form.description.length}/2000 karakter</p>
                {formErrors.description && <p id="prod-description-error" role="alert" className="text-xs text-destructive">{formErrors.description}</p>}
              </div>
            </div>
            <div className="space-y-4 pt-2 border-t">
              <Label className="text-base font-semibold">Pengaturan</Label>
              <div className="flex flex-wrap gap-6">
                <div className="flex items-center gap-2">
                  <Switch id="is_active" checked={form.is_active} onCheckedChange={c => setForm(p => ({ ...p, is_active: c }))} />
                  <Label htmlFor="is_active" className="cursor-pointer">Produk Aktif</Label>
                </div>
                <div className="flex items-center gap-2">
                  <Switch id="is_promo" checked={form.is_promo} onCheckedChange={c => setForm(p => ({ ...p, is_promo: c }))} />
                  <Label htmlFor="is_promo" className="cursor-pointer">Sedang Promo</Label>
                </div>
              </div>
            </div>
            {editingProduct && (
              <div className="border-t pt-4">
                <ProductVariantManager productId={editingProduct.id} basePrice={parseInt(form.price) || 0} />
              </div>
            )}
          </div>
          <div className="flex justify-end gap-3 pt-4 border-t mt-2">
            <Button variant="outline" onClick={() => setDialogOpen(false)} disabled={saveMutation.isPending}>Batal</Button>
            <Button onClick={() => saveMutation.mutate()} disabled={saveMutation.isPending} className="min-w-[100px]">
              {saveMutation.isPending ? 'Menyimpan...' : 'Simpan Produk'}
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </MerchantLayout>
  );
}

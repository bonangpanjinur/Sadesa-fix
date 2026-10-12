import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Package, Plus, Edit, Trash2, MoreHorizontal, ImageIcon, Images, Eye, ShoppingCart, AlertCircle, Search, Filter, X, ChevronLeft, ChevronRight } from 'lucide-react';
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
  shipping_weight_kg?: number | null;
  category: string;
  image_url: string | null;
  is_active: boolean;
  is_promo: boolean;
  view_count: number | null;
  order_count: number | null;
  min_stock_alert?: number | null;
  low_stock_threshold?: number | null;
  pos_linked?: boolean;
}

interface ProductSummary {
  total: number;
  active: number;
  inactive: number;
  outOfStock: number;
  lowStock: number;
  promo: number;
}

interface MissingPhotoProduct {
  id: string;
  name: string;
}

type ProductStatusFilter = 'all' | 'active' | 'inactive' | 'out_of_stock' | 'low_stock' | 'promo';

const PAGE_SIZE = 25;

interface ProductForm {
  name: string;
  description: string;
  price: string;
  stock: string;
  shipping_weight_kg: string;
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
  name: '', description: '', price: '', stock: '0', shipping_weight_kg: '1', category: '', image_url: null, is_active: true, is_promo: false,
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
  const [searchInput, setSearchInput] = useState('');
  const [searchTerm, setSearchTerm] = useState('');
  const [statusFilter, setStatusFilter] = useState<ProductStatusFilter>('all');
  const [categoryFilter, setCategoryFilter] = useState('all');
  const [currentPage, setCurrentPage] = useState(1);

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

  useEffect(() => {
    const timeout = window.setTimeout(() => {
      setSearchTerm(searchInput.trim());
      setCurrentPage(1);
    }, 300);
    return () => window.clearTimeout(timeout);
  }, [searchInput]);

  useEffect(() => {
    setCurrentPage(1);
  }, [statusFilter, categoryFilter]);

  const { data: summary = { total: 0, active: 0, inactive: 0, outOfStock: 0, lowStock: 0, promo: 0 }, isLoading: summaryLoading } = useQuery<ProductSummary>({
    queryKey: ['merchant-product-summary', merchantId],
    queryFn: async () => {
      if (!merchantId) return { total: 0, active: 0, inactive: 0, outOfStock: 0, lowStock: 0, promo: 0 };
      const [totalRes, activeRes, inactiveRes, outOfStockRes, promoRes, stockRes] = await Promise.all([
        supabase.from('products').select('id', { count: 'exact', head: true }).eq('merchant_id', merchantId),
        supabase.from('products').select('id', { count: 'exact', head: true }).eq('merchant_id', merchantId).eq('is_active', true),
        supabase.from('products').select('id', { count: 'exact', head: true }).eq('merchant_id', merchantId).eq('is_active', false),
        supabase.from('products').select('id', { count: 'exact', head: true }).eq('merchant_id', merchantId).eq('stock', 0),
        supabase.from('products').select('id', { count: 'exact', head: true }).eq('merchant_id', merchantId).eq('is_promo', true),
        supabase.from('products').select('stock, min_stock_alert, low_stock_threshold').eq('merchant_id', merchantId),
      ]);
      const queryError = [totalRes.error, activeRes.error, inactiveRes.error, outOfStockRes.error, promoRes.error, stockRes.error].find(Boolean);
      if (queryError) throw queryError;
      const lowStock = (stockRes.data || []).filter((product) => {
        const threshold = product.low_stock_threshold ?? product.min_stock_alert ?? 5;
        return product.stock > 0 && product.stock <= threshold;
      }).length;
      return {
        total: totalRes.count || 0,
        active: activeRes.count || 0,
        inactive: inactiveRes.count || 0,
        outOfStock: outOfStockRes.count || 0,
        lowStock,
        promo: promoRes.count || 0,
      };
    },
    enabled: !!merchantId && !guardLoading,
    staleTime: 60_000,
  });

  // Fetch one server-side page of products. The low-stock candidate query only
  // selects stock fields, then the visible page fetches the full product rows.
  const { data: productsPage = { rows: [], total: 0 }, isLoading: productsLoading, isError: productsError, refetch: refetchProducts } = useQuery<{ rows: ProductRow[]; total: number }>({
    queryKey: ['merchant-products', merchantId, searchTerm, statusFilter, categoryFilter, currentPage],
    queryFn: async () => {
      if (!merchantId) return { rows: [], total: 0 };
      let productIdsForFilter: string[] | null = null;
      let query = supabase
        .from('products')
        .select('id, name, description, price, stock, category, image_url, is_active, is_promo, view_count, order_count, min_stock_alert, low_stock_threshold', { count: 'exact' })
        .eq('merchant_id', merchantId);

      if (searchTerm) query = query.ilike('name', `%${searchTerm}%`);
      if (categoryFilter !== 'all') query = query.eq('category', categoryFilter);
      if (statusFilter === 'active') query = query.eq('is_active', true);
      if (statusFilter === 'inactive') query = query.eq('is_active', false);
      if (statusFilter === 'out_of_stock') query = query.eq('stock', 0);
      if (statusFilter === 'promo') query = query.eq('is_promo', true);
      if (statusFilter === 'low_stock') {
        const { data: candidates, error: candidateError } = await supabase
          .from('products')
          .select('id, name, stock, min_stock_alert, low_stock_threshold')
          .eq('merchant_id', merchantId)
          .ilike('name', searchTerm ? `%${searchTerm}%` : '%')
          .eq(categoryFilter === 'all' ? 'merchant_id' : 'category', categoryFilter === 'all' ? merchantId : categoryFilter);
        if (candidateError) throw candidateError;
        productIdsForFilter = (candidates || [])
          .filter((product) => {
            const threshold = product.low_stock_threshold ?? product.min_stock_alert ?? 5;
            return product.stock > 0 && product.stock <= threshold;
          })
          .map((product) => product.id);
        if (productIdsForFilter.length === 0) return { rows: [], total: 0 };
        query = query.in('id', productIdsForFilter);
      }

      const { data, count, error } = await query
        .order('created_at', { ascending: false })
        .range((currentPage - 1) * PAGE_SIZE, currentPage * PAGE_SIZE - 1);
      if (error) throw error;
      const productIds = (data || []).map((product) => product.id);
      const { data: posProducts, error: posError } = productIds.length
        ? await supabase
          .from('pos_products' as never)
          .select('merchant_product_id')
          .in('merchant_product_id', productIds)
          .not('merchant_product_id', 'is', null)
        : { data: [], error: null };
      if (posError) throw posError;
      const linkedProductIds = new Set(
        ((posProducts || []) as unknown as Array<{ merchant_product_id: string | null }>)
          .map((row) => row.merchant_product_id)
          .filter((id): id is string => Boolean(id)),
      );
      return {
        rows: (data || []).map((product) => ({ ...product, pos_linked: linkedProductIds.has(product.id) })) as ProductRow[],
        total: count || 0,
      };
    },
    enabled: !!merchantId && !guardLoading,
    staleTime: 60_000,
  });

  const { data: missingPhotoProducts = [] } = useQuery<MissingPhotoProduct[]>({
    queryKey: ['merchant-products-missing-photos', merchantId],
    queryFn: async () => {
      if (!merchantId) return [];
      const { data: rows, error } = await supabase.from('products').select('id, name, image_url').eq('merchant_id', merchantId);
      if (error) throw error;
      const productIds = (rows || []).map((row) => row.id);
      const galleryResult = productIds.length
        ? await supabase.from('product_images' as never).select('product_id, image_url').in('product_id', productIds)
        : { data: [], error: null };
      const galleryProductIds = new Set(
        ((galleryResult.data || []) as unknown as Array<{ product_id: string; image_url: string | null }>)
          .filter((row) => Boolean(row.image_url?.trim()))
          .map((row) => row.product_id),
      );
      return (rows || [])
        .filter((row) => !row.image_url?.trim() && !galleryProductIds.has(row.id))
        .map((row) => ({ id: row.id, name: row.name }));
    },
    enabled: !!merchantId && !guardLoading,
    staleTime: 60_000,
  });

  const products = productsPage.rows;
  const totalProducts = productsPage.total;
  const totalPages = Math.max(1, Math.ceil(totalProducts / PAGE_SIZE));
  const loading = guardLoading || productsLoading;

  useEffect(() => {
    setCurrentPage((page) => Math.min(page, totalPages));
  }, [totalPages]);

  const saveMutation = useMutation({
    mutationFn: async () => {
      if (!merchantId) return;
      const shippingWeightKg = Number(form.shipping_weight_kg);
      if (!Number.isFinite(shippingWeightKg) || shippingWeightKg <= 0 || shippingWeightKg > 1000) {
        setFormErrors({ shipping_weight_kg: 'Berat harus lebih dari 0 dan maksimal 1.000 kg.' });
        throw new Error('Periksa berat produk untuk pengiriman');
      }
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
      if (!editingProduct && !form.image_url?.trim()) {
        setFormErrors({ image_url: 'Foto produk wajib diunggah sebelum diterbitkan.' });
        throw new Error('Foto produk wajib diunggah sebelum diterbitkan');
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
        shipping_weight_kg: shippingWeightKg,
        category: parsed.data.category,
        category_id: selectedProductCategory?.id || null,
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
      queryClient.invalidateQueries({ queryKey: ['merchant-product-summary', merchantId] });
      queryClient.invalidateQueries({ queryKey: ['merchant-products-missing-photos', merchantId] });
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
      queryClient.invalidateQueries({ queryKey: ['merchant-product-summary', merchantId] });
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
      queryClient.invalidateQueries({ queryKey: ['merchant-product-summary', merchantId] });
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
      shipping_weight_kg: String(product.shipping_weight_kg ?? 1),
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
        const threshold = item.low_stock_threshold ?? item.min_stock_alert ?? 5;
        const isLowStock = !isOutOfStock && item.stock <= threshold;
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
            <Button variant="ghost" size="icon" aria-label={`Buka aksi produk ${item.name}`} title="Aksi produk"><MoreHorizontal className="h-4 w-4" /></Button>
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
      <div className="mb-4 flex flex-col items-stretch gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div className="flex items-center gap-2">
          <Package className="h-5 w-5 text-primary" />
          <span className="text-muted-foreground text-sm">{summaryLoading ? 'Memuat ringkasan...' : `${summary.total} produk`}</span>
        </div>
        <Button onClick={openCreateDialog} className="w-full sm:w-auto"><Plus className="h-4 w-4 mr-2" />Tambah Produk</Button>
      </div>

      {missingPhotoProducts.length > 0 && (
        <div role="alert" className="mb-4 flex items-start gap-3 rounded-xl border border-amber-200 bg-amber-50 p-4 text-amber-950">
          <AlertCircle className="mt-0.5 h-5 w-5 shrink-0 text-amber-600" />
          <div className="min-w-0">
            <p className="font-semibold">{missingPhotoProducts.length} produk perlu ditambahkan foto</p>
            <p className="mt-1 text-sm text-amber-900/80">Produk lama tanpa foto tetap tersimpan, tetapi tidak akan masuk bagian Produk terbaru sampai datanya dilengkapi.</p>
            <p className="mt-2 text-xs text-amber-900/70">{missingPhotoProducts.slice(0, 3).map((product) => product.name).join(', ')}{missingPhotoProducts.length > 3 ? ` dan ${missingPhotoProducts.length - 3} lainnya` : ''}</p>
          </div>
        </div>
      )}

      <div className="mb-4 grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-6" aria-label="Ringkasan status katalog">
        {[
          { key: 'all' as const, label: 'Semua', value: summary.total, tone: 'text-foreground' },
          { key: 'active' as const, label: 'Aktif', value: summary.active, tone: 'text-primary' },
          { key: 'inactive' as const, label: 'Nonaktif', value: summary.inactive, tone: 'text-muted-foreground' },
          { key: 'out_of_stock' as const, label: 'Stok habis', value: summary.outOfStock, tone: 'text-destructive' },
          { key: 'low_stock' as const, label: 'Stok menipis', value: summary.lowStock, tone: 'text-warning' },
          { key: 'promo' as const, label: 'Promo', value: summary.promo, tone: 'text-info' },
        ].map((item) => (
          <button
            key={item.key}
            type="button"
            onClick={() => setStatusFilter(item.key)}
            aria-pressed={statusFilter === item.key}
            className={`rounded-xl border bg-card p-3 text-left transition-colors hover:border-primary/40 hover:bg-primary/[0.03] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary ${statusFilter === item.key ? 'border-primary bg-primary/[0.05] shadow-sm' : 'border-border'}`}
          >
            <p className="text-[11px] font-medium text-muted-foreground">{item.label}</p>
            <p className={`mt-1 text-xl font-bold ${item.tone}`}>{summaryLoading ? '—' : item.value.toLocaleString('id-ID')}</p>
          </button>
        ))}
      </div>

      <div className="mb-4 flex flex-col gap-2 sm:flex-row sm:items-center">
        <div className="relative min-w-0 flex-1">
          <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" aria-hidden="true" />
          <Input
            value={searchInput}
            onChange={(event) => setSearchInput(event.target.value)}
            placeholder="Cari nama produk..."
            aria-label="Cari nama produk"
            className="h-10 pl-9 pr-9"
          />
          {searchInput && (
            <button type="button" onClick={() => setSearchInput('')} className="absolute right-2 top-1/2 -translate-y-1/2 rounded-md p-1 text-muted-foreground hover:bg-muted hover:text-foreground" aria-label="Hapus pencarian">
              <X className="h-4 w-4" />
            </button>
          )}
        </div>
        <Select value={statusFilter} onValueChange={(value) => setStatusFilter(value as ProductStatusFilter)}>
          <SelectTrigger className="h-10 w-full sm:w-[180px]" aria-label="Filter status produk">
            <Filter className="mr-2 h-4 w-4 opacity-70" />
            <SelectValue placeholder="Status produk" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">Semua status</SelectItem>
            <SelectItem value="active">Aktif</SelectItem>
            <SelectItem value="inactive">Nonaktif</SelectItem>
            <SelectItem value="out_of_stock">Stok habis</SelectItem>
            <SelectItem value="low_stock">Stok menipis</SelectItem>
            <SelectItem value="promo">Sedang promo</SelectItem>
          </SelectContent>
        </Select>
        <Select value={categoryFilter} onValueChange={setCategoryFilter}>
          <SelectTrigger className="h-10 w-full sm:w-[190px]" aria-label="Filter kategori produk">
            <SelectValue placeholder="Kategori" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">Semua kategori</SelectItem>
            {categories.map((category) => <SelectItem key={category.id} value={category.slug}>{getCategoryDisplayLabel(categories as ProductCategory[], category)}</SelectItem>)}
          </SelectContent>
        </Select>
      </div>

      <DataTable
        columns={columns}
        data={products}
        loading={loading}
        pageSize={PAGE_SIZE}
        searchKeys={undefined}
        filters={[]}
        error={productsError ? 'Daftar produk gagal dimuat. Periksa koneksi lalu coba lagi.' : null}
        onRetry={() => void refetchProducts()}
        mobileCardAriaLabel="Daftar produk versi kartu"
        mobileCardRender={(item) => {
          const isOutOfStock = item.stock === 0;
          const threshold = item.low_stock_threshold ?? item.min_stock_alert ?? 5;
          const isLowStock = !isOutOfStock && item.stock <= threshold;
          return (
            <div className="space-y-3">
              <div className="flex items-start gap-3">
                {item.image_url ? (
                  <img src={item.image_url} alt="" className="h-14 w-14 shrink-0 rounded-xl object-cover" />
                ) : (
                  <div className="flex h-14 w-14 shrink-0 items-center justify-center rounded-xl bg-secondary">
                    <ImageIcon className="h-6 w-6 text-muted-foreground" aria-hidden="true" />
                  </div>
                )}
                <div className="min-w-0 flex-1">
                  <p className="truncate font-medium">{item.name}</p>
                  <p className="mt-0.5 truncate text-xs text-muted-foreground">
                    {getCategoryDisplayLabel(categories as ProductCategory[], getCategoryBySlug(categories as ProductCategory[], item.category) || { id: '', name: item.category, slug: item.category, parent_id: null, icon: null })}
                  </p>
                  <p className="mt-1 font-semibold text-primary">Rp {item.price.toLocaleString('id-ID')}</p>
                </div>
                {item.is_active ? <Badge className="shrink-0 bg-primary/10 text-primary">Aktif</Badge> : <Badge variant="outline" className="shrink-0">Nonaktif</Badge>}
              </div>
              <div className="flex flex-wrap items-center gap-2 text-xs">
                <span className={isOutOfStock ? 'font-semibold text-destructive' : isLowStock ? 'font-semibold text-warning' : 'text-muted-foreground'}>Stok {item.stock}</span>
                {isLowStock && <Badge variant="outline" className="border-warning/50 px-1.5 py-0 text-[10px] text-warning">Rendah</Badge>}
                {isOutOfStock && <Badge variant="outline" className="border-destructive/50 px-1.5 py-0 text-[10px] text-destructive">Habis</Badge>}
                {item.is_promo && <Badge variant="secondary" className="px-1.5 py-0 text-[10px]">Promo</Badge>}
                <span className="ml-auto text-muted-foreground">{(item.order_count || 0).toLocaleString('id-ID')} terjual</span>
              </div>
              <div className="grid grid-cols-2 gap-2 border-t pt-3">
                <Button variant="outline" size="sm" onClick={() => openEditDialog(item)}><Edit className="mr-1.5 h-3.5 w-3.5" />Edit</Button>
                <Button size="sm" onClick={() => navigate(`/merchant/products/${item.id}`)}><Images className="mr-1.5 h-3.5 w-3.5" />Gambar & Varian</Button>
              </div>
            </div>
          );
        }}
      />

      {!productsError && totalProducts > 0 && (
        <div className="flex items-center justify-between gap-3 pt-2">
          <p className="text-xs font-medium text-muted-foreground">
            Menampilkan <span className="text-foreground">{(currentPage - 1) * PAGE_SIZE + 1}</span>–<span className="text-foreground">{Math.min(currentPage * PAGE_SIZE, totalProducts)}</span> dari <span className="text-foreground">{totalProducts}</span> produk
          </p>
          <div className="flex items-center gap-1.5">
            <Button variant="outline" size="icon" className="h-8 w-8" onClick={() => setCurrentPage((page) => Math.max(1, page - 1))} disabled={currentPage === 1 || loading} aria-label="Halaman sebelumnya">
              <ChevronLeft className="h-4 w-4" />
            </Button>
            <span className="px-2 text-xs font-semibold">{currentPage} / {totalPages}</span>
            <Button variant="outline" size="icon" className="h-8 w-8" onClick={() => setCurrentPage((page) => Math.min(totalPages, page + 1))} disabled={currentPage === totalPages || loading} aria-label="Halaman berikutnya">
              <ChevronRight className="h-4 w-4" />
            </Button>
          </div>
        </div>
      )}

      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>{editingProduct ? 'Edit Produk' : 'Tambah Produk Baru'}</DialogTitle>
            <DialogDescription>Lengkapi informasi produk di bawah ini. Tanda (*) wajib diisi.</DialogDescription>
          </DialogHeader>
          <div className="grid gap-6 py-4">
            <div className="space-y-3">
              <Label className="text-base font-semibold">Gambar Produk {!editingProduct && '*'}</Label>
              <div className="space-y-2">
                <ImageUpload bucket="product-images" path={`merchants/${merchantId}/products`} value={form.image_url}
                  onChange={url => setForm(p => ({ ...p, image_url: url }))} aspectRatio="square" maxSizeMB={5} placeholder="Upload gambar produk" />
                <div className="flex items-start gap-2 p-2 bg-muted/50 rounded-md">
                  <AlertCircle className="h-3.5 w-3.5 text-muted-foreground mt-0.5" />
                  <p className="text-[10px] text-muted-foreground leading-tight">Gunakan gambar berkualitas tinggi (1:1). Jika upload gagal, periksa ukuran file dan koneksi, lalu coba lagi.</p>
                </div>
                {formErrors.image_url && <p role="alert" className="text-xs text-destructive">{formErrors.image_url}</p>}
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
                <Label>Berat pengiriman (kg) *</Label>
                <Input type="number" min={0.001} max={1000} step={0.001} value={form.shipping_weight_kg} onChange={e => { setForm(p => ({ ...p, shipping_weight_kg: e.target.value })); setFormErrors(p => ({ ...p, shipping_weight_kg: '' })); }} placeholder="1" required aria-invalid={Boolean(formErrors.shipping_weight_kg)} aria-describedby={formErrors.shipping_weight_kg ? 'prod-shipping-weight-error' : undefined} />
                <p className="text-xs text-muted-foreground">Dipakai untuk quote ekspedisi berbasis berat.</p>
                {formErrors.shipping_weight_kg && <p id="prod-shipping-weight-error" role="alert" className="text-xs text-destructive">{formErrors.shipping_weight_kg}</p>}
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

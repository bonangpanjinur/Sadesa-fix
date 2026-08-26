import { useCallback, useEffect, useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { motion } from 'framer-motion';
import { ArrowLeft, Save, Trash2, Package, AlertTriangle, Loader2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { ProductVariantManager } from './ProductVariantManager';
import { MultipleImageUpload } from './MultipleImageUpload';
import { StockAlerts } from './StockAlerts';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from 'sonner';
import { z } from 'zod';

interface ProductData {
  id: string;
  name: string;
  description: string | null;
  price: number;
  stock: number;
  category: string;
  image_url: string | null;
  is_active: boolean;
  is_promo: boolean;
  discount_percent: number | null;
  discount_end_date: string | null;
  min_stock_alert: number | null;
  merchant_id: string;
}

interface Category {
  id: string;
  name: string;
  slug: string;
  icon: string | null;
}

interface MerchantProductDetailEditorProps {
  productId: string;
  merchantId: string;
  onBack: () => void;
}

export const productDetailSchema = z.object({
  name: z.string().trim().min(2, 'Nama produk minimal 2 karakter').max(150, 'Nama produk maksimal 150 karakter'),
  description: z.string().trim().max(2000, 'Deskripsi maksimal 2.000 karakter'),
  price: z.coerce.number({ invalid_type_error: 'Harga wajib diisi' }).int('Harga harus berupa angka bulat').positive('Harga harus lebih dari 0').max(1_000_000_000, 'Harga terlalu besar'),
  stock: z.coerce.number({ invalid_type_error: 'Stok wajib berupa angka' }).int('Stok harus berupa angka bulat').min(0, 'Stok tidak boleh negatif').max(1_000_000, 'Stok terlalu besar'),
  category: z.string().min(1, 'Pilih kategori produk'),
  discount_percent: z.coerce.number({ invalid_type_error: 'Diskon wajib berupa angka' }).int('Diskon harus berupa angka bulat').min(0, 'Diskon minimal 0%').max(100, 'Diskon maksimal 100%').optional(),
  min_stock_alert: z.coerce.number({ invalid_type_error: 'Batas stok wajib berupa angka' }).int('Batas stok harus berupa angka bulat').min(0, 'Batas stok tidak boleh negatif').max(1_000_000, 'Batas stok terlalu besar'),
});

export function MerchantProductDetailEditor({ productId, merchantId, onBack }: MerchantProductDetailEditorProps) {
  const [product, setProduct] = useState<ProductData | null>(null);
  const [categories, setCategories] = useState<Category[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [formErrors, setFormErrors] = useState<Record<string, string>>({});
  const [form, setForm] = useState({
    name: '',
    description: '',
    price: '',
    stock: '',
    category: '',
    is_active: true,
    is_promo: false,
    discount_percent: '',
    discount_end_date: '',
    min_stock_alert: '5',
  });

  const fetchData = useCallback(async () => {
    try {
      const [productRes, categoriesRes] = await Promise.all([
        supabase
          .from('products')
          .select('*')
          .eq('id', productId)
          .maybeSingle(),
        supabase
          .from('categories')
          .select('id, name, slug, icon')
          .eq('is_active', true)
          .order('sort_order'),
      ]);

      if (productRes.error) throw productRes.error;

      const p = productRes.data;
      if (p) {
        setProduct(p);
        setForm({
          name: p.name || '',
          description: p.description || '',
          price: p.price?.toString() || '',
          stock: p.stock?.toString() || '',
          category: p.category || '',
          is_active: p.is_active,
          is_promo: p.is_promo,
          discount_percent: p.discount_percent?.toString() || '',
          discount_end_date: p.discount_end_date ? p.discount_end_date.split('T')[0] : '',
          min_stock_alert: p.min_stock_alert?.toString() || '5',
        });
      }

      setCategories((categoriesRes.data || []) as unknown as Category[]);
    } catch (error) {
      console.error('Error fetching product:', error);
      toast.error('Gagal memuat produk');
    } finally {
      setLoading(false);
    }
  }, [productId]);

  useEffect(() => {
    fetchData();
  }, [fetchData]);

  const handleSave = async () => {
    const parsed = productDetailSchema.safeParse({
      ...form,
      discount_percent: form.discount_percent.trim() ? form.discount_percent : undefined,
    });
    if (!parsed.success) {
      const nextErrors: Record<string, string> = {};
      parsed.error.errors.forEach((issue) => {
        const field = issue.path[0];
        if (typeof field === 'string' && !nextErrors[field]) nextErrors[field] = issue.message;
      });
      setFormErrors(nextErrors);
      toast.error('Periksa kembali data produk');
      return;
    }
    setFormErrors({});
    setSaving(true);
    try {
      const { error } = await supabase
        .from('products')
        .update({
          name: parsed.data.name,
          description: parsed.data.description || null,
          price: parsed.data.price,
          stock: parsed.data.stock,
          category: parsed.data.category,
          is_active: form.is_active,
          is_promo: form.is_promo,
          discount_percent: parsed.data.discount_percent ?? null,
          discount_end_date: form.discount_end_date ? new Date(form.discount_end_date).toISOString() : null,
          min_stock_alert: parsed.data.min_stock_alert,
          updated_at: new Date().toISOString(),
        })
        .eq('id', productId);

      if (error) throw error;

      toast.success('Produk berhasil disimpan');
    } catch (error: unknown) {
      console.error('Error saving product:', error);
      const errorMessage = error instanceof Error ? error.message : 'Gagal menyimpan produk';
      if (errorMessage.includes('Bucket not found')) {
        toast.error('Error: Bucket storage "products" tidak ditemukan. Silakan jalankan migrasi SQL.');
      } else {
        toast.error(errorMessage);
      }
    } finally {
      setSaving(false);
    }
  };

  const handleDelete = async () => {
    if (!confirm('Hapus produk ini? Tindakan ini tidak dapat dibatalkan.')) return;

    try {
      const { error } = await supabase
        .from('products')
        .delete()
        .eq('id', productId);

      if (error) throw error;

      toast.success('Produk dihapus');
      onBack();
    } catch (error) {
      console.error('Error deleting product:', error);
      toast.error('Gagal menghapus produk');
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center py-20">
        <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
      </div>
    );
  }

  if (!product) {
    return (
      <div className="text-center py-20">
        <Package className="h-12 w-12 text-muted-foreground mx-auto mb-4" />
        <p className="text-muted-foreground">Produk tidak ditemukan</p>
        <Button onClick={onBack} className="mt-4">Kembali</Button>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <Button variant="ghost" size="icon" onClick={onBack}>
            <ArrowLeft className="h-5 w-5" />
          </Button>
          <div>
            <h2 className="font-bold text-lg">{product.name}</h2>
            <p className="text-sm text-muted-foreground">Edit detail produk</p>
          </div>
        </div>
        <div className="flex gap-2">
          <Button variant="destructive" size="sm" onClick={handleDelete}>
            <Trash2 className="h-4 w-4 mr-1" />
            Hapus
          </Button>
          <Button onClick={handleSave} disabled={saving}>
            <Save className="h-4 w-4 mr-1" />
            {saving ? 'Menyimpan...' : 'Simpan'}
          </Button>
        </div>
      </div>

      <Tabs defaultValue="basic" className="space-y-4">
        <TabsList className="w-full grid grid-cols-4">
          <TabsTrigger value="basic">Info Dasar</TabsTrigger>
          <TabsTrigger value="images">Gambar</TabsTrigger>
          <TabsTrigger value="variants">Varian</TabsTrigger>
          <TabsTrigger value="stock">Stok</TabsTrigger>
        </TabsList>

        {/* Basic Info Tab */}
        <TabsContent value="basic">
          <Card>
            <CardHeader>
              <CardTitle>Informasi Produk</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="grid md:grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label>Nama Produk *</Label>
                  <Input
                    value={form.name}
                    onChange={(e) => { setForm(prev => ({ ...prev, name: e.target.value })); setFormErrors(prev => ({ ...prev, name: '' })); }}
                    placeholder="Nama produk"
                    required
                    minLength={2}
                    maxLength={150}
                    aria-invalid={Boolean(formErrors.name)}
                    aria-describedby={formErrors.name ? 'detail-product-name-error' : undefined}
                  />
                  {formErrors.name && <p id="detail-product-name-error" role="alert" className="text-xs text-destructive">{formErrors.name}</p>}
                </div>
                <div className="space-y-2">
                  <Label>Kategori</Label>
                  <Select
                    value={form.category}
                    onValueChange={(value) => { setForm(prev => ({ ...prev, category: value })); setFormErrors(prev => ({ ...prev, category: '' })); }}
                  >
                    <SelectTrigger>
                      <SelectValue placeholder="Pilih kategori" />
                    </SelectTrigger>
                    <SelectContent>
                      {categories.map((cat) => (
                        <SelectItem key={cat.id} value={cat.slug}>
                          {cat.icon} {cat.name}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  {formErrors.category && <p role="alert" className="text-xs text-destructive">{formErrors.category}</p>}
                </div>
              </div>

              <div className="space-y-2">
                <Label>Deskripsi</Label>
                <Textarea
                  value={form.description}
                  onChange={(e) => setForm(prev => ({ ...prev, description: e.target.value }))}
                  placeholder="Deskripsi produk..."
                  rows={4}
                />
              </div>

              <div className="grid md:grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label>Harga (Rp) *</Label>
                  <Input
                    type="number"
                    min={1}
                    max={1000000000}
                    step={1}
                    value={form.price}
                    onChange={(e) => { setForm(prev => ({ ...prev, price: e.target.value })); setFormErrors(prev => ({ ...prev, price: '' })); }}
                    placeholder="10000"
                    required
                    aria-invalid={Boolean(formErrors.price)}
                    aria-describedby={formErrors.price ? 'detail-product-price-error' : undefined}
                  />
                  {formErrors.price && <p id="detail-product-price-error" role="alert" className="text-xs text-destructive">{formErrors.price}</p>}
                </div>
                <div className="space-y-2">
                  <Label>Stok</Label>
                  <Input
                    type="number"
                    min={0}
                    max={1000000}
                    step={1}
                    value={form.stock}
                    onChange={(e) => { setForm(prev => ({ ...prev, stock: e.target.value })); setFormErrors(prev => ({ ...prev, stock: '' })); }}
                    placeholder="100"
                    aria-invalid={Boolean(formErrors.stock)}
                    aria-describedby={formErrors.stock ? 'detail-product-stock-error' : undefined}
                  />
                  {formErrors.stock && <p id="detail-product-stock-error" role="alert" className="text-xs text-destructive">{formErrors.stock}</p>}
                </div>
              </div>

              <div className="flex items-center gap-6 pt-4 border-t">
                <div className="flex items-center gap-2">
                  <Switch
                    checked={form.is_active}
                    onCheckedChange={(checked) => setForm(prev => ({ ...prev, is_active: checked }))}
                  />
                  <Label>Produk Aktif</Label>
                </div>
                <div className="flex items-center gap-2">
                  <Switch
                    checked={form.is_promo}
                    onCheckedChange={(checked) => setForm(prev => ({ ...prev, is_promo: checked }))}
                  />
                  <Label>Promo</Label>
                </div>
              </div>

              {form.is_promo && (
                <motion.div
                  initial={{ opacity: 0, height: 0 }}
                  animate={{ opacity: 1, height: 'auto' }}
                  className="grid md:grid-cols-2 gap-4 p-4 bg-primary/5 rounded-lg border border-primary/20"
                >
                  <div className="space-y-2">
                    <Label>Diskon (%)</Label>
                    <Input
                      type="number"
                      value={form.discount_percent}
                      onChange={(e) => { setForm(prev => ({ ...prev, discount_percent: e.target.value })); setFormErrors(prev => ({ ...prev, discount_percent: '' })); }}
                      placeholder="10"
                      min={0}
                      max={100}
                      step={1}
                      aria-invalid={Boolean(formErrors.discount_percent)}
                      aria-describedby={formErrors.discount_percent ? 'detail-discount-error' : undefined}
                    />
                    {formErrors.discount_percent && <p id="detail-discount-error" role="alert" className="text-xs text-destructive">{formErrors.discount_percent}</p>}
                  </div>
                  <div className="space-y-2">
                    <Label>Berlaku Hingga</Label>
                    <Input
                      type="date"
                      value={form.discount_end_date}
                      onChange={(e) => setForm(prev => ({ ...prev, discount_end_date: e.target.value }))}
                    />
                  </div>
                </motion.div>
              )}
            </CardContent>
          </Card>
        </TabsContent>

        {/* Images Tab */}
        <TabsContent value="images">
          <Card>
            <CardHeader>
              <CardTitle>Gambar Produk</CardTitle>
            </CardHeader>
            <CardContent>
              <MultipleImageUpload
                productId={productId}
                merchantId={merchantId}
                maxImages={5}
              />
            </CardContent>
          </Card>
        </TabsContent>

        {/* Variants Tab */}
        <TabsContent value="variants">
          <Card>
            <CardHeader>
              <CardTitle>Varian Produk</CardTitle>
            </CardHeader>
            <CardContent>
              <ProductVariantManager
                productId={productId}
                basePrice={parseInt(form.price) || 0}
              />
            </CardContent>
          </Card>
        </TabsContent>

        {/* Stock Tab */}
        <TabsContent value="stock">
          <Card>
            <CardHeader>
              <CardTitle>Manajemen Stok</CardTitle>
            </CardHeader>
            <CardContent className="space-y-6">
              <div className="grid md:grid-cols-2 gap-6">
                <div className="space-y-2">
                  <Label>Stok Saat Ini</Label>
                  <Input
                    type="number"
                    value={form.stock}
                    onChange={(e) => setForm(prev => ({ ...prev, stock: e.target.value }))}
                  />
                </div>
                <div className="space-y-2">
                  <Label>Peringatan Stok Minimum</Label>
                  <Input
                    type="number"
                    value={form.min_stock_alert}
                    onChange={(e) => setForm(prev => ({ ...prev, min_stock_alert: e.target.value }))}
                  />
                  <p className="text-xs text-muted-foreground">
                    Dapatkan notifikasi saat stok di bawah angka ini
                  </p>
                </div>
              </div>

              <StockAlerts merchantId={merchantId} />
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>
    </div>
  );
}

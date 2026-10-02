import { useState, useEffect, useCallback } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { Image, Plus, Trash2, Edit, MoreHorizontal, Eye, EyeOff, ArrowUp, ArrowDown, RefreshCw } from 'lucide-react';
import { AdminLayout } from '@/components/admin/AdminLayout';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from '@/components/ui/dialog';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { format } from 'date-fns';
import { ImageUpload } from '@/components/ui/ImageUpload';
import { useAdminCategories } from '@/hooks/useAdminCategories';
import { hideRedundantFoodRootCategories } from '@/lib/productCategories';

type BannerStatus = 'active' | 'scheduled' | 'expired' | 'inactive';

function getBannerStatus(banner: Pick<Banner, 'is_active' | 'is_approved' | 'start_date' | 'end_date'>): BannerStatus {
  if (!banner.is_active) return 'inactive';
  const now = Date.now();
  if (!banner.is_approved) return 'scheduled';
  if (new Date(banner.start_date).getTime() > now) return 'scheduled';
  if (banner.end_date && new Date(banner.end_date).getTime() < now) return 'expired';
  return 'active';
}

const bannerStatusLabels: Record<BannerStatus, string> = { active: 'Aktif', scheduled: 'Terjadwal', expired: 'Berakhir', inactive: 'Nonaktif' };
const bannerStatusVariants: Record<BannerStatus, 'default' | 'secondary' | 'destructive' | 'outline'> = { active: 'default', scheduled: 'outline', expired: 'destructive', inactive: 'secondary' };

function toDateInput(value?: string | null) {
  return value ? value.slice(0, 10) : '';
}

interface Banner {
  id: string;
  title: string | null;
  subtitle: string | null;
  image_url: string | null;
  link_url: string | null;
  is_active: boolean;
  is_approved: boolean;
  start_date: string;
  end_date: string | null;
  sort_order: number | null;
  category_id: string | null;
}

export default function AdminBannersPage() {
  const queryClient = useQueryClient();
  const { data: activeCategories = [] } = useAdminCategories();
  const mainCategories = hideRedundantFoodRootCategories(activeCategories.filter((category) => !category.parent_id));
  const [banners, setBanners] = useState<Banner[]>([]);
  const [loading, setLoading] = useState(true);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [editingBanner, setEditingBanner] = useState<Banner | null>(null);
  const [saving, setSaving] = useState(false);
  const [formData, setFormData] = useState({
    title: '',
    subtitle: '',
    image_url: '',
    link_url: '',
    category_id: '',
    is_active: true,
    start_date: new Date().toISOString().slice(0, 10),
    end_date: '',
  });

  const fetchBanners = useCallback(async () => {
    try {
      const { data, error } = await supabase
        .from('promotions')
        .select('id, title, subtitle, image_url, link_url, category_id, is_active, is_approved, start_date, end_date, sort_order')
        .eq('type', 'banner')
        .order('sort_order', { ascending: true });

      if (error) throw error;
      setBanners(data || []);
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ['homepage-banners'] }),
        queryClient.invalidateQueries({ queryKey: ['food-catalog-banners'] }),
        queryClient.invalidateQueries({ queryKey: ['category-banners'] }),
      ]);
    } catch (error) {
      console.error('Error fetching banners:', error);
      toast.error('Gagal memuat banner');
    } finally {
      setLoading(false);
    }
  }, [queryClient]);

  useEffect(() => {
    void fetchBanners();
  }, [fetchBanners]);

  const handleOpenDialog = (banner?: Banner) => {
    if (banner) {
      setEditingBanner(banner);
      setFormData({
        title: banner.title || '',
        subtitle: banner.subtitle || '',
        image_url: banner.image_url || '',
        link_url: banner.link_url || '',
        category_id: banner.category_id || '',
        is_active: banner.is_active,
        start_date: toDateInput(banner.start_date),
        end_date: toDateInput(banner.end_date),
      });
    } else {
      setEditingBanner(null);
      setFormData({
        title: '',
        subtitle: '',
        image_url: '',
        link_url: '',
        category_id: '',
        is_active: true,
        start_date: new Date().toISOString().slice(0, 10),
        end_date: '',
      });
    }
    setDialogOpen(true);
  };

  const handleSubmit = async () => {
    const title = formData.title.trim();
    const subtitle = formData.subtitle.trim();
    const linkUrl = formData.link_url.trim();
    if (title.length > 120) {
      toast.error('Judul maksimal 120 karakter');
      return;
    }
    if (subtitle.length > 300) {
      toast.error('Subtitle maksimal 300 karakter');
      return;
    }
    if (linkUrl) {
      const isRelative = linkUrl.startsWith('/') && !linkUrl.startsWith('//');
      let isAbsolute = false;
      try {
        const parsed = new URL(linkUrl);
        isAbsolute = parsed.protocol === 'http:' || parsed.protocol === 'https:';
      } catch {
        isAbsolute = false;
      }
      if (!isRelative && !isAbsolute) {
        toast.error('Link harus berupa path internal atau URL http(s) yang valid');
        return;
      }
    }
    if (formData.start_date && Number.isNaN(new Date(formData.start_date).getTime())) {
      toast.error('Tanggal mulai tidak valid');
      return;
    }
    if (formData.end_date && Number.isNaN(new Date(formData.end_date).getTime())) {
      toast.error('Tanggal berakhir tidak valid');
      return;
    }
    if (formData.start_date && formData.end_date && new Date(formData.end_date) < new Date(formData.start_date)) {
      toast.error('Tanggal berakhir harus setelah tanggal mulai');
      return;
    }

    setSaving(true);
    try {
      const targetCategoryId = formData.category_id || null;
      const categoryBannerCount = banners.filter((banner) => banner.category_id === targetCategoryId).length;
      const payload = {
        // Keep an empty string for compatibility with databases where the
        // optional-title migration has not been applied yet.
        title,
        subtitle: subtitle || null,
        image_url: formData.image_url.trim() || null,
        link_url: linkUrl || null,
        category_id: formData.category_id || null,
        is_active: formData.is_active,
        is_approved: true,
        start_date: formData.start_date ? new Date(`${formData.start_date}T00:00:00`).toISOString() : new Date().toISOString(),
        end_date: formData.end_date ? new Date(`${formData.end_date}T23:59:59`).toISOString() : null,
        type: 'banner',
        sort_order: editingBanner?.category_id === targetCategoryId
          ? editingBanner.sort_order ?? categoryBannerCount
          : categoryBannerCount,
      };

      if (editingBanner) {
        const { error } = await supabase
          .from('promotions')
          .update(payload)
          .eq('id', editingBanner.id);
        if (error) throw error;
        toast.success('Banner berhasil diperbarui');
      } else {
        const { error } = await supabase
          .from('promotions')
          .insert(payload);
        if (error) throw error;
        toast.success('Banner berhasil ditambahkan');
      }

      setDialogOpen(false);
      await fetchBanners();
    } catch (error) {
      console.error('Error saving banner:', error);
      const message = error instanceof Error
        ? error.message
        : typeof error === 'object' && error !== null && 'message' in error
          ? String(error.message)
          : 'Gagal menyimpan banner';
      toast.error(message);
    } finally {
      setSaving(false);
    }
  };

  const toggleActive = async (id: string, current: boolean) => {
    try {
      const { error } = await supabase.from('promotions').update({ is_active: !current }).eq('id', id);
      if (error) throw error;
      toast.success(current ? 'Banner dinonaktifkan' : 'Banner diaktifkan');
      await fetchBanners();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Gagal mengubah status');
    }
  };

  const deleteBanner = async (id: string) => {
    if (!confirm('Yakin ingin menghapus banner ini?')) return;
    try {
      const { error } = await supabase.from('promotions').delete().eq('id', id);
      if (error) throw error;
      toast.success('Banner dihapus');
      await fetchBanners();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Gagal menghapus banner');
    }
  };

  const moveOrder = async (id: string, direction: 'up' | 'down') => {
    const targetBanner = banners.find((banner) => banner.id === id);
    if (!targetBanner) return;
    const categoryBanners = banners.filter((banner) => banner.category_id === targetBanner.category_id);
    const index = categoryBanners.findIndex((banner) => banner.id === id);
    const newIndex = direction === 'up' ? index - 1 : index + 1;
    if (newIndex < 0 || newIndex >= categoryBanners.length) return;

    const reorderedCategoryBanners = [...categoryBanners];
    [reorderedCategoryBanners[index], reorderedCategoryBanners[newIndex]] = [reorderedCategoryBanners[newIndex], reorderedCategoryBanners[index]];
    const categoryPositions = banners.flatMap((banner, position) => (
      banner.category_id === targetBanner.category_id ? [position] : []
    ));
    const newBanners = [...banners];
    categoryPositions.forEach((position, categoryIndex) => {
      newBanners[position] = { ...reorderedCategoryBanners[categoryIndex], sort_order: categoryIndex };
    });

    try {
      const results = await Promise.all(
        reorderedCategoryBanners.map((banner, sortOrder) =>
          supabase.from('promotions').update({ sort_order: sortOrder }).eq('id', banner.id)
        )
      );
      const failed = results.find((result) => result.error);
      if (failed?.error) throw failed.error;
      setBanners(newBanners);
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ['homepage-banners'] }),
        queryClient.invalidateQueries({ queryKey: ['food-catalog-banners'] }),
        queryClient.invalidateQueries({ queryKey: ['category-banners'] }),
      ]);
    } catch {
      toast.error('Gagal mengubah urutan');
    }
  };

  return (
    <AdminLayout title="Manajemen Banner" subtitle="Kelola banner umum dan iklan per kategori">
      <div className="flex justify-between items-center mb-6">
        <div className="flex items-center gap-2">
          <Image className="h-5 w-5 text-primary" />
          <span className="text-muted-foreground">{banners.length} banner</span>
        </div>
        <div className="flex items-center gap-2">
          <Button variant="outline" size="icon" onClick={() => { setLoading(true); void fetchBanners(); }} aria-label="Muat ulang banner">
            <RefreshCw className="h-4 w-4" />
          </Button>
          <Button onClick={() => handleOpenDialog()}>
            <Plus className="h-4 w-4 mr-2" />
            Tambah Banner
          </Button>
        </div>
      </div>

      {loading ? (
        <div className="flex items-center justify-center py-20">
          <div className="animate-spin rounded-full h-10 w-10 border-2 border-primary border-t-transparent" />
        </div>
      ) : banners.length === 0 ? (
        <div className="text-center py-20 text-muted-foreground">
          <Image className="h-16 w-16 mx-auto mb-4 opacity-50" />
          <p>Belum ada banner</p>
          <Button className="mt-4" onClick={() => handleOpenDialog()}>
            Tambah Banner Pertama
          </Button>
        </div>
      ) : (
        <div className="grid gap-4">
          {banners.map((banner) => (
            <div
              key={banner.id}
              className="bg-card border border-border rounded-xl overflow-hidden flex"
            >
              <div className="w-48 h-28 bg-muted shrink-0">
                {banner.image_url ? (
                  <img
                    src={banner.image_url}
                    alt={banner.title || 'Banner promosi'}
                    className="w-full h-full object-cover"
                  />
                ) : (
                  <div className="w-full h-full flex items-center justify-center">
                    <Image className="h-8 w-8 text-muted-foreground" />
                  </div>
                )}
              </div>
              
              <div className="flex-1 p-4 flex items-center justify-between">
                <div>
                  {banner.title && <h3 className="font-semibold">{banner.title}</h3>}
                  <Badge variant="outline" className="mt-1">
                    {banner.category_id
                      ? mainCategories.find((category) => category.id === banner.category_id)?.name || 'Kategori nonaktif'
                      : 'Banner umum'}
                  </Badge>
                  {banner.subtitle && (
                    <p className="text-sm text-muted-foreground">{banner.subtitle}</p>
                  )}
                  <div className="flex flex-wrap items-center gap-2 mt-2">
                    {(() => { const status = getBannerStatus(banner); return <Badge variant={bannerStatusVariants[status]}>{bannerStatusLabels[status]}</Badge>; })()}
                    <span className="text-xs text-muted-foreground">
                      Mulai: {format(new Date(banner.start_date), 'dd/MM/yyyy')}
                    </span>
                    {banner.end_date && <span className="text-xs text-muted-foreground">Berakhir: {format(new Date(banner.end_date), 'dd/MM/yyyy')}</span>}
                  </div>
                </div>

                <div className="flex items-center gap-2">
                  <Button variant="ghost" size="icon" onClick={() => moveOrder(banner.id, 'up')} disabled={banners.filter((item) => item.category_id === banner.category_id).findIndex((item) => item.id === banner.id) === 0}>
                    <ArrowUp className="h-4 w-4" />
                  </Button>
                  <Button variant="ghost" size="icon" onClick={() => moveOrder(banner.id, 'down')} disabled={banners.filter((item) => item.category_id === banner.category_id).findIndex((item) => item.id === banner.id) === banners.filter((item) => item.category_id === banner.category_id).length - 1}>
                    <ArrowDown className="h-4 w-4" />
                  </Button>
                  
                  <DropdownMenu>
                    <DropdownMenuTrigger asChild>
                      <Button variant="ghost" size="icon">
                        <MoreHorizontal className="h-4 w-4" />
                      </Button>
                    </DropdownMenuTrigger>
                    <DropdownMenuContent align="end">
                      <DropdownMenuItem onClick={() => handleOpenDialog(banner)}>
                        <Edit className="h-4 w-4 mr-2" />
                        Edit
                      </DropdownMenuItem>
                      <DropdownMenuItem onClick={() => toggleActive(banner.id, banner.is_active)}>
                        {banner.is_active ? (
                          <><EyeOff className="h-4 w-4 mr-2" />Nonaktifkan</>
                        ) : (
                          <><Eye className="h-4 w-4 mr-2" />Aktifkan</>
                        )}
                      </DropdownMenuItem>
                      <DropdownMenuItem onClick={() => deleteBanner(banner.id)} className="text-destructive">
                        <Trash2 className="h-4 w-4 mr-2" />
                        Hapus
                      </DropdownMenuItem>
                    </DropdownMenuContent>
                  </DropdownMenu>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Improved Dialog - compact layout */}
      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent className="max-w-2xl max-h-[85vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>{editingBanner ? 'Edit Banner' : 'Tambah Banner Baru'}</DialogTitle>
            <DialogDescription>Atur gambar, teks, tautan, periode, dan kategori tujuan banner.</DialogDescription>
          </DialogHeader>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {/* Left: Image upload */}
            <div className="space-y-2">
              <Label>Gambar Banner</Label>
              <p className="text-xs text-muted-foreground">Gambar ini menjadi visual utama banner pada lokasi dan kategori yang dipilih.</p>
              <ImageUpload
                value={formData.image_url || null}
                onChange={(url) => setFormData({ ...formData, image_url: url || '' })}
                bucket="promotions"
                path="banners"
                aspectRatio="wide"
                placeholder="Klik atau tarik gambar banner ke sini"
              />
              <p className="text-[11px] text-muted-foreground">Ukuran rekomendasi: 1200 × 400 px (rasio 3:1). Maksimal 5 MB.</p>
            </div>

            {/* Right: Form fields */}
            <div className="space-y-3">
              <div>
                <Label>Judul banner (opsional)</Label>
                <Input
                  value={formData.title}
                  onChange={(e) => setFormData({ ...formData, title: e.target.value })}
                  placeholder="Judul banner"
                />
              </div>

              <div>
                <Label>Subtitle</Label>
                <Input
                  value={formData.subtitle}
                  onChange={(e) => setFormData({ ...formData, subtitle: e.target.value })}
                  placeholder="Deskripsi singkat"
                />
              </div>

              <div>
                <Label htmlFor="banner-category">Tampilkan di</Label>
                <select
                  id="banner-category"
                  value={formData.category_id}
                  onChange={(event) => setFormData({ ...formData, category_id: event.target.value })}
                  className="mt-1 flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background focus:outline-none focus:ring-2 focus:ring-ring"
                >
                  <option value="">Banner umum — halaman utama</option>
                  {editingBanner?.category_id && !mainCategories.some((category) => category.id === editingBanner.category_id) && (
                    <option value={editingBanner.category_id}>Kategori nonaktif (pertahankan target)</option>
                  )}
                  {mainCategories.map((category) => (
                    <option key={category.id} value={category.id}>{category.name}</option>
                  ))}
                </select>
                <p className="mt-1 text-[11px] text-muted-foreground">Iklan kategori tampil pada halaman kategori tersebut. Kategori mengikuti pengaturan kategori utama yang aktif.</p>
              </div>

              <div>
                <Label>Link URL</Label>
                <Input
                  value={formData.link_url}
                  onChange={(e) => setFormData({ ...formData, link_url: e.target.value })}
                  placeholder="/products atau URL"
                />
              </div>

              <div>
                <Label>Tanggal Mulai</Label>
                <Input
                  type="date"
                  value={formData.start_date}
                  onChange={(e) => setFormData({ ...formData, start_date: e.target.value })}
                />
              </div>

              <div>
                <Label>Tanggal Berakhir</Label>
                <Input
                  type="date"
                  value={formData.end_date}
                  onChange={(e) => setFormData({ ...formData, end_date: e.target.value })}
                />
                <p className="mt-1 text-[11px] text-muted-foreground">Kosongkan jika banner tidak memiliki tanggal kedaluwarsa.</p>
              </div>

              <div className="flex items-center gap-3 pt-1">
                <Switch
                  checked={formData.is_active}
                  onCheckedChange={(checked) => setFormData({ ...formData, is_active: checked })}
                />
                <Label className="cursor-pointer">Aktif</Label>
              </div>
            </div>
          </div>

          <DialogFooter className="mt-2">
            <Button variant="outline" onClick={() => setDialogOpen(false)}>Batal</Button>
            <Button onClick={() => void handleSubmit()} disabled={saving}>{saving ? 'Menyimpan...' : 'Simpan'}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </AdminLayout>
  );
}

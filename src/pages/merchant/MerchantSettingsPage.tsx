import { useState, useEffect, useCallback } from 'react';
import { Save, Store, MapPin, FileText, Loader2, CreditCard, QrCode, Bell, Shield, CheckCircle2, Link as LinkIcon, Eye, EyeOff, Navigation, Tags } from 'lucide-react';
import { MerchantLayout } from '@/components/merchant/MerchantLayout';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import { Checkbox } from '@/components/ui/checkbox';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { ImageUpload } from '@/components/ui/ImageUpload';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { useMerchantGuard } from '@/hooks/useMerchantGuard';
import { toast } from 'sonner';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useAdminCategories } from '@/hooks/useAdminCategories';
import { merchantSettingsSchema } from '@/lib/validationSchemas';
import { AddressDropdowns } from '@/components/admin/AddressDropdowns';
import { MerchantLocationPicker } from '@/components/merchant/MerchantLocationPicker';
import { fetchDistricts, fetchProvinces, fetchRegencies, fetchVillages } from '@/lib/addressApi';
import { MerchantOperatingHoursCard } from '@/components/merchant/MerchantOperatingHoursCard';

interface MerchantData {
  id: string;
  name: string;
  phone: string | null;
  address: string | null;
  province: string | null;
  city: string | null;
  district: string | null;
  subdistrict: string | null;
  location_lat: number | null;
  location_lng: number | null;
  google_maps_url: string | null;
  business_category: string | null;
  business_description: string | null;
  open_time: string | null;
  close_time: string | null;
  is_open: boolean;
  image_url: string | null;
  cover_image_url: string | null;
  order_mode: string;
  classification_price: string | null;
  bank_name: string | null;
  bank_account_number: string | null;
  bank_account_name: string | null;
  qris_image_url: string | null;
  payment_cod_enabled: boolean | null;
  payment_transfer_enabled: boolean | null;
  notification_sound_enabled: boolean | null;
  halal_status: string | null;
  halal_certificate_url: string | null;
  ktp_url: string | null;
  verifikator_code: string | null;
  slug: string | null;
}

const PRICE_CLASSIFICATIONS = [
  { value: 'UNDER_5K', label: 'Sangat Murah (< Rp 5.000)' },
  { value: 'FROM_5K_TO_10K', label: 'Murah (Rp 5.000 - Rp 10.000)' },
  { value: 'FROM_10K_TO_20K', label: 'Sedang (Rp 10.000 - Rp 20.000)' },
  { value: 'ABOVE_20K', label: 'Premium (> Rp 20.000)' },
];

export default function MerchantSettingsPage() {
  const { user } = useAuth();
  const { merchantId: guardMerchantId, loading: guardLoading } = useMerchantGuard();
  const { data: categories = [], isLoading: categoriesLoading } = useAdminCategories();
  const queryClient = useQueryClient();

  const [formData, setFormData] = useState({
    name: '', phone: '', address: '', province: '', city: '', district: '', subdistrict: '',
    province_code: '', city_code: '', district_code: '', subdistrict_code: '',
    location_lat: null as number | null, location_lng: null as number | null,
    google_maps_url: '', business_category: '',
    business_description: '', open_time: '08:00', close_time: '17:00',
    is_open: false, classification_price: '', order_mode: 'ADMIN_ASSISTED',
    bank_name: '', bank_account_number: '', bank_account_name: '',
    payment_cod_enabled: false, payment_transfer_enabled: true,
    notification_sound_enabled: true, verifikator_code: '', slug: '',
  });
  const [imageUrl, setImageUrl] = useState<string | null>(null);
  const [coverImageUrl, setCoverImageUrl] = useState<string | null>(null);
  const [qrisImageUrl, setQrisImageUrl] = useState<string | null>(null);
  const [selectedCategoryIds, setSelectedCategoryIds] = useState<string[]>([]);

  const { data: merchant, isLoading: fetchLoading } = useQuery<MerchantData | null>({
    queryKey: ['merchant-settings', guardMerchantId],
    queryFn: async () => {
      if (!guardMerchantId) return null;
      const { data, error } = await supabase
        .from('merchants')
        .select('id, name, phone, address, province, city, district, subdistrict, location_lat, location_lng, google_maps_url, business_category, business_description, open_time, close_time, is_open, image_url, cover_image_url, order_mode, classification_price, bank_name, bank_account_number, bank_account_name, qris_image_url, payment_cod_enabled, payment_transfer_enabled, notification_sound_enabled, halal_status, halal_certificate_url, ktp_url, verifikator_code, slug')
        .eq('id', guardMerchantId)
        .maybeSingle();
      if (error) throw error;
      return data || null;
    },
    enabled: !!guardMerchantId && !guardLoading,
    staleTime: 60_000,
  });

  const { isLoading: merchantCategoriesLoading } = useQuery({
    queryKey: ['merchant-categories', guardMerchantId],
    enabled: !!guardMerchantId && !guardLoading,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('merchant_categories')
        .select('category_id')
        .eq('merchant_id', guardMerchantId!);
      if (error) throw error;
      const ids = (data || []).map((row) => row.category_id as string);
      setSelectedCategoryIds(ids);
      return ids;
    },
  });

  // Populate form when merchant data loads
  useEffect(() => {
    if (!merchant) return;
    setFormData({
      name: merchant.name || '',
      phone: merchant.phone || '',
      address: merchant.address || '',
      province: merchant.province || '',
      city: merchant.city || '',
      district: merchant.district || '',
      subdistrict: merchant.subdistrict || '',
      province_code: '',
      city_code: '',
      district_code: '',
      subdistrict_code: '',
      location_lat: merchant.location_lat === null || merchant.location_lat === undefined ? null : Number(merchant.location_lat),
      location_lng: merchant.location_lng === null || merchant.location_lng === undefined ? null : Number(merchant.location_lng),
      google_maps_url: merchant.google_maps_url || '',
      business_category: merchant.business_category || '',
      business_description: merchant.business_description || '',
      open_time: merchant.open_time?.slice(0, 5) || '08:00',
      close_time: merchant.close_time?.slice(0, 5) || '17:00',
      is_open: merchant.is_open,
      classification_price: merchant.classification_price || '',
      order_mode: merchant.order_mode === 'SELF_MANAGED' ? 'SELF' : (merchant.order_mode || 'ADMIN_ASSISTED'),
      bank_name: merchant.bank_name || '',
      bank_account_number: merchant.bank_account_number || '',
      bank_account_name: merchant.bank_account_name || '',
      payment_cod_enabled: false,
      payment_transfer_enabled: merchant.payment_transfer_enabled ?? true,
      notification_sound_enabled: merchant.notification_sound_enabled ?? true,
      verifikator_code: merchant.verifikator_code || '',
      slug: merchant.slug || '',
    });
    setImageUrl(merchant.image_url);
    setCoverImageUrl(merchant.cover_image_url);
    setQrisImageUrl(merchant.qris_image_url);

    let active = true;
    const resolveAddressCodes = async () => {
      try {
        const provinces = await fetchProvinces();
        const province = provinces.find(item => item.name.trim().toLowerCase() === (merchant.province || '').trim().toLowerCase());
        if (!province) return;
        const cities = await fetchRegencies(province.code);
        const city = cities.find(item => item.name.trim().toLowerCase() === (merchant.city || '').trim().toLowerCase());
        if (!city) return;
        const districts = await fetchDistricts(city.code);
        const district = districts.find(item => item.name.trim().toLowerCase() === (merchant.district || '').trim().toLowerCase());
        if (!district) return;
        const subdistricts = await fetchVillages(district.code);
        const subdistrict = subdistricts.find(item => item.name.trim().toLowerCase() === (merchant.subdistrict || '').trim().toLowerCase());
        if (active) {
          setFormData(prev => ({
            ...prev,
            province_code: province.code,
            city_code: city.code,
            district_code: district.code,
            subdistrict_code: subdistrict?.code || '',
          }));
        }
      } catch (error) {
        console.warn('Gagal memuat kode wilayah toko:', error);
      }
    };
    void resolveAddressCodes();
    return () => { active = false; };
  }, [merchant]);

  useEffect(() => {
    if (!merchant || merchantCategoriesLoading || selectedCategoryIds.length > 0) return;
    const legacy = categories.find((category) => category.slug === merchant.business_category);
    if (legacy) setSelectedCategoryIds([legacy.id]);
  }, [merchant, merchantCategoriesLoading, selectedCategoryIds.length, categories]);

  const saveMutation = useMutation({
    mutationFn: async () => {
      if (!merchant) return;
      if (selectedCategoryIds.length === 0) throw new Error('Pilih minimal satu kategori usaha yang tersedia.');
      if (selectedCategoryIds.some((id) => !categories.some((category) => category.id === id))) {
        throw new Error('Salah satu kategori tidak aktif atau sudah dihapus admin. Pilih ulang kategori usaha.');
      }
      const parsed = merchantSettingsSchema.safeParse(formData);
      if (!parsed.success) {
        throw new Error(parsed.error.issues[0]?.message || 'Periksa kembali data pengaturan toko.');
      }
      const settings = parsed.data;
      const { error } = await supabase.rpc('update_merchant_settings_atomic', {
        p_merchant_id: merchant.id,
        p_settings: {
          ...settings,
          // COD is temporarily disabled for marketplace checkout.
          payment_cod_enabled: false,
          image_url: imageUrl || null,
          cover_image_url: coverImageUrl || null,
          qris_image_url: qrisImageUrl || null,
        },
        p_category_ids: selectedCategoryIds,
      });
      if (error) throw error;
    },
    onSuccess: () => {
      toast.success('Pengaturan toko berhasil disimpan. COD belum tersedia di marketplace.');
      queryClient.invalidateQueries({ queryKey: ['merchant-settings', guardMerchantId] });
      queryClient.invalidateQueries({ queryKey: ['merchant-profile', user?.id] });
      queryClient.invalidateQueries({ queryKey: ['merchant-categories', guardMerchantId] });
    },
    onError: (error: unknown) => {
      const code = (error as { code?: string })?.code;
      if (code === '23505') {
        toast.error('Slug toko sudah digunakan. Silakan pilih slug lain.');
      } else if (code === '23514') {
        toast.error('Nilai pengaturan toko tidak valid. Periksa jam, pembayaran, dan mode pesanan.');
      } else {
        const fields = error as { message?: string; details?: string; hint?: string };
        const message = error instanceof Error
          ? error.message
          : fields?.message || fields?.details || fields?.hint || 'Periksa kembali data pengaturan toko.';
        toast.error(`Gagal menyimpan pengaturan: ${message}`);
      }
    },
  });

  const handleChange = (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => {
    setFormData(prev => ({ ...prev, [e.target.name]: e.target.value }));
  };

  const handleLocationChange = useCallback((location: { lat: number; lng: number }) => {
    setFormData(prev => ({ ...prev, location_lat: location.lat, location_lng: location.lng }));
  }, []);

  const handleAddressChange = useCallback((data: {
    provinceCode: string;
    provinceName: string;
    regencyCode: string;
    regencyName: string;
    districtCode: string;
    districtName: string;
    villageCode: string;
    villageName: string;
  }) => {
    setFormData(prev => ({
      ...prev,
      province_code: data.provinceCode,
      province: data.provinceName,
      city_code: data.regencyCode,
      city: data.regencyName,
      district_code: data.districtCode,
      district: data.districtName,
      subdistrict_code: data.villageCode,
      subdistrict: data.villageName,
    }));
  }, []);

  const loading = guardLoading || fetchLoading;

  if (loading) {
    return (
      <MerchantLayout title="Pengaturan Toko" subtitle="Kelola informasi toko Anda">
        <div className="flex items-center justify-center py-20">
          <div className="animate-spin rounded-full h-10 w-10 border-2 border-primary border-t-transparent" />
        </div>
      </MerchantLayout>
    );
  }

  if (!merchant) {
    return (
      <MerchantLayout title="Pengaturan Toko" subtitle="Kelola informasi toko Anda">
        <div className="text-center py-20"><p className="text-muted-foreground">Toko tidak ditemukan</p></div>
      </MerchantLayout>
    );
  }

  return (
    <MerchantLayout title="Pengaturan Toko" subtitle="Kelola informasi toko Anda">
      <form onSubmit={e => { e.preventDefault(); saveMutation.mutate(); }} className="space-y-6 max-w-2xl">
        <Card>
          <CardHeader>
            <CardTitle className="text-base flex items-center gap-2"><Store className="h-5 w-5" />Foto Toko</CardTitle>
            <CardDescription>Foto utama yang ditampilkan di halaman toko</CardDescription>
          </CardHeader>
          <CardContent className="grid gap-5 sm:grid-cols-2">
            <div className="space-y-2">
              <Label>Foto Profil</Label>
              <ImageUpload value={imageUrl} onChange={setImageUrl} bucket="merchant-images" path={`store/${merchant.id}/profile`} aspectRatio="square" stableFileName placeholder="Upload foto profil toko" />
              <p className="text-xs text-muted-foreground">Foto yang mewakili toko di kartu dan daftar merchant.</p>
            </div>
            <div className="space-y-2">
              <Label>Foto Sampul</Label>
              <ImageUpload value={coverImageUrl} onChange={setCoverImageUrl} bucket="merchant-images" path={`store/${merchant.id}/cover`} aspectRatio="wide" stableFileName placeholder="Upload foto sampul toko" />
              <p className="text-xs text-muted-foreground">Banner yang tampil di bagian atas profil publik toko.</p>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-base flex items-center gap-2"><FileText className="h-5 w-5" />Informasi Dasar</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="name">Nama Toko</Label>
              <Input id="name" name="name" value={formData.name} onChange={handleChange} maxLength={100} required />
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label htmlFor="phone">No. Telepon</Label>
                <Input id="phone" name="phone" type="tel" inputMode="tel" value={formData.phone} onChange={handleChange} maxLength={30} />
              </div>
              <div className="space-y-2 col-span-2">
                <Label className="flex items-center gap-2"><Tags className="h-4 w-4" />Kategori Bisnis</Label>
                <div className="rounded-lg border bg-muted/20 p-3">
                  <p className="text-xs text-muted-foreground mb-3">Pilih semua kategori yang relevan agar toko mudah ditemukan pelanggan.</p>
                  <div className="grid gap-2 sm:grid-cols-2">
                    {categories.map((category) => (
                      <label key={category.id} className="flex items-center gap-3 rounded-md border bg-background px-3 py-2 cursor-pointer hover:border-primary/50">
                        <Checkbox checked={selectedCategoryIds.includes(category.id)} onCheckedChange={(checked) => setSelectedCategoryIds((prev) => checked ? [...new Set([...prev, category.id])] : prev.filter((id) => id !== category.id))} />
                        <span className="text-sm">{category.icon ? `${category.icon} ` : ''}{category.name}</span>
                      </label>
                    ))}
                  </div>
                  {categoriesLoading && <p className="text-xs text-muted-foreground mt-2">Memuat kategori...</p>}
                </div>
              </div>
            </div>
            <div className="space-y-2">
              <Label htmlFor="business_description">Deskripsi Toko</Label>
              <Textarea id="business_description" name="business_description" value={formData.business_description} onChange={handleChange} maxLength={2000} rows={3} placeholder="Ceritakan tentang toko Anda..." />
            </div>
              <div className="space-y-2">
                <Label htmlFor="verifikator_code">Kode Verifikator</Label>
              <div className="relative">
                <Shield className="absolute left-3 top-2.5 h-4 w-4 text-muted-foreground" />
                  <Input id="verifikator_code" value={formData.verifikator_code} readOnly disabled className="pl-9 uppercase" placeholder="Belum ditetapkan" />
              </div>
               <p className="text-[10px] text-muted-foreground">Kode ini ditetapkan oleh verifikator dan tidak dapat diubah dari halaman toko.</p>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-base flex items-center gap-2"><LinkIcon className="h-5 w-5" />Link Toko</CardTitle>
            <CardDescription>URL unik untuk membagikan toko Anda</CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="slug">Slug Toko</Label>
              <div className="flex items-center gap-2">
                <span className="text-sm text-muted-foreground whitespace-nowrap">{window.location.origin}/s/</span>
                <Input id="slug" name="slug" value={formData.slug}
                  onChange={e => { const val = e.target.value.toLowerCase().replace(/[^a-z0-9-]/g, '').slice(0, 80); setFormData(p => ({ ...p, slug: val })); }}
                  placeholder="nama-toko" className="font-mono" />
              </div>
              <p className="text-[10px] text-muted-foreground">Hanya huruf kecil, angka, dan strip (-). Contoh: kedai-maju</p>
            </div>
            {formData.slug && (
              <div className="bg-primary/5 border border-primary/20 rounded-lg p-3">
                <p className="text-xs text-primary font-medium">Link toko Anda:</p>
                <p className="text-sm font-mono text-foreground mt-1">{window.location.origin}/s/{formData.slug}</p>
              </div>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-base flex items-center gap-2"><MapPin className="h-5 w-5" />Lokasi</CardTitle>
              <CardDescription>Lengkapi alamat agar pelanggan dan kurir dapat menemukan toko dengan tepat.</CardDescription>
          </CardHeader>
            <CardContent className="space-y-5">
              <div className="rounded-lg border border-primary/20 bg-primary/5 p-3 text-sm text-muted-foreground">
                <p className="font-medium text-foreground">Alamat pengantaran</p>
                <p className="mt-1 text-xs">Isi detail jalan/nomor rumah, lalu pilih wilayah administratif. Data ini dipakai di profil toko dan membantu penentuan pengiriman.</p>
              </div>
              <div className="space-y-2">
                <Label htmlFor="address">Alamat Jalan & Detail <span className="text-destructive">*</span></Label>
                <Textarea id="address" name="address" value={formData.address} onChange={handleChange} maxLength={500} rows={3} required placeholder="Contoh: Jl. Siliwangi No. 12, RT 02/RW 04, dekat Pasar..." />
                <p className="text-xs text-muted-foreground">{formData.address.length}/500 karakter · Minimal 10 karakter</p>
              </div>
              <AddressDropdowns
                provinceCode={formData.province_code}
                provinceName={formData.province}
                regencyCode={formData.city_code}
                regencyName={formData.city}
                districtCode={formData.district_code}
                districtName={formData.district}
                villageCode={formData.subdistrict_code}
                villageName={formData.subdistrict}
                onChange={handleAddressChange}
              />
              <div className="space-y-3 border-t pt-4">
                <div className="flex items-center gap-2">
                  <Navigation className="h-4 w-4 text-primary" />
                  <div>
                    <Label>Titik Lokasi Toko</Label>
                    <p className="text-xs text-muted-foreground">Klik peta atau gunakan lokasi perangkat. Opsional, tetapi disarankan.</p>
                  </div>
                </div>
                <MerchantLocationPicker
                  value={formData.location_lat !== null && formData.location_lng !== null
                    ? { lat: formData.location_lat, lng: formData.location_lng }
                    : null}
                  onChange={handleLocationChange}
                />
              </div>
              <div className="space-y-2 border-t pt-4">
                <Label htmlFor="google_maps_url">Link Google Maps <span className="font-normal text-muted-foreground">(opsional)</span></Label>
                <Input
                  id="google_maps_url"
                  name="google_maps_url"
                  type="url"
                  value={formData.google_maps_url}
                  onChange={handleChange}
                  maxLength={2048}
                  placeholder="https://maps.google.com/?q=..."
                />
                <p className="text-xs text-muted-foreground">Gunakan tombol Share di Google Maps lalu tempel link-nya. Link ini tampil sebagai tombol peta di profil toko.</p>
              </div>
            </CardContent>
        </Card>

        {formData.business_category === 'kuliner' && (
          <Card>
            <CardHeader>
              <CardTitle className="text-base flex items-center gap-2"><Shield className="h-5 w-5" />Sertifikasi Halal</CardTitle>
              <CardDescription>Status kehalalan usaha kuliner Anda</CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="flex items-center justify-between p-3 bg-muted rounded-lg">
                <div className="text-sm font-medium">Status Saat Ini:</div>
                <div className={`text-xs font-bold px-2 py-1 rounded-full ${
                  merchant.halal_status === 'VERIFIED' ? 'bg-green-100 text-green-700' :
                  merchant.halal_status === 'PENDING_VERIFICATION' ? 'bg-yellow-100 text-yellow-700' :
                  merchant.halal_status === 'REQUESTED' ? 'bg-blue-100 text-blue-700' : 'bg-gray-100 text-gray-700'
                }`}>
                  {merchant.halal_status === 'VERIFIED' ? 'TERVERIFIKASI' :
                   merchant.halal_status === 'PENDING_VERIFICATION' ? 'MENUNGGU VERIFIKASI' :
                   merchant.halal_status === 'REQUESTED' ? 'PENGAJUAN BARU' : 'BELUM ADA'}
                </div>
              </div>
              {merchant.halal_certificate_url && (
                <div className="space-y-2">
                  <Label>Sertifikat Halal</Label>
                  <div className="relative aspect-video rounded-lg overflow-hidden border">
                    <img src={merchant.halal_certificate_url} alt="Sertifikat Halal" className="object-cover w-full h-full" />
                  </div>
                </div>
              )}
              {merchant.halal_status === 'NONE' && (
                <div className="bg-primary/5 border border-primary/20 rounded-lg p-3 flex gap-3 items-start">
                  <CheckCircle2 className="w-5 h-5 text-primary shrink-0 mt-0.5" />
                  <div className="text-xs">
                    <p className="font-bold text-primary">Tingkatkan Kepercayaan Pelanggan!</p>
                    <p className="text-muted-foreground">Ajukan sertifikasi halal gratis melalui admin atau unggah sertifikat jika sudah punya.</p>
                  </div>
                </div>
              )}
            </CardContent>
          </Card>
        )}

        <MerchantOperatingHoursCard merchantId={merchant.id} />

        <Card>
          <CardHeader>
            <CardTitle className="text-base flex items-center gap-2"><CreditCard className="h-5 w-5" />Pengaturan Pembayaran</CardTitle>
            <CardDescription>Kelola rekening bank dan QRIS untuk menerima pembayaran non-tunai</CardDescription>
          </CardHeader>
          <CardContent className="space-y-6">
            <div role="status" className="rounded-lg border border-warning/30 bg-warning/5 p-3">
              <p className="text-sm font-medium">COD belum tersedia</p>
              <p className="mt-1 text-xs text-muted-foreground">
                Pembayaran tunai saat barang diterima sedang dinonaktifkan untuk marketplace. Pengaturan toko tidak dapat mengaktifkan COD; metode ini akan tetap nonaktif saat Anda menyimpan.
              </p>
            </div>
            <div className="space-y-3">
              {[
                { key: 'payment_transfer_enabled', label: 'Transfer Bank & QRIS', desc: 'Terima pembayaran via transfer dan QRIS' },
              ].map(({ key, label, desc }) => (
                <div key={key} className="flex items-center justify-between p-3 bg-secondary/50 rounded-lg">
                  <div>
                    <p className="font-medium text-sm">{label}</p>
                    <p className="text-xs text-muted-foreground">{desc}</p>
                  </div>
                  <Switch
                    checked={formData[key as keyof typeof formData] as boolean}
                    onCheckedChange={v => setFormData(p => ({ ...p, [key]: v }))}
                  />
                </div>
              ))}
            </div>
            <div className="space-y-4 border-t pt-4">
              <h4 className="font-medium text-sm flex items-center gap-2"><CreditCard className="h-4 w-4" />Rekening Bank</h4>
              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label>Nama Bank</Label>
                  <Input name="bank_name" value={formData.bank_name} onChange={handleChange} maxLength={100} placeholder="Contoh: BRI, BCA, Mandiri" />
                </div>
                <div className="space-y-2">
                  <Label>Nomor Rekening</Label>
                  <Input name="bank_account_number" value={formData.bank_account_number} onChange={handleChange} maxLength={50} inputMode="numeric" placeholder="Nomor rekening" />
                </div>
              </div>
              <div className="space-y-2">
                <Label>Atas Nama</Label>
                <Input name="bank_account_name" value={formData.bank_account_name} onChange={handleChange} maxLength={150} placeholder="Nama pemilik rekening" />
              </div>
              {!formData.bank_name && !formData.bank_account_number && (
                <p className="text-xs text-muted-foreground bg-muted p-2 rounded">💡 Jika tidak diisi, akan menggunakan rekening admin sebagai default</p>
              )}
            </div>
            <div className="space-y-4 border-t pt-4">
              <h4 className="font-medium text-sm flex items-center gap-2"><QrCode className="h-4 w-4" />QRIS</h4>
              <ImageUpload value={qrisImageUrl} onChange={setQrisImageUrl} bucket="merchant-images" path={`qris/${merchant.id}`} placeholder="Upload gambar QRIS" stableFileName />
              {!qrisImageUrl && (
                <p className="text-xs text-muted-foreground bg-muted p-2 rounded">💡 Jika tidak diisi, akan menggunakan QRIS admin sebagai default</p>
              )}
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-base flex items-center gap-2"><Bell className="h-5 w-5" />Notifikasi</CardTitle>
            <CardDescription>Atur suara notifikasi pesanan masuk</CardDescription>
          </CardHeader>
          <CardContent>
            <div className="flex items-center justify-between p-3 bg-secondary/50 rounded-lg">
              <div>
                <p className="font-medium text-sm">Suara Notifikasi Pesanan Baru</p>
                <p className="text-xs text-muted-foreground">Bunyikan suara saat pesanan baru masuk</p>
              </div>
              <Switch checked={formData.notification_sound_enabled} onCheckedChange={v => setFormData(p => ({ ...p, notification_sound_enabled: v }))} />
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-base flex items-center gap-2"><Store className="h-5 w-5" />Status Toko</CardTitle>
            <CardDescription>Kontrol apakah toko tampil sebagai buka bagi pelanggan.</CardDescription>
          </CardHeader>
          <CardContent>
            <div className="flex items-center justify-between p-3 bg-secondary/50 rounded-lg">
              <div className="flex items-center gap-3">
                {formData.is_open ? <Eye className="h-4 w-4 text-emerald-600" /> : <EyeOff className="h-4 w-4 text-muted-foreground" />}
                <div>
                  <p className="font-medium text-sm">{formData.is_open ? 'Toko sedang buka' : 'Toko sedang tutup'}</p>
                  <p className="text-xs text-muted-foreground">Pelanggan akan melihat status ini di halaman toko.</p>
                </div>
              </div>
              <Switch checked={formData.is_open} onCheckedChange={v => setFormData(p => ({ ...p, is_open: v }))} />
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader><CardTitle className="text-base">Pengaturan Harga & Pesanan</CardTitle></CardHeader>
          <CardContent className="space-y-4">
            <div className="space-y-2">
              <Label>Klasifikasi Harga</Label>
              <Select value={formData.classification_price} onValueChange={v => setFormData(p => ({ ...p, classification_price: v }))}>
                <SelectTrigger><SelectValue placeholder="Pilih klasifikasi" /></SelectTrigger>
                <SelectContent>
                  {PRICE_CLASSIFICATIONS.map(cls => <SelectItem key={cls.value} value={cls.value}>{cls.label}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-2">
              <Label>Mode Pesanan</Label>
              <Select value={formData.order_mode} onValueChange={v => setFormData(p => ({ ...p, order_mode: v }))}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="ADMIN_ASSISTED">Dibantu Admin</SelectItem>
                  <SelectItem value="SELF">Kelola Sendiri</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </CardContent>
        </Card>

        <Button type="submit" className="w-full" disabled={saveMutation.isPending}>
          {saveMutation.isPending ? <><Loader2 className="h-4 w-4 mr-2 animate-spin" />Menyimpan...</> : <><Save className="h-4 w-4 mr-2" />Simpan Pengaturan</>}
        </Button>
      </form>
    </MerchantLayout>
  );
}

import { useState, useRef } from 'react';
import { Loader2, Camera, User, LocateFixed, MapPin } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { AddressSelector, formatFullAddress, createEmptyAddressData, type AddressData } from '@/components/AddressSelector';
import { PhoneInput } from '@/components/ui/PhoneInput';
import { supabase } from '@/integrations/supabase/client';
import { toast } from '@/hooks/use-toast';
import { isValidIndonesianPhone } from '@/lib/phoneValidation';
import { isValidKtpNumber, normalizeKtpNumber } from '@/lib/identityValidation';

interface ProfileEditorProps {
  userId: string;
  initialData: {
    full_name: string;
    phone: string | null;
    address: string | null;
    avatar_url?: string | null;
    province_id?: string | null;
    province_name?: string | null;
    city_id?: string | null;
    city_name?: string | null;
    district_id?: string | null;
    district_name?: string | null;
    village_id?: string | null;
    village_name?: string | null;
    address_detail?: string | null;
    ktp_number?: string | null;
  };
  onSave: (data: { full_name: string; phone: string | null; address: string | null; avatar_url?: string | null; ktp_number?: string | null }) => void;
  onCancel: () => void;
  forceCompletion?: boolean;
  requireCourierProfile?: boolean;
  requireMerchantProfile?: boolean;
}

export function ProfileEditor({ userId, initialData, onSave, onCancel, forceCompletion = false, requireCourierProfile = false, requireMerchantProfile = false }: ProfileEditorProps) {
  const [saving, setSaving] = useState(false);
  const [uploadingAvatar, setUploadingAvatar] = useState(false);
  const [avatarUrl, setAvatarUrl] = useState(initialData.avatar_url || '');
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [mapsUrl, setMapsUrl] = useState(() => {
    const match = initialData.address?.match(/https?:\/\/(?:www\.)?google\.com\/maps\?q=[^\s]+/i);
    return match?.[0] || '';
  });
  const [locationLoading, setLocationLoading] = useState(false);
  const [locationError, setLocationError] = useState<string | null>(null);
  const [gpsUnavailable, setGpsUnavailable] = useState(false);
  const [fullName, setFullName] = useState(initialData.full_name || '');
  const [phone, setPhone] = useState(initialData.phone || '');
  const [ktpNumber, setKtpNumber] = useState(initialData.ktp_number || '');
  const [phoneValid, setPhoneValid] = useState(true);
  const [addressData, setAddressData] = useState<AddressData>(() => {
    // Initialize with stored address components if available
    if (initialData.province_id) {
      return {
        province: initialData.province_id || '',
        provinceName: initialData.province_name || '',
        city: initialData.city_id || '',
        cityName: initialData.city_name || '',
        district: initialData.district_id || '',
        districtName: initialData.district_name || '',
        village: initialData.village_id || '',
        villageName: initialData.village_name || '',
        detail: initialData.address_detail || '',
      };
    }
    return createEmptyAddressData();
  });

  const handlePhoneValidation = (isValid: boolean) => {
    setPhoneValid(isValid || !phone);
  };

  const handleGetCurrentLocation = () => {
    if (!navigator.geolocation) {
      setGpsUnavailable(true);
      setLocationError('Browser ini tidak mendukung GPS. Gunakan browser versi terbaru.');
      return;
    }
    setLocationLoading(true);
    setLocationError(null);
    navigator.geolocation.getCurrentPosition(
      ({ coords }) => {
        setMapsUrl(`https://www.google.com/maps?q=${coords.latitude},${coords.longitude}`);
        setGpsUnavailable(false);
        setLocationLoading(false);
      },
      (error) => {
        setGpsUnavailable(true);
        setLocationLoading(false);
        setLocationError(
          error.code === error.PERMISSION_DENIED
            ? 'Izin lokasi ditolak. Aktifkan GPS dan izinkan akses lokasi di browser.'
            : 'Lokasi tidak dapat diambil. Pastikan GPS aktif lalu coba lagi.',
        );
      },
      { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 },
    );
  };

  const isGoogleMapsUrl = (value: string) => {
    try {
      const url = new URL(value);
      return (
        (url.protocol === 'https:' || url.protocol === 'http:') &&
        (url.hostname === 'google.com' || url.hostname.endsWith('.google.com') || url.hostname === 'maps.app.goo.gl') &&
        (url.hostname === 'maps.app.goo.gl' || url.pathname.startsWith('/maps'))
      );
    } catch {
      return false;
    }
  };

  const handleAvatarUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    if (!file.type.startsWith('image/')) {
      toast({ title: 'File harus berupa foto', variant: 'destructive' });
      return;
    }

    if (file.size > 2 * 1024 * 1024) {
      toast({ title: 'Ukuran file maksimal 2MB', variant: 'destructive' });
      return;
    }

    setUploadingAvatar(true);
    try {
      const ext = file.name.split('.').pop()?.toLowerCase() || 'jpg';
      const filePath = `${userId}/avatar.${ext}`;

      const { error: uploadError } = await supabase.storage
        .from('profile-images')
        .upload(filePath, file, { upsert: true });

      if (uploadError) throw uploadError;

      const { data: { publicUrl } } = supabase.storage
        .from('profile-images')
        .getPublicUrl(filePath);

      setAvatarUrl(publicUrl);

      // Update profile immediately
      const { error: profileError } = await supabase
        .from('profiles')
        .update({ avatar_url: publicUrl })
        .eq('user_id', userId);

      if (profileError) throw profileError;

      toast({ title: 'Foto profil selfie berhasil diperbarui' });
    } catch (error) {
      console.error('Avatar upload error:', error);
      toast({ title: 'Gagal mengupload foto', variant: 'destructive' });
    } finally {
      setUploadingAvatar(false);
    }
  };

  const handleSave = async () => {
    if (!fullName.trim()) {
      toast({
        title: 'Nama lengkap wajib diisi',
        variant: 'destructive',
      });
      return;
    }

    if (phone && !isValidIndonesianPhone(phone)) {
      toast({
        title: 'Format nomor telepon tidak valid',
        description: 'Gunakan format 08xx-xxxx-xxxx',
        variant: 'destructive',
      });
      return;
    }

    if (requireCourierProfile && !phone.trim()) {
      toast({
        title: 'Nomor WhatsApp wajib diisi',
        description: 'Gunakan nomor WhatsApp yang aktif agar pelanggan dan sistem dapat menghubungi Anda.',
        variant: 'destructive',
      });
      return;
    }

    if (requireMerchantProfile && !phone.trim()) {
      toast({
        title: 'Nomor WhatsApp wajib diisi',
        description: 'Gunakan nomor WhatsApp yang aktif agar pelanggan dan sistem dapat menghubungi Anda.',
        variant: 'destructive',
      });
      return;
    }

    if (requireCourierProfile && !avatarUrl) {
      toast({
        title: 'Foto profil wajib ditambahkan',
        description: 'Tambahkan foto profil yang jelas agar pelanggan dapat mengenali kurir.',
        variant: 'destructive',
      });
      return;
    }

    if (requireMerchantProfile && !isValidKtpNumber(ktpNumber)) {
      toast({
        title: 'Nomor KTP wajib diisi',
        description: 'Masukkan 16 digit nomor KTP pemilik akun merchant.',
        variant: 'destructive',
      });
      return;
    }

    if (requireMerchantProfile && !avatarUrl) {
      toast({
        title: 'Foto profil akun wajib ditambahkan',
        description: 'Unggah foto profil pemilik akun, bukan foto toko.',
        variant: 'destructive',
      });
      return;
    }

    const hasAnyAddressValue = Boolean(
      addressData.province || addressData.city || addressData.district || addressData.village || addressData.detail.trim(),
    );
    const hasCompleteAddress = Boolean(
      addressData.province && addressData.city && addressData.district && addressData.village && addressData.detail.trim(),
    );
    if (hasAnyAddressValue && !hasCompleteAddress) {
      toast({
        title: 'Alamat belum lengkap',
        description: 'Lengkapi wilayah hingga desa/kelurahan, atau kosongkan alamat untuk menyimpannya nanti.',
        variant: 'destructive',
      });
      return;
    }
    if (mapsUrl && !isGoogleMapsUrl(mapsUrl)) {
      toast({
        title: 'URL Google Maps tidak valid',
        description: 'Gunakan URL lokasi Google Maps yang dihasilkan dari GPS atau tautan Google Maps yang valid.',
        variant: 'destructive',
      });
      return;
    }

    setSaving(true);

    try {
      // Format the full address from the selector
      const formattedAddress = hasCompleteAddress ? formatFullAddress(addressData) : '';
      const addressWithMapsUrl = formattedAddress && mapsUrl
        ? `${formattedAddress}\nGoogle Maps: ${mapsUrl}`
        : formattedAddress || null;

      const { error } = await supabase
        .from('profiles')
        .update({
          full_name: fullName.trim(),
          phone: phone.trim() || null,
          ktp_number: ktpNumber.trim() || null,
          address: addressWithMapsUrl || null,
          province_id: hasCompleteAddress ? addressData.province : null,
          province_name: hasCompleteAddress ? addressData.provinceName : null,
          city_id: hasCompleteAddress ? addressData.city : null,
          city_name: hasCompleteAddress ? addressData.cityName : null,
          district_id: hasCompleteAddress ? addressData.district : null,
          district_name: hasCompleteAddress ? addressData.districtName : null,
          village_id: hasCompleteAddress ? addressData.village : null,
          village_name: hasCompleteAddress ? addressData.villageName : null,
          address_detail: hasCompleteAddress ? addressData.detail : null,
        })
        .eq('user_id', userId);

      if (error) throw error;

      onSave({
        full_name: fullName.trim(),
        phone: phone.trim() || null,
        address: addressWithMapsUrl,
        avatar_url: avatarUrl || null,
        ktp_number: ktpNumber.trim() || null,
      });

      toast({ title: 'Profil berhasil diperbarui' });
    } catch (error) {
      console.error('Error updating profile:', error);
      toast({
        title: 'Gagal memperbarui profil',
        variant: 'destructive',
      });
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="space-y-4">
      {forceCompletion && (
        <div className="rounded-lg border border-primary/20 bg-primary/5 p-3 text-sm text-foreground">
          {requireCourierProfile
            ? 'Foto profil dan nomor WhatsApp aktif wajib untuk menggunakan fitur kerja kurir.'
            : requireMerchantProfile
              ? 'Foto profil akun, nomor KTP, dan nomor WhatsApp aktif wajib untuk menggunakan fitur kerja merchant.'
            : 'Lengkapi alamat atau tambahkan foto selfie kapan saja jika fitur tertentu membutuhkannya.'}
        </div>
      )}
      {/* Optional profile photo */}
      <div className="space-y-2">
        <Label>Foto Profil {(requireCourierProfile || requireMerchantProfile) && <span className="text-destructive">*</span>}{!(requireCourierProfile || requireMerchantProfile) && <span className="font-normal text-muted-foreground">(opsional)</span>}</Label>
        <p className="text-xs text-muted-foreground">{requireCourierProfile || requireMerchantProfile ? 'Gunakan foto profil akun yang jelas, bukan foto toko. Maksimal 2MB.' : 'Tambahkan foto diri yang jelas bila Anda nyaman. Maksimal 2MB.'}</p>
        <div className="flex justify-center">
        <div className="relative">
          <div className="w-20 h-20 rounded-full bg-primary/10 flex items-center justify-center overflow-hidden border-2 border-border">
            {avatarUrl ? (
              <img src={avatarUrl} alt="Avatar" className="w-full h-full object-cover" />
            ) : (
              <User className="h-10 w-10 text-primary" />
            )}
            {uploadingAvatar && (
              <div className="absolute inset-0 bg-background/60 flex items-center justify-center rounded-full">
                <Loader2 className="h-5 w-5 animate-spin text-primary" />
              </div>
            )}
          </div>
          <button
            type="button"
            onClick={() => fileInputRef.current?.click()}
            className="absolute -bottom-1 -right-1 w-7 h-7 bg-primary text-primary-foreground rounded-full flex items-center justify-center shadow-md hover:opacity-90 transition"
            disabled={uploadingAvatar}
          >
            <Camera className="h-3.5 w-3.5" />
          </button>
          <input
            ref={fileInputRef}
            type="file"
            accept="image/*"
            className="hidden"
            onChange={handleAvatarUpload}
          />
        </div>
      </div>
      </div>

      <div className="space-y-2">
        <Label>Nama Lengkap</Label>
        <Input
          value={fullName}
          onChange={(e) => setFullName(e.target.value)}
          placeholder="Nama lengkap"
        />
      </div>

      <div className="space-y-2">
        <Label>No. WhatsApp {(requireCourierProfile || requireMerchantProfile) && <span className="text-destructive">*</span>}{!(requireCourierProfile || requireMerchantProfile) && <span className="font-normal text-muted-foreground">(opsional)</span>}</Label>
        <PhoneInput
          value={phone}
          onChange={setPhone}
          onValidationChange={handlePhoneValidation}
          disabled={saving}
        />
      </div>

      {requireMerchantProfile && (
        <div className="space-y-2">
          <Label htmlFor="ktp-number">Nomor KTP <span className="text-destructive">*</span></Label>
          <Input
            id="ktp-number"
            value={ktpNumber}
            onChange={(event) => setKtpNumber(normalizeKtpNumber(event.target.value))}
            placeholder="16 digit nomor KTP"
            inputMode="numeric"
            maxLength={16}
            autoComplete="off"
            disabled={saving}
          />
          <p className="text-xs text-muted-foreground">Nomor KTP pemilik akun merchant, bukan nomor identitas toko.</p>
        </div>
      )}

      <div className="space-y-2">
        <Label>Alamat</Label>
        <AddressSelector
          value={addressData}
          onChange={setAddressData}
          disabled={saving}
        />
      </div>

      <div className="space-y-2 rounded-lg border border-primary/20 bg-primary/5 p-3">
        <div className="flex items-center justify-between gap-3">
          <div>
            <Label className="flex items-center gap-2"><MapPin className="h-4 w-4 text-primary" /> Lokasi Google Maps <span className="font-normal text-muted-foreground">(opsional)</span></Label>
            <p className="mt-1 text-xs text-muted-foreground">Ambil otomatis dari GPS atau masukkan tautan Google Maps. Boleh dikosongkan.</p>
          </div>
          <Button type="button" variant="outline" size="sm" onClick={handleGetCurrentLocation} disabled={saving || locationLoading}>
            {locationLoading ? <Loader2 className="h-4 w-4 animate-spin" /> : <><LocateFixed className="mr-1 h-4 w-4" /> {gpsUnavailable ? 'Coba GPS lagi' : 'Aktifkan GPS'}</>}
          </Button>
        </div>
        <div className="space-y-1.5 rounded-md border border-dashed border-border bg-background/60 p-2.5">
            <Label htmlFor="manual-google-maps-url" className="text-xs">URL Google Maps manual</Label>
            <Input
              id="manual-google-maps-url"
              value={mapsUrl}
              onChange={(event) => {
                setMapsUrl(event.target.value);
                setLocationError(null);
              }}
              placeholder="https://www.google.com/maps?q=latitude,longitude"
              type="url"
              inputMode="url"
              disabled={saving}
              aria-label="URL lokasi Google Maps manual"
            />
            <p className="text-[11px] leading-relaxed text-muted-foreground">Buka Google Maps, pilih lokasi, tekan Bagikan, lalu tempel tautannya di sini.</p>
        </div>
        {mapsUrl && <p className="break-all text-xs text-green-700" aria-live="polite">Lokasi siap disimpan: {mapsUrl}</p>}
        {locationError && <p className="text-xs text-destructive" role="alert">{locationError}</p>}
      </div>

      <div className="flex gap-2 pt-2">
        {!forceCompletion && (
          <Button
            variant="outline"
            onClick={onCancel}
            className="flex-1"
            disabled={saving}
          >
            Batal
          </Button>
        )}
        <Button
          onClick={handleSave}
          className="flex-1"
          disabled={saving || uploadingAvatar || (!phoneValid && !!phone)}
        >
          {saving ? <Loader2 className="h-4 w-4 animate-spin" /> : 'Simpan'}
        </Button>
      </div>
    </div>
  );
}

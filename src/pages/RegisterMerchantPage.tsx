import { useState, useEffect, useCallback, useRef } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { 
  Store, Phone, MapPin, CheckCircle,
  Tag, Building, AlertCircle, Check, Loader2, Save, Trash2
} from 'lucide-react';
import { PageHeader } from '../components/layout/PageHeader';
import { BottomNav } from '../components/layout/BottomNav';
import { Button } from '../components/ui/button';
import { useAuth } from '../contexts/AuthContext';
import { Input } from '../components/ui/input';
import { Textarea } from '../components/ui/textarea';
import { Label } from '../components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '../components/ui/select';
import { Checkbox } from '../components/ui/checkbox';
import { supabase } from '../integrations/supabase/client';
import { toast } from 'sonner';
import { 
  fetchProvinces, fetchRegencies, fetchDistricts, fetchVillages,
  type Region
} from '../lib/addressApi';
import type { Village } from '../types';
import { MerchantLocationPicker } from '../components/merchant/MerchantLocationPicker';
import { AddressDropdowns } from '../components/admin/AddressDropdowns';
import { HalalRegistrationInfo } from '../components/merchant/HalalRegistrationInfo';
import { merchantSchema } from '@/lib/commerceSchemas';
import { useAdminCategories } from '@/hooks/useAdminCategories';

type MerchantFormData = z.infer<typeof merchantSchema>;

const DRAFT_KEY = 'merchant_registration_draft';
const WEEK_DAYS = [
  { day: 1, label: 'Senin' }, { day: 2, label: 'Selasa' }, { day: 3, label: 'Rabu' },
  { day: 4, label: 'Kamis' }, { day: 5, label: 'Jumat' }, { day: 6, label: 'Sabtu' }, { day: 0, label: 'Minggu' },
];

type ScheduleDay = { openTime: string; closeTime: string; isClosed: boolean };
type WeeklySchedule = Record<number, ScheduleDay>;

const createDefaultSchedule = (): WeeklySchedule => Object.fromEntries(
  WEEK_DAYS.map(({ day }) => [day, { openTime: '08:00', closeTime: '21:00', isClosed: false }]),
) as WeeklySchedule;

const timeOptions = [
  '05:00', '06:00', '07:00', '08:00', '09:00', '10:00', '11:00', '12:00',
  '13:00', '14:00', '15:00', '16:00', '17:00', '18:00', '19:00', '20:00',
  '21:00', '22:00', '23:00', '00:00'
];

interface ReferralInfo {
  isValid: boolean;
  tradeGroup: string;
  description: string;
  isLoading: boolean;
}

interface DraftData {
  referralCode: string;
  name: string;
  businessCategory: string;
  businessCategoryIds?: string[];
  businessDescription: string;
  phone: string;
  openTime: string;
  closeTime: string;
  weeklySchedule?: WeeklySchedule;
  addressDetail: string;
  selectedProvince: string;
  selectedCity: string;
  selectedDistrict: string;
  selectedSubdistrict: string;
  merchantLocation: { lat: number; lng: number } | null;
  halalStatus: string;
  halalCertUrl?: string;
  ktpUrl?: string;
}

export default function RegisterMerchantPage() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const { user, refetchRoles } = useAuth();
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [hasDraft, setHasDraft] = useState(false);
  const [selectedCategoryIds, setSelectedCategoryIds] = useState<string[]>([]);
  const [weeklySchedule, setWeeklySchedule] = useState<WeeklySchedule>(createDefaultSchedule);
  const { data: categoryOptions = [], isLoading: categoryLoading } = useAdminCategories();
  const draftRestoredRef = useRef(false);
  const saveDraftTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  
  const [addressData, setAddressData] = useState({
    provinceCode: '',
    provinceName: '',
    regencyCode: '',
    regencyName: '',
    districtCode: '',
    districtName: '',
    villageCode: '',
    villageName: '',
  });
  
  const [matchedVillage, setMatchedVillage] = useState<Village | null>(null);
  const [villageLoading, setVillageLoading] = useState(false);
  const [merchantLocation, setMerchantLocation] = useState<{ lat: number; lng: number } | null>(null);
  
  const [halalStatus, setHalalStatus] = useState<'NONE' | 'PENDING_VERIFICATION' | 'REQUESTED'>('NONE');
  const [halalCertUrl, setHalalCertUrl] = useState<string | undefined>(undefined);
  const [ktpUrl, setKtpUrl] = useState<string | undefined>(undefined);
  
  const [referralInfo, setReferralInfo] = useState<ReferralInfo>({
    isValid: false,
    tradeGroup: '',
    description: '',
    isLoading: false,
  });
  const [referralCode, setReferralCode] = useState(() => searchParams.get('ref')?.trim().toUpperCase() || '');

  const { register, handleSubmit, setValue, watch, getValues, trigger, formState: { errors } } = useForm<MerchantFormData>({
    resolver: zodResolver(merchantSchema),
    mode: 'onBlur',
    reValidateMode: 'onChange',
    defaultValues: {
      openTime: '08:00',
      closeTime: '21:00',
    },
  });

  // === DRAFT: Save ===
  const saveDraft = useCallback(() => {
    const values = getValues();
    const draft: DraftData = {
      referralCode,
      name: values.name || '',
      businessCategory: values.businessCategory || '',
      businessCategoryIds: selectedCategoryIds,
      businessDescription: values.businessDescription || '',
      phone: values.phone || '',
      openTime: values.openTime || '',
      closeTime: values.closeTime || '',
      weeklySchedule,
      addressDetail: values.addressDetail || '',
      selectedProvince: addressData.provinceCode,
      selectedCity: addressData.regencyCode,
      selectedDistrict: addressData.districtCode,
      selectedSubdistrict: addressData.villageCode,
      merchantLocation,
      halalStatus,
      halalCertUrl,
      ktpUrl,
    };
    try {
      localStorage.setItem(DRAFT_KEY, JSON.stringify(draft));
      setHasDraft(true);
    } catch (err) { console.warn('[register-merchant] gagal menyimpan draf:', err); }
  }, [getValues, referralCode, selectedCategoryIds, weeklySchedule, addressData, merchantLocation, halalStatus, halalCertUrl, ktpUrl]);

  // Debounced auto-save
  const scheduleSaveDraft = useCallback(() => {
    if (saveDraftTimerRef.current) clearTimeout(saveDraftTimerRef.current);
    saveDraftTimerRef.current = setTimeout(() => saveDraft(), 500);
  }, [saveDraft]);

  // Watch all form fields for auto-save
  const watchedFields = watch();
  useEffect(() => {
    if (draftRestoredRef.current) {
      scheduleSaveDraft();
    }
  }, [watchedFields, referralCode, addressData, merchantLocation, halalStatus, halalCertUrl, ktpUrl, scheduleSaveDraft]);

  // === DRAFT: Restore on mount ===
  useEffect(() => {
    try {
      const raw = localStorage.getItem(DRAFT_KEY);
      if (!raw) {
        draftRestoredRef.current = true;
        return;
      }
      const draft: DraftData = JSON.parse(raw);
      setHasDraft(true);

      // Restore simple fields
      if (draft.name) setValue('name', draft.name);
      if (draft.businessCategory) setValue('businessCategory', draft.businessCategory);
      if (draft.businessCategoryIds?.length) setSelectedCategoryIds(draft.businessCategoryIds);
      if (draft.businessDescription) setValue('businessDescription', draft.businessDescription);
      if (draft.phone) setValue('phone', draft.phone);
      if (draft.openTime) setValue('openTime', draft.openTime);
      if (draft.closeTime) setValue('closeTime', draft.closeTime);
      if (draft.weeklySchedule) setWeeklySchedule(draft.weeklySchedule);
      if (draft.addressDetail) setValue('addressDetail', draft.addressDetail);
      if (draft.referralCode) setReferralCode((current) => current || draft.referralCode.toUpperCase());
      if (draft.merchantLocation) setMerchantLocation(draft.merchantLocation);
      if (draft.halalStatus) setHalalStatus(draft.halalStatus as 'NONE' | 'PENDING_VERIFICATION' | 'REQUESTED');
      if (draft.halalCertUrl) setHalalCertUrl(draft.halalCertUrl);
      if (draft.ktpUrl) setKtpUrl(draft.ktpUrl);

      // Restore address chain
      setAddressData({
        provinceCode: draft.selectedProvince || '',
        provinceName: '', // Will be updated by dropdown component
        regencyCode: draft.selectedCity || '',
        regencyName: '',
        districtCode: draft.selectedDistrict || '',
        districtName: '',
        villageCode: draft.selectedSubdistrict || '',
        villageName: '',
      });
      if (draft.selectedProvince) setValue('province', draft.selectedProvince);
      if (draft.selectedCity) setValue('city', draft.selectedCity);
      if (draft.selectedDistrict) setValue('district', draft.selectedDistrict);
      if (draft.selectedSubdistrict) setValue('subdistrict', draft.selectedSubdistrict);

      toast.info('Draft formulir dipulihkan');
    } catch {
      console.warn('Failed to restore draft');
    }
    draftRestoredRef.current = true;
  }, [setValue]);

  const clearDraft = () => {
    localStorage.removeItem(DRAFT_KEY);
    setHasDraft(false);
    toast.success('Draft dihapus');
  };

  // Check if selected subdistrict matches any village in our DB
  useEffect(() => {
    const checkVillageMatch = async () => {
      if (addressData.villageCode && addressData.villageName) {
        setVillageLoading(true);
        try {
          const { data, error } = await supabase
            .from('villages')
            .select('*')
            .eq('subdistrict', addressData.villageName)
            .eq('is_active', true)
            .maybeSingle();
          
          if (data) {
            setMatchedVillage(data as unknown as Village);
          } else {
            setMatchedVillage(null);
          }
        } catch (error) {
          console.error('Error checking village match:', error);
        } finally {
          setVillageLoading(false);
        }
      } else {
        setMatchedVillage(null);
      }
    };
    checkVillageMatch();
  }, [addressData.villageCode, addressData.villageName]);

  const validateReferralCode = useCallback(async (code: string) => {
    if (code.length < 3) {
      setReferralInfo({ isValid: false, tradeGroup: '', description: '', isLoading: false });
      return;
    }
    setReferralInfo(prev => ({ ...prev, isLoading: true }));
    try {
      const { data, error } = await supabase
        .from('verifikator_codes')
        .select('*')
        .eq('code', code.toUpperCase())
        .eq('is_active', true)
        .maybeSingle();

      if (error || !data) {
        setReferralInfo({ isValid: false, tradeGroup: '', description: '', isLoading: false });
        return;
      }
      if (data.max_usage && data.usage_count >= data.max_usage) {
        setReferralInfo({ isValid: false, tradeGroup: '', description: 'Kode sudah mencapai batas maksimal penggunaan', isLoading: false });
        return;
      }
      setReferralInfo({
        isValid: true,
        tradeGroup: data.trade_group,
        description: data.description || '',
        isLoading: false,
      });
      setValue('referralCode', code.toUpperCase());
    } catch (error) {
      console.error('Error validating referral:', error);
      setReferralInfo({ isValid: false, tradeGroup: '', description: '', isLoading: false });
    }
  }, [setValue]);

  useEffect(() => {
    const timer = setTimeout(() => {
      if (referralCode) validateReferralCode(referralCode);
    }, 500);
    return () => clearTimeout(timer);
  }, [referralCode, validateReferralCode]);

  const onSubmit = async (data: MerchantFormData) => {
    const fallbackCategoryIds = categoryOptions.filter((category) => category.slug === data.businessCategory).map((category) => category.id);
    const categoryIds = [...new Set(selectedCategoryIds.length ? selectedCategoryIds : fallbackCategoryIds)];
    const selectedCategories = categoryOptions.filter((category) => categoryIds.includes(category.id));
    if (selectedCategories.length === 0 || selectedCategories.length !== categoryIds.length) {
      toast.error('Pilih minimal satu kategori usaha yang masih aktif.');
      return;
    }
    const primaryCategory = selectedCategories[0];
    const openDays = WEEK_DAYS.filter(({ day }) => !weeklySchedule[day]?.isClosed);
    if (openDays.length === 0) {
      toast.error('Pilih minimal satu hari operasional.');
      return;
    }
    if (referralCode && referralCode.length > 0 && !referralInfo.isValid) {
      toast.error('Kode referral tidak valid');
      return;
    }

    if (selectedCategories.some((category) => category.slug === 'kuliner') && halalStatus === 'NONE' && !ktpUrl) {
      toast.error('Foto KTP wajib diunggah untuk kategori kuliner yang belum memiliki sertifikat halal');
      return;
    }

    setIsSubmitting(true);
    try {
      const provinceName = addressData.provinceName;
      const cityName = addressData.regencyName;
      const districtName = addressData.districtName;
      const subdistrictName = addressData.villageName;

      if (!user) {
        toast.error('Anda harus login untuk mendaftar');
        navigate('/auth');
        return;
      }

      const { data: existingMerchant, error: existingMerchantError } = await supabase
        .from('merchants')
        .select('id, registration_status')
        .eq('user_id', user.id)
        .in('registration_status', ['PENDING', 'APPROVED'])
        .maybeSingle();
      if (existingMerchantError) throw existingMerchantError;
      if (existingMerchant) {
        toast.info(existingMerchant.registration_status === 'APPROVED'
          ? 'Akun Anda sudah memiliki toko aktif.'
          : 'Pendaftaran toko Anda masih menunggu persetujuan.');
        navigate('/merchant', { replace: true });
        return;
      }

      // The database auto-approval trigger promotes new registrations to
      // APPROVED/ACTIVE. Submit PENDING here so the public INSERT policy
      // remains strict and the trigger is the single source of truth.
      const registrationStatus = 'PENDING' as const;
      const merchantStatus = 'INACTIVE' as const;
      const legacySchedule = weeklySchedule[1] || weeklySchedule[openDays[0].day];

      const { data: merchant, error } = await supabase.from('merchants').insert({
        name: data.name.trim(),
        user_id: user.id,
        village_id: matchedVillage?.id || null,
        address: data.addressDetail.trim(),
        province: provinceName,
        city: cityName,
        district: districtName,
        subdistrict: subdistrictName,
        phone: data.phone.trim(),
        business_category: primaryCategory.slug,
        business_description: data.businessDescription?.trim() || null,
        verifikator_code: referralCode ? referralCode.toUpperCase() : null,
        trade_group: referralInfo.tradeGroup || null,
        registration_status: registrationStatus,
        status: merchantStatus,
        order_mode: 'ADMIN_ASSISTED',
        is_open: false,
        open_time: legacySchedule.openTime,
        close_time: legacySchedule.closeTime,
        registered_at: new Date().toISOString(),
        location_lat: merchantLocation?.lat || null,
        location_lng: merchantLocation?.lng || null,
        halal_status: halalStatus,
        halal_certificate_url: halalCertUrl,
        ktp_url: ktpUrl,
      }).select('id').single();

      if (error) throw error;

      const { error: categoryError } = await supabase.from('merchant_categories').insert(
        selectedCategories.map((category) => ({ merchant_id: merchant.id, category_id: category.id })),
      );
      if (categoryError) throw categoryError;

      const { error: scheduleError } = await supabase.from('merchant_operating_hours').insert(
        WEEK_DAYS.map(({ day }) => ({
          merchant_id: merchant.id,
          day_of_week: day,
          open_time: weeklySchedule[day].openTime,
          close_time: weeklySchedule[day].closeTime,
          is_closed: weeklySchedule[day].isClosed,
        })),
      );
      if (scheduleError) throw scheduleError;

      // Database triggers assign buyer + merchant roles before the insert
      // returns. Refresh the auth role state before navigating so
      // ProtectedRoute does not briefly send the new merchant to /unauthorized.
      await refetchRoles();

      // Clear draft on success
      localStorage.removeItem(DRAFT_KEY);
      setHasDraft(false);
      toast.success('Pendaftaran merchant berhasil. Selamat datang di dashboard merchant!');
      navigate('/merchant', { replace: true });
    } catch (error) {
      console.error('Error submitting merchant registration:', error);
      toast.error('Gagal mengirim pendaftaran. Silakan coba lagi.');
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="min-h-screen bg-background pb-24">
      <PageHeader title="Daftar Jadi Merchant" />
      
      <main className="p-4 max-w-2xl mx-auto">
        {/* Draft banner */}
        {hasDraft && (
          <div className="bg-accent/50 border border-accent rounded-xl p-3 mb-4 flex items-center justify-between">
            <div className="flex items-center gap-2 text-sm">
              <Save className="w-4 h-4 text-primary" />
              <span className="text-muted-foreground">Draft tersimpan otomatis</span>
            </div>
            <Button variant="ghost" size="sm" onClick={clearDraft} className="text-xs h-7 gap-1">
              <Trash2 className="w-3 h-3" />
              Hapus Draft
            </Button>
          </div>
        )}

        <div className="bg-primary/5 border border-primary/10 rounded-xl p-4 mb-6 flex gap-3">
          <AlertCircle className="w-5 h-5 text-primary shrink-0 mt-0.5" />
          <div className="text-sm">
            <p className="font-medium text-primary mb-1">Informasi Pendaftaran</p>
            <p className="text-muted-foreground">Pilih jenis usaha yang paling sesuai. Formulir ini juga dipakai untuk tukang/jasa, petani, peternak, dan penjual produk desa.</p>
          </div>
        </div>

        <form onSubmit={handleSubmit(onSubmit)} className="space-y-6">
          {/* Referral Section */}
          <div className="space-y-4 bg-card border rounded-xl p-4">
            <div className="flex items-center gap-2 mb-2">
              <Tag className="w-5 h-5 text-primary" />
              <h3 className="font-semibold">Kode Referral (Opsional)</h3>
            </div>
            <div className="space-y-2">
              <Label htmlFor="referralCode">Punya kode dari verifikator?</Label>
              <div className="relative">
                <Input
                  id="referralCode"
                  placeholder="Masukkan kode referral"
                  className="uppercase pr-10"
                  value={referralCode}
                  onChange={(e) => setReferralCode(e.target.value)}
                />
                {referralInfo.isLoading && (
                  <div className="absolute right-3 top-1/2 -translate-y-1/2">
                    <Loader2 className="w-4 h-4 text-primary animate-spin" />
                  </div>
                )}
                {!referralInfo.isLoading && referralInfo.isValid && (
                  <Check className="absolute right-3 top-1/2 -translate-y-1/2 w-5 h-5 text-success" />
                )}
              </div>
              {referralInfo.isValid && (
                <div className="bg-success/5 border border-success/20 rounded-lg p-3 flex gap-2 items-start">
                  <CheckCircle className="w-4 h-4 text-success shrink-0 mt-0.5" />
                  <div className="text-xs text-success">
                    <p className="font-bold">Kode Valid: {referralInfo.tradeGroup}</p>
                    <p>{referralInfo.description}</p>
                  </div>
                </div>
              )}
              {referralCode && !referralInfo.isValid && !referralInfo.isLoading && (
                <p className="text-xs text-destructive">Kode tidak ditemukan atau sudah tidak aktif</p>
              )}
            </div>
          </div>

          {/* Business Info */}
          <div className="space-y-4 bg-card border rounded-xl p-4">
            <div className="flex items-center gap-2 mb-2">
              <Store className="w-5 h-5 text-primary" />
              <h3 className="font-semibold">Informasi Usaha</h3>
            </div>
            
              <div className="space-y-2">
                <Label htmlFor="name">Nama Usaha</Label>
                <Input id="name" {...register('name')} placeholder="Contoh: Warung Makan Berkah" required minLength={3} maxLength={100} aria-invalid={Boolean(errors.name)} aria-describedby={errors.name ? 'merchant-name-error' : undefined} />
                {errors.name && <p id="merchant-name-error" role="alert" className="text-xs text-destructive">{errors.name.message}</p>}
              </div>


            <div className="space-y-2">
              <Label>Kategori Usaha</Label>
              <div className="rounded-lg border bg-muted/20 p-3">
                <p className="mb-3 text-xs text-muted-foreground">Pilih satu atau lebih kategori yang sesuai dengan usaha Anda.</p>
                {categoryLoading ? <p className="text-sm text-muted-foreground">Memuat kategori admin...</p> : categoryOptions.length === 0 ? <p className="text-sm text-muted-foreground">Kategori belum tersedia.</p> : <div className="grid gap-2 sm:grid-cols-2">
                  {categoryOptions.map((cat) => {
                    const checked = selectedCategoryIds.includes(cat.id);
                    return <label key={cat.id} className="flex cursor-pointer items-center gap-3 rounded-md border bg-background px-3 py-2 transition hover:border-primary/50">
                      <Checkbox checked={checked} onCheckedChange={(nextChecked) => {
                        const nextIds = nextChecked ? [...new Set([...selectedCategoryIds, cat.id])] : selectedCategoryIds.filter((id) => id !== cat.id);
                        setSelectedCategoryIds(nextIds);
                        const primary = categoryOptions.find((option) => option.id === nextIds[0]);
                        setValue('businessCategory', primary?.slug || '', { shouldDirty: true, shouldTouch: true, shouldValidate: true });
                      }} />
                      <span className="text-sm">{cat.icon ? `${cat.icon} ` : ''}{cat.name}</span>
                    </label>;
                  })}
                </div>}
                {selectedCategoryIds.length > 0 && <p className="mt-3 text-xs text-primary">{selectedCategoryIds.length} kategori dipilih</p>}
              </div>
              {errors.businessCategory && <p role="alert" className="text-xs text-destructive">{errors.businessCategory.message}</p>}
            </div>

            <div className="space-y-2">
              <Label htmlFor="businessDescription">Deskripsi Usaha (Opsional)</Label>
                <Textarea
                  id="businessDescription"
                  {...register('businessDescription')}
                  placeholder="Ceritakan sedikit tentang usaha Anda..."
                  maxLength={500}
                  aria-invalid={Boolean(errors.businessDescription)}
                  className="resize-none h-24"
                />
              {errors.businessDescription && <p className="text-xs text-destructive">{errors.businessDescription.message}</p>}
            </div>
          </div>

          {/* Contact Info */}
          <div className="space-y-4 bg-card border rounded-xl p-4">
            <div className="flex items-center gap-2 mb-2">
              <Phone className="w-5 h-5 text-primary" />
              <h3 className="font-semibold">Kontak & Operasional</h3>
            </div>

            <div className="space-y-2">
              <Label htmlFor="phone">Nomor WhatsApp</Label>
              <Input id="phone" {...register('phone')} placeholder="08xxxxxxxxxx" type="tel" inputMode="tel" autoComplete="tel" required minLength={10} maxLength={15} aria-invalid={Boolean(errors.phone)} aria-describedby={errors.phone ? 'merchant-phone-error' : undefined} />
              {errors.phone && <p id="merchant-phone-error" role="alert" className="text-xs text-destructive">{errors.phone.message}</p>}
            </div>

            <div className="space-y-3">
              <div>
                <Label>Jadwal Operasional Mingguan</Label>
                <p className="mt-1 text-xs text-muted-foreground">Atur jam berbeda untuk weekday, Sabtu, dan Minggu. Hari yang dicentang tutup tidak menerima pesanan.</p>
              </div>
              <div className="space-y-2 rounded-lg border bg-muted/20 p-3">
                {WEEK_DAYS.map(({ day, label }) => {
                  const schedule = weeklySchedule[day];
                  return <div key={day} className="grid items-center gap-2 sm:grid-cols-[minmax(100px,1fr)_1fr_1fr_auto]">
                    <span className="text-sm font-medium">{label}</span>
                    <Select disabled={schedule.isClosed} onValueChange={(value) => setWeeklySchedule((current) => ({ ...current, [day]: { ...current[day], openTime: value } }))} value={schedule.openTime}>
                      <SelectTrigger aria-label={`Jam buka ${label}`}><SelectValue placeholder="Buka" /></SelectTrigger>
                      <SelectContent>{timeOptions.map((time) => <SelectItem key={time} value={time}>{time}</SelectItem>)}</SelectContent>
                    </Select>
                    <Select disabled={schedule.isClosed} onValueChange={(value) => setWeeklySchedule((current) => ({ ...current, [day]: { ...current[day], closeTime: value } }))} value={schedule.closeTime}>
                      <SelectTrigger aria-label={`Jam tutup ${label}`}><SelectValue placeholder="Tutup" /></SelectTrigger>
                      <SelectContent>{timeOptions.map((time) => <SelectItem key={time} value={time}>{time}</SelectItem>)}</SelectContent>
                    </Select>
                    <label className="flex items-center gap-2 text-xs text-muted-foreground">
                      <Checkbox checked={schedule.isClosed} onCheckedChange={(checked) => setWeeklySchedule((current) => ({ ...current, [day]: { ...current[day], isClosed: Boolean(checked) } }))} />
                      Tutup
                    </label>
                  </div>;
                })}
              </div>
              <input type="hidden" {...register('openTime')} />
              <input type="hidden" {...register('closeTime')} />
              {errors.openTime && <p className="text-xs text-destructive">{errors.openTime.message}</p>}
              {errors.closeTime && <p className="text-xs text-destructive">{errors.closeTime.message}</p>}
            </div>
          </div>

          {/* Location Info */}
          <div className="space-y-4 bg-card border rounded-xl p-4">
            <div className="flex items-center gap-2 mb-2">
              <MapPin className="w-5 h-5 text-primary" />
              <h3 className="font-semibold">Lokasi Usaha</h3>
            </div>

            <div className="space-y-4">
              <AddressDropdowns
                provinceCode={addressData.provinceCode}
                provinceName={addressData.provinceName}
                regencyCode={addressData.regencyCode}
                regencyName={addressData.regencyName}
                districtCode={addressData.districtCode}
                districtName={addressData.districtName}
                villageCode={addressData.villageCode}
                villageName={addressData.villageName}
                onChange={(data) => {
                  setAddressData(data);
                  void setValue('province', data.provinceCode, { shouldDirty: true, shouldTouch: true, shouldValidate: true });
                  void setValue('city', data.regencyCode, { shouldDirty: true, shouldTouch: true, shouldValidate: true });
                  void setValue('district', data.districtCode, { shouldDirty: true, shouldTouch: true, shouldValidate: true });
                  void setValue('subdistrict', data.villageCode, { shouldDirty: true, shouldTouch: true, shouldValidate: true });
                  
                  // Trigger validation for these fields
                  trigger(['province', 'city', 'district', 'subdistrict']);
                }}
              />
              <div className="grid grid-cols-2 gap-4">
                {errors.province && <p className="text-xs text-destructive">{errors.province.message}</p>}
                {errors.city && <p className="text-xs text-destructive">{errors.city.message}</p>}
                {errors.district && <p className="text-xs text-destructive">{errors.district.message}</p>}
                {errors.subdistrict && <p className="text-xs text-destructive">{errors.subdistrict.message}</p>}
              </div>

              {villageLoading && (
                <div className="flex items-center gap-2 text-xs text-muted-foreground animate-pulse">
                  <div className="w-2 h-2 bg-primary rounded-full" />
                  Mengecek ketersediaan desa digital...
                </div>
              )}

              {matchedVillage && (
                <div className="bg-primary/5 border border-primary/20 rounded-lg p-3 flex gap-3 items-start">
                  <Building className="w-5 h-5 text-primary shrink-0 mt-0.5" />
                  <div className="text-xs">
                    <p className="font-bold text-primary">Desa Digital Terdeteksi!</p>
                    <p className="text-muted-foreground">Usaha Anda akan terhubung dengan sistem digital {matchedVillage.name}.</p>
                  </div>
                </div>
              )}

              <div className="space-y-2">
                <Label htmlFor="addressDetail">Alamat Lengkap</Label>
                <Textarea 
                  id="addressDetail" 
                  {...register('addressDetail')} 
                  placeholder="Nama jalan, nomor rumah, patokan..."
                  required
                  minLength={10}
                  maxLength={200}
                  aria-invalid={Boolean(errors.addressDetail)}
                  aria-describedby={errors.addressDetail ? 'merchant-address-error' : undefined}
                  className="resize-none h-20"
                />
                {errors.addressDetail && <p id="merchant-address-error" role="alert" className="text-xs text-destructive">{errors.addressDetail.message}</p>}
              </div>

              <div className="space-y-2">
                <Label>Titik Lokasi (Opsional)</Label>
                <MerchantLocationPicker 
                  value={merchantLocation}
                  onChange={(location) => setMerchantLocation(location)}
                />
                <p className="text-[10px] text-muted-foreground">Gunakan titik lokasi agar pembeli lebih mudah menemukan usaha Anda.</p>
              </div>
            </div>
          </div>

          {watch('businessCategory') === 'kuliner' && (
            <HalalRegistrationInfo 
              onStatusChange={(status, cert, ktp) => {
                setHalalStatus(status);
                setHalalCertUrl(cert);
                setKtpUrl(ktp);
              }}
            />
          )}

          <div className="pt-4">
            <Button 
              type="submit" 
              className="w-full h-12 text-lg font-bold" 
              disabled={isSubmitting}
            >
              {isSubmitting ? (
                <div className="flex items-center gap-2">
                  <Loader2 className="w-4 h-4 text-white animate-spin" />
                  Memproses...
                </div>
              ) : (
                'Daftar Sekarang'
              )}
            </Button>
            <p className="text-[10px] text-center text-muted-foreground mt-4 px-4">
              Dengan mendaftar, Anda menyetujui Syarat & Ketentuan serta Kebijakan Privasi kami sebagai mitra merchant.
            </p>
          </div>
        </form>
      </main>

      <BottomNav />
    </div>
  );
}

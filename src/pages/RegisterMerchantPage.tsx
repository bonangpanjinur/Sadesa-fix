import { useState, useEffect, useCallback, useRef, useMemo, type ReactNode } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { 
  Store, Phone, MapPin, CheckCircle,
  Tag, Building, AlertCircle, Check, Loader2, Save, Trash2, ChevronDown, X
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
import { getCategoryChildren, getCategoryDisplayLabel, sortProductCategories, type ProductCategory } from '@/lib/productCategories';
import { restoreSignupAddress, toRegistrationAddressPrefill } from '@/lib/signupAddressMetadata';

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
}

export default function RegisterMerchantPage() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const { user, refetchRoles } = useAuth();
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [hasDraft, setHasDraft] = useState(false);
  const [selectedCategoryIds, setSelectedCategoryIds] = useState<string[]>([]);
  const [expandedCategoryIds, setExpandedCategoryIds] = useState<string[]>([]);
  const [weeklySchedule, setWeeklySchedule] = useState<WeeklySchedule>(createDefaultSchedule);
  const { data: categoryOptions = [], isLoading: categoryLoading } = useAdminCategories();
  const rootCategories = useMemo(() => {
    const categoryIds = new Set(categoryOptions.map((category) => category.id));
    return sortProductCategories(categoryOptions.filter((category) => (
      !category.parent_id || !categoryIds.has(category.parent_id)
    )));
  }, [categoryOptions]);
  const selectedCategories = useMemo(
    () => selectedCategoryIds.map((id) => categoryOptions.find((category) => category.id === id)).filter((category): category is ProductCategory => Boolean(category)),
    [categoryOptions, selectedCategoryIds],
  );
  const draftRestoredRef = useRef(false);
  const addressWasCustomizedRef = useRef(false);
  const saveDraftTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const referralValidationRequestRef = useRef(0);
  
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

  function updateCategorySelection(nextIds: string[]) {
    const uniqueIds = [...new Set(nextIds)];
    setSelectedCategoryIds(uniqueIds);
    const primary = categoryOptions.find((category) => category.id === uniqueIds[0]);
    setValue('businessCategory', primary?.slug || '', { shouldDirty: true, shouldTouch: true, shouldValidate: true });
  }

  function toggleCategory(categoryId: string, checked: boolean) {
    const nextIds = checked
      ? [...new Set([...selectedCategoryIds, categoryId])]
      : selectedCategoryIds.filter((id) => id !== categoryId);
    updateCategorySelection(nextIds);
  }

  function toggleCategoryExpanded(categoryId: string) {
    setExpandedCategoryIds((current) => current.includes(categoryId)
      ? current.filter((id) => id !== categoryId)
      : [...current, categoryId]);
  }

  function renderCategoryNode(category: ProductCategory, depth = 0): ReactNode {
    const children = getCategoryChildren(categoryOptions, category.id);
    const checked = selectedCategoryIds.includes(category.id);
    const expanded = expandedCategoryIds.includes(category.id);
    const childrenId = `merchant-category-children-${category.id}`;

    return (
      <div key={category.id} className={depth > 0 ? 'space-y-2' : ''}>
        <div className={`flex items-center gap-1 rounded-xl border transition-colors ${checked ? 'border-primary/50 bg-primary/5' : 'border-border bg-background hover:border-primary/30'}`}>
          <label className="flex min-w-0 flex-1 cursor-pointer items-center gap-3 px-3 py-3">
            <Checkbox checked={checked} onCheckedChange={(nextChecked) => toggleCategory(category.id, Boolean(nextChecked))} />
            {category.icon && <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-muted text-lg">{category.icon}</span>}
            <span className={`min-w-0 truncate text-sm ${depth === 0 ? 'font-semibold' : 'font-medium'}`}>{category.name}</span>
          </label>
          {children.length > 0 && (
            <button
              type="button"
              aria-label={`${expanded ? 'Tutup' : 'Buka'} subkategori ${category.name}`}
              aria-expanded={expanded}
              aria-controls={childrenId}
              onClick={() => toggleCategoryExpanded(category.id)}
              className="mr-2 inline-flex shrink-0 items-center gap-1.5 rounded-lg px-2 py-2 text-xs text-muted-foreground transition hover:bg-muted hover:text-foreground"
            >
              <span className="hidden sm:inline">{children.length} subkategori</span>
              <ChevronDown className={`h-4 w-4 transition-transform ${expanded ? 'rotate-180' : ''}`} />
            </button>
          )}
        </div>
        {children.length > 0 && (
          <div id={childrenId} hidden={!expanded} className="ml-3 mt-2 space-y-2 border-l-2 border-primary/15 pl-3 sm:ml-4 sm:pl-4">
            {children.map((child) => renderCategoryNode(child, depth + 1))}
          </div>
        )}
      </div>
    );
  }

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
    };
    try {
      localStorage.setItem(DRAFT_KEY, JSON.stringify(draft));
      setHasDraft(true);
    } catch (err) { console.warn('[register-merchant] gagal menyimpan draf:', err); }
  }, [getValues, referralCode, selectedCategoryIds, weeklySchedule, addressData, merchantLocation, halalStatus]);

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
  }, [watchedFields, referralCode, addressData, merchantLocation, halalStatus, scheduleSaveDraft]);

  useEffect(() => () => {
    if (saveDraftTimerRef.current) clearTimeout(saveDraftTimerRef.current);
  }, []);

  // === DRAFT: Restore on mount ===
  useEffect(() => {
    try {
      const raw = localStorage.getItem(DRAFT_KEY);
      if (!raw) {
        draftRestoredRef.current = true;
        return;
      }
      const draft = JSON.parse(raw) as DraftData & { halalCertUrl?: string; ktpUrl?: string };
      if (draft.halalCertUrl || draft.ktpUrl) {
        delete draft.halalCertUrl;
        delete draft.ktpUrl;
        localStorage.setItem(DRAFT_KEY, JSON.stringify(draft));
      }
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
      addressWasCustomizedRef.current = Boolean(
        draft.selectedProvince || draft.selectedCity || draft.selectedDistrict || draft.selectedSubdistrict,
      );
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
    addressWasCustomizedRef.current = true;
    setAddressData(data);
    void setValue('province', data.provinceCode, { shouldDirty: true, shouldTouch: true, shouldValidate: true });
    void setValue('city', data.regencyCode, { shouldDirty: true, shouldTouch: true, shouldValidate: true });
    void setValue('district', data.districtCode, { shouldDirty: true, shouldTouch: true, shouldValidate: true });
    void setValue('subdistrict', data.villageCode, { shouldDirty: true, shouldTouch: true, shouldValidate: true });
    void trigger(['province', 'city', 'district', 'subdistrict']);
  }, [setValue, trigger]);

  useEffect(() => {
    if (!user || !draftRestoredRef.current || addressWasCustomizedRef.current) return;
    let active = true;
    const prefillBusinessAddress = async () => {
      try {
        const { data, error } = await supabase
          .from('profiles')
          .select('province_id, province_name, city_id, city_name, district_id, district_name, village_id, village_name, address_detail, address')
          .eq('user_id', user.id)
          .order('updated_at', { ascending: false })
          .limit(1)
          .maybeSingle();
        if (error) throw error;
        const profile = restoreSignupAddress(data, user.user_metadata);
        const location = toRegistrationAddressPrefill(profile);
        if (!active || addressWasCustomizedRef.current || !location) return;

        const nextAddress = {
          provinceCode: location.provinceCode,
          provinceName: location.provinceName,
          regencyCode: location.cityCode,
          regencyName: location.cityName,
          districtCode: location.districtCode,
          districtName: location.districtName,
          villageCode: location.villageCode,
          villageName: location.villageName,
        };
        addressWasCustomizedRef.current = true;
        setAddressData(nextAddress);
        void setValue('province', nextAddress.provinceCode, { shouldValidate: true });
        void setValue('city', nextAddress.regencyCode, { shouldValidate: true });
        void setValue('district', nextAddress.districtCode, { shouldValidate: true });
        void setValue('subdistrict', nextAddress.villageCode, { shouldValidate: true });
        if (location.addressDetail) setValue('addressDetail', location.addressDetail);

        const mapsUrl = profile?.address?.match(/https?:\/\/[^\s]+/i)?.[0];
        const coordinates = mapsUrl?.match(/[?&]q=(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)/i);
        if (coordinates) setMerchantLocation({ lat: Number(coordinates[1]), lng: Number(coordinates[2]) });
      } catch (error) {
        console.warn('Unable to prefill merchant address from profile:', error);
      }
    };
    void prefillBusinessAddress();
    return () => { active = false; };
  }, [setValue, user]);

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
    const requestId = ++referralValidationRequestRef.current;
    if (code.length < 3) {
      setReferralInfo({ isValid: false, tradeGroup: '', description: '', isLoading: false });
      return;
    }
    setReferralInfo(prev => ({ ...prev, isLoading: true }));
    try {
      const { data, error } = await (supabase as any).rpc('check_merchant_referral_code', { p_code: code.toUpperCase() });
      if (requestId !== referralValidationRequestRef.current) return;
      const result = data as { valid?: boolean; owner_role?: string } | null;
      if (error || result?.valid !== true) {
        setReferralInfo({ isValid: false, tradeGroup: '', description: 'Kode referral tidak valid, tidak aktif, atau sudah mencapai batas penggunaan', isLoading: false });
        return;
      }
      setReferralInfo({
        isValid: true,
        tradeGroup: result.owner_role === 'ADMIN_DESA' ? 'Admin Desa' : 'Verifikator',
        description: '',
        isLoading: false,
      });
      setValue('referralCode', code.toUpperCase());
    } catch (error) {
      if (requestId !== referralValidationRequestRef.current) return;
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

      const { data: merchantId, error } = await supabase.rpc('register_merchant_atomic', {
        p_user_id: user.id,
        p_name: data.name.trim(),
        p_village_id: matchedVillage?.id || null,
        p_address: data.addressDetail.trim(),
        p_province: provinceName,
        p_city: cityName,
        p_district: districtName,
        p_subdistrict: subdistrictName,
        p_phone: data.phone.trim(),
        p_business_category: primaryCategory.slug,
        p_business_description: data.businessDescription?.trim() || null,
        p_verifikator_code: referralCode ? referralCode.toUpperCase() : null,
        p_trade_group: referralInfo.tradeGroup || null,
        p_location_lat: merchantLocation?.lat || null,
        p_location_lng: merchantLocation?.lng || null,
        p_halal_status: halalStatus,
        p_halal_certificate_url: halalCertUrl || null,
        p_ktp_url: ktpUrl || null,
        p_category_ids: categoryIds,
        p_schedule: WEEK_DAYS.map(({ day }) => ({
          day_of_week: day,
          open_time: weeklySchedule[day].openTime,
          close_time: weeklySchedule[day].closeTime,
          is_closed: weeklySchedule[day].isClosed,
        })),
      });

      if (error || !merchantId) throw error || new Error('Pendaftaran merchant tidak menghasilkan ID');

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
                  onChange={(e) => {
                    referralValidationRequestRef.current += 1;
                    setReferralCode(e.target.value);
                    setReferralInfo({ isValid: false, tradeGroup: '', description: '', isLoading: false });
                  }}
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
              <div className="flex items-center justify-between gap-3">
                <Label>Kategori Usaha</Label>
                <span className="shrink-0 rounded-full bg-primary/10 px-2.5 py-1 text-xs font-semibold text-primary">{selectedCategories.length} dipilih</span>
              </div>
              <div className="rounded-xl border bg-muted/10 p-3 sm:p-4">
                <p className="mb-3 text-xs leading-relaxed text-muted-foreground">Pilih kategori induk, lalu buka subkategori untuk memilih jenis usaha yang lebih spesifik. Anda dapat memilih lebih dari satu.</p>
                {selectedCategories.length > 0 && (
                  <div className="mb-4 rounded-xl border border-primary/20 bg-primary/5 p-3">
                    <div className="mb-2 flex items-center justify-between gap-3">
                      <p className="text-xs font-semibold text-foreground">Kategori terpilih</p>
                      <button type="button" onClick={() => updateCategorySelection([])} className="text-xs font-medium text-primary hover:underline">Bersihkan</button>
                    </div>
                    <div className="flex flex-wrap gap-2">
                      {selectedCategories.map((category) => (
                        <span key={category.id} className="inline-flex max-w-full items-center gap-1.5 rounded-full border bg-background px-2.5 py-1.5 text-xs font-medium">
                          <span className="truncate">{getCategoryDisplayLabel(categoryOptions, category)}</span>
                          <button type="button" aria-label={`Hapus kategori ${category.name}`} onClick={() => toggleCategory(category.id, false)} className="shrink-0 rounded-full p-0.5 text-muted-foreground transition hover:bg-muted hover:text-foreground">
                            <X className="h-3.5 w-3.5" />
                          </button>
                        </span>
                      ))}
                    </div>
                  </div>
                )}
                {categoryLoading ? <p className="py-4 text-center text-sm text-muted-foreground">Memuat kategori usaha...</p> : categoryOptions.length === 0 ? <p className="py-4 text-center text-sm text-muted-foreground">Kategori belum tersedia.</p> : rootCategories.length === 0 ? <p className="py-4 text-center text-sm text-muted-foreground">Struktur kategori belum tersedia.</p> : <div className="grid gap-2 sm:grid-cols-2">
                  {rootCategories.map((category) => (
                    <div key={category.id} className="min-w-0">
                      {renderCategoryNode(category)}
                    </div>
                  ))}
                </div>}
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
                onChange={handleAddressChange}
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

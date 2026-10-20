import { useState, useEffect } from 'react';
import { Save, ToggleLeft, Globe, CreditCard, AlertCircle, Truck, Percent, Plus, Trash2, ShieldCheck, Palette, Package, ArrowDown, ArrowUp } from 'lucide-react';
import { Link } from 'react-router-dom';
import { ImageUpload } from '@/components/ui/ImageUpload';
import { AdminLayout } from '@/components/admin/AdminLayout';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Label } from '@/components/ui/label';
import { Switch } from '@/components/ui/switch';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { fetchAppSettings, updateAppSetting } from '@/lib/adminApi';
import { clearCODSettingsCache } from '@/lib/codSecurity';
import { BrandingAppearanceSettings } from '@/components/admin/BrandingAppearanceSettings';
import { validateShippingFeeSettings, validateShippingZonesSettings } from '@/lib/shippingSettingsValidation';
import { supabase } from '@/integrations/supabase/client';
import type { 
  AppSetting, 
  RegistrationSettings, 
  PaymentSettings, 
  ShippingFeeSettings,
  PlatformFeeSettings,
  ShippingZonesSettings,
  ShippingZone,
  CODSettings,
} from '@/types/admin';
import { BUSINESS_PROFILE, DEFAULT_HELP_FAQS, type HelpFaqItem } from '@/config/businessProfile';
import { toast } from 'sonner';

type ShippingPricingAuditEntry = {
  id: number;
  setting_key: 'shipping_base_fee' | 'shipping_zones';
  old_value: unknown;
  new_value: unknown;
  changed_by: string | null;
  created_at: string;
};

export default function AdminSettingsPage() {
  const [settings, setSettings] = useState<AppSetting[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState<string | null>(null);
  const [shippingAudit, setShippingAudit] = useState<ShippingPricingAuditEntry[]>([]);
  const [shippingAuditLoading, setShippingAuditLoading] = useState(true);
  const [shippingAuditError, setShippingAuditError] = useState(false);

  useEffect(() => {
    loadSettings();
    void loadShippingAudit();
  }, []);

  const loadSettings = async () => {
    try {
      const data = await fetchAppSettings();
      setSettings(data);
    } catch (error) {
      console.error('Error loading settings:', error);
    } finally {
      setLoading(false);
    }
  };

  const loadShippingAudit = async () => {
    setShippingAuditLoading(true);
    setShippingAuditError(false);
    try {
      const { data, error } = await supabase
        .from('shipping_pricing_change_log' as never)
        .select('id,setting_key,old_value,new_value,changed_by,created_at' as never)
        .order('created_at' as never, { ascending: false } as never)
        .limit(25);
      if (error) throw error;
      setShippingAudit((data || []) as unknown as ShippingPricingAuditEntry[]);
    } catch (error) {
      console.error('Error loading shipping pricing audit:', error);
      setShippingAuditError(true);
    } finally {
      setShippingAuditLoading(false);
    }
  };

  const getSetting = (key: string): AppSetting | undefined => {
    return settings.find(s => s.key === key);
  };

  const getTextSetting = (keys: string[], fallback: string): string => {
    for (const key of keys) {
      const value = getSetting(key)?.value as unknown;
      if (typeof value === 'string' && value.trim()) return value;
      if (typeof value === 'number' && Number.isFinite(value)) return String(value);
      if (value && typeof value === 'object' && 'value' in value) {
        const nested = (value as { value?: unknown }).value;
        if (typeof nested === 'string' && nested.trim()) return nested;
      }
    }
    return fallback;
  };

  const handleToggleRegistration = async (key: string, currentValue: boolean) => {
    setSaving(key);
    const success = await updateAppSetting(key, { enabled: !currentValue });
    if (success) {
      toast.success('Pengaturan berhasil disimpan');
      loadSettings();
    } else {
      toast.error('Gagal menyimpan pengaturan');
    }
    setSaving(null);
  };

  const handleSavePayment = async (key: string, values: PaymentSettings) => {
    setSaving(key);
    const success = await updateAppSetting(key, values as unknown as Record<string, unknown>);
    if (success) {
      toast.success('Pengaturan payment gateway berhasil disimpan');
      loadSettings();
    } else {
      toast.error('Gagal menyimpan pengaturan');
    }
    setSaving(null);
  };

  const registrationVillage = getSetting('registration_village')?.value as unknown as RegistrationSettings | undefined;
  const registrationMerchant = getSetting('registration_merchant')?.value as unknown as RegistrationSettings | undefined;
  const registrationCourier = getSetting('registration_courier')?.value as unknown as RegistrationSettings | undefined;
  const paymentMidtrans = getSetting('payment_midtrans')?.value as unknown as PaymentSettings | undefined;
  const paymentXendit = getSetting('payment_xendit')?.value as unknown as PaymentSettings | undefined;
  const shippingBaseFee = getSetting('shipping_base_fee')?.value as unknown as ShippingFeeSettings | undefined;
  const platformFee = getSetting('platform_fee')?.value as unknown as PlatformFeeSettings | undefined;
  const shippingZones = getSetting('shipping_zones')?.value as unknown as ShippingZonesSettings | undefined;
  const codSettings = getSetting('cod_settings')?.value as unknown as CODSettings | undefined;
  const adminPaymentInfo = getSetting('admin_payment_info')?.value as unknown as { bank_name: string; bank_account_number: string; bank_account_name: string; qris_image_url: string } | undefined;
  const freeTierQuota = getSetting('free_tier_quota')?.value as unknown as { limit: number } | undefined;
  const courierMinBalance = getSetting('courier_minimum_balance')?.value as unknown as { amount: number } | undefined;
  const helpFaqValue = getSetting('help_faq')?.value as unknown;
  const helpFaqItems = helpFaqValue && typeof helpFaqValue === 'object' && !Array.isArray(helpFaqValue) && 'items' in helpFaqValue
    ? (helpFaqValue as { items?: HelpFaqItem[] }).items
    : Array.isArray(helpFaqValue) ? helpFaqValue as HelpFaqItem[] : undefined;
  const helpCenterInitialValues = {
    legalName: getTextSetting(['company_legal_name', 'legal_name', 'company_name'], BUSINESS_PROFILE.legalName),
    address: getTextSetting(['business_address', 'address', 'company_address'], BUSINESS_PROFILE.address),
    phone: getTextSetting(['business_phone', 'support_phone', 'phone'], BUSINESS_PROFILE.phone),
    whatsapp: getTextSetting(['business_whatsapp', 'support_whatsapp', 'whatsapp'], BUSINESS_PROFILE.whatsapp),
    email: getTextSetting(['business_email', 'support_email', 'email'], BUSINESS_PROFILE.email),
    operatingHours: getTextSetting(['business_operating_hours', 'operating_hours', 'hours'], BUSINESS_PROFILE.operatingHours),
    serviceArea: getTextSetting(['business_service_area', 'service_area', 'coverage_area'], BUSINESS_PROFILE.serviceArea),
    faqs: helpFaqItems?.length ? helpFaqItems : DEFAULT_HELP_FAQS,
  };

  return (
    <AdminLayout title="Pengaturan" subtitle="Konfigurasi fitur dan kustomisasi aplikasi">
      <div className="max-w-4xl mx-auto">
          {loading ? (
            <div className="flex items-center justify-center py-20">
              <div className="animate-spin rounded-full h-10 w-10 border-2 border-primary border-t-transparent" />
            </div>
          ) : (
            <Tabs defaultValue="branding" className="space-y-6">
              <TabsList className="grid w-full grid-cols-4">
                <TabsTrigger value="branding">Kustomisasi</TabsTrigger>
                <TabsTrigger value="features">Fitur & Registrasi</TabsTrigger>
                <TabsTrigger value="shipping">Pengiriman</TabsTrigger>
                <TabsTrigger value="payment">Pembayaran & API</TabsTrigger>
              </TabsList>

              {/* Branding & Appearance Tab */}
              <TabsContent value="branding">
                <Card className="mb-6">
                  <CardHeader>
                    <CardTitle className="flex items-center gap-2">
                      <Palette className="h-5 w-5" />
                      Branding & Tampilan
                    </CardTitle>
                    <CardDescription>
                      Kelola identitas brand, pengaturan PWA, SEO, dan layout homepage
                    </CardDescription>
                  </CardHeader>
                  <CardContent>
                    <BrandingAppearanceSettings isSaving={saving} />
                  </CardContent>
                </Card>
                <Card>
                  <CardHeader>
                    <CardTitle className="flex items-center gap-2">
                      <Globe className="h-5 w-5" />
                      Informasi Kontak &amp; Pusat Bantuan
                    </CardTitle>
                    <CardDescription>
                      Data ini tampil di halaman <code>/help</code> dan <code>/contact</code>. FAQ dapat diubah tanpa mengubah kode aplikasi.
                    </CardDescription>
                  </CardHeader>
                  <CardContent>
                    <HelpCenterSettingsForm
                      initialValues={helpCenterInitialValues}
                      isSaving={saving === 'help_center'}
                      onSave={async (values) => {
                        setSaving('help_center');
                        const updates: Array<[string, Record<string, unknown>]> = [
                          ['company_legal_name', { value: values.legalName.trim() }],
                          ['business_address', { value: values.address.trim() }],
                          ['business_phone', { value: values.phone.trim() }],
                          ['business_whatsapp', { value: values.whatsapp.trim() }],
                          ['business_email', { value: values.email.trim() }],
                          ['business_operating_hours', { value: values.operatingHours.trim() }],
                          ['business_service_area', { value: values.serviceArea.trim() }],
                          ['help_faq', { items: values.faqs }],
                        ];
                        const results = await Promise.all(updates.map(([key, value]) => updateAppSetting(key, value)));
                        if (results.every(Boolean)) {
                          toast.success('Informasi kontak dan Pusat Bantuan berhasil disimpan');
                          await loadSettings();
                        } else {
                          toast.error('Sebagian pengaturan gagal disimpan');
                        }
                        setSaving(null);
                      }}
                    />
                  </CardContent>
                </Card>
              </TabsContent>

              {/* Features & Registration Tab */}
              <TabsContent value="features" className="space-y-6">
                <Card>
                  <CardHeader>
                    <CardTitle className="flex items-center gap-2">
                      <ToggleLeft className="h-5 w-5" />
                      Pengaturan Registrasi
                    </CardTitle>
                    <CardDescription>
                      Aktifkan atau nonaktifkan fitur pendaftaran untuk berbagai entitas
                    </CardDescription>
                  </CardHeader>
                  <CardContent className="space-y-4">
                    <div className="flex items-center justify-between p-4 bg-secondary/50 rounded-lg">
                      <div>
                        <p className="font-medium text-sm">Registrasi Desa Wisata</p>
                        <p className="text-xs text-muted-foreground">Izinkan pendaftaran desa wisata baru</p>
                      </div>
                      <Switch
                        checked={registrationVillage?.enabled ?? true}
                        onCheckedChange={() => handleToggleRegistration('registration_village', registrationVillage?.enabled ?? true)}
                        disabled={saving === 'registration_village'}
                      />
                    </div>

                    <div className="flex items-center justify-between p-4 bg-secondary/50 rounded-lg">
                      <div>
                        <p className="font-medium text-sm">Registrasi Pedagang/UMKM</p>
                        <p className="text-xs text-muted-foreground">Izinkan pendaftaran merchant baru</p>
                      </div>
                      <Switch
                        checked={registrationMerchant?.enabled ?? true}
                        onCheckedChange={() => handleToggleRegistration('registration_merchant', registrationMerchant?.enabled ?? true)}
                        disabled={saving === 'registration_merchant'}
                      />
                    </div>

                    <div className="flex items-center justify-between p-4 bg-secondary/50 rounded-lg">
                      <div>
                        <p className="font-medium text-sm">Registrasi Kurir/Ojek</p>
                        <p className="text-xs text-muted-foreground">Izinkan pendaftaran kurir atau ojek desa</p>
                      </div>
                      <Switch
                        checked={registrationCourier?.enabled ?? true}
                        onCheckedChange={() => handleToggleRegistration('registration_courier', registrationCourier?.enabled ?? true)}
                        disabled={saving === 'registration_courier'}
                      />
                    </div>

                    <div className="flex items-center justify-between p-4 bg-secondary/50 rounded-lg">
                      <div>
                        <p className="font-medium text-sm">Auto-Approve Pedagang/UMKM</p>
                        <p className="text-xs text-muted-foreground">Aktif sementara: pendaftaran merchant langsung disetujui tanpa verifikasi manual.</p>
                      </div>
                      <span className="rounded-full bg-success/10 px-3 py-1 text-xs font-semibold text-success">Aktif</span>
                    </div>
                  </CardContent>
                </Card>

                {/* Free Tier Quota */}
                <Card>
                  <CardHeader>
                    <CardTitle className="flex items-center gap-2">
                      <Package className="h-5 w-5" />
                      Kuota Gratis Merchant
                    </CardTitle>
                    <CardDescription>
                      Jumlah kuota transaksi gratis per bulan untuk merchant tanpa paket berbayar
                    </CardDescription>
                  </CardHeader>
                  <CardContent>
                    <FreeTierQuotaForm
                      initialLimit={freeTierQuota?.limit ?? 100}
                      onSave={async (limit) => {
                        setSaving('free_tier_quota');
                        const success = await updateAppSetting('free_tier_quota', { limit });
                        if (success) {
                          toast.success('Kuota gratis berhasil disimpan');
                          loadSettings();
                        } else {
                          toast.error('Gagal menyimpan');
                        }
                        setSaving(null);
                      }}
                      isSaving={saving === 'free_tier_quota'}
                    />
                  </CardContent>
                </Card>

                {/* Courier commission is configured in the authoritative wallet settings page. */}
                <Card>
                  <CardHeader>
                    <CardTitle className="flex items-center gap-2">
                      <Truck className="h-5 w-5" />
                      Komisi Kurir
                    </CardTitle>
                    <CardDescription>
                      Pengaturan komisi kurir dikelola bersama konfigurasi wallet dan payout aktual
                    </CardDescription>
                  </CardHeader>
                  <CardContent className="space-y-3">
                    <p className="text-sm text-muted-foreground">
                      Pengaturan legacy tidak lagi digunakan. Payout membaca tarif, status aktif, dan cakupan
                      pengiriman dari <code>commission_fee_settings</code>.
                    </p>
                    <Button asChild variant="outline">
                      <Link to="/admin/wallet-commissions">Buka pengaturan komisi wallet</Link>
                    </Button>
                  </CardContent>
                </Card>

                <Card>
                  <CardHeader>
                    <CardTitle className="flex items-center gap-2">
                      <ShieldCheck className="h-5 w-5" />
                      Pengaturan COD (Cash on Delivery)
                    </CardTitle>
                    <CardDescription>
                      Konfigurasi keamanan dan batasan fitur COD
                    </CardDescription>
                  </CardHeader>
                  <CardContent>
                    <CODSettingsForm
                      initialValues={codSettings}
                      onSave={async (values) => {
                        setSaving('cod_settings');
                        const success = await updateAppSetting('cod_settings', values as unknown as Record<string, unknown>);
                        if (success) {
                          clearCODSettingsCache();
                          toast.success('Pengaturan COD berhasil disimpan');
                          loadSettings();
                        } else {
                          toast.error('Gagal menyimpan pengaturan');
                        }
                        setSaving(null);
                      }}
                      isSaving={saving === 'cod_settings'}
                    />
                  </CardContent>
                </Card>

                <Card>
                  <CardHeader>
                    <CardTitle className="flex items-center gap-2">
                      <Percent className="h-5 w-5" />
                      Pengaturan Biaya Platform
                    </CardTitle>
                    <CardDescription>
                      Konfigurasi komisi platform dari setiap transaksi
                    </CardDescription>
                  </CardHeader>
                  <CardContent>
                    <PlatformFeeForm
                      initialValues={platformFee}
                      onSave={async (values) => {
                        setSaving('platform_fee');
                        const success = await updateAppSetting('platform_fee', values as unknown as Record<string, unknown>);
                        if (success) {
                          toast.success('Pengaturan biaya platform berhasil disimpan');
                          loadSettings();
                        } else {
                          toast.error('Gagal menyimpan pengaturan');
                        }
                        setSaving(null);
                      }}
                      isSaving={saving === 'platform_fee'}
                    />
                  </CardContent>
                </Card>
              </TabsContent>

              {/* Shipping Tab */}
              <TabsContent value="shipping" className="space-y-6">
                <Card>
                  <CardHeader>
                    <CardTitle className="flex items-center gap-2">
                      <Truck className="h-5 w-5" />
                      Pengaturan Biaya Kirim
                    </CardTitle>
                    <CardDescription>
                      Konfigurasi biaya pengiriman berdasarkan jarak dan zona
                    </CardDescription>
                  </CardHeader>
                  <CardContent className="space-y-6">
                    <ShippingFeeForm
                      initialValues={shippingBaseFee}
                      onSave={async (values) => {
                        setSaving('shipping_base_fee');
                        const success = await updateAppSetting('shipping_base_fee', values as unknown as Record<string, unknown>);
                        if (success) {
                          toast.success('Pengaturan biaya kirim berhasil disimpan');
                          loadSettings();
                          void loadShippingAudit();
                        } else {
                          toast.error('Gagal menyimpan pengaturan');
                        }
                        setSaving(null);
                      }}
                      isSaving={saving === 'shipping_base_fee'}
                    />

                    <div className="border-t border-border pt-6">
                      <h4 className="font-medium mb-4">Zona Pengiriman dan Kesulitan Jalan</h4>
                      <p className="mb-4 text-sm text-muted-foreground">Ongkir ojek tetap dihitung berdasarkan jarak. Fee zona ditambahkan sebagai surcharge untuk jalan yang lebih sulit.</p>
                      <ShippingZonesForm
                        initialValues={shippingZones}
                        onSave={async (values) => {
                          setSaving('shipping_zones');
                          const success = await updateAppSetting('shipping_zones', values as unknown as Record<string, unknown>);
                          if (success) {
                            toast.success('Zona pengiriman berhasil disimpan');
                            loadSettings();
                            void loadShippingAudit();
                          } else {
                            toast.error('Gagal menyimpan zona');
                          }
                          setSaving(null);
                        }}
                        isSaving={saving === 'shipping_zones'}
                      />
                    </div>
                  </CardContent>
                </Card>

                <Card>
                  <CardHeader>
                    <CardTitle>Riwayat perubahan tarif</CardTitle>
                    <CardDescription>25 perubahan terakhir untuk tarif dasar dan zona pengiriman.</CardDescription>
                  </CardHeader>
                  <CardContent>
                    {shippingAuditLoading ? (
                      <p className="text-sm text-muted-foreground">Memuat riwayat perubahan...</p>
                    ) : shippingAuditError ? (
                      <p role="alert" className="text-sm text-destructive">Riwayat perubahan belum dapat dimuat.</p>
                    ) : shippingAudit.length === 0 ? (
                      <p className="text-sm text-muted-foreground">Belum ada perubahan tarif yang tercatat.</p>
                    ) : (
                      <div className="space-y-3">
                        {shippingAudit.map((entry) => (
                          <div key={entry.id} className="rounded-lg border p-3">
                            <div className="flex flex-wrap items-start justify-between gap-2">
                              <div>
                                <p className="text-sm font-medium">
                                  {entry.setting_key === 'shipping_base_fee' ? 'Tarif dasar' : 'Zona pengiriman'}
                                </p>
                                <p className="text-xs text-muted-foreground">
                                  {new Date(entry.created_at).toLocaleString('id-ID')} · {entry.changed_by ? `Admin ${entry.changed_by.slice(0, 8)}` : 'Sistem'}
                                </p>
                              </div>
                            </div>
                            <details className="mt-2 text-xs">
                              <summary className="cursor-pointer text-primary">Lihat nilai sebelum dan sesudah</summary>
                              <div className="mt-2 grid gap-2 md:grid-cols-2">
                                <div><p className="mb-1 text-muted-foreground">Sebelum</p><pre className="overflow-x-auto whitespace-pre-wrap rounded bg-secondary p-2">{JSON.stringify(entry.old_value, null, 2) ?? '—'}</pre></div>
                                <div><p className="mb-1 text-muted-foreground">Sesudah</p><pre className="overflow-x-auto whitespace-pre-wrap rounded bg-secondary p-2">{JSON.stringify(entry.new_value, null, 2) ?? '—'}</pre></div>
                              </div>
                            </details>
                          </div>
                        ))}
                      </div>
                    )}
                  </CardContent>
                </Card>

                {/* Courier Minimum Balance */}
                <Card>
                  <CardHeader>
                    <CardTitle className="flex items-center gap-2">
                      <Truck className="h-5 w-5" />
                      Saldo Minimum Kurir
                    </CardTitle>
                    <CardDescription>
                      Saldo minimum yang harus tersisa saat kurir melakukan penarikan
                    </CardDescription>
                  </CardHeader>
                  <CardContent>
                    <CourierMinBalanceForm
                      initialAmount={courierMinBalance?.amount ?? 50000}
                      onSave={async (amount) => {
                        setSaving('courier_minimum_balance');
                        const success = await updateAppSetting('courier_minimum_balance', { amount });
                        if (success) {
                          toast.success('Saldo minimum kurir berhasil disimpan');
                          loadSettings();
                        } else {
                          toast.error('Gagal menyimpan');
                        }
                        setSaving(null);
                      }}
                      isSaving={saving === 'courier_minimum_balance'}
                    />
                  </CardContent>
                </Card>
              </TabsContent>

              {/* Payment & API Tab */}
              <TabsContent value="payment" className="space-y-6">
                {/* Admin Default Payment Info */}
                <Card>
                  <CardHeader>
                    <CardTitle className="flex items-center gap-2">
                      <CreditCard className="h-5 w-5" />
                      Rekening & QRIS Default Admin
                    </CardTitle>
                    <CardDescription>
                      Rekening dan QRIS ini digunakan untuk merchant yang belum mengatur pembayaran sendiri
                    </CardDescription>
                  </CardHeader>
                  <CardContent>
                    <AdminPaymentInfoForm
                      initialValues={adminPaymentInfo}
                      onSave={async (values) => {
                        setSaving('admin_payment_info');
                        const success = await updateAppSetting('admin_payment_info', values as unknown as Record<string, unknown>);
                        if (success) {
                          toast.success('Rekening default berhasil disimpan');
                          loadSettings();
                        } else {
                          toast.error('Gagal menyimpan');
                        }
                        setSaving(null);
                      }}
                      isSaving={saving === 'admin_payment_info'}
                    />
                  </CardContent>
                </Card>

                <Card>
                  <CardHeader>
                    <CardTitle className="flex items-center gap-2">
                      <Globe className="h-5 w-5" />
                      API Alamat Wilayah
                    </CardTitle>
                    <CardDescription>Sumber data wilayah Indonesia yang digunakan seluruh formulir alamat</CardDescription>
                  </CardHeader>
                  <CardContent className="space-y-2 text-sm">
                    <p><span className="font-medium">Provider:</span> EMSIFA API v2</p>
                    <p><span className="font-medium">Base URL:</span> https://www.emsifa.com/api-wilayah-indonesia/v2</p>
                    <p className="text-muted-foreground">Data dimuat melalui Supabase Edge Function dengan fallback langsung ke EMSIFA v2. Provider ini dikunci agar semua formulir memakai sumber data yang sama.</p>
                  </CardContent>
                </Card>

                <Card>
                  <CardHeader>
                    <CardTitle className="flex items-center gap-2">
                      <CreditCard className="h-5 w-5" />
                      Payment Gateway
                    </CardTitle>
                    <CardDescription>
                      Konfigurasi gateway pembayaran (Midtrans & Xendit)
                    </CardDescription>
                  </CardHeader>
                  <CardContent className="space-y-6">
                    <div className="border border-border rounded-lg p-4">
                      <div className="flex items-center justify-between mb-4">
                        <div>
                          <h3 className="font-medium">Midtrans</h3>
                        </div>
                        <Switch
                          checked={paymentMidtrans?.enabled ?? false}
                          onCheckedChange={(checked) => handleSavePayment('payment_midtrans', { ...paymentMidtrans, enabled: checked } as PaymentSettings)}
                          disabled={saving === 'payment_midtrans'}
                        />
                      </div>
                      {paymentMidtrans?.enabled && (
                        <PaymentMidtransForm
                          initialValues={paymentMidtrans}
                          onSave={(values) => handleSavePayment('payment_midtrans', values)}
                          isSaving={saving === 'payment_midtrans'}
                        />
                      )}
                    </div>

                    <div className="border border-border rounded-lg p-4">
                      <div className="flex items-center justify-between mb-4">
                        <div>
                          <h3 className="font-medium">Xendit</h3>
                        </div>
                        <Switch
                          checked={paymentXendit?.enabled ?? false}
                          onCheckedChange={(checked) => handleSavePayment('payment_xendit', { ...paymentXendit, enabled: checked } as PaymentSettings)}
                          disabled={saving === 'payment_xendit'}
                        />
                      </div>
                      {paymentXendit?.enabled && (
                        <PaymentXenditForm
                          initialValues={paymentXendit}
                          onSave={(values) => handleSavePayment('payment_xendit', values)}
                          isSaving={saving === 'payment_xendit'}
                        />
                      )}
                    </div>
                  </CardContent>
                </Card>
              </TabsContent>
            </Tabs>
          )}
      </div>
    </AdminLayout>
  );
}

interface HelpCenterSettingsValues {
  legalName: string;
  address: string;
  phone: string;
  whatsapp: string;
  email: string;
  operatingHours: string;
  serviceArea: string;
  faqs: HelpFaqItem[];
}

function HelpCenterSettingsForm({ initialValues, onSave, isSaving }: { initialValues: HelpCenterSettingsValues; onSave: (values: HelpCenterSettingsValues) => Promise<void>; isSaving: boolean }) {
  const [values, setValues] = useState<HelpCenterSettingsValues>(() => ({ ...initialValues, faqs: initialValues.faqs.map(item => ({ ...item })) }));
  const updateField = (field: Exclude<keyof HelpCenterSettingsValues, 'faqs'>, value: string) => setValues(prev => ({ ...prev, [field]: value }));
  const updateFaq = (index: number, field: keyof HelpFaqItem, value: string) => setValues(prev => ({
    ...prev,
    faqs: prev.faqs.map((item, currentIndex) => currentIndex === index ? { ...item, [field]: value } : item),
  }));
  const addFaq = () => setValues(prev => ({ ...prev, faqs: [...prev.faqs, { question: '', answer: '' }] }));
  const removeFaq = (index: number) => setValues(prev => ({ ...prev, faqs: prev.faqs.filter((_, currentIndex) => currentIndex !== index) }));
  const handleSubmit = (event: React.FormEvent) => {
    event.preventDefault();
    const faqs = values.faqs
      .map(item => ({ question: item.question.trim(), answer: item.answer.trim() }))
      .filter(item => item.question && item.answer);
    if (!values.email.trim() || faqs.length === 0) return;
    void onSave({ ...values, faqs });
  };
  return (
    <form onSubmit={handleSubmit} className="space-y-6">
      <div className="grid gap-4 md:grid-cols-2">
        <div className="space-y-2"><Label>Nama badan usaha</Label><Input value={values.legalName} onChange={event => updateField('legalName', event.target.value)} /></div>
        <div className="space-y-2"><Label>Email bantuan <span className="text-destructive">*</span></Label><Input type="email" value={values.email} onChange={event => updateField('email', event.target.value)} required /></div>
        <div className="space-y-2"><Label>Telepon hotline</Label><Input value={values.phone} onChange={event => updateField('phone', event.target.value)} placeholder="Contoh: 081234567890" /></div>
        <div className="space-y-2"><Label>WhatsApp layanan</Label><Input value={values.whatsapp} onChange={event => updateField('whatsapp', event.target.value)} placeholder="Contoh: 081234567890" /></div>
        <div className="space-y-2 md:col-span-2"><Label>Alamat operasional / unit pelayanan</Label><Textarea value={values.address} onChange={event => updateField('address', event.target.value)} rows={2} /></div>
        <div className="space-y-2"><Label>Jam operasional</Label><Input value={values.operatingHours} onChange={event => updateField('operatingHours', event.target.value)} /></div>
        <div className="space-y-2"><Label>Wilayah layanan</Label><Input value={values.serviceArea} onChange={event => updateField('serviceArea', event.target.value)} /></div>
      </div>
      <div className="space-y-3 border-t pt-5">
        <div className="flex items-center justify-between gap-3"><div><h3 className="font-semibold">Pertanyaan Umum (FAQ)</h3><p className="text-xs text-muted-foreground">Tampil di /help dan /contact.</p></div><Button type="button" variant="outline" onClick={addFaq}><Plus className="mr-2 h-4 w-4" />Tambah FAQ</Button></div>
        {values.faqs.map((item, index) => (
          <div key={`faq-${index}`} className="space-y-3 rounded-lg border bg-secondary/30 p-3">
            <div className="flex items-center justify-between gap-2"><Label>Pertanyaan {index + 1}</Label><Button type="button" variant="ghost" size="icon" aria-label={`Hapus FAQ ${index + 1}`} onClick={() => removeFaq(index)} disabled={values.faqs.length <= 1}><Trash2 className="h-4 w-4 text-destructive" /></Button></div>
            <Input value={item.question} onChange={event => updateFaq(index, 'question', event.target.value)} placeholder="Tulis pertanyaan" />
            <Textarea value={item.answer} onChange={event => updateFaq(index, 'answer', event.target.value)} placeholder="Tulis jawaban" rows={3} />
          </div>
        ))}
      </div>
      <Button type="submit" disabled={isSaving || !values.email.trim() || !values.faqs.some(item => item.question.trim() && item.answer.trim())}><Save className="mr-2 h-4 w-4" />{isSaving ? 'Menyimpan...' : 'Simpan Informasi Bantuan'}</Button>
    </form>
  );
}

function PaymentMidtransForm({ initialValues, onSave, isSaving }: { initialValues?: PaymentSettings; onSave: (values: PaymentSettings) => Promise<void>; isSaving: boolean; }) {
  const [serverKey, setServerKey] = useState(initialValues?.server_key || '');
  const [clientKey, setClientKey] = useState(initialValues?.client_key || '');
  const [isProduction, setIsProduction] = useState(initialValues?.is_production || false);
  const handleSubmit = (e: React.FormEvent) => { e.preventDefault(); onSave({ enabled: true, server_key: serverKey, client_key: clientKey, is_production: isProduction }); };
  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <div className="grid gap-4 md:grid-cols-2">
        <div className="space-y-2"><Label>Server Key</Label><Input type="password" value={serverKey} onChange={(e) => setServerKey(e.target.value)} /></div>
        <div className="space-y-2"><Label>Client Key</Label><Input value={clientKey} onChange={(e) => setClientKey(e.target.value)} /></div>
      </div>
      <div className="flex items-center gap-2"><Switch checked={isProduction} onCheckedChange={setIsProduction} /><Label className="text-sm">Mode Production</Label></div>
      <Button type="submit" disabled={isSaving}><Save className="h-4 w-4 mr-2" /> {isSaving ? 'Menyimpan...' : 'Simpan'}</Button>
    </form>
  );
}

function PaymentXenditForm({ initialValues, onSave, isSaving }: { initialValues?: PaymentSettings; onSave: (values: PaymentSettings) => Promise<void>; isSaving: boolean; }) {
  const [secretKey, setSecretKey] = useState(initialValues?.secret_key || '');
  const [publicKey, setPublicKey] = useState(initialValues?.public_key || '');
  const [callbackToken, setCallbackToken] = useState(initialValues?.callback_token || '');
  const [isProduction, setIsProduction] = useState(initialValues?.is_production || false);
  const handleSubmit = (e: React.FormEvent) => { e.preventDefault(); onSave({ enabled: true, secret_key: secretKey, public_key: publicKey, callback_token: callbackToken, is_production: isProduction }); };
  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <div className="grid gap-4 md:grid-cols-2">
        <div className="space-y-2"><Label>Secret Key</Label><Input type="password" value={secretKey} onChange={(e) => setSecretKey(e.target.value)} /></div>
        <div className="space-y-2"><Label>Public Key</Label><Input value={publicKey} onChange={(e) => setPublicKey(e.target.value)} /></div>
        <div className="space-y-2"><Label>Callback Token</Label><Input type="password" value={callbackToken} onChange={(e) => setCallbackToken(e.target.value)} /></div>
      </div>
      <div className="flex items-center gap-2"><Switch checked={isProduction} onCheckedChange={setIsProduction} /><Label className="text-sm">Mode Production</Label></div>
      <Button type="submit" disabled={isSaving}><Save className="h-4 w-4 mr-2" /> {isSaving ? 'Menyimpan...' : 'Simpan'}</Button>
    </form>
  );
}

function ShippingFeeForm({ initialValues, onSave, isSaving }: { initialValues?: ShippingFeeSettings; onSave: (values: ShippingFeeSettings) => Promise<void>; isSaving: boolean; }) {
  const [baseFee, setBaseFee] = useState(initialValues?.base_fee?.toString() || '5000');
  const [perKmFee, setPerKmFee] = useState(initialValues?.per_km_fee?.toString() || '2000');
  const [minFee, setMinFee] = useState(initialValues?.min_fee?.toString() || '5000');
  const [maxFee, setMaxFee] = useState(initialValues?.max_fee?.toString() || '50000');
  const [freeShippingMinOrder, setFreeShippingMinOrder] = useState(initialValues?.free_shipping_min_order?.toString() || '100000');
  const [validationError, setValidationError] = useState<string | null>(null);
  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    const values = {
      base_fee: baseFee.trim() ? Number(baseFee) : Number.NaN,
      per_km_fee: perKmFee.trim() ? Number(perKmFee) : Number.NaN,
      min_fee: minFee.trim() ? Number(minFee) : Number.NaN,
      max_fee: maxFee.trim() ? Number(maxFee) : Number.NaN,
      free_shipping_min_order: freeShippingMinOrder.trim() ? Number(freeShippingMinOrder) : Number.NaN,
    };
    const errors = validateShippingFeeSettings(values);
    if (errors.length) {
      setValidationError(errors[0]);
      return;
    }
    setValidationError(null);
    void onSave(values);
  };
  const updateValue = (setter: (value: string) => void) => (value: string) => {
    setter(value);
    setValidationError(null);
  };
  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <div className="grid gap-4 md:grid-cols-2">
        <div className="space-y-2"><Label>Biaya Dasar (Rp)</Label><Input type="number" min="0" step="1" value={baseFee} onChange={(e) => updateValue(setBaseFee)(e.target.value)} /></div>
        <div className="space-y-2"><Label>Biaya per KM (Rp)</Label><Input type="number" min="0" step="1" value={perKmFee} onChange={(e) => updateValue(setPerKmFee)(e.target.value)} /></div>
        <div className="space-y-2"><Label>Biaya Minimum (Rp)</Label><Input type="number" min="0" step="1" value={minFee} onChange={(e) => updateValue(setMinFee)(e.target.value)} /></div>
        <div className="space-y-2"><Label>Biaya Maksimum (Rp)</Label><Input type="number" min="0" step="1" value={maxFee} onChange={(e) => updateValue(setMaxFee)(e.target.value)} /></div>
      </div>
      <div className="space-y-2"><Label>Gratis Ongkir Min. Order (Rp)</Label><Input type="number" min="0" step="1" value={freeShippingMinOrder} onChange={(e) => updateValue(setFreeShippingMinOrder)(e.target.value)} /></div>
      {validationError && <p role="alert" data-testid="shipping-fee-validation-error" className="text-sm text-destructive">{validationError}</p>}
      <Button type="submit" disabled={isSaving}><Save className="h-4 w-4 mr-2" /> {isSaving ? 'Menyimpan...' : 'Simpan'}</Button>
    </form>
  );
}

function ShippingZonesForm({ initialValues, onSave, isSaving }: { initialValues?: ShippingZonesSettings; onSave: (values: ShippingZonesSettings) => Promise<void>; isSaving: boolean; }) {
  const [zones, setZones] = useState<ShippingZone[]>(initialValues?.zones || [{ name: 'Dalam Desa', max_distance_km: 5, fee: 5000 }]);
  const [validationError, setValidationError] = useState<string | null>(null);
  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    const errors = validateShippingZonesSettings({ zones });
    if (errors.length) {
      setValidationError(errors[0]);
      return;
    }
    setValidationError(null);
    void onSave({ zones });
  };
  const updateZone = (index: number, field: keyof ShippingZone, value: string) => {
    setZones((prev) => prev.map((zone, currentIndex) => currentIndex === index
      ? { ...zone, [field]: field === 'name' ? value : value.trim() ? Number(value) : Number.NaN }
      : zone));
    setValidationError(null);
  };
  const addZone = () => {
    setZones((prev) => {
      const lastDistance = prev[prev.length - 1]?.max_distance_km;
      const nextDistance = Number.isFinite(lastDistance) && lastDistance > 0 ? lastDistance + 5 : 5;
      return [...prev, { name: 'Zona Baru', max_distance_km: nextDistance, fee: 0 }];
    });
    setValidationError(null);
  };
  const removeZone = (index: number) => { setZones(prev => prev.filter((_, i) => i !== index)); };
  const moveZone = (index: number, direction: -1 | 1) => {
    setZones((prev) => {
      const nextIndex = index + direction;
      if (nextIndex < 0 || nextIndex >= prev.length) return prev;
      const reordered = [...prev];
      [reordered[index], reordered[nextIndex]] = [reordered[nextIndex], reordered[index]];
      return reordered;
    });
    setValidationError(null);
  };
  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <p className="text-xs text-muted-foreground">Urutkan batas zona dari jarak terdekat ke terjauh. Batas jarak tidak boleh berulang agar rentang zona tidak tumpang tindih.</p>
      <div className="space-y-3">
        {zones.map((zone, index) => (
          <div key={`${index}-${zone.name}`} className="flex items-center gap-2 p-3 bg-secondary/50 rounded-lg">
            <div className="flex-1 grid gap-2 md:grid-cols-3">
              <Input aria-label={`Nama zona ${index + 1}`} value={zone.name} onChange={(e) => updateZone(index, 'name', e.target.value)} />
              <Input type="number" min="0" step="any" aria-label={`Batas jarak zona ${index + 1} (km)`} value={Number.isFinite(zone.max_distance_km) ? zone.max_distance_km : ''} onChange={(e) => updateZone(index, 'max_distance_km', e.target.value)} />
              <Input type="number" min="0" step="1" aria-label={`Surcharge zona ${index + 1} (Rp)`} value={Number.isFinite(zone.fee) ? zone.fee : ''} onChange={(e) => updateZone(index, 'fee', e.target.value)} />
            </div>
            <div className="flex shrink-0 items-center">
              <Button type="button" variant="ghost" size="icon" aria-label={`Pindahkan zona ${index + 1} ke atas`} onClick={() => moveZone(index, -1)} disabled={index === 0}><ArrowUp className="h-4 w-4" /></Button>
              <Button type="button" variant="ghost" size="icon" aria-label={`Pindahkan zona ${index + 1} ke bawah`} onClick={() => moveZone(index, 1)} disabled={index === zones.length - 1}><ArrowDown className="h-4 w-4" /></Button>
              <Button type="button" variant="ghost" size="icon" aria-label={`Hapus zona ${index + 1}`} onClick={() => removeZone(index)} disabled={zones.length <= 1}><Trash2 className="h-4 w-4 text-destructive" /></Button>
            </div>
          </div>
        ))}
      </div>
      {validationError && <p role="alert" data-testid="shipping-zones-validation-error" className="text-sm text-destructive">{validationError}</p>}
      <div className="flex items-center gap-2"><Button type="button" variant="outline" onClick={addZone}><Plus className="h-4 w-4 mr-2" /> Tambah Zona</Button><Button type="submit" disabled={isSaving}><Save className="h-4 w-4 mr-2" /> {isSaving ? 'Menyimpan...' : 'Simpan'}</Button></div>
    </form>
  );
}

function PlatformFeeForm({ initialValues, onSave, isSaving }: { initialValues?: PlatformFeeSettings; onSave: (values: PlatformFeeSettings) => Promise<void>; isSaving: boolean; }) {
  const [enabled, setEnabled] = useState(initialValues?.enabled ?? true);
  const [percentage, setPercentage] = useState(initialValues?.percentage?.toString() || '5');
  const [minFee, setMinFee] = useState(initialValues?.min_fee?.toString() || '1000');
  const [maxFee, setMaxFee] = useState(initialValues?.max_fee?.toString() || '50000');
  const handleSubmit = (e: React.FormEvent) => { e.preventDefault(); onSave({ enabled, percentage: parseFloat(percentage) || 0, min_fee: parseInt(minFee) || 0, max_fee: parseInt(maxFee) || 0 }); };
  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <div className="flex items-center justify-between p-4 bg-secondary/50 rounded-lg"><div><p className="font-medium text-sm">Aktifkan Biaya Platform</p></div><Switch checked={enabled} onCheckedChange={setEnabled} /></div>
      {enabled && <div className="grid gap-4 md:grid-cols-3"><div className="space-y-2"><Label>Persentase (%)</Label><Input type="number" step="0.1" value={percentage} onChange={(e) => setPercentage(e.target.value)} /></div><div className="space-y-2"><Label>Minimum (Rp)</Label><Input type="number" value={minFee} onChange={(e) => setMinFee(e.target.value)} /></div><div className="space-y-2"><Label>Maksimum (Rp)</Label><Input type="number" value={maxFee} onChange={(e) => setMaxFee(e.target.value)} /></div></div>}
      <Button type="submit" disabled={isSaving}><Save className="h-4 w-4 mr-2" /> {isSaving ? 'Menyimpan...' : 'Simpan'}</Button>
    </form>
  );
}

function CODSettingsForm({ initialValues, onSave, isSaving }: { initialValues?: CODSettings; onSave: (values: CODSettings) => Promise<void>; isSaving: boolean; }) {
  const [enabled, setEnabled] = useState(initialValues?.enabled ?? true);
  const [maxAmount, setMaxAmount] = useState(initialValues?.max_amount?.toString() || '75000');
  const [maxDistance, setMaxDistance] = useState(initialValues?.max_distance_km?.toString() || '3');
  const [minTrustScore, setMinTrustScore] = useState(initialValues?.min_trust_score?.toString() || '50');
  const [confirmationTimeout, setConfirmationTimeout] = useState(initialValues?.confirmation_timeout_minutes?.toString() || '15');
  const [penaltyPoints, setPenaltyPoints] = useState(initialValues?.penalty_points?.toString() || '50');
  const [successBonus, setSuccessBonus] = useState(initialValues?.success_bonus_points?.toString() || '1');
  const handleSubmit = (e: React.FormEvent) => { e.preventDefault(); onSave({ enabled, max_amount: parseInt(maxAmount) || 75000, max_distance_km: parseInt(maxDistance) || 3, service_fee: 0, min_trust_score: parseInt(minTrustScore) || 50, confirmation_timeout_minutes: parseInt(confirmationTimeout) || 15, penalty_points: parseInt(penaltyPoints) || 50, success_bonus_points: parseInt(successBonus) || 1 }); };
  return (
    <form onSubmit={handleSubmit} className="space-y-6">
      <div className="flex items-center justify-between p-4 bg-secondary/50 rounded-lg"><div><p className="font-medium text-sm">Aktifkan Fitur COD</p></div><Switch checked={enabled} onCheckedChange={setEnabled} /></div>
      {enabled && <div className="grid gap-4 md:grid-cols-2"><div className="space-y-2"><Label>Maksimal Nominal COD (Rp)</Label><Input type="number" value={maxAmount} onChange={(e) => setMaxAmount(e.target.value)} /></div><div className="space-y-2"><Label>Maksimal Jarak (KM)</Label><Input type="number" value={maxDistance} onChange={(e) => setMaxDistance(e.target.value)} /></div></div>}
      <Button type="submit" disabled={isSaving}><Save className="h-4 w-4 mr-2" /> {isSaving ? 'Menyimpan...' : 'Simpan'}</Button>
    </form>
  );
}

interface AdminPaymentInfoValues {
  bank_name: string;
  bank_account_number: string;
  bank_account_name: string;
  qris_image_url: string;
}

function AdminPaymentInfoForm({ initialValues, onSave, isSaving }: { initialValues?: AdminPaymentInfoValues; onSave: (values: AdminPaymentInfoValues) => Promise<void>; isSaving: boolean; }) {
  const [bankName, setBankName] = useState(initialValues?.bank_name || '');
  const [bankAccountNumber, setBankAccountNumber] = useState(initialValues?.bank_account_number || '');
  const [bankAccountName, setBankAccountName] = useState(initialValues?.bank_account_name || '');
  const [qrisImageUrl, setQrisImageUrl] = useState(initialValues?.qris_image_url || '');

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    onSave({ bank_name: bankName, bank_account_number: bankAccountNumber, bank_account_name: bankAccountName, qris_image_url: qrisImageUrl });
  };

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <div className="grid gap-4 md:grid-cols-3">
        <div className="space-y-2">
          <Label>Nama Bank</Label>
          <Input value={bankName} onChange={(e) => setBankName(e.target.value)} placeholder="BRI, BCA, Mandiri" />
        </div>
        <div className="space-y-2">
          <Label>Nomor Rekening</Label>
          <Input value={bankAccountNumber} onChange={(e) => setBankAccountNumber(e.target.value)} placeholder="Nomor rekening admin" />
        </div>
        <div className="space-y-2">
          <Label>Atas Nama</Label>
          <Input value={bankAccountName} onChange={(e) => setBankAccountName(e.target.value)} placeholder="Nama pemilik" />
        </div>
      </div>
      <div className="space-y-2">
        <Label>Gambar QRIS Admin</Label>
        <ImageUpload
          value={qrisImageUrl || null}
          onChange={(url) => setQrisImageUrl(url || '')}
          bucket="admin-assets"
          path="qris"
          aspectRatio="square"
          placeholder="Upload gambar QRIS"
          maxSizeMB={3}
        />
      </div>
      <Button type="submit" disabled={isSaving}><Save className="h-4 w-4 mr-2" /> {isSaving ? 'Menyimpan...' : 'Simpan'}</Button>
    </form>
  );
}

function FreeTierQuotaForm({ initialLimit, onSave, isSaving }: { initialLimit: number; onSave: (limit: number) => Promise<void>; isSaving: boolean }) {
  const [limit, setLimit] = useState(initialLimit.toString());
  const handleSubmit = (e: React.FormEvent) => { e.preventDefault(); onSave(parseInt(limit) || 100); };
  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <div className="space-y-2">
        <Label>Jumlah Kuota Gratis per Bulan</Label>
        <Input type="number" value={limit} onChange={(e) => setLimit(e.target.value)} min={0} />
        <p className="text-xs text-muted-foreground">Merchant tanpa paket berbayar akan mendapat kuota ini setiap bulan secara gratis</p>
      </div>
      <Button type="submit" disabled={isSaving}><Save className="h-4 w-4 mr-2" /> {isSaving ? 'Menyimpan...' : 'Simpan'}</Button>
    </form>
  );
}

function CourierMinBalanceForm({ initialAmount, onSave, isSaving }: { initialAmount: number; onSave: (amount: number) => Promise<void>; isSaving: boolean }) {
  const [amount, setAmount] = useState(initialAmount.toString());
  const handleSubmit = (e: React.FormEvent) => { e.preventDefault(); onSave(parseInt(amount) || 50000); };
  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <div className="space-y-2">
        <Label>Saldo Minimum (Rp)</Label>
        <Input type="number" value={amount} onChange={(e) => setAmount(e.target.value)} min={0} step={1000} />
        <p className="text-xs text-muted-foreground">Kurir harus menyisakan minimal saldo ini saat melakukan penarikan</p>
      </div>
      <Button type="submit" disabled={isSaving}><Save className="h-4 w-4 mr-2" /> {isSaving ? 'Menyimpan...' : 'Simpan'}</Button>
    </form>
  );
}

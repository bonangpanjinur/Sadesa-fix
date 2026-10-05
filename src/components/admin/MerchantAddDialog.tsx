import { useEffect, useMemo, useState } from 'react';
import { Check, Clock, ImagePlus, Loader2, MapPin, Plus, Save, Shield, Store, User } from 'lucide-react';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Checkbox } from '@/components/ui/checkbox';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { ImageUpload } from '@/components/ui/ImageUpload';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { fetchDistricts, fetchProvinces, fetchRegencies, fetchVillages, type Region } from '@/lib/addressApi';
import { AdminLocationPicker } from './AdminLocationPicker';
import { getAvailableMerchantUsers, type MerchantUser } from '@/lib/adminApi';
import { useAdminCategories } from '@/hooks/useAdminCategories';

interface MerchantAddDialogProps { open: boolean; onOpenChange: (open: boolean) => void; onSuccess: () => void; }
type ScheduleDay = { open_time: string; close_time: string; is_closed: boolean };
type WeeklySchedule = Record<number, ScheduleDay>;

const DAYS = [
  { day: 1, label: 'Senin' }, { day: 2, label: 'Selasa' }, { day: 3, label: 'Rabu' },
  { day: 4, label: 'Kamis' }, { day: 5, label: 'Jumat' }, { day: 6, label: 'Sabtu' }, { day: 0, label: 'Minggu' },
];
const createSchedule = (): WeeklySchedule => Object.fromEntries(DAYS.map(({ day }) => [day, { open_time: '08:00', close_time: '21:00', is_closed: false }])) as WeeklySchedule;

const initialForm = {
  name: '', user_id: '', phone: '', address: '', province_code: '', province_name: '', regency_code: '', regency_name: '',
  district_code: '', district_name: '', village_code: '', village_name: '', village_id: '', business_description: '',
  is_open: false, image_url: null as string | null, cover_image_url: null as string | null, location_lat: null as number | null,
  location_lng: null as number | null, verifikator_code: '',
};

export function MerchantAddDialog({ open, onOpenChange, onSuccess }: MerchantAddDialogProps) {
  const { data: categories = [], isLoading: categoriesLoading } = useAdminCategories();
  const [formData, setFormData] = useState(initialForm);
  const [selectedCategoryIds, setSelectedCategoryIds] = useState<string[]>([]);
  const [schedule, setSchedule] = useState<WeeklySchedule>(createSchedule);
  const [provinces, setProvinces] = useState<Region[]>([]);
  const [regencies, setRegencies] = useState<Region[]>([]);
  const [districts, setDistricts] = useState<Region[]>([]);
  const [villages, setVillages] = useState<Region[]>([]);
  const [availableUsers, setAvailableUsers] = useState<MerchantUser[]>([]);
  const [loading, setLoading] = useState(false);
  const [loadingAddress, setLoadingAddress] = useState(false);
  const [loadingUsers, setLoadingUsers] = useState(false);
  const [verifikatorName, setVerifikatorName] = useState<string | null>(null);
  const [verifikatorValid, setVerifikatorValid] = useState<boolean | null>(null);

  const selectedCategories = useMemo(() => categories.filter((category) => selectedCategoryIds.includes(category.id)), [categories, selectedCategoryIds]);
  const update = <K extends keyof typeof initialForm>(key: K, value: (typeof initialForm)[K]) => setFormData((current) => ({ ...current, [key]: value }));

  useEffect(() => {
    if (!open) return;
    setFormData(initialForm);
    setSelectedCategoryIds([]);
    setSchedule(createSchedule());
    setVerifikatorName(null);
    setVerifikatorValid(null);
    void (async () => {
      setLoadingUsers(true);
      try { setProvinces(await fetchProvinces()); setAvailableUsers(await getAvailableMerchantUsers()); }
      catch { toast.error('Gagal memuat data awal formulir pedagang'); }
      finally { setLoadingUsers(false); }
    })();
  }, [open]);

  const handleProvince = async (code: string) => {
    const selected = provinces.find((item) => item.code === code); if (!selected) return;
    setFormData((current) => ({ ...current, province_code: code, province_name: selected.name, regency_code: '', regency_name: '', district_code: '', district_name: '', village_code: '', village_name: '', village_id: '' }));
    setRegencies([]); setDistricts([]); setVillages([]); setLoadingAddress(true);
    try { setRegencies(await fetchRegencies(code)); } catch { toast.error('Gagal memuat kabupaten/kota'); } finally { setLoadingAddress(false); }
  };
  const handleRegency = async (code: string) => {
    const selected = regencies.find((item) => item.code === code); if (!selected) return;
    setFormData((current) => ({ ...current, regency_code: code, regency_name: selected.name, district_code: '', district_name: '', village_code: '', village_name: '', village_id: '' }));
    setDistricts([]); setVillages([]); setLoadingAddress(true);
    try { setDistricts(await fetchDistricts(code)); } catch { toast.error('Gagal memuat kecamatan'); } finally { setLoadingAddress(false); }
  };
  const handleDistrict = async (code: string) => {
    const selected = districts.find((item) => item.code === code); if (!selected) return;
    setFormData((current) => ({ ...current, district_code: code, district_name: selected.name, village_code: '', village_name: '', village_id: '' }));
    setVillages([]); setLoadingAddress(true);
    try {
      const apiVillages = await fetchVillages(code); setVillages(apiVillages);
      const { data } = await supabase.from('villages').select('id, name').eq('district', selected.name).eq('regency', formData.regency_name).eq('is_active', true);
      setVillages(apiVillages.map((v) => ({ ...v, id: (data || []).find((db) => db.name.toLowerCase() === v.name.toLowerCase())?.id })));
    } catch { toast.error('Gagal memuat desa/kelurahan'); } finally { setLoadingAddress(false); }
  };
  const handleVillage = (code: string) => {
    const selected = villages.find((item) => item.code === code); if (!selected) return;
    setFormData((current) => ({ ...current, village_code: code, village_name: selected.name, village_id: (selected as Region & { id?: string }).id || '' }));
  };

  const validateCode = async (value: string) => {
    const code = value.trim().toUpperCase(); update('verifikator_code', code);
    if (!code) { setVerifikatorValid(null); setVerifikatorName(null); return; }
    const { data, error } = await supabase.from('verifikator_codes').select('trade_group').eq('code', code).eq('is_active', true).maybeSingle();
    setVerifikatorValid(!error && Boolean(data)); setVerifikatorName(data?.trade_group || null);
  };

  const handleSubmit = async () => {
    const openDays = DAYS.filter(({ day }) => !schedule[day].is_closed);
    if (!formData.name.trim()) return toast.error('Nama pedagang wajib diisi');
    if (!formData.phone.trim()) return toast.error('Nomor telepon wajib diisi');
    if (selectedCategories.length === 0) return toast.error('Pilih minimal satu kategori usaha');
    if (openDays.length === 0) return toast.error('Pilih minimal satu hari operasional');
    if (!formData.province_code || !formData.regency_code || !formData.district_code || !formData.village_code) return toast.error('Lokasi usaha wajib dilengkapi');
    if (formData.verifikator_code && verifikatorValid !== true) return toast.error('Kode verifikator tidak valid');
    setLoading(true);
    try {
      const { data: merchantId, error } = await supabase.rpc('admin_create_merchant_atomic', {
        p_merchant: {
          name: formData.name.trim(),
          user_id: formData.user_id || null,
          phone: formData.phone.trim(),
          address: formData.address.trim() || null,
          province: formData.province_name,
          city: formData.regency_name,
          district: formData.district_name,
          subdistrict: formData.village_name,
          village_id: formData.village_id || null,
          business_category: selectedCategories[0].slug,
          business_description: formData.business_description.trim() || null,
          is_open: formData.is_open,
          image_url: formData.image_url,
          cover_image_url: formData.cover_image_url,
          location_lat: formData.location_lat,
          location_lng: formData.location_lng,
          verifikator_code: formData.verifikator_code || null,
          trade_group: verifikatorName,
        },
        p_category_ids: selectedCategories.map((category) => category.id),
        p_schedule: DAYS.map(({ day }) => ({ day_of_week: day, ...schedule[day] })),
      });
      if (error || !merchantId) throw error || new Error('Pedagang tidak berhasil dibuat');
      toast.success('Pedagang baru berhasil ditambahkan'); onSuccess(); onOpenChange(false);
    } catch (error) {
      console.error('Error adding merchant:', error);
      const message = error instanceof Error ? error.message : 'Gagal menambahkan pedagang';
      toast.error(message.includes('duplicate') || message.includes('unique') ? 'Pedagang dengan data tersebut sudah ada.' : message);
    } finally { setLoading(false); }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-4xl max-h-[92vh] overflow-y-auto">
        <DialogHeader><DialogTitle className="flex items-center gap-2"><Store className="h-5 w-5 text-primary" />Tambah Pedagang</DialogTitle><DialogDescription>Lengkapi data pedagang seperti formulir pendaftaran agar siap dikelola.</DialogDescription></DialogHeader>
        <div className="space-y-6 py-2">
          <section className="space-y-4 rounded-lg border p-4"><h3 className="font-semibold flex items-center gap-2"><Store className="h-4 w-4" />Informasi Usaha</h3>
            <div className="grid gap-4 sm:grid-cols-2"><div className="space-y-2"><Label>Nama Usaha *</Label><Input value={formData.name} onChange={(e) => update('name', e.target.value)} placeholder="Contoh: Warung Berkah" /></div><div className="space-y-2"><Label>Nomor WhatsApp *</Label><Input value={formData.phone} onChange={(e) => update('phone', e.target.value)} placeholder="08xxxxxxxxxx" /></div></div>
            <div className="space-y-2"><Label>Kategori Usaha *</Label><div className="grid gap-2 rounded-md border bg-muted/20 p-3 sm:grid-cols-2">{categoriesLoading ? <p className="text-sm text-muted-foreground">Memuat kategori...</p> : categories.map((category) => <label key={category.id} className="flex items-center gap-2 rounded border bg-background p-2 text-sm"><Checkbox checked={selectedCategoryIds.includes(category.id)} onCheckedChange={(checked) => setSelectedCategoryIds((current) => checked ? [...new Set([...current, category.id])] : current.filter((id) => id !== category.id))} />{category.icon ? `${category.icon} ` : ''}{category.name}</label>)}</div></div>
            <div className="space-y-2"><Label>Deskripsi Usaha</Label><Textarea value={formData.business_description} onChange={(e) => update('business_description', e.target.value)} rows={3} placeholder="Ceritakan usaha pedagang..." /></div>
            <div className="grid gap-4 sm:grid-cols-2"><div><Label className="mb-2 block">Foto Profil</Label><ImageUpload bucket="merchant-images" path="profiles/admin-new" value={formData.image_url} onChange={(url) => update('image_url', url)} aspectRatio="square" placeholder="Upload foto pedagang" /></div><div><Label className="mb-2 block">Foto Sampul</Label><ImageUpload bucket="merchant-images" path="covers/admin-new" value={formData.cover_image_url} onChange={(url) => update('cover_image_url', url)} aspectRatio="wide" placeholder="Upload foto sampul" /></div></div>
          </section>
          <section className="space-y-4 rounded-lg border p-4"><h3 className="font-semibold flex items-center gap-2"><Clock className="h-4 w-4" />Jadwal Operasional Mingguan</h3><p className="text-xs text-muted-foreground">Atur jam masuk dan tutup untuk setiap hari. Hari yang ditutup tidak menerima pesanan.</p><div className="space-y-2">{DAYS.map(({ day, label }) => { const item = schedule[day]; return <div key={day} className="grid items-center gap-2 rounded-md bg-muted/30 p-2 sm:grid-cols-[100px_1fr_1fr_auto]"><span className="text-sm font-medium">{label}</span><Input type="time" value={item.open_time} disabled={item.is_closed} onChange={(e) => setSchedule((current) => ({ ...current, [day]: { ...item, open_time: e.target.value } }))} aria-label={`Jam buka ${label}`} /><Input type="time" value={item.close_time} disabled={item.is_closed} onChange={(e) => setSchedule((current) => ({ ...current, [day]: { ...item, close_time: e.target.value } }))} aria-label={`Jam tutup ${label}`} /><label className="flex items-center gap-2 text-xs"><Checkbox checked={item.is_closed} onCheckedChange={(checked) => setSchedule((current) => ({ ...current, [day]: { ...item, is_closed: Boolean(checked) } }))} />Tutup</label></div>; })}</div></section>
          <section className="space-y-4 rounded-lg border p-4"><h3 className="font-semibold flex items-center gap-2"><MapPin className="h-4 w-4" />Lokasi Usaha</h3><div className="grid gap-4 sm:grid-cols-2"><div className="space-y-2"><Label>Provinsi *</Label><Select value={formData.province_code} onValueChange={handleProvince}><SelectTrigger><SelectValue placeholder="Pilih provinsi" /></SelectTrigger><SelectContent>{provinces.map((item) => <SelectItem key={item.code} value={item.code}>{item.name}</SelectItem>)}</SelectContent></Select></div><div className="space-y-2"><Label>Kabupaten/Kota *</Label><Select value={formData.regency_code} onValueChange={handleRegency} disabled={!formData.province_code || loadingAddress}><SelectTrigger><SelectValue placeholder="Pilih kabupaten/kota" /></SelectTrigger><SelectContent>{regencies.map((item) => <SelectItem key={item.code} value={item.code}>{item.name}</SelectItem>)}</SelectContent></Select></div><div className="space-y-2"><Label>Kecamatan *</Label><Select value={formData.district_code} onValueChange={handleDistrict} disabled={!formData.regency_code || loadingAddress}><SelectTrigger><SelectValue placeholder="Pilih kecamatan" /></SelectTrigger><SelectContent>{districts.map((item) => <SelectItem key={item.code} value={item.code}>{item.name}</SelectItem>)}</SelectContent></Select></div><div className="space-y-2"><Label>Desa/Kelurahan *</Label><Select value={formData.village_code} onValueChange={handleVillage} disabled={!formData.district_code || loadingAddress}><SelectTrigger><SelectValue placeholder="Pilih desa/kelurahan" /></SelectTrigger><SelectContent>{villages.map((item) => <SelectItem key={item.code} value={item.code}>{item.name}</SelectItem>)}</SelectContent></Select></div></div><Textarea value={formData.address} onChange={(e) => update('address', e.target.value)} placeholder="Alamat lengkap (jalan, nomor rumah, patokan)" rows={2} /><AdminLocationPicker value={formData.location_lat !== null && formData.location_lng !== null ? { lat: formData.location_lat, lng: formData.location_lng } : null} onChange={(location) => setFormData((current) => ({ ...current, location_lat: location.lat, location_lng: location.lng }))} /></section>
          <section className="grid gap-4 rounded-lg border p-4 sm:grid-cols-2"><div className="space-y-2"><Label className="flex items-center gap-2"><User className="h-4 w-4" />Hubungkan Pemilik (opsional)</Label><Select value={formData.user_id || 'none'} onValueChange={(value) => update('user_id', value === 'none' ? '' : value)} disabled={loadingUsers}><SelectTrigger><SelectValue placeholder={loadingUsers ? 'Memuat user...' : 'Pilih akun pedagang'} /></SelectTrigger><SelectContent><SelectItem value="none">Tanpa pemilik</SelectItem>{availableUsers.map((user) => <SelectItem key={user.user_id} value={user.user_id}>{user.full_name || 'Tanpa nama'}{user.phone ? ` — ${user.phone}` : ''}</SelectItem>)}</SelectContent></Select></div><div className="space-y-2"><Label className="flex items-center gap-2"><Shield className="h-4 w-4" />Kode Verifikator (opsional)</Label><Input value={formData.verifikator_code} onChange={(e) => void validateCode(e.target.value)} placeholder="Kode referral/verifikator" />{verifikatorValid === true && <p className="text-xs text-success flex items-center gap-1"><Check className="h-3 w-3" />{verifikatorName || 'Kode valid'}</p>}</div></section>
        </div>
        <DialogFooter><Button variant="outline" onClick={() => onOpenChange(false)} disabled={loading}>Batal</Button><Button onClick={() => void handleSubmit()} disabled={loading || categoriesLoading}><Save className="mr-2 h-4 w-4" />{loading ? 'Menyimpan...' : 'Simpan Pedagang'}</Button></DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

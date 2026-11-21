import { useEffect, useState } from 'react';
import { CheckCircle2, Clock3, FileImage, Loader2, QrCode, Upload } from 'lucide-react';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';

type Status = 'SUBMITTED' | 'IN_REVIEW' | 'NEEDS_CORRECTION' | 'REJECTED' | 'APPROVED_PENDING_ISSUANCE' | 'ISSUED_PENDING_ACTIVATION' | 'ACTIVE';
type Application = { id: string; application_number: string; status: Status; business_criteria_code: string; business_age_code: string; qris_merchant_name_short: string; qris_merchant_name: string; documents: Record<string,string>; decision_note: string | null; submitted_at: string; revision_number: number; gdc_mpm_enabled?: boolean };
// qris_applications is a newly introduced table not yet present in generated Supabase types.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const db = supabase as any;
const requiredDocuments = [
  { code: 'OWNER_ID', label: 'Foto KTP Pemilik' },
  { code: 'OWNER_SELFIE', label: 'Foto Selfie Pemilik' },
  { code: 'BUSINESS_LOCATION', label: 'Foto Lokasi Usaha' },
  { code: 'PRODUCT', label: 'Foto Produk' },
] as const;
const maxDocumentSize = 2 * 1024 * 1024;
const statusLabels: Record<Status,string> = {
  SUBMITTED: 'Menunggu verifikasi', IN_REVIEW: 'Sedang ditinjau', NEEDS_CORRECTION: 'Perlu perbaikan', REJECTED: 'Pengajuan ditolak',
  APPROVED_PENDING_ISSUANCE: 'Disetujui — menunggu konfigurasi GDC', ISSUED_PENDING_ACTIVATION: 'Menunggu aktivasi admin', ACTIVE: 'Disetujui — menunggu aktivasi QRIS Dinamis',
};

export function MerchantQrisApplicationCard({ merchantId, merchantName, bankName, accountNumber, accountName }: { merchantId: string; merchantName: string; bankName: string | null; accountNumber: string | null; accountName: string | null }) {
  const { user } = useAuth();
  const [application, setApplication] = useState<Application | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState(false);
  const [loadAttempt, setLoadAttempt] = useState(0);
  const [saving, setSaving] = useState(false);
  const [uploadStatus, setUploadStatus] = useState<string | null>(null);
  const [criteria, setCriteria] = useState('');
  const [businessAge, setBusinessAge] = useState('');
  const [shortName, setShortName] = useState('');
  const [merchantQrisName, setMerchantQrisName] = useState('');
  const [files, setFiles] = useState<Record<string, File>>({});

  useEffect(() => {
    let active = true;
    setLoading(true);
    setLoadError(false);
    void db.from('qris_applications').select('*').eq('merchant_id', merchantId).order('created_at', { ascending: false }).limit(1).maybeSingle()
      .then(({ data, error }: { data: Application | null; error: Error | null }) => {
        if (!active) return;
        if (error) throw error;
        if (data) {
          setApplication(data);
          setCriteria(data.business_criteria_code);
          setBusinessAge(data.business_age_code);
          setShortName(data.qris_merchant_name_short);
          setMerchantQrisName(data.qris_merchant_name);
        }
      }).catch(() => {
        if (!active) return;
        setLoadError(true);
        toast.error('Gagal memuat status pengajuan QRIS. Coba muat ulang sebelum mengirim dokumen.');
      }).finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
  }, [merchantId, loadAttempt]);

  const needsCorrection = application?.status === 'NEEDS_CORRECTION';
  const canApply = !application || needsCorrection || application.status === 'REJECTED';
  const dynamicQrisActive = application?.status === 'ACTIVE' && application.gdc_mpm_enabled === true;
  const handleFileChange = (code: string, event: React.ChangeEvent<HTMLInputElement>) => {
    const input = event.currentTarget;
    const file = input.files?.[0];
    if (!file) return;
    if (!['image/jpeg', 'image/png'].includes(file.type)) {
      toast.error('Dokumen harus berupa JPG atau PNG.');
      input.value = '';
      return;
    }
    if (file.size > maxDocumentSize) {
      toast.error('Ukuran setiap dokumen maksimal 2 MB. Pilih foto yang lebih kecil.');
      input.value = '';
      return;
    }
    setFiles((current) => ({ ...current, [code]: file }));
  };
  const submit = async () => {
    if (!user) return;
    if (!bankName?.trim() || !accountNumber?.trim() || !accountName?.trim()) return toast.error('Lengkapi rekening bank default di Pengaturan Pembayaran sebelum mengajukan QRIS.');
    if (!criteria || !businessAge || !shortName.trim() || !merchantQrisName.trim()) return toast.error('Lengkapi semua informasi usaha dan nama merchant QRIS.');
    if (shortName.trim().length > 25 || merchantQrisName.trim().length > 50) return toast.error('Nama merchant QRIS melebihi batas karakter.');
    const missing = requiredDocuments.filter(({ code }) => !files[code] && !application?.documents?.[code]);
    if (missing.length) return toast.error(`Lengkapi dokumen: ${missing.map((item) => item.label).join(', ')}.`);
    setSaving(true);
    setUploadStatus('Menyiapkan dokumen...');
    const uploadedPaths: string[] = [];
    let databaseWriteStarted = false;
    try {
      const editingCorrection = application?.status === 'NEEDS_CORRECTION';
      const applicationId = editingCorrection ? application!.id : crypto.randomUUID();
      const documentPaths = { ...(editingCorrection ? application?.documents : {}) };
      for (const [index, { code, label }] of requiredDocuments.entries()) {
        const file = files[code];
        if (!file) continue;
        const objectPath = `${user.id}/${applicationId}/${code.toLowerCase()}-${crypto.randomUUID()}.${file.type === 'image/png' ? 'png' : 'jpg'}`;
        uploadedPaths.push(objectPath);
        setUploadStatus(`Mengunggah ${label} (${index + 1} dari ${requiredDocuments.length})...`);
        const { error: uploadError } = await supabase.storage.from('qris-applications').upload(objectPath, file, { upsert: true, contentType: file.type });
        if (uploadError) throw uploadError;
        documentPaths[code] = objectPath;
      }
      setUploadStatus('Menyimpan pengajuan QRIS Dinamis...');
      const payload = {
        id: applicationId, merchant_id: merchantId, applicant_user_id: user.id,
        business_criteria_code: criteria, business_age_code: businessAge,
        qris_merchant_name_short: shortName.trim(), qris_merchant_name: merchantQrisName.trim(),
        default_bank_name: bankName, default_account_number: accountNumber, default_account_name: accountName,
        documents: documentPaths, status: 'SUBMITTED', revision_number: application ? application.revision_number + 1 : 1,
        submitted_at: new Date().toISOString(), updated_at: new Date().toISOString(),
      };
      databaseWriteStarted = true;
      const { data, error } = editingCorrection
        ? await db.from('qris_applications').update(payload).eq('id', applicationId).select('*').single()
        : await db.from('qris_applications').insert(payload).select('*').single();
      if (error) throw error;
      setApplication(data as Application);
      setFiles({});
      toast.success('Pengajuan QRIS Dinamis GDC berhasil dikirim. Admin akan memverifikasi data Anda.');
    } catch (error) {
      if (!databaseWriteStarted && uploadedPaths.length > 0) {
        try {
          await supabase.storage.from('qris-applications').remove(uploadedPaths);
        } catch {
          // Keep the form usable even if temporary-file cleanup is unavailable.
        }
      }
      toast.error(error instanceof Error ? error.message : 'Pengajuan QRIS gagal dikirim.');
    } finally {
      setSaving(false);
      setUploadStatus(null);
    }
  };

  return <Card>
    <CardHeader>
      <CardTitle className="flex items-center gap-2 text-base"><QrCode className="h-5 w-5" />Pengajuan QRIS Dinamis GDC</CardTitle>
      <CardDescription>Ajukan aktivasi QRIS Dinamis untuk toko Anda. Admin akan memverifikasi data dan dokumen, lalu mengatur mapping merchant GDC. QR pembayaran dibuat untuk setiap pesanan sesuai total belanja; pengaturan QRIS statis toko tetap terpisah.</CardDescription>
    </CardHeader>
    <CardContent className="space-y-5">
      {loading ? <div className="flex items-center gap-2 text-sm text-muted-foreground"><Loader2 className="h-4 w-4 animate-spin" />Memuat status pengajuan…</div> : loadError ? (
        <div className="space-y-3 rounded-lg border border-destructive/30 bg-destructive/5 p-4" role="alert">
          <p className="text-sm">Status pengajuan QRIS tidak berhasil dimuat. Formulir dinonaktifkan agar pengajuan tidak terkirim ganda.</p>
          <Button type="button" variant="outline" onClick={() => setLoadAttempt((attempt) => attempt + 1)}>Coba muat ulang</Button>
        </div>
      ) : <>
        {application && <div className={`rounded-lg border p-4 ${dynamicQrisActive ? 'border-emerald-300 bg-emerald-50' : 'border-primary/20 bg-primary/5'}`}>
          <div className="flex items-center gap-2 font-semibold">{dynamicQrisActive ? <CheckCircle2 className="h-4 w-4 text-emerald-700" /> : <Clock3 className="h-4 w-4 text-primary" />}{dynamicQrisActive ? 'QRIS Dinamis GDC aktif' : statusLabels[application.status]}</div>
          <p className="mt-1 text-xs text-muted-foreground">Nomor pengajuan {application.application_number} · {new Date(application.submitted_at).toLocaleDateString('id-ID')}</p>
          {application.decision_note && <p className="mt-2 text-sm">Catatan admin: {application.decision_note}</p>}
        </div>}
        {dynamicQrisActive && <div className="rounded-lg border border-emerald-300 bg-emerald-50 p-4"><p className="font-semibold text-emerald-900">QRIS Dinamis GDC aktif untuk {merchantName}</p><p className="mt-1 text-sm text-emerald-800">Pembeli dapat memilih QRIS Dinamis di checkout. QR pembayaran dibuat berdasarkan total pesanan.</p></div>}
        {canApply && <div className="space-y-4">
          {!application && <div className="rounded-lg bg-muted p-3 text-sm">Lengkapi formulir untuk mengajukan aktivasi QRIS Dinamis GDC bagi <strong>{merchantName}</strong>.</div>}
          <div className="rounded-lg border bg-muted/40 p-3 text-sm"><p className="font-medium">Nomor Akun Default</p><p className="mt-1 text-muted-foreground">{bankName && accountNumber && accountName ? `${bankName} · ${accountNumber} · ${accountName}` : 'Rekening penerimaan belum lengkap. Lengkapi rekening bank di bagian Pengaturan Pembayaran sebelum mengajukan.'}</p></div>
          <div className="grid gap-4 sm:grid-cols-2">
            <div className="space-y-2"><Label>Kriteria Bisnis (UMKM atau bukan)</Label><Select value={criteria} onValueChange={setCriteria}><SelectTrigger><SelectValue placeholder="Pilih kriteria bisnis" /></SelectTrigger><SelectContent>
              <SelectItem value="UMI">UMI — Usaha Mikro (UMKM; aset maks. Rp50 juta; omzet maks. Rp300 juta)</SelectItem>
              <SelectItem value="UME">UME — Usaha Menengah (UMKM; aset Rp500 juta–Rp10 miliar; omzet &gt;Rp2,5–50 miliar)</SelectItem>
              <SelectItem value="UBE">UBE — Usaha Besar (bukan UMKM; aset di atas Rp10 miliar)</SelectItem>
            </SelectContent></Select><p className="text-xs text-muted-foreground">Pilih UMKM untuk usaha mikro/menengah atau bukan UMKM untuk usaha besar. Rentang yang belum tercakup akan ditinjau manual oleh admin.</p></div>
            <div className="space-y-2"><Label>Lama Usaha</Label><Select value={businessAge} onValueChange={setBusinessAge}><SelectTrigger><SelectValue placeholder="Pilih lama usaha" /></SelectTrigger><SelectContent><SelectItem value="LT_6_MONTHS">Kurang dari 6 bulan</SelectItem><SelectItem value="6_TO_12_MONTHS">6–12 bulan</SelectItem><SelectItem value="1_TO_3_YEARS">1–3 tahun</SelectItem><SelectItem value="GT_3_YEARS">Lebih dari 3 tahun</SelectItem></SelectContent></Select></div>
            <div className="space-y-2"><Label>Nama Merchant QRIS (maks. 25 karakter)</Label><Input maxLength={25} value={shortName} onChange={(event) => setShortName(event.target.value)} placeholder="Nama singkat merchant" /><p className="text-right text-xs text-muted-foreground">{shortName.length}/25</p></div>
            <div className="space-y-2"><Label>Nama Merchant QRIS (maks. 50 karakter)</Label><Input maxLength={50} value={merchantQrisName} onChange={(event) => setMerchantQrisName(event.target.value)} placeholder="Nama yang ditampilkan pada QRIS" /><p className="text-right text-xs text-muted-foreground">{merchantQrisName.length}/50</p></div>
          </div>
          <div className="grid gap-4 sm:grid-cols-2">{requiredDocuments.map(({ code, label }) => <div key={code} className="space-y-2"><Label>{label} <span className="text-destructive">*</span></Label><label className="flex cursor-pointer items-center gap-3 rounded-lg border border-dashed p-3 text-sm hover:bg-muted/60"><FileImage className="h-5 w-5 text-muted-foreground" /><span className="min-w-0 flex-1 truncate">{files[code]?.name || (application?.documents?.[code] ? 'Dokumen tersimpan · pilih untuk mengganti' : 'Pilih foto JPG/PNG')}</span><Upload className="h-4 w-4" /><input type="file" accept="image/jpeg,image/png" aria-label={label} className="sr-only" onChange={(event) => handleFileChange(code, event)} /></label><p className="text-xs text-muted-foreground">JPG atau PNG, maksimal 2 MB.</p></div>)}</div>
          <p className="text-xs text-muted-foreground">Dengan mengirim, Anda menyatakan data benar. Dokumen disimpan privat untuk keperluan verifikasi QRIS.</p>
          {uploadStatus && <p role="status" className="flex items-center gap-2 text-sm text-muted-foreground"><Loader2 className="h-4 w-4 animate-spin" />{uploadStatus}</p>}
          <Button type="button" onClick={() => void submit()} disabled={saving} className="gap-2">{saving && <Loader2 className="h-4 w-4 animate-spin" />}{needsCorrection ? 'Kirim Perbaikan' : 'Kirim Pengajuan QRIS Dinamis'}</Button>
        </div>}
      </>}
    </CardContent>
  </Card>;
}

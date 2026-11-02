import { Component, type ChangeEvent, type ErrorInfo, type ReactNode, useEffect, useState } from 'react';
import { AlertCircle, CheckCircle2, Clock3, FileImage, Loader2, QrCode, Upload } from 'lucide-react';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { observe } from '@/lib/observability';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';

type Status = 'SUBMITTED' | 'IN_REVIEW' | 'NEEDS_CORRECTION' | 'REJECTED' | 'APPROVED_PENDING_ISSUANCE' | 'ISSUED_PENDING_ACTIVATION' | 'ACTIVE';
type Application = { id: string; application_number: string; status: Status; business_criteria_code: string; business_age_code: string; qris_merchant_name_short: string; qris_merchant_name: string; documents: Record<string, string> | null; decision_note: string | null; submitted_at: string; revision_number: number };
// qris_applications is a newly introduced table not yet present in generated Supabase types.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const db = supabase as any;
const requiredDocuments = [
  { code: 'OWNER_ID', label: 'Foto KTP Pemilik' },
  { code: 'OWNER_SELFIE', label: 'Foto Selfie Pemilik' },
  { code: 'BUSINESS_LOCATION', label: 'Foto Lokasi Usaha' },
  { code: 'PRODUCT', label: 'Foto Produk' },
] as const;
const statusLabels: Record<Status, string> = {
  SUBMITTED: 'Menunggu verifikasi', IN_REVIEW: 'Sedang ditinjau', NEEDS_CORRECTION: 'Perlu perbaikan', REJECTED: 'Pengajuan ditolak',
  APPROVED_PENDING_ISSUANCE: 'Disetujui — menunggu penerbitan', ISSUED_PENDING_ACTIVATION: 'Menunggu aktivasi', ACTIVE: 'QRIS Sadesa aktif',
};
const MAX_DOCUMENT_BYTES = 2 * 1024 * 1024;
const ACCEPTED_DOCUMENT_TYPES = new Set(['image/jpeg', 'image/png']);

type CardProps = { merchantId: string; merchantName: string; qrisImageUrl: string | null; bankName: string | null; accountNumber: string | null; accountName: string | null };

function documentError(file: File): string | null {
  const extension = file.name.split('.').pop()?.toLowerCase();
  if (!ACCEPTED_DOCUMENT_TYPES.has(file.type) || !['jpg', 'jpeg', 'png'].includes(extension || '')) return 'Gunakan file JPG atau PNG.';
  if (file.size <= 0) return 'File kosong tidak dapat diunggah.';
  if (file.size > MAX_DOCUMENT_BYTES) return 'Ukuran file maksimal 2 MB.';
  return null;
}

function readableUploadError(error: unknown): string {
  const message = error instanceof Error ? error.message : String(error || '');
  if (/bucket|storage|not found/i.test(message)) return 'Penyimpanan dokumen QRIS belum siap. Hubungi admin desa.';
  if (/policy|permission|not authorized|row-level/i.test(message)) return 'Anda tidak memiliki izin mengunggah dokumen ini. Silakan muat ulang halaman.';
  if (/network|fetch|timeout|abort/i.test(message)) return 'Koneksi terputus saat mengunggah. Periksa internet lalu coba lagi.';
  return 'Dokumen gagal diunggah. Periksa format dan ukuran file lalu coba lagi.';
}

class QrisCardErrorBoundary extends Component<{ children: ReactNode }, { hasError: boolean }> {
  state = { hasError: false };

  static getDerivedStateFromError(): { hasError: boolean } {
    return { hasError: true };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error('[qris-application] render failed', error, info);
  }

  render() {
    if (this.state.hasError) {
      return <Card><CardContent className="flex items-start gap-3 py-6 text-sm"><AlertCircle className="mt-0.5 h-5 w-5 shrink-0 text-destructive" /><div><p className="font-medium">Form QRIS belum dapat ditampilkan</p><p className="mt-1 text-muted-foreground">Muat ulang halaman. Data pengaturan toko lain tetap aman.</p><Button type="button" variant="outline" size="sm" className="mt-3" onClick={() => window.location.reload()}>Muat ulang</Button></div></CardContent></Card>;
    }
    return this.props.children;
  }
}

export function MerchantQrisApplicationCard(props: CardProps) {
  return <QrisCardErrorBoundary><MerchantQrisApplicationCardContent {...props} /></QrisCardErrorBoundary>;
}

function MerchantQrisApplicationCardContent({ merchantId, merchantName, qrisImageUrl, bankName, accountNumber, accountName }: CardProps) {
  const { user } = useAuth();
  const [application, setApplication] = useState<Application | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState(false);
  const [saving, setSaving] = useState(false);
  const [criteria, setCriteria] = useState('');
  const [businessAge, setBusinessAge] = useState('');
  const [shortName, setShortName] = useState('');
  const [merchantQrisName, setMerchantQrisName] = useState('');
  const [files, setFiles] = useState<Record<string, File>>({});
  const [fileErrors, setFileErrors] = useState<Record<string, string>>({});

  useEffect(() => {
    let active = true;
    setLoading(true);
    setLoadError(false);
    void db.from('qris_applications').select('*').eq('merchant_id', merchantId).order('created_at', { ascending: false }).limit(1).maybeSingle()
      .then(({ data, error }: { data: Application | null; error: Error | null }) => {
        if (!active) return;
        if (error) {
          console.error('[qris-application] load failed', error);
          setLoadError(true);
          return;
        }
        if (data) {
          setApplication({ ...data, documents: data.documents && typeof data.documents === 'object' ? data.documents : {} });
          setCriteria(data.business_criteria_code || '');
          setBusinessAge(data.business_age_code || '');
          setShortName(data.qris_merchant_name_short || '');
          setMerchantQrisName(data.qris_merchant_name || '');
        }
      })
      .catch((error: unknown) => {
        if (!active) return;
        console.error('[qris-application] load crashed', error);
        setLoadError(true);
      })
      .finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
  }, [merchantId]);

  const needsCorrection = application?.status === 'NEEDS_CORRECTION';
  const canApply = !application || needsCorrection || application.status === 'REJECTED';

  const handleFileChange = (code: string, event: ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    event.target.value = '';
    if (!file) return;
    const error = documentError(file);
    setFileErrors((current) => {
      const next = { ...current };
      if (error) next[code] = error; else delete next[code];
      return next;
    });
    if (!error) setFiles((current) => ({ ...current, [code]: file }));
  };

  const submit = async () => {
    if (!user || saving) return;
    if (!bankName?.trim() || !accountNumber?.trim() || !accountName?.trim()) return toast.error('Lengkapi rekening bank default di Pengaturan Pembayaran sebelum mengajukan QRIS.');
    if (!criteria || !businessAge || !shortName.trim() || !merchantQrisName.trim()) return toast.error('Lengkapi semua informasi usaha dan nama merchant QRIS.');
    if (shortName.trim().length > 25 || merchantQrisName.trim().length > 50) return toast.error('Nama merchant QRIS melebihi batas karakter.');
    const missing = requiredDocuments.filter(({ code }) => !files[code] && !application?.documents?.[code]);
    if (missing.length) return toast.error(`Lengkapi dokumen: ${missing.map((item) => item.label).join(', ')}.`);
    if (Object.keys(fileErrors).length) return toast.error('Perbaiki format atau ukuran dokumen sebelum mengirim.');

    setSaving(true);
    const uploadedPaths: string[] = [];
    try {
      const editingCorrection = application?.status === 'NEEDS_CORRECTION';
      const applicationId = editingCorrection ? application!.id : crypto.randomUUID();
      const documentPaths: Record<string, string> = { ...(editingCorrection ? application?.documents || {} : {}) };
      for (const { code } of requiredDocuments) {
        const file = files[code];
        if (!file) continue;
        const validationError = documentError(file);
        if (validationError) throw new Error(validationError);
        const extension = file.type === 'image/png' ? 'png' : 'jpg';
        const objectPath = `${user.id}/${applicationId}/${code.toLowerCase()}-${Date.now()}.${extension}`;
        await observe('upload', 'file_upload', async () => {
          const { error: uploadError } = await supabase.storage.from('qris-applications').upload(objectPath, file, {
            upsert: true,
            contentType: file.type,
            cacheControl: '3600',
          });
          if (uploadError) throw uploadError;
        }, {
          bucket: 'qris-applications',
          fileType: file.type || 'unknown',
          sizeBytes: file.size,
        });
        uploadedPaths.push(objectPath);
        documentPaths[code] = objectPath;
      }
      const payload = {
        id: applicationId, merchant_id: merchantId, applicant_user_id: user.id,
        business_criteria_code: criteria, business_age_code: businessAge,
        qris_merchant_name_short: shortName.trim(), qris_merchant_name: merchantQrisName.trim(),
        default_bank_name: bankName.trim(), default_account_number: accountNumber.trim(), default_account_name: accountName.trim(),
        documents: documentPaths, status: 'SUBMITTED', revision_number: application ? application.revision_number + 1 : 1,
        submitted_at: new Date().toISOString(), updated_at: new Date().toISOString(),
      };
      const { data, error } = editingCorrection
        ? await db.from('qris_applications').update(payload).eq('id', applicationId).select('*').single()
        : await db.from('qris_applications').insert(payload).select('*').single();
      if (error) throw error;
      setApplication({ ...(data as Application), documents: (data as Application).documents || {} });
      setFiles({});
      toast.success('Pengajuan QRIS Sadesa berhasil dikirim. Admin akan memverifikasi data Anda.');
    } catch (error) {
      if (uploadedPaths.length) await supabase.storage.from('qris-applications').remove(uploadedPaths);
      toast.error(readableUploadError(error));
    } finally { setSaving(false); }
  };

  return <Card>
    <CardHeader>
      <CardTitle className="flex items-center gap-2 text-base"><QrCode className="h-5 w-5" />QRIS Sadesa</CardTitle>
      <CardDescription>Ajukan data QRIS untuk toko Anda. Tim Desa akan memverifikasi dan mendaftarkan merchant ke Neo/GDC secara manual. Setelah QRIS statis diterbitkan, tim akan mengunggah dan mengaktifkannya; merchant tidak dapat mengunggah atau mengganti QRIS sendiri.</CardDescription>
    </CardHeader>
    <CardContent className="space-y-5">
      {loading && <div className="flex items-center gap-2 rounded-lg border bg-muted/40 p-3 text-sm text-muted-foreground"><Loader2 className="h-4 w-4 animate-spin" />Memuat status pengajuan sambil menyiapkan formulir…</div>}
      {loadError && <div className="flex items-start gap-3 rounded-lg border border-destructive/30 bg-destructive/5 p-4 text-sm"><AlertCircle className="mt-0.5 h-4 w-4 shrink-0 text-destructive" /><div><p className="font-medium">Status QRIS belum dapat dimuat</p><p className="mt-1 text-muted-foreground">Formulir tetap dapat diisi. Muat ulang halaman sebelum mengirim jika masalah berlanjut.</p></div></div>}
      <>
        {application && <div className={`rounded-lg border p-4 ${application.status === 'ACTIVE' ? 'border-emerald-300 bg-emerald-50' : 'border-primary/20 bg-primary/5'}`}>
          <div className="flex items-center gap-2 font-semibold">{application.status === 'ACTIVE' ? <CheckCircle2 className="h-4 w-4 text-emerald-700" /> : <Clock3 className="h-4 w-4 text-primary" />}{statusLabels[application.status]}</div>
          <p className="mt-1 text-xs text-muted-foreground">Nomor pengajuan {application.application_number} · {new Date(application.submitted_at).toLocaleDateString('id-ID')}</p>
          {application.decision_note && <p className="mt-2 text-sm">Catatan admin: {application.decision_note}</p>}
        </div>}
        {application?.status === 'ACTIVE' && qrisImageUrl && <div className="rounded-lg border p-4"><p className="mb-3 text-sm font-semibold">QRIS Sadesa toko Anda</p><img src={qrisImageUrl} alt={`QRIS Sadesa ${merchantName}`} className="mx-auto max-h-72 w-auto rounded-md object-contain" onError={(event) => { event.currentTarget.style.display = 'none'; }} /><p className="mt-3 text-xs text-muted-foreground">QRIS ini ditetapkan oleh admin dan tidak dapat diganti dari akun merchant.</p></div>}
        {canApply && <div className="space-y-4">
          {!application && <div className="rounded-lg bg-muted p-3 text-sm">Lengkapi formulir untuk meminta penerbitan QRIS Sadesa bagi <strong>{merchantName}</strong>.</div>}
          <div className="rounded-lg border bg-muted/40 p-3 text-sm"><p className="font-medium">Nomor Akun Default</p><p className="mt-1 text-muted-foreground">{bankName && accountNumber && accountName ? `${bankName} · ${accountNumber} · ${accountName}` : 'Rekening penerimaan belum lengkap. Lengkapi rekening bank di bagian Pengaturan Pembayaran sebelum mengajukan.'}</p></div>
          <div className="grid gap-4 sm:grid-cols-2">
            <div className="space-y-2"><Label>Kriteria Bisnis</Label><Select value={criteria} onValueChange={setCriteria}><SelectTrigger><SelectValue placeholder="Pilih kriteria bisnis" /></SelectTrigger><SelectContent><SelectItem value="UMI">UMI — Usaha Mikro (aset maks. Rp50 juta; omzet maks. Rp300 juta)</SelectItem><SelectItem value="UME">UME — Usaha Menengah (aset Rp500 juta–Rp10 miliar; omzet &gt;Rp2,5–50 miliar)</SelectItem><SelectItem value="UBE">UBE — Usaha Besar (aset di atas Rp10 miliar)</SelectItem></SelectContent></Select><p className="text-xs text-muted-foreground">Rentang kriteria yang belum tercakup akan ditinjau manual oleh admin.</p></div>
            <div className="space-y-2"><Label>Lama Usaha</Label><Select value={businessAge} onValueChange={setBusinessAge}><SelectTrigger><SelectValue placeholder="Pilih lama usaha" /></SelectTrigger><SelectContent><SelectItem value="LT_6_MONTHS">Kurang dari 6 bulan</SelectItem><SelectItem value="6_TO_12_MONTHS">6–12 bulan</SelectItem><SelectItem value="1_TO_3_YEARS">1–3 tahun</SelectItem><SelectItem value="GT_3_YEARS">Lebih dari 3 tahun</SelectItem></SelectContent></Select></div>
            <div className="space-y-2"><Label>Nama Merchant QRIS (maks. 25 karakter)</Label><Input maxLength={25} value={shortName} onChange={(event) => setShortName(event.target.value)} placeholder="Nama singkat merchant" /><p className="text-right text-xs text-muted-foreground">{shortName.length}/25</p></div>
            <div className="space-y-2"><Label>Nama Merchant QRIS (maks. 50 karakter)</Label><Input maxLength={50} value={merchantQrisName} onChange={(event) => setMerchantQrisName(event.target.value)} placeholder="Nama yang ditampilkan pada QRIS" /><p className="text-right text-xs text-muted-foreground">{merchantQrisName.length}/50</p></div>
          </div>
          <div className="grid gap-4 sm:grid-cols-2">{requiredDocuments.map(({ code, label }) => <div key={code} className="space-y-2"><Label>{label} <span className="text-destructive">*</span></Label><label className="flex cursor-pointer items-center gap-3 rounded-lg border border-dashed p-3 text-sm hover:bg-muted/60"><FileImage className="h-5 w-5 text-muted-foreground" /><span className="min-w-0 flex-1 truncate">{files[code]?.name || (application?.documents?.[code] ? 'Dokumen tersimpan · pilih untuk mengganti' : 'Pilih foto JPG/PNG')}</span><Upload className="h-4 w-4" /><input type="file" accept="image/jpeg,image/png" className="sr-only" onChange={(event) => handleFileChange(code, event)} /></label>{fileErrors[code] ? <p role="alert" className="text-xs text-destructive">{fileErrors[code]}</p> : <p className="text-xs text-muted-foreground">JPG atau PNG, maksimal 2 MB.</p>}</div>)}</div>
          <p className="text-xs text-muted-foreground">Dengan mengirim, Anda menyatakan data benar. Dokumen disimpan privat untuk keperluan verifikasi QRIS.</p>
          <Button type="button" onClick={() => void submit()} disabled={saving} className="gap-2">{saving && <Loader2 className="h-4 w-4 animate-spin" />}{needsCorrection ? 'Kirim Perbaikan' : 'Kirim Pengajuan QRIS'}</Button>
        </div>}
      </>
    </CardContent>
  </Card>;
}

import { FormEvent, useEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { ArrowLeft, Mail, Send } from 'lucide-react';
import { Header } from '@/components/layout/Header';
import { BottomNav } from '@/components/layout/BottomNav';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { safeGoBack } from '@/lib/utils';

const PRIVACY_EMAIL = 'bopan86@gmail.com';

export default function AccountDeletionPage() {
  const navigate = useNavigate();
  const [email, setEmail] = useState('');
  const [name, setName] = useState('');
  const [details, setDetails] = useState('');

  useEffect(() => {
    document.title = 'Penghapusan Akun dan Data | SaDesa';
    const description = 'Ajukan permintaan penghapusan akun dan data SaDesa.';
    let meta = document.querySelector<HTMLMetaElement>('meta[name="description"]');
    if (!meta) {
      meta = document.createElement('meta');
      meta.name = 'description';
      document.head.appendChild(meta);
    }
    meta.content = description;
  }, []);

  function submitRequest(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const subject = 'Permintaan Penghapusan Akun dan Data SaDesa';
    const body = [
      'Saya ingin mengajukan penghapusan akun dan data SaDesa.',
      '',
      `Nama: ${name}`,
      `Email akun SaDesa: ${email}`,
      `Detail tambahan: ${details || '-'}`,
      '',
      'Saya memahami bahwa sebagian data dapat dipertahankan jika diwajibkan hukum atau diperlukan untuk keamanan dan penyelesaian transaksi.',
    ].join('\n');
    window.location.href = `mailto:${PRIVACY_EMAIL}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`;
  }

  return (
    <div className="mobile-shell flex min-h-screen flex-col bg-background">
      <Header />
      <main className="flex-1 overflow-y-auto pb-24">
        <article className="mx-auto max-w-2xl px-5 py-6 sm:px-8">
          <button
            onClick={() => safeGoBack(navigate)}
            className="mb-5 flex items-center gap-2 text-sm text-muted-foreground transition hover:text-foreground"
          >
            <ArrowLeft className="h-4 w-4" />
            <span>Kembali</span>
          </button>

          <div className="mb-6 rounded-2xl border border-emerald-100 bg-emerald-50/70 p-5 dark:border-emerald-900 dark:bg-emerald-950/30">
            <p className="mb-2 text-xs font-semibold uppercase tracking-[0.18em] text-emerald-700 dark:text-emerald-300">Pusat privasi SaDesa</p>
            <h1 className="text-2xl font-bold tracking-tight text-foreground sm:text-3xl">Penghapusan Akun dan Data</h1>
            <p className="mt-3 text-sm leading-6 text-muted-foreground">
              Gunakan halaman ini untuk mengajukan permintaan penghapusan akun SaDesa dan data pribadi terkait.
            </p>
          </div>

          <div className="space-y-6 text-sm leading-6 text-muted-foreground">
            <section>
              <h2 className="mb-2 text-base font-semibold text-foreground">Cara mengajukan permintaan</h2>
              <ol className="list-decimal space-y-2 pl-5">
                <li>Isi alamat email yang digunakan pada akun SaDesa agar kami dapat memverifikasi permintaan.</li>
                <li>Klik tombol <strong className="text-foreground">Kirim Permintaan melalui Email</strong>.</li>
                <li>Kirim email yang sudah disiapkan. Kami dapat meminta verifikasi tambahan untuk melindungi akun Anda.</li>
              </ol>
              <p className="mt-3">
                Permintaan juga dapat dikirim langsung ke{' '}
                <a className="font-medium text-emerald-700 hover:underline dark:text-emerald-300" href={`mailto:${PRIVACY_EMAIL}`}>{PRIVACY_EMAIL}</a>.
              </p>
            </section>

            <form onSubmit={submitRequest} className="space-y-4 rounded-2xl border border-border bg-card p-5 shadow-sm">
              <div className="space-y-2">
                <Label htmlFor="deletion-name">Nama pemilik akun</Label>
                <Input id="deletion-name" required value={name} onChange={(event) => setName(event.target.value)} placeholder="Nama lengkap" />
              </div>
              <div className="space-y-2">
                <Label htmlFor="deletion-email">Email akun SaDesa</Label>
                <Input id="deletion-email" required type="email" value={email} onChange={(event) => setEmail(event.target.value)} placeholder="nama@email.com" />
              </div>
              <div className="space-y-2">
                <Label htmlFor="deletion-details">Detail tambahan (opsional)</Label>
                <Textarea id="deletion-details" value={details} onChange={(event) => setDetails(event.target.value)} placeholder="Contoh: hapus akun merchant atau seluruh data profil" rows={4} />
              </div>
              <Button type="submit" className="w-full gap-2">
                <Send className="h-4 w-4" />
                Kirim Permintaan melalui Email
              </Button>
            </form>

            <section className="rounded-xl border border-border bg-muted/30 p-4">
              <h2 className="mb-2 text-base font-semibold text-foreground">Apa yang akan dihapus?</h2>
              <p>
                Setelah verifikasi, kami akan menonaktifkan akun dan menghapus atau menganonimkan data pribadi yang tidak wajib disimpan. Data transaksi, catatan keamanan, atau data lain yang wajib dipertahankan oleh hukum dapat disimpan selama masa yang diwajibkan, lalu dihapus sesuai kebijakan retensi kami.
              </p>
            </section>

            <div className="flex flex-wrap gap-4 border-t border-border pt-5">
              <Link to="/privacy-policy" className="inline-flex items-center gap-2 font-medium text-emerald-700 hover:underline dark:text-emerald-300"><Mail className="h-4 w-4" />Kebijakan Privasi</Link>
              <Link to="/terms" className="font-medium text-emerald-700 hover:underline dark:text-emerald-300">Syarat &amp; Ketentuan</Link>
            </div>
          </div>
        </article>
      </main>
      <BottomNav />
    </div>
  );
}

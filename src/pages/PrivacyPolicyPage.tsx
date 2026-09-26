import { useEffect } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { ArrowLeft, Mail } from 'lucide-react';
import { Header } from '@/components/layout/Header';
import { BottomNav } from '@/components/layout/BottomNav';
import { safeGoBack } from '@/lib/utils';

const sections = [
  {
    title: '1. Ruang Lingkup',
    content: (
      <p>
        Kebijakan Privasi ini menjelaskan bagaimana SaDesa mengumpulkan, menggunakan,
        menyimpan, dan melindungi informasi ketika Anda menggunakan aplikasi dan situs
        SaDesa sebagai pembeli, merchant, desa, kurir, penyedia jasa, atau pengunjung.
      </p>
    ),
  },
  {
    title: '2. Informasi yang Kami Kumpulkan',
    content: (
      <>
        <p>Kami dapat mengumpulkan informasi berikut sesuai fitur yang Anda gunakan:</p>
        <ul className="list-disc space-y-1 pl-5">
          <li>Identitas akun seperti nama, alamat email, nomor telepon, dan foto profil.</li>
          <li>Alamat pengiriman, alamat merchant, koordinat lokasi, dan informasi wilayah.</li>
          <li>Data pesanan, keranjang, pembayaran, pengiriman, ulasan, dukungan, dan komunikasi.</li>
          <li>Data pendaftaran merchant atau kurir, termasuk dokumen verifikasi yang Anda kirimkan.</li>
          <li>Data perangkat, browser, alamat IP, log keamanan, dan aktivitas penggunaan aplikasi.</li>
          <li>Data lokasi hanya ketika diperlukan oleh fitur dan diizinkan melalui perangkat Anda.</li>
          <li>Data yang Anda berikan melalui kamera, unggahan file, notifikasi push, atau fitur berbagi.</li>
        </ul>
      </>
    ),
  },
  {
    title: '3. Cara Kami Menggunakan Informasi',
    content: (
      <ul className="list-disc space-y-1 pl-5">
        <li>Membuat dan mengelola akun serta memberikan layanan SaDesa.</li>
        <li>Memproses pesanan, pembayaran, pengiriman, pemesanan jasa, dan pengembalian dana.</li>
        <li>Menghubungkan pembeli dengan merchant, desa, kurir, atau penyedia jasa terkait.</li>
        <li>Mengirim notifikasi transaksi, keamanan, layanan, dan pembaruan aplikasi.</li>
        <li>Memverifikasi identitas, mencegah penipuan, dan menjaga keamanan platform.</li>
        <li>Meningkatkan performa, fitur, aksesibilitas, dan pengalaman pengguna.</li>
        <li>Memenuhi kewajiban hukum, menyelesaikan sengketa, dan menegakkan ketentuan layanan.</li>
      </ul>
    ),
  },
  {
    title: '4. Dasar dan Pembagian Informasi',
    content: (
      <>
        <p>
          Kami memproses data untuk menjalankan layanan yang Anda minta, memenuhi kewajiban
          hukum, menjaga kepentingan keamanan yang sah, atau berdasarkan persetujuan Anda
          ketika persetujuan diperlukan.
        </p>
        <p>
          Informasi hanya dibagikan seperlunya kepada pihak yang membantu layanan, seperti
          merchant dan kurir untuk memenuhi pesanan, penyedia pembayaran, penyedia hosting
          dan penyimpanan, penyedia notifikasi, serta pihak berwenang apabila diwajibkan hukum.
          Kami tidak menjual data pribadi Anda.
        </p>
      </>
    ),
  },
  {
    title: '5. Penyimpanan dan Keamanan',
    content: (
      <p>
        Kami menerapkan pengamanan teknis dan organisasi yang wajar, termasuk enkripsi saat
        transmisi, pembatasan akses berbasis peran, pencatatan aktivitas, dan perlindungan
        penyimpanan. Tidak ada sistem yang sepenuhnya bebas risiko. Kami menyimpan data selama
        diperlukan untuk tujuan pengumpulan, kewajiban hukum, penyelesaian sengketa, dan
        keamanan, kemudian menghapus atau menganonimkannya sesuai kebijakan yang berlaku.
      </p>
    ),
  },
  {
    title: '6. Penyimpanan Lokal, Cookie, dan Notifikasi',
    content: (
      <p>
        SaDesa dapat menggunakan local storage, IndexedDB, cache aplikasi, dan cookie teknis
        untuk sesi login, keranjang, preferensi, dukungan offline, dan keamanan. Service worker
        dapat menyimpan aset publik agar aplikasi berjalan lebih baik. Anda dapat mengatur izin
        notifikasi, lokasi, kamera, dan penyimpanan dari pengaturan browser atau perangkat.
      </p>
    ),
  },
  {
    title: '7. Hak Anda dan Penghapusan Akun',
    content: (
      <>
        <p>Dengan tunduk pada hukum yang berlaku, Anda dapat meminta untuk:</p>
        <ul className="list-disc space-y-1 pl-5">
          <li>mengakses atau memperbarui informasi pribadi;</li>
          <li>meminta koreksi, penghapusan, atau pembatasan pemrosesan data;</li>
          <li>menarik persetujuan atau menolak pemrosesan tertentu; dan</li>
          <li>mendapatkan penjelasan atau mengajukan keluhan terkait privasi.</li>
        </ul>
        <p>
          Untuk meminta penghapusan akun dan data, kirim permintaan melalui email kontak di
          bawah dari alamat email akun Anda. Sebagian data dapat dipertahankan jika diwajibkan
          hukum atau diperlukan untuk keamanan dan penyelesaian transaksi.
        </p>
      </>
    ),
  },
  {
    title: '8. Privasi Anak',
    content: (
      <p>
        SaDesa tidak ditujukan untuk anak di bawah usia yang diperbolehkan oleh hukum yang
        berlaku untuk memberikan data pribadi sendiri. Jika Anda mengetahui adanya data anak
        yang dikumpulkan tanpa izin yang sesuai, silakan hubungi kami agar dapat ditindaklanjuti.
      </p>
    ),
  },
  {
    title: '9. Perubahan Kebijakan',
    content: (
      <p>
        Kami dapat memperbarui kebijakan ini dari waktu ke waktu. Perubahan akan dipublikasikan
        pada halaman ini beserta tanggal pembaruan terbaru. Penggunaan layanan setelah perubahan
        berlaku berarti Anda telah membaca kebijakan yang diperbarui.
      </p>
    ),
  },
];

export default function PrivacyPolicyPage() {
  const navigate = useNavigate();

  useEffect(() => {
    document.title = 'Kebijakan Privasi | SaDesa';
    const description = 'Kebijakan Privasi SaDesa tentang pengumpulan, penggunaan, dan perlindungan data pengguna.';
    let meta = document.querySelector<HTMLMetaElement>('meta[name="description"]');
    if (!meta) {
      meta = document.createElement('meta');
      meta.name = 'description';
      document.head.appendChild(meta);
    }
    meta.content = description;
  }, []);

  return (
    <div className="mobile-shell flex min-h-screen flex-col bg-background">
      <Header />
      <main className="flex-1 overflow-y-auto pb-24">
        <article className="mx-auto max-w-3xl px-5 py-6 sm:px-8">
          <button
            onClick={() => safeGoBack(navigate)}
            className="mb-5 flex items-center gap-2 text-sm text-muted-foreground transition hover:text-foreground"
          >
            <ArrowLeft className="h-4 w-4" />
            <span>Kembali</span>
          </button>

          <div className="mb-8 rounded-2xl border border-emerald-100 bg-emerald-50/70 p-5 dark:border-emerald-900 dark:bg-emerald-950/30">
            <p className="mb-2 text-xs font-semibold uppercase tracking-[0.18em] text-emerald-700 dark:text-emerald-300">Dokumen resmi SaDesa</p>
            <h1 className="text-2xl font-bold tracking-tight text-foreground sm:text-3xl">Kebijakan Privasi</h1>
            <p className="mt-3 text-sm leading-6 text-muted-foreground">
              Terakhir diperbarui: 26 September 2026. Halaman ini dapat diakses tanpa login dan
              merupakan URL kebijakan privasi untuk aplikasi SaDesa.
            </p>
          </div>

          <div className="prose prose-sm max-w-none space-y-6 text-sm leading-6 text-muted-foreground dark:prose-invert">
            {sections.map((section) => (
              <section key={section.title}>
                <h2 className="mb-2 text-base font-semibold text-foreground">{section.title}</h2>
                {section.content}
              </section>
            ))}

            <section className="rounded-xl border border-border bg-muted/30 p-4 not-prose">
              <h2 className="mb-2 text-base font-semibold text-foreground">10. Hubungi Kami</h2>
              <p className="leading-6">
                Untuk pertanyaan privasi, permintaan penghapusan akun, atau keluhan terkait data,
                hubungi pengelola SaDesa:
              </p>
              <a
                href="mailto:bopan86@gmail.com?subject=Permintaan%20Privasi%20SaDesa"
                className="mt-3 inline-flex items-center gap-2 font-medium text-emerald-700 hover:underline dark:text-emerald-300"
              >
                <Mail className="h-4 w-4" />
                bopan86@gmail.com
              </a>
            </section>

            <section className="rounded-xl border border-emerald-200 bg-emerald-50/60 p-4 not-prose dark:border-emerald-900 dark:bg-emerald-950/30">
              <h2 className="mb-2 text-base font-semibold text-foreground">Permintaan Penghapusan Akun dan Data</h2>
              <p className="leading-6">
                Anda dapat mengajukan penghapusan akun dan data terkait melalui halaman khusus kami.
              </p>
              <Link
                to="/account-deletion"
                className="mt-3 inline-flex font-medium text-emerald-700 hover:underline dark:text-emerald-300"
              >
                Ajukan penghapusan akun dan data
              </Link>
            </section>

            <p className="border-t border-border pt-5">
              Dengan menggunakan SaDesa, Anda mengakui telah membaca kebijakan ini. Baca juga{' '}
              <Link to="/terms" className="font-medium text-emerald-700 hover:underline dark:text-emerald-300">
                Syarat &amp; Ketentuan
              </Link>
              .
            </p>
          </div>
        </article>
      </main>
      <BottomNav />
    </div>
  );
}

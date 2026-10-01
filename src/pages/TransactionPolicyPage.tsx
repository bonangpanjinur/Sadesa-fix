import { ArrowLeft, CircleAlert, CreditCard, PackageCheck, RefreshCcw, Truck } from 'lucide-react';
import { Link, useNavigate } from 'react-router-dom';
import { Header } from '@/components/layout/Header';
import { BottomNav } from '@/components/layout/BottomNav';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { safeGoBack } from '@/lib/utils';

const policies = [
  { icon: CreditCard, title: 'Pembayaran', body: 'Total pembayaran ditampilkan di checkout sebelum konfirmasi. Metode yang tersedia dapat meliputi transfer bank, QRIS, COD untuk area tertentu, dan pembayaran online melalui penyedia pembayaran yang aktif.' },
  { icon: Truck, title: 'Pengiriman dan layanan antar', body: 'Biaya pengiriman atau layanan dihitung berdasarkan tipe layanan, jarak, wilayah, dan detail pesanan. Estimasi dapat berubah mengikuti ketersediaan merchant dan kurir.' },
  { icon: CircleAlert, title: 'Pembatalan', body: 'Pembatalan dapat diajukan sebelum merchant memproses pesanan. Setelah pesanan diproses atau kurir berangkat, pembatalan dapat dikenai ketentuan sesuai status pesanan.' },
  { icon: RefreshCcw, title: 'Refund dan pengembalian', body: 'Refund dapat diajukan bila produk tidak sesuai, rusak, kurang, atau layanan tidak terlaksana. Sertakan nomor pesanan, alasan, dan bukti foto/video bila diperlukan. Refund diproses setelah pemeriksaan dan persetujuan.' },
  { icon: PackageCheck, title: 'Keluhan', body: 'Sampaikan keluhan melalui Pusat Bantuan atau detail pesanan sesegera mungkin setelah pesanan diterima agar tim dapat membantu merchant, pembeli, dan kurir menyelesaikan masalah.' },
];

export default function TransactionPolicyPage() {
  const navigate = useNavigate();
  return <div className="mobile-shell flex min-h-screen flex-col bg-background"><Header /><main className="flex-1 overflow-y-auto pb-[var(--bottom-nav-space)]"><div className="mx-auto max-w-3xl space-y-5 px-4 py-5 sm:px-6 sm:py-8"><button type="button" onClick={() => safeGoBack(navigate)} className="inline-flex min-h-10 items-center gap-2 rounded-lg px-2 text-sm text-muted-foreground hover:bg-muted hover:text-foreground"><ArrowLeft className="h-4 w-4" /> Kembali</button><section><p className="text-xs font-bold uppercase tracking-[0.16em] text-primary">Kebijakan transaksi</p><h1 className="mt-1 text-2xl font-bold">Refund, pembatalan, dan pengiriman</h1><p className="mt-2 text-sm text-muted-foreground">Informasi ini membantu pembeli memahami transaksi sebelum melanjutkan checkout.</p></section><div className="space-y-3">{policies.map(({ icon: Icon, title, body }) => <Card key={title}><CardHeader className="pb-2"><CardTitle className="flex items-center gap-2 text-base"><Icon className="h-5 w-5 text-primary" />{title}</CardTitle></CardHeader><CardContent className="text-sm leading-relaxed text-muted-foreground">{body}</CardContent></Card>)}</div><div className="rounded-xl border border-primary/20 bg-primary/[0.04] p-4 text-sm">Punya pertanyaan sebelum membeli? <Link to="/contact" className="font-semibold text-primary hover:underline">Hubungi tim SaDesa</Link>.</div></div></main><BottomNav /></div>;
}

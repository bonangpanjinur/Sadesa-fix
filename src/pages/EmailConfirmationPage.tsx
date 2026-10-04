import { useState } from 'react';
import { useNavigate, useLocation } from 'react-router-dom';
import { motion } from 'framer-motion';
import { Mail, ArrowLeft, RefreshCw, CheckCircle, Loader2, ExternalLink } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { supabase } from '@/integrations/supabase/client';
import { normalizeEmail, signupEmailSchema } from '@/lib/emailValidation';
import { checkPersistentRateLimit, RATE_LIMITS } from '@/lib/rateLimit';
import { toast } from '@/hooks/use-toast';

export default function EmailConfirmationPage() {
  const navigate = useNavigate();
  const location = useLocation();
  const initialEmail = (location.state as { email?: string })?.email || '';
  const [email] = useState(normalizeEmail(initialEmail));
  const [resending, setResending] = useState(false);
  const [resent, setResent] = useState(false);
  const [error, setError] = useState('');

  const handleResend = async () => {
    if (!signupEmailSchema.safeParse(email).success) {
      setError('Email pendaftaran tidak ditemukan. Silakan daftar kembali.');
      return;
    }

    const resendLimit = checkPersistentRateLimit(email, 'resendOtp', RATE_LIMITS.resendOtp);
    if (!resendLimit.allowed) {
      setError(`Batas kirim ulang tercapai. Coba lagi dalam ${Math.ceil(resendLimit.resetIn / 60000)} menit.`);
      return;
    }

    setResending(true);
    setError('');
    try {
      const { error: resendError } = await supabase.auth.resend({ type: 'signup', email });
      if (resendError) throw resendError;
      setResent(true);
      toast({ title: 'Email verifikasi berhasil dikirim ulang.' });
    } catch (resendError: unknown) {
      setError(resendError instanceof Error ? resendError.message : 'Gagal mengirim ulang email verifikasi.');
    } finally {
      setResending(false);
    }
  };

  return (
    <div className="mobile-shell bg-background flex flex-col min-h-screen">
      <div className="p-4">
        <button
          onClick={() => navigate('/auth')}
          className="w-8 h-8 rounded-full hover:bg-secondary flex items-center justify-center"
          aria-label="Kembali ke masuk"
        >
          <ArrowLeft className="h-5 w-5" />
        </button>
      </div>

      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        className="flex-1 flex flex-col items-center justify-center px-6 pb-10 text-center"
      >
        <div className="w-20 h-20 rounded-full bg-primary/10 flex items-center justify-center mb-6">
          <Mail className="h-10 w-10 text-primary" />
        </div>

        <h1 className="text-2xl font-bold text-foreground mb-3">Cek Email Anda</h1>
        <p className="text-muted-foreground text-sm leading-relaxed max-w-sm">
          Pendaftaran Anda hampir selesai. Kami telah mengirim email verifikasi ke:
        </p>
        {email && <p className="font-semibold text-foreground mt-2 mb-5 break-all">{email}</p>}

        <div className="w-full max-w-sm rounded-xl border border-primary/20 bg-primary/5 p-4 text-left">
          <p className="font-medium text-sm text-foreground mb-2">Verifikasi pendaftaran Anda</p>
          <ol className="text-xs text-muted-foreground space-y-2 list-decimal pl-4">
            <li>Buka inbox email tersebut dan cari email dari SaDesa.</li>
            <li>Klik tombol <strong className="text-foreground">Verifikasi Email</strong> di dalam email.</li>
            <li>Setelah berhasil, kembali ke aplikasi dan masuk menggunakan akun Anda.</li>
          </ol>
        </div>

        <a
          href="https://mail.google.com/"
          target="_blank"
          rel="noreferrer"
          className="mt-5 inline-flex items-center gap-2 text-sm font-medium text-primary hover:underline"
        >
          Buka Gmail <ExternalLink className="h-4 w-4" />
        </a>

        {error && (
          <p role="alert" className="w-full max-w-sm mt-4 text-xs text-destructive">
            {error}
          </p>
        )}

        <div className="w-full max-w-sm space-y-3 mt-6">
          <Button variant="outline" className="w-full" onClick={handleResend} disabled={resending || resent || !email}>
            {resent ? (
              <><CheckCircle className="h-4 w-4 mr-2" />Email terkirim</>
            ) : (
              <><RefreshCw className={`h-4 w-4 mr-2 ${resending ? 'animate-spin' : ''}`} />{resending ? 'Mengirim...' : 'Kirim ulang email verifikasi'}</>
            )}
          </Button>
          <Button className="w-full" onClick={() => navigate('/auth')}>
            Saya sudah memverifikasi email
          </Button>
        </div>

        <p className="text-xs text-muted-foreground mt-6 max-w-sm leading-relaxed">
          Belum menerima email? Periksa folder Spam atau Promosi. Pastikan alamat email yang didaftarkan benar-benar aktif.
        </p>
      </motion.div>
    </div>
  );
}

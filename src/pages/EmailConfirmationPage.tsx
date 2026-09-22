import { useState } from 'react';
import { useNavigate, useLocation } from 'react-router-dom';
import { motion } from 'framer-motion';
import { Mail, ArrowLeft, RefreshCw, CheckCircle, Loader2, KeyRound } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { supabase } from '@/integrations/supabase/client';
import { normalizeEmail, signupEmailSchema } from '@/lib/emailValidation';
import { toast } from '@/hooks/use-toast';

export default function EmailConfirmationPage() {
  const navigate = useNavigate();
  const location = useLocation();
  const initialEmail = (location.state as { email?: string })?.email || '';
  const [email] = useState(normalizeEmail(initialEmail));
  const [token, setToken] = useState('');
  const [resending, setResending] = useState(false);
  const [verifying, setVerifying] = useState(false);
  const [resent, setResent] = useState(false);
  const [error, setError] = useState('');

  const handleVerifyToken = async (event: React.FormEvent) => {
    event.preventDefault();
    setError('');

    if (!signupEmailSchema.safeParse(email).success) {
      setError('Email pendaftaran tidak ditemukan. Silakan daftar kembali.');
      return;
    }
    if (!/^\d{6}$/.test(token)) {
      setError('Masukkan kode OTP 6 digit dari email Anda.');
      return;
    }

    setVerifying(true);
    try {
      const { error: verifyError } = await supabase.auth.verifyOtp({
        email,
        token,
        type: 'signup',
      });
      if (verifyError) throw verifyError;
      toast({ title: 'Email berhasil diverifikasi!' });
      navigate('/auth', { replace: true });
    } catch (verificationError: unknown) {
      setError(verificationError instanceof Error ? verificationError.message : 'Kode OTP tidak valid atau sudah kedaluwarsa.');
    } finally {
      setVerifying(false);
    }
  };

  const handleResend = async () => {
    if (!signupEmailSchema.safeParse(email).success) {
      setError('Email pendaftaran tidak ditemukan. Silakan daftar kembali.');
      return;
    }
    setResending(true);
    setError('');
    try {
      const { error: resendError } = await supabase.auth.resend({ type: 'signup', email });
      if (resendError) throw resendError;
      setResent(true);
      setToken('');
      toast({ title: 'Email verifikasi dikirim ulang!' });
    } catch (resendError: unknown) {
      setError(resendError instanceof Error ? resendError.message : 'Gagal mengirim ulang email verifikasi.');
    } finally {
      setResending(false);
    }
  };

  return (
    <div className="mobile-shell bg-background flex flex-col min-h-screen">
      <div className="p-4">
        <button onClick={() => navigate('/auth')} className="w-8 h-8 rounded-full hover:bg-secondary flex items-center justify-center" aria-label="Kembali ke masuk">
          <ArrowLeft className="h-5 w-5" />
        </button>
      </div>

      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        className="flex-1 flex flex-col items-center justify-center px-6 text-center"
      >
        <div className="w-20 h-20 rounded-full bg-primary/10 flex items-center justify-center mb-6">
          <Mail className="h-10 w-10 text-primary" />
        </div>

        <h1 className="text-2xl font-bold text-foreground mb-2">Verifikasi Email</h1>
        <p className="text-muted-foreground text-sm mb-2">
          Kami mengirim link verifikasi dan kode OTP ke:
        </p>
        {email && <p className="font-semibold text-foreground mb-6 break-all">{email}</p>}

        <form onSubmit={handleVerifyToken} className="w-full max-w-sm space-y-3 text-left">
          <label htmlFor="verification-token" className="text-sm font-medium text-foreground">
            Kode OTP 6 digit
          </label>
          <div className="relative">
            <KeyRound className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
            <Input
              id="verification-token"
              value={token}
              onChange={(event) => {
                setToken(event.target.value.replace(/\D/g, '').slice(0, 6));
                setError('');
              }}
              inputMode="numeric"
              autoComplete="one-time-code"
              pattern="[0-9]{6}"
              maxLength={6}
              placeholder="123456"
              className="pl-10 tracking-[0.35em]"
              aria-describedby={error ? 'verification-error' : 'verification-help'}
            />
          </div>
          <p id="verification-help" className="text-xs text-muted-foreground">
            Anda juga dapat langsung mengeklik link verifikasi di email.
          </p>
          {error && <p id="verification-error" role="alert" className="text-xs text-destructive">{error}</p>}
          <Button type="submit" className="w-full" disabled={verifying || !email}>
            {verifying ? <><Loader2 className="h-4 w-4 mr-2 animate-spin" />Memverifikasi...</> : 'Verifikasi OTP'}
          </Button>
        </form>

        <div className="bg-muted/50 rounded-xl p-4 mt-6 text-left w-full max-w-sm">
          <h3 className="font-medium text-sm text-foreground mb-2">Belum menerima email?</h3>
          <ol className="text-xs text-muted-foreground space-y-2 list-decimal pl-4">
            <li>Periksa inbox dan folder Spam.</li>
            <li>Pastikan email yang didaftarkan benar-benar aktif.</li>
            <li>Kirim ulang email verifikasi jika diperlukan.</li>
          </ol>
        </div>

        <div className="space-y-3 w-full max-w-sm mt-6">
          <Button variant="outline" className="w-full" onClick={handleResend} disabled={resending || resent || !email}>
            {resent ? <><CheckCircle className="h-4 w-4 mr-2" />Email terkirim!</> : <><RefreshCw className={`h-4 w-4 mr-2 ${resending ? 'animate-spin' : ''}`} />{resending ? 'Mengirim...' : 'Kirim ulang email'}</>}
          </Button>
          <Button className="w-full" onClick={() => navigate('/auth')}>Kembali ke Halaman Masuk</Button>
        </div>
      </motion.div>
    </div>
  );
}

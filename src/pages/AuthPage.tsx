import { useState, useEffect } from 'react';
import { useNavigate, Link, useLocation } from 'react-router-dom';
import { safeGoBack } from '@/lib/utils';
import { motion } from 'framer-motion';
import { ArrowLeft, Eye, EyeOff, Mail, Lock, User, Loader2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from '@/hooks/use-toast';
import { getRedirectPathForRoles } from '@/types/auth';
import { normalizeEmail, signupEmailSchema } from '@/lib/emailValidation';
import { checkPersistentRateLimit, RATE_LIMITS } from '@/lib/rateLimit';
import { createOtpExpiration, getOtpExpirationKey } from '@/lib/otp';
import { AddressSelector, createEmptyAddressData, type AddressData } from '@/components/AddressSelector';
import { z } from 'zod';

const signUpSchema = z.object({
  fullName: z.string().min(2, 'Nama minimal 2 karakter').max(100, 'Nama terlalu panjang'),
  email: signupEmailSchema,
  password: z.string()
    .min(8, 'Password minimal 8 karakter')
    .regex(/[A-Za-z]/, 'Password harus mengandung huruf')
    .regex(/[0-9]/, 'Password harus mengandung angka'),
  confirmPassword: z.string(),
  address: z.object({
    province: z.string().min(1, 'Provinsi wajib dipilih'),
    city: z.string().min(1, 'Kabupaten/Kota wajib dipilih'),
    district: z.string().min(1, 'Kecamatan wajib dipilih'),
    village: z.string().min(1, 'Desa/Kelurahan wajib dipilih'),
  }),
}).refine((data) => data.password === data.confirmPassword, {
  message: 'Password tidak sama',
  path: ['confirmPassword'],
});

const signInSchema = z.object({
  email: signupEmailSchema,
  password: z.string().min(1, 'Password wajib diisi'),
});

export default function AuthPage() {
  const navigate = useNavigate();
  const location = useLocation();
  const { user, roles, loading: authLoading, rolesLoading, signIn, signUp } = useAuth();
  const [isLogin, setIsLogin] = useState(true);
  const [loading, setLoading] = useState(false);
  const [showPassword, setShowPassword] = useState(false);
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [addressData, setAddressData] = useState<AddressData>(createEmptyAddressData);
  
  const [formData, setFormData] = useState({
    fullName: '',
    email: '',
    password: '',
    confirmPassword: '',
  });

  // Redirect authenticated users to their role-specific dashboard
  useEffect(() => {
    if (authLoading || rolesLoading) return;
    
    if (user && roles.length > 0) {
      const from = (location.state as { from?: { pathname: string; search?: string } })?.from;
      const redirectPath = from ? `${from.pathname}${from.search || ''}` : getRedirectPathForRoles(roles);
      navigate(redirectPath, { replace: true });
    }
  }, [user, roles, authLoading, rolesLoading, navigate, location]);

  const validateForm = (values = formData) => {
    const schema = isLogin ? signInSchema : signUpSchema;
    const result = schema.safeParse(isLogin ? values : { ...values, address: addressData });
    if (result.success) {
      setErrors({});
      return true;
    }

    const fieldErrors: Record<string, string> = {};
    result.error.errors.forEach((err) => {
      const field = err.path[0];
      if (typeof field === 'string' && !fieldErrors[field]) {
        fieldErrors[field] = err.message;
      }
    });
    setErrors(fieldErrors);
    return false;
  };

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const { name, value } = e.target;
    const nextFormData = { ...formData, [name]: value };
    setFormData(nextFormData);
    setErrors(prev => ({ ...prev, [name]: '' }));
  };

  const handleBlur = (e: React.FocusEvent<HTMLInputElement>) => {
    const field = e.target.name;
    const schema = isLogin ? signInSchema : signUpSchema;
    const result = schema.safeParse(formData);
    const fieldError = result.success
      ? undefined
      : result.error.errors.find((error) => error.path[0] === field)?.message;
    setErrors(prev => ({ ...prev, [field]: fieldError ?? '' }));
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrors({});
    if (!validateForm()) return;
    setLoading(true);

    try {
      if (isLogin) {
        const { error } = await signIn(normalizeEmail(formData.email), formData.password);
        if (error) {
          toast({
            title: 'Gagal masuk',
            description: error.message === 'Invalid login credentials'
              ? 'Email atau password salah'
              : error.message.toLowerCase().includes('email not confirmed')
                ? 'Email belum dikonfirmasi. Silakan klik tautan verifikasi di inbox Anda.'
                : error.message,
            variant: 'destructive',
          });
        } else {
          toast({ title: 'Berhasil masuk!' });
          // Redirect will happen automatically via useEffect
        }
      } else {
        const signupEmail = normalizeEmail(formData.email);
        const otpLimit = checkPersistentRateLimit(signupEmail, 'signupOtp', RATE_LIMITS.signupOtp);
        if (!otpLimit.allowed) {
          toast({
            title: 'Terlalu banyak permintaan',
            description: `Email verifikasi dapat dikirim lagi dalam ${Math.ceil(otpLimit.resetIn / 60000)} menit.`,
            variant: 'destructive',
          });
          return;
        }
        const { data, error } = await signUp(
          signupEmail,
          formData.password,
          formData.fullName.trim(),
          addressData,
        );
        if (error) {
          toast({
            title: 'Gagal daftar',
            description: error.message,
            variant: 'destructive',
          });
        } else {
          if (data?.session) {
            toast({ title: 'Akun berhasil didaftarkan.' });
          } else {
            try {
              window.localStorage.setItem(getOtpExpirationKey(signupEmail), String(createOtpExpiration()));
            } catch {
              // The verification flow remains protected by Supabase's token expiry.
            }
            navigate('/email-confirmation', { state: { email: normalizeEmail(formData.email) } });
          }
        }
      }
    } finally {
      setLoading(false);
    }
  };

  // Show loading while checking auth state
  if (authLoading || rolesLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-background">
        <div className="flex flex-col items-center gap-3">
          <Loader2 className="h-8 w-8 animate-spin text-primary" />
          <p className="text-sm text-muted-foreground">Memuat...</p>
        </div>
      </div>
    );
  }

  // Don't render if user is already logged in (will redirect)
  if (user) {
    return null;
  }

  return (
    <div className="mobile-shell bg-background flex flex-col min-h-screen">
      {/* Header */}
      <div className="p-4 flex items-center gap-3">
        <button 
          onClick={() => safeGoBack(navigate)}
          className="w-8 h-8 rounded-full hover:bg-secondary flex items-center justify-center"
        >
          <ArrowLeft className="h-5 w-5" />
        </button>
        <h2 className="font-bold text-lg text-foreground">
          {isLogin ? 'Masuk' : 'Daftar'}
        </h2>
      </div>
      
      <motion.div 
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        className="flex-1 px-6 py-4"
      >
        <div className="text-center mb-8">
          <h1 className="text-2xl font-bold text-foreground mb-2">
            {isLogin ? 'Selamat Datang!' : 'Buat Akun Baru'}
          </h1>
          <p className="text-muted-foreground text-sm">
            {isLogin 
              ? 'Masuk untuk melanjutkan belanja' 
              : 'Daftar untuk mulai berbelanja di SaDesa'}
          </p>
        </div>

        <form onSubmit={handleSubmit} className="space-y-4">
          {!isLogin && (
            <div className="space-y-2">
              <Label htmlFor="fullName">Nama Lengkap</Label>
              <div className="relative">
                <User className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                <Input
                  id="fullName"
                  name="fullName"
                  placeholder="Masukkan nama lengkap"
                  value={formData.fullName}
                  onChange={handleChange}
                  onBlur={handleBlur}
                  autoComplete="name"
                  required
                  minLength={2}
                  maxLength={100}
                  aria-invalid={Boolean(errors.fullName)}
                  aria-describedby={errors.fullName ? 'fullName-error' : undefined}
                  className="pl-10"
                />
              </div>
              {errors.fullName && (
                <p id="fullName-error" role="alert" className="text-xs text-destructive">{errors.fullName}</p>
              )}
            </div>
          )}

          {!isLogin && (
            <div className="space-y-2">
              <Label>Alamat Utama <span className="text-destructive">*</span></Label>
              <p className="text-xs text-muted-foreground">Pilih seluruh wilayah: provinsi, kabupaten/kota, kecamatan, dan desa/kelurahan.</p>
              <AddressSelector
                value={addressData}
                onChange={(nextAddress) => {
                  setAddressData(nextAddress);
                  setErrors((previous) => ({ ...previous, address: '' }));
                }}
                showDetailInput={false}
                requiredFields
                disabled={loading}
              />
              {errors.address && <p role="alert" className="text-xs text-destructive">{errors.address}</p>}
            </div>
          )}

          <div className="space-y-2">
            <Label htmlFor="email">Email</Label>
            <div className="relative">
              <Mail className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
              <Input
                id="email"
                name="email"
                type="email"
                placeholder="contoh@email.com"
                value={formData.email}
                onChange={handleChange}
                onBlur={handleBlur}
                autoComplete="email"
                inputMode="email"
                required
                maxLength={254}
                aria-invalid={Boolean(errors.email)}
                aria-describedby={errors.email ? 'email-error' : undefined}
                className="pl-10"
              />
            </div>
            <p className="text-[10px] text-muted-foreground italic">Gunakan email yang benar-benar aktif. Tautan verifikasi akan dikirim ke inbox Anda.</p>
            {errors.email && (
              <p id="email-error" role="alert" className="text-xs text-destructive">{errors.email}</p>
            )}
          </div>

          <div className="space-y-2">
            <Label htmlFor="password">Password</Label>
            <div className="relative">
              <Lock className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
              <Input
                id="password"
                name="password"
                type={showPassword ? 'text' : 'password'}
                placeholder="Masukkan password"
                value={formData.password}
                onChange={handleChange}
                onBlur={handleBlur}
                autoComplete={isLogin ? 'current-password' : 'new-password'}
                required
                minLength={isLogin ? 1 : 8}
                aria-invalid={Boolean(errors.password)}
                aria-describedby={errors.password ? 'password-error' : 'password-hint'}
                className="pl-10 pr-10"
              />
              <button
                type="button"
                onClick={() => setShowPassword(!showPassword)}
                aria-label={showPassword ? 'Sembunyikan password' : 'Tampilkan password'}
                aria-pressed={showPassword}
                className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
              >
                {showPassword ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
              </button>
            </div>
            {!isLogin && !errors.password && (
              <p id="password-hint" className="text-xs text-muted-foreground">Minimal 8 karakter, mengandung huruf dan angka.</p>
            )}
            {errors.password && (
              <p id="password-error" role="alert" className="text-xs text-destructive">{errors.password}</p>
            )}
          </div>

          {!isLogin && (
            <div className="space-y-2">
              <Label htmlFor="confirmPassword">Konfirmasi Password</Label>
              <div className="relative">
                <Lock className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                <Input
                  id="confirmPassword"
                  name="confirmPassword"
                  type={showPassword ? 'text' : 'password'}
                  placeholder="Ulangi password"
                  value={formData.confirmPassword}
                  onChange={handleChange}
                  onBlur={handleBlur}
                  autoComplete="new-password"
                  required
                  minLength={8}
                  aria-invalid={Boolean(errors.confirmPassword)}
                  aria-describedby={errors.confirmPassword ? 'confirmPassword-error' : undefined}
                  className="pl-10"
                />
              </div>
              {errors.confirmPassword && (
                <p id="confirmPassword-error" role="alert" className="text-xs text-destructive">{errors.confirmPassword}</p>
              )}
            </div>
          )}

          {isLogin && (
            <div className="mt-4 text-center">
              <Link to="/forgot-password" className="text-sm text-muted-foreground hover:text-primary">
                Lupa password?
              </Link>
            </div>
          )}
          <Button 
            type="submit" 
            className="w-full shadow-brand" 
            size="lg"
            disabled={loading}
          >
            {loading ? (
              <>
                <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                {isLogin ? 'Masuk...' : 'Mendaftar...'}
              </>
            ) : (
              isLogin ? 'Masuk' : 'Daftar'
            )}
          </Button>
        </form>

        <div className="mt-6 text-center">
          <p className="text-sm text-muted-foreground">
            {isLogin ? 'Belum punya akun?' : 'Sudah punya akun?'}
            <button
              type="button"
              onClick={() => {
                setIsLogin(!isLogin);
                setErrors({});
              }}
              className="ml-1 text-primary font-semibold hover:underline"
            >
              {isLogin ? 'Daftar' : 'Masuk'}
            </button>
          </p>
        </div>

        <div className="mt-4 text-center">
          <p className="text-[10px] text-muted-foreground">
            Dengan masuk, Anda menyetujui{' '}
            <Link to="/terms" className="underline hover:text-primary">Syarat & Ketentuan</Link>
            {' '}dan{' '}
            <Link to="/privacy" className="underline hover:text-primary">Kebijakan Privasi</Link>
          </p>
        </div>
      </motion.div>
    </div>
  );
}

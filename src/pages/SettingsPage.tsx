import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { safeGoBack } from '@/lib/utils';
import { motion } from 'framer-motion';
import { ArrowLeft, Bell, Globe, Shield, Lock, Loader2, Mail } from 'lucide-react';
import { Header } from '@/components/layout/Header';
import { BottomNav } from '@/components/layout/BottomNav';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { PushNotificationSettings } from '@/components/settings/PushNotificationSettings';
import { LanguageSwitcher } from '@/components/common/LanguageSwitcher';
import { useTranslation } from '@/lib/i18n';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { passwordSchema } from '@/lib/validationSchemas';
import { normalizeEmail, signupEmailSchema } from '@/lib/emailValidation';

export default function SettingsPage() {
  const navigate = useNavigate();
  const { user, isCourier } = useAuth();
  const { t } = useTranslation();
  const [showPasswordForm, setShowPasswordForm] = useState(false);
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [changingPassword, setChangingPassword] = useState(false);
  const [showEmailForm, setShowEmailForm] = useState(false);
  const [newEmail, setNewEmail] = useState('');
  const [changingEmail, setChangingEmail] = useState(false);

  const resetPasswordForm = () => {
    setShowPasswordForm(false);
    setNewPassword('');
    setConfirmPassword('');
  };

  const handleChangePassword = async () => {
    const passwordResult = passwordSchema.safeParse(newPassword);
    if (!passwordResult.success) {
      toast.error(t('settings.password.policy_error'));
      return;
    }
    if (newPassword !== confirmPassword) {
      toast.error(t('settings.password.mismatch'));
      return;
    }

    setChangingPassword(true);
    try {
      const { error } = await supabase.auth.updateUser({ password: newPassword });
      if (error) throw error;
      toast.success(t('settings.password.changed'));
      resetPasswordForm();
    } catch (error: unknown) {
      toast.error(error instanceof Error ? error.message : t('settings.password.update_failed'));
    } finally {
      setChangingPassword(false);
    }
  };

  const resetEmailForm = () => {
    setShowEmailForm(false);
    setNewEmail('');
  };

  const handleChangeEmail = async () => {
    const normalizedEmail = normalizeEmail(newEmail);
    const emailResult = signupEmailSchema.safeParse(normalizedEmail);
    if (!emailResult.success) {
      toast.error(emailResult.error.issues[0]?.message || 'Masukkan email yang valid.');
      return;
    }
    if (normalizedEmail === normalizeEmail(user?.email || '')) {
      toast.error('Email baru harus berbeda dari email saat ini.');
      return;
    }

    setChangingEmail(true);
    try {
      const { error } = await supabase.auth.updateUser(
        { email: normalizedEmail },
        { emailRedirectTo: `${window.location.origin}/auth` },
      );
      if (error) throw error;
      toast.success('Tautan konfirmasi telah dikirim ke email baru. Buka email tersebut untuk menyelesaikan perubahan.');
      resetEmailForm();
    } catch (error: unknown) {
      toast.error(error instanceof Error ? error.message : 'Gagal mengubah email.');
    } finally {
      setChangingEmail(false);
    }
  };

  return (
    <div className="mobile-shell flex min-h-screen flex-col bg-background">
      <Header />

      <div className="flex-1 overflow-y-auto pb-24">
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          className="px-5 py-4"
        >
          <div className="mb-6 flex items-center gap-3">
            <Button
              variant="ghost"
              size="icon"
              aria-label={t('settings.back')}
              title={t('settings.back')}
              onClick={() => safeGoBack(navigate)}
            >
              <ArrowLeft className="h-5 w-5" />
            </Button>
            <div>
              <h1 className="text-xl font-bold">{t('settings.title')}</h1>
              <p className="text-sm text-muted-foreground">{t('settings.description')}</p>
            </div>
          </div>

          <div className="space-y-4">
            {user && (
              <Card>
                <CardHeader className="pb-3">
                  <div className="flex items-center gap-2">
                    <Bell className="h-5 w-5 text-primary" />
                    <CardTitle className="text-base">{t('settings.push.title')}</CardTitle>
                  </div>
                  <CardDescription>{t('settings.push.description')}</CardDescription>
                </CardHeader>
                <CardContent>
                  <PushNotificationSettings required={isCourier} />
                </CardContent>
              </Card>
            )}

            <Card>
              <CardHeader className="pb-3">
                <div className="flex items-center gap-2">
                  <Globe className="h-5 w-5 text-primary" />
                  <CardTitle className="text-base">{t('settings.language.title')}</CardTitle>
                </div>
                <CardDescription>{t('settings.language.description')}</CardDescription>
              </CardHeader>
              <CardContent className="space-y-2">
                <p className="text-xs text-muted-foreground">{t('settings.language.active')}</p>
                <LanguageSwitcher variant="inline" />
              </CardContent>
            </Card>

            <Card>
              <CardHeader className="pb-3">
                <div className="flex items-center gap-2">
                  <Shield className="h-5 w-5 text-primary" />
                  <CardTitle className="text-base">{t('settings.privacy.title')}</CardTitle>
                </div>
                <CardDescription>{t('settings.privacy.description')}</CardDescription>
              </CardHeader>
              <CardContent className="space-y-3">
                {user && (
                  <>
                    {!showEmailForm ? (
                      <Button type="button" variant="outline" className="w-full justify-start" onClick={() => setShowEmailForm(true)}>
                        <Mail className="mr-2 h-4 w-4" />
                        Ganti email akun
                      </Button>
                    ) : (
                      <div className="space-y-3 rounded-lg border border-border p-3">
                        <div>
                          <p className="text-sm font-medium">Ganti email akun</p>
                          <p className="mt-1 text-xs text-muted-foreground">Tautan konfirmasi akan dikirim ke email baru. Email lama tetap aktif sampai perubahan dikonfirmasi.</p>
                        </div>
                        <div className="space-y-1.5">
                          <Label htmlFor="new-email" className="text-xs">Email baru</Label>
                          <Input
                            id="new-email"
                            type="email"
                            autoComplete="email"
                            inputMode="email"
                            disabled={changingEmail}
                            placeholder="nama@email.com"
                            value={newEmail}
                            onChange={(event) => setNewEmail(event.target.value)}
                          />
                        </div>
                        <div className="flex gap-2">
                          <Button type="button" size="sm" onClick={handleChangeEmail} disabled={changingEmail || !newEmail.trim()}>
                            {changingEmail && <Loader2 className="mr-1 h-3 w-3 animate-spin" aria-hidden="true" />}
                            {changingEmail ? 'Mengirim...' : 'Kirim konfirmasi'}
                          </Button>
                          <Button type="button" size="sm" variant="ghost" onClick={resetEmailForm} disabled={changingEmail}>
                            Batal
                          </Button>
                        </div>
                      </div>
                    )}
                    {!showPasswordForm ? (
                      <Button type="button" variant="outline" className="w-full justify-start" onClick={() => setShowPasswordForm(true)}>
                        <Lock className="mr-2 h-4 w-4" />
                        {t('settings.password.change')}
                      </Button>
                    ) : (
                      <div className="space-y-3 rounded-lg border border-border p-3">
                        <div className="space-y-1.5">
                          <Label htmlFor="new-password" className="text-xs">{t('settings.password.new')}</Label>
                          <Input
                            id="new-password"
                            type="password"
                            autoComplete="new-password"
                            minLength={8}
                            required
                            disabled={changingPassword}
                            placeholder={t('settings.password.placeholder')}
                            value={newPassword}
                            onChange={(event) => setNewPassword(event.target.value)}
                          />
                        </div>
                        <div className="space-y-1.5">
                          <Label htmlFor="confirm-password" className="text-xs">{t('settings.password.confirm')}</Label>
                          <Input
                            id="confirm-password"
                            type="password"
                            autoComplete="new-password"
                            required
                            disabled={changingPassword}
                            placeholder={t('settings.password.confirm_placeholder')}
                            value={confirmPassword}
                            onChange={(event) => setConfirmPassword(event.target.value)}
                          />
                        </div>
                        <div className="flex gap-2">
                          <Button type="button" size="sm" onClick={handleChangePassword} disabled={changingPassword}>
                            {changingPassword && <Loader2 className="mr-1 h-3 w-3 animate-spin" aria-hidden="true" />}
                            {changingPassword ? t('settings.password.saving') : t('settings.password.save')}
                          </Button>
                          <Button type="button" size="sm" variant="ghost" onClick={resetPasswordForm} disabled={changingPassword}>
                            {t('settings.password.cancel')}
                          </Button>
                        </div>
                      </div>
                    )}
                  </>
                )}

                <Button type="button" variant="outline" className="w-full justify-start" onClick={() => navigate('/privacy')}>
                  {t('settings.privacy.policy')}
                </Button>
                <Button type="button" variant="outline" className="w-full justify-start" onClick={() => navigate('/terms')}>
                  {t('settings.privacy.terms')}
                </Button>
              </CardContent>
            </Card>
          </div>

          <p className="mt-8 text-center text-xs text-muted-foreground">{t('settings.footer')}</p>
        </motion.div>
      </div>

      <BottomNav />
    </div>
  );
}

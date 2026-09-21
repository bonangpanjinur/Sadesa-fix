import { useCallback, useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { motion } from 'framer-motion';
import { 
  User, Settings, HelpCircle, LogIn, LogOut, Store, ChevronRight, Edit, Heart, 
  Bell, LayoutDashboard, Shield, CheckCircle, Bike, Building2, MapPin, Star, Clock,
  MessageCircle, Package, Wallet, RefreshCw
} from 'lucide-react';
import { Header } from '@/components/layout/Header';
import { BottomNav } from '@/components/layout/BottomNav';
import { Button } from '@/components/ui/button';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { toast } from '@/hooks/use-toast';
import { ProfileEditor } from '@/components/account/ProfileEditor';

interface Profile {
  full_name: string;
  phone: string | null;
  address: string | null;
  avatar_url?: string | null;
  province_id?: string | null;
  province_name?: string | null;
  city_id?: string | null;
  city_name?: string | null;
  district_id?: string | null;
  district_name?: string | null;
  village_id?: string | null;
  village_name?: string | null;
  address_detail?: string | null;
}

export default function AccountPage() {
  const navigate = useNavigate();
  const { user, signOut, loading: authLoading, isAdmin, isVerifikator, isMerchant, isCourier, isAdminDesa } = useAuth();
  const [profile, setProfile] = useState<Profile | null>(null);
  const [loading, setLoading] = useState(true);
  const [hasPartnerApplication, setHasPartnerApplication] = useState<boolean | null>(null);
  const [editing, setEditing] = useState(false);
  const showVillageRegistration = import.meta.env.VITE_ENABLE_VILLAGE_REGISTRATION === 'true';

  const fetchProfile = useCallback(async () => {
    if (!user) return;

    try {
      const { data, error } = await supabase
        .from('profiles')
        .select('full_name, phone, address, avatar_url, province_id, province_name, city_id, city_name, district_id, district_name, village_id, village_name, address_detail')
        .eq('user_id', user.id)
        .maybeSingle();

      if (error) throw error;

      if (data) {
        setProfile(data);
      }
    } catch (error) {
      console.error('Error fetching profile:', error);
    } finally {
      setLoading(false);
    }
  }, [user]);

  useEffect(() => {
    if (!authLoading && user) {
      fetchProfile();
    } else if (!authLoading) {
      setLoading(false);
    }
  }, [user, authLoading, fetchProfile]);

  useEffect(() => {
    let cancelled = false;
    const checkPartnerApplication = async () => {
      if (!user) {
        setHasPartnerApplication(false);
        return;
      }

      const [merchantResult, courierResult] = await Promise.all([
        supabase.from('merchants').select('id').eq('user_id', user.id).limit(1),
        supabase.from('couriers').select('id').eq('user_id', user.id).limit(1),
      ]);

      if (!cancelled) {
        if (merchantResult.error || courierResult.error) {
          setHasPartnerApplication(true);
          return;
        }
        setHasPartnerApplication(
          (merchantResult.data?.length ?? 0) > 0 || (courierResult.data?.length ?? 0) > 0,
        );
      }
    };

    checkPartnerApplication().catch((error) => {
      console.error('Error checking partner application:', error);
      if (!cancelled) setHasPartnerApplication(true);
    });

    return () => {
      cancelled = true;
    };
  }, [user]);

  const handleProfileSave = async () => {
    setEditing(false);
    // Refetch profile from database to keep state in sync
    await fetchProfile();
  };

  const handleSignOut = async () => {
    await signOut();
    navigate('/');
    toast({ title: 'Berhasil keluar' });
  };

  // Get dashboard buttons based on user roles
  const getDashboardButtons = () => {
    const buttons: { label: string; path: string; icon: React.ReactNode; color: string }[] = [];

    if (isAdmin) {
      buttons.push({
        label: 'Dashboard Admin',
        path: '/admin',
        icon: <Shield className="h-5 w-5" />,
        color: 'bg-destructive/10 text-destructive border-destructive/20',
      });
    }

    if (isAdminDesa) {
      buttons.push({
        label: 'Dashboard Desa',
        path: '/desa',
        icon: <Building2 className="h-5 w-5" />,
        color: 'bg-success/10 text-success border-success/20',
      });
    }

    if (isVerifikator) {
      buttons.push({
        label: 'Dashboard Verifikator',
        path: '/verifikator',
        icon: <CheckCircle className="h-5 w-5" />,
        color: 'bg-info/10 text-info border-info/20',
      });
    }

    if (isMerchant || isAdmin) {
      buttons.push({
        label: 'Dashboard Merchant',
        path: '/merchant',
        icon: <Store className="h-5 w-5" />,
        color: 'bg-warning/10 text-warning border-warning/20',
      });
    }

    if (isCourier) {
      buttons.push({
        label: 'Dashboard Kurir',
        path: '/courier',
        icon: <Bike className="h-5 w-5" />,
        color: 'bg-primary/10 text-primary border-primary/20',
      });
    }

    return buttons;
  };

  const dashboardButtons = getDashboardButtons();

  if (authLoading || loading) {
    return (
      <div className="mobile-shell bg-background flex items-center justify-center min-h-screen">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary" />
      </div>
    );
  }

  return (
    <div className="mobile-shell bg-background flex flex-col min-h-screen">
      <Header />
      
      <div className="flex-1 overflow-y-auto pb-24">
        <motion.div 
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          className="px-5 py-4"
        >
          {user ? (
            <>
              {/* Profile Card */}
              <div className="bg-card rounded-2xl p-6 border border-border mb-6">
                <div className="flex items-center gap-4 mb-4">
                  <div className="w-16 h-16 bg-primary/10 rounded-full flex items-center justify-center overflow-hidden relative group">
                    {profile?.avatar_url ? (
                      <img src={profile.avatar_url} alt="Avatar" className="w-full h-full object-cover" />
                    ) : (
                      <User className="h-8 w-8 text-primary" />
                    )}
                  </div>
                  <div className="flex-1">
                    <h2 className="font-bold text-lg text-foreground">
                      {profile?.full_name || 'Pengguna'}
                    </h2>
                    <p className="text-sm text-muted-foreground">{user.email}</p>
                  </div>
                  {!editing && (
                    <button
                      onClick={() => setEditing(true)}
                      className="p-2 hover:bg-secondary rounded-lg transition"
                    >
                      <Edit className="h-4 w-4 text-muted-foreground" />
                    </button>
                  )}
                </div>

                {editing ? (
                  <ProfileEditor
                    userId={user.id}
                    initialData={{
                      full_name: profile?.full_name || '',
                      phone: profile?.phone || null,
                      address: profile?.address || null,
                      avatar_url: profile?.avatar_url,
                      province_id: profile?.province_id,
                      province_name: profile?.province_name,
                      city_id: profile?.city_id,
                      city_name: profile?.city_name,
                      district_id: profile?.district_id,
                      district_name: profile?.district_name,
                      village_id: profile?.village_id,
                      village_name: profile?.village_name,
                      address_detail: profile?.address_detail,
                    }}
                    onSave={handleProfileSave}
                    onCancel={() => setEditing(false)}
                  />
                ) : (
                  <div className="space-y-2 text-sm">
                    {profile?.phone && (
                      <p className="text-muted-foreground">📱 {profile.phone}</p>
                    )}
                    {profile?.address && (
                      <p className="text-muted-foreground">📍 {profile.address}</p>
                    )}
                    {!profile?.phone && !profile?.address && (
                      <p className="text-muted-foreground italic">
                        Lengkapi profil Anda untuk checkout lebih cepat
                      </p>
                    )}
                  </div>
                )}
              </div>

              {/* Onboarding partner untuk buyer baru */}
              {user && hasPartnerApplication === false && !isMerchant && !isCourier && !isAdmin && !isAdminDesa && !isVerifikator && (
                <section className="mb-6 overflow-hidden rounded-2xl border border-primary/15 bg-gradient-to-br from-primary/5 via-card to-accent/10 p-4">
                  <div className="mb-3">
                    <p className="text-[10px] font-bold uppercase tracking-[0.14em] text-primary">Peluang di Sadesa</p>
                    <h3 className="mt-1 font-heading text-base font-extrabold text-foreground">Mau ikut tumbuh bersama desa?</h3>
                    <p className="mt-1 text-xs leading-relaxed text-muted-foreground">Gunakan akun ini untuk membuka usaha atau mendapatkan penghasilan sebagai kurir.</p>
                  </div>
                  <div className="grid grid-cols-2 gap-2.5">
                    <button
                      type="button"
                      onClick={() => navigate('/register/merchant')}
                      className="group flex min-h-[112px] flex-col justify-between rounded-xl bg-orange-500 p-3 text-left text-white transition hover:-translate-y-0.5 hover:bg-orange-600 active:scale-[0.98]"
                    >
                      <span className="flex h-9 w-9 items-center justify-center rounded-lg bg-white/20"><Store className="h-5 w-5" /></span>
                      <span>
                        <span className="block text-sm font-bold">Daftar Merchant</span>
                        <span className="mt-0.5 block text-[10px] text-white/80">Jual makanan & produk</span>
                      </span>
                    </button>
                    <button
                      type="button"
                      onClick={() => navigate('/register/courier')}
                      className="group flex min-h-[112px] flex-col justify-between rounded-xl bg-emerald-600 p-3 text-left text-white transition hover:-translate-y-0.5 hover:bg-emerald-700 active:scale-[0.98]"
                    >
                      <span className="flex h-9 w-9 items-center justify-center rounded-lg bg-white/20"><Bike className="h-5 w-5" /></span>
                      <span>
                        <span className="block text-sm font-bold">Daftar Kurir</span>
                        <span className="mt-0.5 block text-[10px] text-white/80">Antar pesanan & dapatkan penghasilan</span>
                      </span>
                    </button>
                  </div>
                </section>
              )}

              {/* Quick Access Grid */}
              <div className="grid grid-cols-4 gap-3 mb-6">
                {[
                  { icon: MessageCircle, label: 'Chat', path: '/buyer/chat', color: 'text-primary bg-primary/10' },
                  { icon: Heart, label: 'Wishlist', path: '/wishlist', color: 'text-destructive bg-destructive/10' },
                  { icon: MapPin, label: 'Alamat', path: '/addresses', color: 'text-info bg-info/10' },
                  { icon: HelpCircle, label: 'Bantuan', path: '/help', color: 'text-warning bg-warning/10' },
                ].map((item) => (
                  <button
                    key={item.path}
                    onClick={() => navigate(item.path)}
                    className="flex flex-col items-center gap-1.5 py-3 rounded-xl bg-card border border-border hover:shadow-md transition"
                  >
                    <div className={`w-10 h-10 rounded-full flex items-center justify-center ${item.color}`}>
                      <item.icon className="h-5 w-5" />
                    </div>
                    <span className="text-[11px] font-medium text-foreground">{item.label}</span>
                  </button>
                ))}
              </div>

              {/* Dashboard Buttons */}
              {dashboardButtons.length > 0 && (
                <div className="mb-6">
                  <h3 className="text-sm font-medium text-muted-foreground mb-3 flex items-center gap-2">
                    <LayoutDashboard className="h-4 w-4" />
                    Dashboard Anda
                  </h3>
                  <div className="grid gap-2">
                    {dashboardButtons.map((btn) => (
                      <button
                        key={btn.path}
                        onClick={() => navigate(btn.path)}
                        className={`w-full flex items-center justify-between p-4 rounded-xl border transition hover:shadow-md ${btn.color}`}
                      >
                        <div className="flex items-center gap-3">
                          {btn.icon}
                          <span className="font-medium">{btn.label}</span>
                        </div>
                        <ChevronRight className="h-4 w-4" />
                      </button>
                    ))}
                  </div>
                </div>
              )}
            </>
          ) : (
            <div className="bg-card rounded-2xl p-6 border border-border text-center mb-6">
              <div className="w-20 h-20 bg-secondary rounded-full flex items-center justify-center mx-auto mb-4">
                <User className="h-10 w-10 text-muted-foreground" />
              </div>
              <h2 className="font-bold text-lg text-foreground mb-1">Masuk ke Akun</h2>
              <p className="text-sm text-muted-foreground mb-4">
                Kelola pesanan dan lihat riwayat belanja
              </p>
              <Button className="w-full shadow-brand" onClick={() => navigate('/auth')}>
                <LogIn className="h-4 w-4 mr-2" />
                Masuk / Daftar
              </Button>
            </div>
          )}
          
          {/* Pendaftaran desa wisata disembunyikan sementara; route dan fiturnya tetap dipertahankan. */}
          {showVillageRegistration && user && !isMerchant && !isAdminDesa && !isAdmin && !isVerifikator && !isCourier && (
            <div 
              onClick={() => navigate('/register')}
              className="bg-gradient-to-r from-primary to-brand-dark rounded-2xl p-5 mb-6 text-primary-foreground relative overflow-hidden cursor-pointer hover:shadow-lg transition-shadow"
            >
              <div className="relative z-10">
                <div className="flex items-center gap-2 mb-2">
                  <Store className="h-5 w-5" />
                  <h3 className="font-bold">Bergabung Bersama Kami</h3>
                </div>
                <p className="text-sm opacity-90 mb-3">
                  Daftarkan desa wisata atau usaha UMKM Anda
                </p>
                <Button 
                  variant="secondary"
                  size="sm"
                >
                  Daftar Sekarang
                  <ChevronRight className="h-4 w-4 ml-1" />
                </Button>
              </div>
              <div className="absolute -right-4 -bottom-4 w-24 h-24 bg-primary-foreground/10 rounded-full" />
            </div>
          )}
          
          {/* Menu Items - Grouped */}
          {user && (
            <div className="space-y-4">
              {/* Transaksi Section */}
              <div>
                <h3 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-2 px-1">Transaksi</h3>
                <div className="space-y-1">
                  {[
                    { icon: Package, label: 'Pesanan Saya', path: '/orders' },
                    { icon: Star, label: 'Ulasan Saya', path: '/reviews/mine' },
                    { icon: Bike, label: 'Riwayat Ojek', path: '/ride/history' },
                    { icon: RefreshCw, label: 'Langganan Produk', path: '/langganan' },
                  ].map((item) => (
                    <button
                      key={item.path}
                      onClick={() => navigate(item.path)}
                      className="w-full flex items-center justify-between p-4 bg-card rounded-xl border border-border hover:bg-secondary transition"
                    >
                      <div className="flex items-center gap-3">
                        <item.icon className="h-5 w-5 text-muted-foreground" />
                        <span className="font-medium">{item.label}</span>
                      </div>
                      <ChevronRight className="h-4 w-4 text-muted-foreground" />
                    </button>
                  ))}
                </div>
              </div>

              {/* Reward & Promo Section */}
              <div>
                <h3 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-2 px-1">Reward & Promo</h3>
                <div className="space-y-1">
                  {[
                    { icon: Wallet, label: 'Cashback Saya', path: '/cashback' },
                    { icon: Star, label: 'Loyalty Points', path: '/loyalty' },
                  ].map((item) => (
                    <button
                      key={item.path}
                      onClick={() => navigate(item.path)}
                      className="w-full flex items-center justify-between p-4 bg-card rounded-xl border border-border hover:bg-secondary transition"
                    >
                      <div className="flex items-center gap-3">
                        <item.icon className="h-5 w-5 text-muted-foreground" />
                        <span className="font-medium">{item.label}</span>
                      </div>
                      <ChevronRight className="h-4 w-4 text-muted-foreground" />
                    </button>
                  ))}
                </div>
              </div>

              {/* Lainnya Section */}
              <div>
                <h3 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-2 px-1">Lainnya</h3>
                <div className="space-y-1">
                  {[
                    { icon: Clock, label: 'Terakhir Dilihat', path: '/recently-viewed' },
                    { icon: Bell, label: 'Notifikasi', path: '/notifications' },
                    { icon: Settings, label: 'Pengaturan', path: '/settings' },
                  ].map((item) => (
                    <button
                      key={item.path}
                      onClick={() => navigate(item.path)}
                      className="w-full flex items-center justify-between p-4 bg-card rounded-xl border border-border hover:bg-secondary transition"
                    >
                      <div className="flex items-center gap-3">
                        <item.icon className="h-5 w-5 text-muted-foreground" />
                        <span className="font-medium">{item.label}</span>
                      </div>
                      <ChevronRight className="h-4 w-4 text-muted-foreground" />
                    </button>
                  ))}
                </div>
              </div>

              {/* Keluar */}
              <button 
                onClick={handleSignOut}
                className="w-full flex items-center justify-between p-4 bg-card rounded-xl border border-destructive/20 hover:bg-destructive/5 transition"
              >
                <div className="flex items-center gap-3">
                  <LogOut className="h-5 w-5 text-destructive" />
                  <span className="font-medium text-destructive">Keluar</span>
                </div>
              </button>
            </div>
          )}

          {!user && (
            <div className="space-y-2">
              <button 
                onClick={() => navigate('/settings')}
                className="w-full flex items-center justify-between p-4 bg-card rounded-xl border border-border hover:bg-secondary transition"
              >
                <div className="flex items-center gap-3">
                  <Settings className="h-5 w-5 text-muted-foreground" />
                  <span className="font-medium">Pengaturan</span>
                </div>
                <ChevronRight className="h-4 w-4 text-muted-foreground" />
              </button>
            </div>
          )}
          
          <p className="text-center text-xs text-muted-foreground mt-8">
            SaDesa v1.0.0 • Platform UMKM Desa
          </p>
        </motion.div>
      </div>
      
      <BottomNav />
    </div>
  );
}

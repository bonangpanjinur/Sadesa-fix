import { useState, useEffect } from 'react';
import { AdminLayout } from '@/components/admin/AdminLayout';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { Textarea } from '@/components/ui/textarea';
import { Label } from '@/components/ui/label';
import { supabase } from '@/integrations/supabase/client';
import { useToast } from '@/hooks/use-toast';
import { DollarSign, Clock, CheckCircle, XCircle, Users, TrendingUp, Wallet, Percent, Save, Info } from 'lucide-react';
import { format } from 'date-fns';
import { id } from 'date-fns/locale';

interface VerifikatorEarning {
  id: string;
  verifikator_id: string;
  merchant_id: string;
  subscription_id: string;
  package_id: string;
  package_amount: number;
  commission_percent: number;
  commission_amount: number;
  status: string;
  created_at: string;
  paid_at: string | null;
  merchant?: { name: string };
  package?: { name: string };
}

interface VerifikatorProfile {
  full_name: string;
  phone: string;
}

interface VerifikatorWithdrawal {
  id: string;
  verifikator_id: string;
  amount: number;
  bank_name: string;
  account_number: string;
  account_holder: string;
  status: string;
  admin_notes: string | null;
  processed_at: string | null;
  created_at: string;
  profile?: VerifikatorProfile;
}

interface Stats {
  totalPending: number;
  totalPaid: number;
  pendingWithdrawals: number;
  activeVerifikators: number;
}

interface CommissionPackage {
  id: string;
  name: string;
  price_per_transaction: number;
  group_commission_percent: number;
  is_active: boolean;
}

export default function AdminVerifikatorCommissionsPage() {
  const [earnings, setEarnings] = useState<VerifikatorEarning[]>([]);
  const [withdrawals, setWithdrawals] = useState<VerifikatorWithdrawal[]>([]);
  const [stats, setStats] = useState<Stats>({ totalPending: 0, totalPaid: 0, pendingWithdrawals: 0, activeVerifikators: 0 });
  const [loading, setLoading] = useState(true);
  const [selectedWithdrawal, setSelectedWithdrawal] = useState<VerifikatorWithdrawal | null>(null);
  const [adminNotes, setAdminNotes] = useState('');
  const [processing, setProcessing] = useState(false);
  const [commissionPackages, setCommissionPackages] = useState<CommissionPackage[]>([]);
  const [savingPackageId, setSavingPackageId] = useState<string | null>(null);
  const { toast } = useToast();

  useEffect(() => {
    loadData();
  }, []);

  const loadData = async () => {
    setLoading(true);
    try {
      // Load earnings with merchant and package info
      const { data: earningsData } = await supabase
        .from('verifikator_earnings')
        .select(`
          *,
          merchant:merchants(name),
          package:transaction_packages(name)
        `)
        .order('created_at', { ascending: false });

      // Load withdrawals with profile info
      const { data: withdrawalsData } = await supabase
        .from('verifikator_withdrawals')
        .select('*')
        .order('created_at', { ascending: false });

      const { data: packageData, error: packageError } = await supabase
        .from('transaction_packages')
        .select('id, name, price_per_transaction, group_commission_percent, is_active')
        .order('name', { ascending: true });
      if (packageError) throw packageError;

      // Get verifikator profiles for withdrawals
      if (withdrawalsData && withdrawalsData.length > 0) {
        const verifikatorIds = [...new Set(withdrawalsData.map(w => w.verifikator_id))];
        const { data: profiles } = await supabase
          .from('profiles')
          .select('user_id, full_name, phone')
          .in('user_id', verifikatorIds);

        const profileMap = new Map(profiles?.map(p => [p.user_id, p]) || []);
        withdrawalsData.forEach(w => {
          w.profile = profileMap.get(w.verifikator_id);
        });
      }

      setEarnings(earningsData || []);
      setWithdrawals(withdrawalsData || []);
      setCommissionPackages((packageData || []) as CommissionPackage[]);

      // Calculate stats
      const pendingEarnings = earningsData?.filter(e => e.status === 'PENDING') || [];
      const paidEarnings = earningsData?.filter(e => e.status === 'PAID') || [];
      const pendingWithdrawals = withdrawalsData?.filter(w => w.status === 'PENDING') || [];
      const uniqueVerifikators = new Set(earningsData?.map(e => e.verifikator_id) || []);

      setStats({
        totalPending: pendingEarnings.reduce((sum, e) => sum + e.commission_amount, 0),
        totalPaid: paidEarnings.reduce((sum, e) => sum + e.commission_amount, 0),
        pendingWithdrawals: pendingWithdrawals.length,
        activeVerifikators: uniqueVerifikators.size
      });
    } catch (error) {
      console.error('Error loading data:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleProcessWithdrawal = async (status: 'APPROVED' | 'REJECTED') => {
    if (!selectedWithdrawal) return;
    
    setProcessing(true);
    try {
      const { error } = await supabase.rpc('process_verifikator_withdrawal', {
        p_withdrawal_id: selectedWithdrawal.id,
        p_status: status,
        p_admin_notes: adminNotes || null
      });

      if (error) throw error;

      toast({
        title: status === 'APPROVED' ? 'Withdrawal Disetujui' : 'Withdrawal Ditolak',
        description: `Permintaan withdrawal telah ${status === 'APPROVED' ? 'disetujui' : 'ditolak'}`,
      });

      setSelectedWithdrawal(null);
      setAdminNotes('');
      loadData();
    } catch (error: unknown) {
      toast({
        title: 'Error',
        description: error instanceof Error ? error.message : 'Gagal memproses withdrawal',
        variant: 'destructive',
      });
    } finally {
      setProcessing(false);
    }
  };

  const handleCommissionChange = (packageId: string, value: string) => {
    const parsed = Number(value);
    setCommissionPackages((current) => current.map((pkg) => (
      pkg.id === packageId
        ? { ...pkg, group_commission_percent: Number.isFinite(parsed) ? Math.min(100, Math.max(0, parsed)) : 0 }
        : pkg
    )));
  };

  const saveCommission = async (pkg: CommissionPackage) => {
    if (pkg.group_commission_percent < 0 || pkg.group_commission_percent > 100) {
      toast({ title: 'Persentase tidak valid', description: 'Masukkan nilai antara 0% sampai 100%.', variant: 'destructive' });
      return;
    }
    setSavingPackageId(pkg.id);
    try {
      const { error } = await supabase
        .from('transaction_packages')
        .update({ group_commission_percent: pkg.group_commission_percent })
        .eq('id', pkg.id);
      if (error) throw error;
      toast({
        title: 'Komisi diperbarui',
        description: `${pkg.name}: ${pkg.group_commission_percent}% untuk pembayaran merchant berikutnya.`,
      });
    } catch (error) {
      console.error('Error updating verifier commission:', error);
      toast({ title: 'Gagal memperbarui komisi', description: 'Pastikan Anda memiliki akses admin lalu coba lagi.', variant: 'destructive' });
      loadData();
    } finally {
      setSavingPackageId(null);
    }
  };

  const getStatusBadge = (status: string) => {
    switch (status) {
      case 'PENDING':
        return <Badge variant="outline" className="text-warning border-warning"><Clock className="h-3 w-3 mr-1" /> Pending</Badge>;
      case 'PAID':
      case 'APPROVED':
        return <Badge className="bg-success text-success-foreground"><CheckCircle className="h-3 w-3 mr-1" /> {status === 'PAID' ? 'Dibayar' : 'Disetujui'}</Badge>;
      case 'REJECTED':
        return <Badge variant="destructive"><XCircle className="h-3 w-3 mr-1" /> Ditolak</Badge>;
      default:
        return <Badge variant="secondary">{status}</Badge>;
    }
  };

  const formatCurrency = (amount: number) => {
    return new Intl.NumberFormat('id-ID', { style: 'currency', currency: 'IDR', minimumFractionDigits: 0 }).format(amount);
  };

  return (
    <AdminLayout title="Komisi Verifikator" subtitle="Kelola komisi dan withdrawal verifikator">
      <Card className="mb-6">
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-lg">
            <Percent className="h-5 w-5 text-primary" />
            Pengaturan Penghasilan Verifikator
          </CardTitle>
          <p className="text-sm text-muted-foreground">
            Atur persentase komisi berdasarkan paket merchant. Nilai ini dipakai saat pembayaran subscription baru berhasil.
          </p>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="flex items-start gap-2 rounded-lg border border-info/30 bg-info/5 p-3 text-sm text-muted-foreground">
            <Info className="mt-0.5 h-4 w-4 shrink-0 text-info" />
            <p>Perubahan tidak mengubah komisi yang sudah tercatat. Earning lama tetap mengikuti persentase pada saat pembayaran dibuat.</p>
          </div>
          {commissionPackages.length === 0 ? (
            <p className="py-4 text-center text-sm text-muted-foreground">Belum ada paket transaksi.</p>
          ) : (
            <div className="space-y-2">
              {commissionPackages.map((pkg) => (
                <div key={pkg.id} className="flex flex-col gap-3 rounded-lg border p-3 sm:flex-row sm:items-center sm:justify-between">
                  <div>
                    <p className="font-medium">{pkg.name}</p>
                    <p className="text-xs text-muted-foreground">
                      {pkg.is_active ? 'Aktif' : 'Nonaktif'} · Harga transaksi {formatCurrency(pkg.price_per_transaction)}
                    </p>
                  </div>
                  <div className="flex items-center gap-2">
                    <div className="relative w-28">
                      <input
                        aria-label={`Komisi ${pkg.name}`}
                        className="h-9 w-full rounded-md border bg-background px-3 pr-8 text-right text-sm"
                        type="number"
                        min="0"
                        max="100"
                        step="0.01"
                        value={pkg.group_commission_percent}
                        onChange={(event) => handleCommissionChange(pkg.id, event.target.value)}
                      />
                      <span className="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 text-sm text-muted-foreground">%</span>
                    </div>
                    <Button size="sm" onClick={() => void saveCommission(pkg)} disabled={savingPackageId === pkg.id}>
                      <Save className="mr-1.5 h-4 w-4" />
                      {savingPackageId === pkg.id ? 'Menyimpan...' : 'Simpan'}
                    </Button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>
      {/* Stats Cards */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        <Card>
          <CardContent className="p-4">
            <div className="flex items-center gap-3">
              <div className="p-2 rounded-lg bg-warning/10">
                <Clock className="h-5 w-5 text-warning" />
              </div>
              <div>
                <p className="text-xs text-muted-foreground">Total Pending</p>
                <p className="font-semibold">{formatCurrency(stats.totalPending)}</p>
              </div>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <div className="flex items-center gap-3">
              <div className="p-2 rounded-lg bg-success/10">
                <CheckCircle className="h-5 w-5 text-success" />
              </div>
              <div>
                <p className="text-xs text-muted-foreground">Total Dibayar</p>
                <p className="font-semibold">{formatCurrency(stats.totalPaid)}</p>
              </div>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <div className="flex items-center gap-3">
              <div className="p-2 rounded-lg bg-primary/10">
                <Wallet className="h-5 w-5 text-primary" />
              </div>
              <div>
                <p className="text-xs text-muted-foreground">Pending Withdrawal</p>
                <p className="font-semibold">{stats.pendingWithdrawals}</p>
              </div>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <div className="flex items-center gap-3">
              <div className="p-2 rounded-lg bg-secondary">
                <Users className="h-5 w-5 text-secondary-foreground" />
              </div>
              <div>
                <p className="text-xs text-muted-foreground">Verifikator Aktif</p>
                <p className="font-semibold">{stats.activeVerifikators}</p>
              </div>
            </div>
          </CardContent>
        </Card>
      </div>

      <Tabs defaultValue="withdrawals" className="space-y-4">
        <TabsList>
          <TabsTrigger value="withdrawals" className="gap-2">
            <Wallet className="h-4 w-4" />
            Withdrawal
            {stats.pendingWithdrawals > 0 && (
              <Badge variant="destructive" className="ml-1 h-5 w-5 p-0 flex items-center justify-center text-xs">
                {stats.pendingWithdrawals}
              </Badge>
            )}
          </TabsTrigger>
          <TabsTrigger value="earnings" className="gap-2">
            <TrendingUp className="h-4 w-4" />
            Riwayat Komisi
          </TabsTrigger>
        </TabsList>

        <TabsContent value="withdrawals">
          <Card>
            <CardHeader>
              <CardTitle className="text-lg">Permintaan Withdrawal</CardTitle>
            </CardHeader>
            <CardContent>
              {loading ? (
                <div className="text-center py-8 text-muted-foreground">Memuat...</div>
              ) : withdrawals.length === 0 ? (
                <div className="text-center py-8 text-muted-foreground">Belum ada permintaan withdrawal</div>
              ) : (
                <div className="space-y-3">
                  {withdrawals.map((withdrawal) => (
                    <div key={withdrawal.id} className="p-4 border rounded-lg">
                      <div className="flex items-start justify-between">
                        <div className="space-y-1">
                          <div className="flex items-center gap-2">
                            <p className="font-medium">{withdrawal.profile?.full_name || 'Verifikator'}</p>
                            {getStatusBadge(withdrawal.status)}
                          </div>
                          <p className="text-lg font-bold text-primary">{formatCurrency(withdrawal.amount)}</p>
                          <div className="text-sm text-muted-foreground">
                            <p>{withdrawal.bank_name} - {withdrawal.account_number}</p>
                            <p>a.n. {withdrawal.account_holder}</p>
                          </div>
                          <p className="text-xs text-muted-foreground">
                            {format(new Date(withdrawal.created_at), 'dd MMM yyyy HH:mm', { locale: id })}
                          </p>
                          {withdrawal.admin_notes && (
                            <p className="text-sm text-muted-foreground mt-2 p-2 bg-muted rounded">
                              Catatan: {withdrawal.admin_notes}
                            </p>
                          )}
                        </div>
                        {withdrawal.status === 'PENDING' && (
                          <Button size="sm" onClick={() => setSelectedWithdrawal(withdrawal)}>
                            Proses
                          </Button>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="earnings">
          <Card>
            <CardHeader>
              <CardTitle className="text-lg">Riwayat Komisi</CardTitle>
            </CardHeader>
            <CardContent>
              {loading ? (
                <div className="text-center py-8 text-muted-foreground">Memuat...</div>
              ) : earnings.length === 0 ? (
                <div className="text-center py-8 text-muted-foreground">Belum ada riwayat komisi</div>
              ) : (
                <div className="space-y-3">
                  {earnings.map((earning) => (
                    <div key={earning.id} className="p-4 border rounded-lg">
                      <div className="flex items-start justify-between">
                        <div className="space-y-1">
                          <div className="flex items-center gap-2">
                            <p className="font-medium">{earning.merchant?.name || 'Merchant'}</p>
                            {getStatusBadge(earning.status)}
                          </div>
                          <p className="text-sm text-muted-foreground">
                            Paket: {earning.package?.name} ({formatCurrency(earning.package_amount)})
                          </p>
                          <p className="text-lg font-bold text-success">
                            +{formatCurrency(earning.commission_amount)} ({earning.commission_percent}%)
                          </p>
                          <p className="text-xs text-muted-foreground">
                            {format(new Date(earning.created_at), 'dd MMM yyyy HH:mm', { locale: id })}
                          </p>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>

      {/* Process Withdrawal Dialog */}
      <Dialog open={!!selectedWithdrawal} onOpenChange={() => setSelectedWithdrawal(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Proses Withdrawal</DialogTitle>
          </DialogHeader>
          {selectedWithdrawal && (
            <div className="space-y-4">
              <div className="p-4 bg-muted rounded-lg space-y-2">
                <p className="font-medium">{selectedWithdrawal.profile?.full_name}</p>
                <p className="text-2xl font-bold text-primary">{formatCurrency(selectedWithdrawal.amount)}</p>
                <div className="text-sm">
                  <p>{selectedWithdrawal.bank_name}</p>
                  <p>{selectedWithdrawal.account_number}</p>
                  <p>a.n. {selectedWithdrawal.account_holder}</p>
                </div>
              </div>
              <div className="space-y-2">
                <Label>Catatan Admin (opsional)</Label>
                <Textarea
                  value={adminNotes}
                  onChange={(e) => setAdminNotes(e.target.value)}
                  placeholder="Tambahkan catatan..."
                />
              </div>
            </div>
          )}
          <DialogFooter className="gap-2">
            <Button variant="outline" onClick={() => setSelectedWithdrawal(null)} disabled={processing}>
              Batal
            </Button>
            <Button variant="destructive" onClick={() => handleProcessWithdrawal('REJECTED')} disabled={processing}>
              Tolak
            </Button>
            <Button onClick={() => handleProcessWithdrawal('APPROVED')} disabled={processing}>
              {processing ? 'Memproses...' : 'Setujui'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </AdminLayout>
  );
}

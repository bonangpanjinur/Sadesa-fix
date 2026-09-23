import { useEffect, useMemo, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { ArrowLeft, Loader2, Send, Star, Store } from 'lucide-react';
import { Header } from '@/components/layout/Header';
import { BottomNav } from '@/components/layout/BottomNav';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

interface OrderItemOption {
  id: string;
  product_id: string | null;
  product_name: string;
}

interface EligibleOrder {
  id: string;
  created_at: string;
  items: OrderItemOption[];
}

export default function MerchantReviewPage() {
  const { merchantId } = useParams<{ merchantId: string }>();
  const navigate = useNavigate();
  const { user } = useAuth();
  const [merchantName, setMerchantName] = useState('Toko');
  const [orders, setOrders] = useState<EligibleOrder[]>([]);
  const [orderId, setOrderId] = useState('');
  const [productId, setProductId] = useState('');
  const [rating, setRating] = useState(5);
  const [comment, setComment] = useState('');
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    const loadReviewOptions = async () => {
      if (!user || !merchantId) return;
      setLoading(true);
      const [merchantResult, ordersResult, reviewsResult] = await Promise.all([
        supabase.from('merchants').select('name').eq('id', merchantId).maybeSingle(),
        supabase
          .from('orders')
          .select('id, created_at, order_items(id, product_id, product_name)')
          .eq('buyer_id', user.id)
          .eq('merchant_id', merchantId)
          .in('status', ['DONE', 'DELIVERED'])
          .order('created_at', { ascending: false }),
        supabase.from('reviews').select('order_id').eq('buyer_id', user.id).eq('merchant_id', merchantId),
      ]);

      if (merchantResult.data?.name) setMerchantName(merchantResult.data.name);
      if (ordersResult.error) {
        toast.error('Pesanan toko tidak dapat dimuat');
        setLoading(false);
        return;
      }

      const reviewedOrderIds = new Set((reviewsResult.data || []).map((review) => review.order_id));
      const eligibleOrders = ((ordersResult.data || []) as Array<{ id: string; created_at: string; order_items: OrderItemOption[] | null }>)
        .filter((order) => !reviewedOrderIds.has(order.id))
        .map((order) => ({ id: order.id, created_at: order.created_at, items: order.order_items || [] }))
        .filter((order) => order.items.some((item) => item.product_id));
      setOrders(eligibleOrders);
      if (eligibleOrders[0]) {
        setOrderId(eligibleOrders[0].id);
        const firstItem = eligibleOrders[0].items.find((item) => item.product_id);
        setProductId(firstItem?.product_id || '');
      }
      setLoading(false);
    };

    void loadReviewOptions();
  }, [merchantId, user]);

  const selectedOrder = useMemo(() => orders.find((order) => order.id === orderId) || null, [orders, orderId]);
  const reviewableItems = selectedOrder?.items.filter((item) => item.product_id) || [];

  const handleOrderChange = (value: string) => {
    setOrderId(value);
    const order = orders.find((item) => item.id === value);
    setProductId(order?.items.find((item) => item.product_id)?.product_id || '');
  };

  const handleSubmit = async () => {
    if (!user || !merchantId || !orderId || !productId) {
      toast.error('Pilih pesanan dan produk yang ingin diulas');
      return;
    }

    setSubmitting(true);
    const { error } = await supabase.rpc('submit_order_reviews' as never, {
      p_order_id: orderId,
      p_reviews: [{ product_id: productId, rating, comment: comment.trim() || null, image_urls: [] }],
    } as never);
    setSubmitting(false);

    if (error) {
      console.error('Error submitting merchant review:', error);
      toast.error('Ulasan gagal dikirim. Pastikan pesanan sudah selesai dan belum pernah diulas.');
      return;
    }

    toast.success('Rating dan ulasan berhasil dikirim');
    navigate(`/merchant/${merchantId}`);
  };

  return (
    <div className="mobile-shell flex min-h-screen flex-col bg-background">
      <Header />
      <main className="flex-1 overflow-y-auto px-5 py-5 pb-24">
        <Button variant="ghost" size="sm" className="mb-4 -ml-2" onClick={() => navigate(-1)}>
          <ArrowLeft className="mr-2 h-4 w-4" /> Kembali
        </Button>
        <div className="mb-5 flex items-center gap-3">
          <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-primary/10 text-primary"><Store className="h-6 w-6" /></div>
          <div>
            <h1 className="text-xl font-bold">Ulas toko</h1>
            <p className="text-sm text-muted-foreground">Bagikan pengalamanmu di {merchantName}</p>
          </div>
        </div>

        {loading ? (
          <div className="flex justify-center py-16"><Loader2 className="h-7 w-7 animate-spin text-primary" /></div>
        ) : orders.length === 0 ? (
          <div className="rounded-2xl border border-dashed border-border bg-card px-5 py-10 text-center">
            <Star className="mx-auto h-10 w-10 text-muted-foreground" />
            <h2 className="mt-3 font-semibold">Belum ada pesanan yang bisa diulas</h2>
            <p className="mt-1 text-sm text-muted-foreground">Ulasan dapat diberikan setelah pesanan dari toko ini selesai. Satu pesanan hanya dapat diulas satu kali.</p>
            <Button variant="outline" className="mt-5 rounded-xl" onClick={() => navigate(`/merchant/${merchantId}`)}>Kembali ke toko</Button>
          </div>
        ) : (
          <div className="space-y-4">
            <div className="rounded-2xl border border-border bg-card p-4">
              <label className="mb-2 block text-sm font-medium">Pesanan yang diulas</label>
              <Select value={orderId} onValueChange={handleOrderChange}>
                <SelectTrigger><SelectValue placeholder="Pilih pesanan" /></SelectTrigger>
                <SelectContent>
                  {orders.map((order) => <SelectItem key={order.id} value={order.id}>Pesanan {new Date(order.created_at).toLocaleDateString('id-ID')}</SelectItem>)}
                </SelectContent>
              </Select>
              {reviewableItems.length > 1 && (
                <>
                  <label className="mb-2 mt-4 block text-sm font-medium">Produk yang diulas</label>
                  <Select value={productId} onValueChange={setProductId}>
                    <SelectTrigger><SelectValue placeholder="Pilih produk" /></SelectTrigger>
                    <SelectContent>{reviewableItems.map((item) => <SelectItem key={item.product_id} value={item.product_id || ''}>{item.product_name}</SelectItem>)}</SelectContent>
                  </Select>
                </>
              )}
            </div>

            <div className="rounded-2xl border border-border bg-card p-4">
              <label className="block text-sm font-medium">Rating toko</label>
              <div className="mt-3 flex items-center gap-1">
                {[1, 2, 3, 4, 5].map((value) => (
                  <button key={value} type="button" aria-label={`Beri rating ${value} dari 5`} onClick={() => setRating(value)} className="rounded-lg p-1 transition hover:bg-primary/10">
                    <Star className={`h-8 w-8 ${value <= rating ? 'fill-amber-400 text-amber-400' : 'text-muted-foreground'}`} />
                  </button>
                ))}
                <span className="ml-2 text-sm font-semibold text-foreground">{rating}/5</span>
              </div>
              <label className="mb-2 mt-5 block text-sm font-medium">Ulasan <span className="font-normal text-muted-foreground">(opsional)</span></label>
              <Textarea value={comment} onChange={(event) => setComment(event.target.value)} placeholder="Ceritakan pengalamanmu dengan toko ini..." rows={5} maxLength={1000} />
              <p className="mt-1 text-right text-xs text-muted-foreground">{comment.length}/1000</p>
            </div>

            <Button className="w-full rounded-xl" onClick={handleSubmit} disabled={submitting || !productId}>
              {submitting ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <Send className="mr-2 h-4 w-4" />}
              {submitting ? 'Mengirim...' : 'Kirim rating dan ulasan'}
            </Button>
          </div>
        )}
      </main>
      <BottomNav />
    </div>
  );
}

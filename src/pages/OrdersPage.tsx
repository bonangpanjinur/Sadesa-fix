import { useState, useEffect, useCallback } from "react";
import { useInfiniteQuery, useQuery, useQueryClient } from "@tanstack/react-query";
import { useNavigate, useSearchParams, useParams } from "react-router-dom";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Progress } from "@/components/ui/progress";
import { formatPrice } from "@/lib/utils";
import { BottomNav } from "@/components/layout/BottomNav";
import {
  Package, Clock, Truck, CheckCircle, XCircle, ShoppingBag,
  Store, LogIn, MapPin, Star, RefreshCw, ChevronRight, CalendarDays,
  MessageCircle, X, RotateCcw, AlertCircle, FileText, Bike,
} from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import { Header } from "@/components/layout/Header";

import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";
import { useReorder } from "@/hooks/useReorder";
import type { Product } from "@/types";
import { formatDistanceToNow } from "date-fns";
import { id as idLocale } from "date-fns/locale";
import { OrderChat } from "@/components/chat/OrderChat";
import { toast } from "@/hooks/use-toast";
import { OrderCancelDialog } from "@/components/order/OrderCancelDialog";
import { OrderDetailSheet } from "@/components/order/OrderDetailSheet";
import { CourierRatingDialog } from "@/components/buyer/CourierRatingDialog";
import { getBuyerTransactionKind } from "@/lib/buyerTransaction";

interface BuyerOrderItem {
  id: string;
  quantity: number;
  product_name: string;
  product_price: number;
  product_id?: string | null;
  products: { name: string; image_url: string | null } | null;
}

interface BuyerOrder {
  id: string;
  status: string;
  total: number;
  created_at: string;
  merchant_id: string | null;
  service_type?: string | null;
  pickup_address?: string | null;
  pickup_lat?: number | null;
  pickup_lng?: number | null;
  package_type?: string | null;
  package_weight_kg?: number | null;
  courier_notes?: string | null;
  delivery_type?: string | null;
  delivery_address?: string | null;
  delivery_name?: string | null;
  delivery_phone?: string | null;
  delivery_lat?: number | null;
  delivery_lng?: number | null;
  merchants: { name: string; phone: string | null; user_id?: string | null } | null;
  order_items?: BuyerOrderItem[];
  is_self_delivery?: boolean;
  has_review?: boolean;
  payment_method?: string | null;
  payment_status?: string | null;
  courier_id?: string | null;
  courier_name?: string | null;
  courier_rated?: boolean;
}

interface RideOrder {
  id: string;
  status: string;
  pickup_address: string;
  destination_address: string;
  distance_km: number;
  estimated_fare: number;
  final_fare: number | null;
  rating: number | null;
  created_at: string;
  completed_at: string | null;
}

type HistoryItem =
  | { kind: "marketplace"; item: BuyerOrder }
  | { kind: "ride"; item: RideOrder };

// Database-aligned status config
const STATUS_CONFIG: Record<string, { label: string; icon: React.ElementType; color: string }> = {
  NEW: { label: "Pesanan Baru", icon: Clock, color: "bg-amber-50 text-amber-700 border-amber-200" },
  PENDING_PAYMENT: { label: "Menunggu Pembayaran", icon: Clock, color: "bg-amber-50 text-amber-700 border-amber-200" },
  PENDING_CONFIRMATION: { label: "Menunggu Konfirmasi", icon: Clock, color: "bg-orange-50 text-orange-700 border-orange-200" },
  CONFIRMED: { label: "Dikonfirmasi", icon: CheckCircle, color: "bg-sky-50 text-sky-700 border-sky-200" },
  PROCESSED: { label: "Sedang Diproses", icon: Package, color: "bg-blue-50 text-blue-700 border-blue-200" },
  READY: { label: "Siap Dikirim/Diambil", icon: Package, color: "bg-sky-50 text-sky-700 border-sky-200" },
  ASSIGNED: { label: "Kurir Ditugaskan", icon: Truck, color: "bg-teal-50 text-teal-700 border-teal-200" },
  COURIER_ASSIGNED: { label: "Menunggu Kurir", icon: Truck, color: "bg-teal-50 text-teal-700 border-teal-200" },
  COURIER_ACCEPTED: { label: "Kurir Menuju Toko", icon: Truck, color: "bg-cyan-50 text-cyan-700 border-cyan-200" },
  PICKED_UP: { label: "Pesanan Diambil Kurir", icon: Truck, color: "bg-cyan-50 text-cyan-700 border-cyan-200" },
  DELIVERING: { label: "Kurir Mengantar", icon: Truck, color: "bg-cyan-50 text-cyan-700 border-cyan-200" },
  SENT: { label: "Dalam Perjalanan", icon: Truck, color: "bg-indigo-50 text-indigo-700 border-indigo-200" },
  DELIVERED: { label: "Sudah Diantar", icon: MapPin, color: "bg-violet-50 text-violet-700 border-violet-200" },
  DONE: { label: "Selesai", icon: CheckCircle, color: "bg-emerald-50 text-emerald-700 border-emerald-200" },
  CANCELLED: { label: "Dibatalkan", icon: XCircle, color: "bg-red-50 text-red-700 border-red-200" },
  CANCELED: { label: "Dibatalkan", icon: XCircle, color: "bg-red-50 text-red-700 border-red-200" },
};

const ORDER_STEPS = ["NEW", "PENDING_CONFIRMATION", "PROCESSED", "READY", "ASSIGNED", "COURIER_ACCEPTED", "PICKED_UP", "DELIVERING", "DELIVERED", "DONE"];

const PENDING_STATUSES = ["NEW", "PENDING_PAYMENT", "PENDING_CONFIRMATION"];
const PROCESSING_STATUSES = ["CONFIRMED", "PROCESSED", "READY", "ASSIGNED", "COURIER_ASSIGNED", "COURIER_ACCEPTED"];
const SHIPPING_STATUSES = ["PICKED_UP", "SENT", "DELIVERING", "DELIVERED"];
const DONE_STATUSES = ["DONE"];
const CANCELLED_STATUSES = ["CANCELLED", "CANCELED"];
const RIDE_ACTIVE_STATUSES = ["SEARCHING", "ACCEPTED", "PICKED_UP", "IN_TRANSIT"];
const RIDE_CANCELLED_STATUSES = ["CANCELLED", "CANCELED"];
const RIDE_STATUS_CONFIG: Record<string, { label: string; color: string }> = {
  SEARCHING: { label: "Mencari Driver", color: "bg-amber-50 text-amber-700 border-amber-200" },
  ACCEPTED: { label: "Driver Ditemukan", color: "bg-blue-50 text-blue-700 border-blue-200" },
  PICKED_UP: { label: "Dalam Perjalanan", color: "bg-cyan-50 text-cyan-700 border-cyan-200" },
  IN_TRANSIT: { label: "Menuju Tujuan", color: "bg-indigo-50 text-indigo-700 border-indigo-200" },
  COMPLETED: { label: "Selesai", color: "bg-emerald-50 text-emerald-700 border-emerald-200" },
  CANCELLED: { label: "Dibatalkan", color: "bg-red-50 text-red-700 border-red-200" },
  CANCELED: { label: "Dibatalkan", color: "bg-red-50 text-red-700 border-red-200" },
};

const TAB_FILTERS = [
  { value: "all", label: "Semua", icon: ShoppingBag },
  { value: "pending", label: "Belum Bayar", icon: Clock },
  { value: "processing", label: "Diproses", icon: Package },
  { value: "shipped", label: "Dikirim", icon: Truck },
  { value: "completed", label: "Selesai", icon: CheckCircle },
  { value: "cancelled", label: "Dibatalkan", icon: XCircle },
];

const getStatusGroup = (status: string): string => {
  if (PENDING_STATUSES.includes(status)) return "pending";
  if (PROCESSING_STATUSES.includes(status)) return "processing";
  if (SHIPPING_STATUSES.includes(status)) return "shipped";
  if (DONE_STATUSES.includes(status)) return "completed";
  if (CANCELLED_STATUSES.includes(status)) return "cancelled";
  return "all";
};

const getRideStatusGroup = (status: string): string => {
  if (status === "SEARCHING") return "pending";
  if (status === "ACCEPTED") return "processing";
  if (["PICKED_UP", "IN_TRANSIT"].includes(status)) return "shipped";
  if (status === "COMPLETED") return "completed";
  if (RIDE_CANCELLED_STATUSES.includes(status)) return "cancelled";
  return "all";
};

const getHistoryStatusGroup = (item: HistoryItem): string =>
  item.kind === "ride" ? getRideStatusGroup(item.item.status) : getStatusGroup(item.item.status);

function getOrderProgress(status: string): number {
  if (CANCELLED_STATUSES.includes(status)) return 0;
  const idx = ORDER_STEPS.indexOf(status);
  if (idx === -1) {
    // Map pending statuses to step 0
    if (PENDING_STATUSES.includes(status)) return (1 / ORDER_STEPS.length) * 100;
    return 0;
  }
  return ((idx + 1) / ORDER_STEPS.length) * 100;
}

function getRideProgress(status: string): number {
  if (RIDE_CANCELLED_STATUSES.includes(status)) return 0;
  const steps = ["SEARCHING", "ACCEPTED", "PICKED_UP", "IN_TRANSIT", "COMPLETED"];
  const idx = steps.indexOf(status);
  return idx === -1 ? 0 : ((idx + 1) / steps.length) * 100;
}

const BUYER_ORDER_PAGE_SIZE = 50;

async function loadBuyerOrders(userId: string, offset = 0): Promise<BuyerOrder[]> {
  type OrderRow = Omit<BuyerOrder, 'order_items'> & {
    order_items?: BuyerOrderItem[];
  };
  let data: OrderRow[] | null = null;

  // Level 1: Full query with all relations including nested products
  const r1 = await supabase
    .from("orders")
    .select("id, status, total, created_at, merchant_id, service_type, pickup_address, pickup_lat, pickup_lng, package_type, package_weight_kg, courier_notes, delivery_type, delivery_address, delivery_name, delivery_phone, delivery_lat, delivery_lng, courier_id, is_self_delivery, has_review, payment_method, payment_status, merchants(name, phone, user_id), order_items(id, quantity, product_name, product_price, product_id, products(name, image_url))")
    .eq("buyer_id", userId)
    .order("created_at", { ascending: false })
    .range(offset, offset + BUYER_ORDER_PAGE_SIZE - 1);

  if (!r1.error) {
    data = r1.data as unknown as OrderRow[];
  } else {
    console.warn("L1 failed:", r1.error.message);
      const r2 = await supabase
        .from("orders")
        .select("id, status, total, created_at, merchant_id, pickup_address, pickup_lat, pickup_lng, package_type, package_weight_kg, courier_notes, delivery_type, delivery_address, delivery_name, delivery_phone, delivery_lat, delivery_lng, courier_id, is_self_delivery, has_review, payment_method, payment_status, merchants(name, phone), order_items(id, quantity, product_name, product_price, product_id)")
      .eq("buyer_id", userId)
      .order("created_at", { ascending: false })
      .range(offset, offset + BUYER_ORDER_PAGE_SIZE - 1);
    if (!r2.error) {
      data = r2.data as unknown as OrderRow[];
    } else {
      console.warn("L2 failed:", r2.error.message);
      const r3 = await supabase
        .from("orders")
        .select("id, status, total, created_at, merchant_id, pickup_address, pickup_lat, pickup_lng, package_type, package_weight_kg, courier_notes, delivery_type, delivery_address, delivery_name, delivery_phone, delivery_lat, delivery_lng, courier_id, payment_method, payment_status, merchants(name, phone), order_items(id, quantity, product_name, product_price, product_id)")
        .eq("buyer_id", userId)
        .order("created_at", { ascending: false })
        .range(offset, offset + BUYER_ORDER_PAGE_SIZE - 1);
      if (!r3.error) {
        data = r3.data as unknown as OrderRow[];
      } else {
        console.warn("L3 failed:", r3.error.message);
      const r4 = await supabase
        .from("orders")
        .select("id, status, total, created_at, merchant_id, pickup_address, pickup_lat, pickup_lng, package_type, package_weight_kg, courier_notes, delivery_type, delivery_address, delivery_name, delivery_phone, delivery_lat, delivery_lng, courier_id, payment_method, payment_status, order_items(id, quantity, product_name, product_price, product_id)")
          .eq("buyer_id", userId)
          .order("created_at", { ascending: false })
          .range(offset, offset + BUYER_ORDER_PAGE_SIZE - 1);
        if (!r4.error) {
          data = r4.data as unknown as OrderRow[];
        } else {
          throw new Error("All query levels failed: " + r4.error.message);
        }
      }
    }
  }

  // Fill missing product images
  if (data && data.length > 0) {
    const needsImages = data.some((o) => o.order_items?.some((i) => i.product_id && !i.products));
    if (needsImages) {
      const productIds = [...new Set(data.flatMap((o) => (o.order_items || []).filter((i) => i.product_id && !i.products).map((i) => i.product_id)))] as string[];
      if (productIds.length > 0) {
        const { data: productsData } = await supabase.from('products').select('id, name, image_url').in('id', productIds);
        if (productsData) {
          const productMap = Object.fromEntries(productsData.map(p => [p.id, p]));
          data = data.map((o) => ({
            ...o,
            order_items: (o.order_items || []).map((i) => ({
              ...i,
              products: i.products || (i.product_id && productMap[i.product_id] ? { name: productMap[i.product_id].name, image_url: productMap[i.product_id].image_url } : null),
            })),
          }));
        }
      }
    }
  }

  // Fill missing merchant user_id
  if (data && data.length > 0) {
    const merchantIdsNeedingUserId = [...new Set(data.filter((o) => o.merchant_id && (!o.merchants || !o.merchants.user_id)).map((o) => o.merchant_id))] as string[];
    if (merchantIdsNeedingUserId.length > 0) {
      const { data: merchantsData } = await supabase.from('merchants').select('id, user_id, name, phone').in('id', merchantIdsNeedingUserId);
      if (merchantsData) {
        const merchantMap = Object.fromEntries(merchantsData.map(m => [m.id, m]));
        data = data.map((o) => {
          if (o.merchant_id && merchantMap[o.merchant_id]) {
            const m = merchantMap[o.merchant_id];
            return { ...o, merchants: { name: o.merchants?.name || m.name, phone: o.merchants?.phone || m.phone, user_id: o.merchants?.user_id || m.user_id } };
          }
          return o;
        });
      }
    }
  }

  return (data as unknown as BuyerOrder[]) || [];
}

const OrdersPage = () => {
  const { user } = useAuth();
  const queryClient = useQueryClient();
  const [activeTab, setActiveTab] = useState("all");
  const [activeCategory, setActiveCategory] = useState<"all" | "product" | "transport">("all");
  const [chatOrder, setChatOrder] = useState<{ orderId: string; merchantUserId: string; merchantName: string } | null>(null);
  const [cancelOrderId, setCancelOrderId] = useState<string | null>(null);
  const [selectedOrderId, setSelectedOrderId] = useState<string | null>(null);
  const [isDetailSheetOpen, setIsDetailSheetOpen] = useState(false);
  const [ratingOrder, setRatingOrder] = useState<{ id: string; orderNumber: string; courierId: string; courierName: string } | null>(null);
  const navigate = useNavigate();
  const { orderId: orderIdFromPath } = useParams<{ orderId: string }>();
  const reorder = useReorder();
  const [searchParams, setSearchParams] = useSearchParams();

  useEffect(() => { window.scrollTo(0, 0); }, []);

  // Handle orderId query parameter from notification click
  useEffect(() => {
    const orderIdFromUrl = orderIdFromPath || searchParams.get('orderId');
    if (orderIdFromUrl) {
      setSelectedOrderId(orderIdFromUrl);
      setIsDetailSheetOpen(true);
      if (!orderIdFromPath && searchParams.has('orderId')) {
        searchParams.delete('orderId');
        setSearchParams(searchParams, { replace: true });
      }
    }
  }, [orderIdFromPath, searchParams, setSearchParams]);

  // React Query: orders data with caching (P3-01)
  const {
    data: orderPages,
    isLoading: loading,
    isFetching: refreshing,
    isError: fetchError,
    refetch,
    fetchNextPage: fetchNextOrderPage,
    hasNextPage: hasMoreOrders,
    isFetchingNextPage: loadingMoreOrders,
  } = useInfiniteQuery<BuyerOrder[]>({
    queryKey: ['buyer-orders', user?.id],
    queryFn: ({ pageParam }) => loadBuyerOrders(user!.id, pageParam as number),
    initialPageParam: 0,
    getNextPageParam: (lastPage, allPages) =>
      lastPage.length === BUYER_ORDER_PAGE_SIZE ? allPages.length * BUYER_ORDER_PAGE_SIZE : undefined,
    enabled: !!user,
    staleTime: 30_000,
  });
  const orders = orderPages?.pages.flat() ?? [];

  const {
    data: rides = [],
    isLoading: ridesLoading,
    isFetching: ridesRefreshing,
    refetch: refetchRides,
  } = useQuery<RideOrder[]>({
    queryKey: ['passenger-rides', user?.id],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('ride_requests')
        .select('id, status, pickup_address, destination_address, distance_km, estimated_fare, final_fare, rating, created_at, completed_at')
        .eq('passenger_id', user!.id)
        .order('created_at', { ascending: false })
        .limit(50);
      if (error) throw error;
      return (data || []) as unknown as RideOrder[];
    },
    enabled: !!user,
    staleTime: 30_000,
  });

  const fetchOrders = useCallback(async (isRefresh = false) => {
    if (isRefresh) await Promise.all([refetch(), refetchRides()]);
  }, [refetch, refetchRides]);

  // Realtime subscription for order status updates — updates React Query cache directly
  useEffect(() => {
    if (!user) return;
    const channel = supabase
      .channel('buyer-orders-realtime')
      .on(
        'postgres_changes',
        { event: 'UPDATE', schema: 'public', table: 'orders', filter: `buyer_id=eq.${user.id}` },
        (payload) => {
          const newOrder = payload.new as { id: string; status: string; payment_status?: string | null };
          const newStatus = newOrder.status;
          queryClient.setQueryData<BuyerOrder[]>(['buyer-orders', user.id], (prev = []) => {
            const oldOrder = prev.find(o => o.id === newOrder.id);
            if (oldOrder && oldOrder.status !== newStatus) {
              const statusLabel = STATUS_CONFIG[newStatus]?.label || newStatus;
              toast({ title: `Pesanan #${newOrder.id.substring(0, 8).toUpperCase()}`, description: `Status berubah: ${statusLabel}` });
            }
            return prev.map(order =>
              order.id === newOrder.id ? { ...order, status: newStatus, payment_status: newOrder.payment_status ?? order.payment_status } : order
            );
          });
        }
      )
      .subscribe();
    return () => { supabase.removeChannel(channel); };
  }, [user, queryClient]);

  // Keep ride entries in the combined order history fresh while a ride is active.
  useEffect(() => {
    if (!user) return;
    const channel = supabase
      .channel('buyer-rides-in-orders')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'ride_requests', filter: `passenger_id=eq.${user.id}` },
        () => { void refetchRides(); },
      )
      .subscribe();
    return () => { supabase.removeChannel(channel); };
  }, [user, refetchRides]);

  // Reorder handler - delegated to shared hook (validates stock, merchant status, etc.)
  const handleReorder = useCallback(
    (order: BuyerOrder) => reorder(order.order_items || []),
    [reorder],
  );

  const historyItems: HistoryItem[] = [
    ...orders.map((order) => ({ kind: "marketplace" as const, item: order })),
    ...rides.map((ride) => ({ kind: "ride" as const, item: ride })),
  ].sort((a, b) => new Date(b.item.created_at).getTime() - new Date(a.item.created_at).getTime());

  const categoryMatches = (item: HistoryItem) => {
    if (activeCategory === "all") return true;
    if (item.kind === "ride") return activeCategory === "transport";
    return activeCategory === (getBuyerTransactionKind(item.item) === "courier_delivery" ? "transport" : "product");
  };

  const filteredHistory = historyItems.filter((item) => {
    if (!categoryMatches(item)) return false;
    if (activeTab === "all") return true;
    return getHistoryStatusGroup(item) === activeTab;
  });

  const getTabCount = (tabValue: string) => {
    if (tabValue === "all") return historyItems.filter(categoryMatches).length;
    return historyItems.filter((item) => categoryMatches(item) && getHistoryStatusGroup(item) === tabValue).length;
  };

  const activeOrderCount = historyItems.filter((item) =>
    item.kind === "ride"
      ? RIDE_ACTIVE_STATUSES.includes(item.item.status)
      : !["DONE", "CANCELLED", "CANCELED"].includes(item.item.status),
  ).length;

  const handleContactSeller = async (e: React.MouseEvent, order: BuyerOrder) => {
    e.stopPropagation();
    let merchantUserId = order.merchants?.user_id;

    // If user_id not available, fetch it on-demand
    if (!merchantUserId && order.merchant_id) {
      const { data: merchant } = await supabase
        .from('merchants')
        .select('user_id')
        .eq('id', order.merchant_id)
        .maybeSingle();
      merchantUserId = merchant?.user_id ?? null;
    }

    // Prefer in-app chat
    if (merchantUserId && order.merchant_id) {
      setChatOrder({
        orderId: order.id,
        merchantUserId,
        merchantName: order.merchants?.name || 'Penjual',
      });
      return;
    }
    // Fallback to WhatsApp
    const phone = order.merchants?.phone;
    if (phone) {
      const cleaned = phone.replace(/\D/g, '');
      const formatted = cleaned.startsWith('0') ? '62' + cleaned.slice(1) : cleaned;
      window.open(`https://wa.me/${formatted}`, '_blank');
    }
  };

  // Not logged in state
  if (!user) {
    return (
      <div className="mobile-shell bg-background pb-20">
        <Header />
        <div className="p-6 flex flex-col items-center justify-center min-h-[60vh] text-center">
          <div className="w-20 h-20 rounded-full bg-primary/10 flex items-center justify-center mb-5">
            <LogIn className="w-10 h-10 text-primary" />
          </div>
          <h3 className="text-lg font-semibold text-foreground mb-2">Belum Login</h3>
          <p className="text-sm text-muted-foreground mb-6 max-w-[240px]">
            Silakan login untuk melihat dan melacak pesanan Anda
          </p>
          <Button onClick={() => navigate("/auth")} className="rounded-full px-8">
            <LogIn className="w-4 h-4 mr-2" /> Login Sekarang
          </Button>
        </div>
        <BottomNav />
      </div>
    );
  }

  return (
    <div className="mobile-shell bg-muted/30 pb-20">
      <Header />
      {/* Page Title */}
      <div className="px-5 py-4 bg-card border-b border-border">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-lg font-bold text-foreground">Pesanan Saya</h1>
            {activeOrderCount > 0 && (
              <p className="text-xs text-muted-foreground">
                {activeOrderCount} pesanan aktif
              </p>
            )}
          </div>
          <button
            onClick={() => fetchOrders(true)}
            disabled={refreshing || ridesRefreshing}
            className="p-2 rounded-full hover:bg-secondary transition-colors"
          >
            <RefreshCw className={`w-5 h-5 text-muted-foreground ${refreshing || ridesRefreshing ? "animate-spin" : ""}`} />
          </button>
        </div>
      </div>

      <div className="container max-w-md mx-auto px-4 -mt-3">
        <Tabs defaultValue="all" className="w-full" onValueChange={setActiveTab}>
          <div className="bg-card rounded-xl shadow-sm p-1.5 mb-4">
            <div className="grid grid-cols-3 gap-1 mb-2">
              {([['all', 'Semua'], ['product', 'Produk'], ['transport', 'Ojek & Kurir']] as const).map(([value, label]) => (
                <button key={value} type="button" onClick={() => setActiveCategory(value)} className={`rounded-lg px-2 py-2 text-[11px] font-medium transition-colors ${activeCategory === value ? 'bg-emerald-100 text-emerald-800' : 'text-muted-foreground hover:bg-muted'}`}>
                  {label}
                </button>
              ))}
            </div>
            <TabsList className="w-full justify-start overflow-x-auto bg-transparent h-auto p-0 gap-1 no-scrollbar">
              {TAB_FILTERS.map((tab) => {
                const count = getTabCount(tab.value);
                return (
                  <TabsTrigger
                    key={tab.value}
                    value={tab.value}
                    className="rounded-lg border-0 bg-transparent data-[state=active]:bg-primary data-[state=active]:text-primary-foreground px-3 py-2 h-auto flex-shrink-0 text-xs font-medium gap-1.5 transition-all"
                  >
                    <tab.icon className="w-3.5 h-3.5" />
                    {tab.label}
                    {count > 0 && (
                      <span className="ml-0.5 min-w-[18px] h-[18px] rounded-full bg-muted-foreground/15 data-[state=active]:bg-primary-foreground/20 text-[10px] font-bold flex items-center justify-center">
                        {count}
                      </span>
                    )}
                  </TabsTrigger>
                );
              })}
            </TabsList>
          </div>

          {/* Orders list */}
          <div className="space-y-3 min-h-[50vh]">
            {loading || ridesLoading ? (
              Array.from({ length: 3 }).map((_, i) => (
                <Card key={i} className="overflow-hidden border-0 shadow-sm">
                  <CardContent className="p-0">
                    <div className="p-4 border-b flex justify-between items-center">
                      <div className="space-y-1.5">
                        <Skeleton className="h-3 w-20" />
                        <Skeleton className="h-4 w-32" />
                      </div>
                      <Skeleton className="h-6 w-24 rounded-full" />
                    </div>
                    <div className="p-4 flex gap-4">
                      <Skeleton className="w-20 h-20 rounded-lg" />
                      <div className="flex-1 space-y-2">
                        <Skeleton className="h-4 w-3/4" />
                        <Skeleton className="h-3 w-1/2" />
                        <Skeleton className="h-5 w-1/3 mt-2" />
                      </div>
                    </div>
                  </CardContent>
                </Card>
              ))
            ) : fetchError ? (
              <div className="flex flex-col items-center justify-center py-20 text-center">
                <div className="w-24 h-24 rounded-full bg-destructive/10 flex items-center justify-center mb-5">
                  <XCircle className="w-12 h-12 text-destructive/50" />
                </div>
                <h3 className="text-lg font-semibold text-foreground mb-1">Gagal memuat pesanan</h3>
                <p className="text-muted-foreground text-sm max-w-[220px] mb-6">
                  Terjadi masalah saat mengambil data pesanan. Silakan coba lagi.
                </p>
                <Button className="rounded-full px-6" onClick={() => fetchOrders(true)}>
                  <RefreshCw className="w-4 h-4 mr-2" /> Coba Lagi
                </Button>
              </div>
            ) : filteredHistory.length > 0 ? (
              filteredHistory.map((historyItem) => {
                if (historyItem.kind === "ride") {
                  const ride = historyItem.item;
                  const statusConf = RIDE_STATUS_CONFIG[ride.status] || RIDE_STATUS_CONFIG.SEARCHING;
                  const relativeTime = formatDistanceToNow(new Date(ride.created_at), { addSuffix: true, locale: idLocale });
                  const isActive = RIDE_ACTIVE_STATUSES.includes(ride.status);
                  const fare = ride.final_fare ?? ride.estimated_fare;

                  return (
                    <Card
                      key={`ride-${ride.id}`}
                      className="overflow-hidden border-0 shadow-sm hover:shadow-md transition-shadow cursor-pointer active:scale-[0.99]"
                      onClick={() => navigate(`/ride/${ride.id}`)}
                    >
                      <CardContent className="p-0">
                        <div className="px-4 py-3 border-b border-border/50 flex justify-between items-center">
                          <div className="flex-1 min-w-0">
                            <div className="flex items-center gap-1.5 text-xs text-muted-foreground mb-0.5">
                              <CalendarDays className="w-3 h-3" />
                              <span>{relativeTime}</span>
                              <span className="text-border">•</span>
                              <span className="font-mono">#{ride.id.substring(0, 8).toUpperCase()}</span>
                            </div>
                            <div className="flex items-center gap-1.5 text-sm">
                              <Bike className="w-3.5 h-3.5 text-primary" />
                              <span className="font-medium">Ojek & Kurir</span>
                            </div>
                          </div>
                          <Badge
                            variant="outline"
                            className={`${statusConf.color} border px-2.5 py-1 text-[11px] font-medium flex-shrink-0`}
                          >
                            {statusConf.label}
                          </Badge>
                        </div>

                        {isActive && (
                          <div className="px-4 pt-3">
                            <Progress value={getRideProgress(ride.status)} className="h-1.5" />
                          </div>
                        )}

                        <div className="p-4 flex gap-4">
                          <div className="w-20 h-20 bg-primary/10 rounded-lg flex-shrink-0 flex items-center justify-center">
                            <Bike className="w-10 h-10 text-primary" />
                          </div>
                          <div className="flex-1 min-w-0 flex flex-col justify-between">
                            <div className="space-y-1.5">
                              <div className="flex items-center gap-2 text-sm">
                                <span className="w-2 h-2 rounded-full bg-primary flex-shrink-0" />
                                <span className="truncate">{ride.pickup_address}</span>
                              </div>
                              <div className="flex items-center gap-2 text-sm">
                                <span className="w-2 h-2 rounded-full bg-destructive flex-shrink-0" />
                                <span className="truncate">{ride.destination_address}</span>
                              </div>
                            </div>
                            <div className="flex items-end justify-between mt-2">
                              <div>
                                <p className="text-[11px] text-muted-foreground">
                                  {Number(ride.distance_km || 0).toFixed(1)} km
                                </p>
                                <p className="text-sm font-bold text-primary">{formatPrice(fare)}</p>
                              </div>
                              <ChevronRight className="w-4 h-4 text-muted-foreground" />
                            </div>
                          </div>
                        </div>

                        <div className="px-4 py-3 border-t border-border/50 bg-muted/30 flex justify-end">
                          <Button
                            size="sm"
                            variant="outline"
                            className="text-xs h-8 rounded-full px-4"
                            onClick={(e) => { e.stopPropagation(); navigate(`/ride/${ride.id}`); }}
                          >
                            <MapPin className="w-3 h-3 mr-1" />
                            {isActive ? "Lacak Perjalanan" : "Lihat Detail"}
                          </Button>
                        </div>
                      </CardContent>
                    </Card>
                  );
                }

                const order = historyItem.item;
                const transactionKind = getBuyerTransactionKind(order);
                const isCourierDelivery = transactionKind === "courier_delivery";
                const firstItem = order.order_items?.[0];
                // Support both image_url from DB and image from mapped Product interface
                const imageUrl = firstItem?.products?.image_url;
                const productName = firstItem?.product_name || firstItem?.products?.name || "Produk";
                const itemCount = order.order_items?.length || 0;
                const statusConf = STATUS_CONFIG[order.status] || STATUS_CONFIG.NEW;
                const StatusIcon = statusConf.icon;
                const relativeTime = formatDistanceToNow(new Date(order.created_at), { addSuffix: true, locale: idLocale });
                const shortId = order.id.substring(0, 8).toUpperCase();
                const progress = getOrderProgress(order.status);
                const isActive = !DONE_STATUSES.includes(order.status) && !CANCELLED_STATUSES.includes(order.status);

                return (
                  <Card
                    key={order.id}
                    className="overflow-hidden border-0 shadow-sm hover:shadow-md transition-shadow cursor-pointer active:scale-[0.99]"
                    onClick={() => navigate(`/orders/${order.id}/tracking`)}
                  >
                    <CardContent className="p-0">
                      {/* Card header */}
                      <div className="px-4 py-3 border-b border-border/50 flex justify-between items-center">
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center gap-1.5 text-xs text-muted-foreground mb-0.5">
                            <CalendarDays className="w-3 h-3" />
                            <span>{relativeTime}</span>
                            <span className="text-border">•</span>
                            <span className="font-mono">#{shortId}</span>
                          </div>
                          <div className="flex items-center gap-1.5 text-sm">
                            {isCourierDelivery ? <Bike className="w-3.5 h-3.5 text-primary" /> : <Store className="w-3.5 h-3.5 text-muted-foreground" />}
                            <span className="font-medium truncate max-w-[160px]">{isCourierDelivery ? "Ojek & Kurir" : order.merchants?.name || "Toko"}</span>
                          </div>
                        </div>
                        <Badge
                          variant="outline"
                          className={`${statusConf.color} border px-2.5 py-1 text-[11px] font-medium gap-1 flex-shrink-0`}
                        >
                          <StatusIcon className="w-3 h-3" />
                          {statusConf.label}
                        </Badge>
                      </div>

                      {/* Progress bar for active orders */}
                      {isActive && (
                        <div className="px-4 pt-3">
                          <Progress value={progress} className="h-1.5" />
                        </div>
                      )}

                      {/* Product or courier service info */}
                      <div className="p-4 flex gap-4">
                        <div className="w-20 h-20 bg-muted rounded-lg flex-shrink-0 overflow-hidden flex items-center justify-center">
                          {isCourierDelivery ? <Bike className="w-10 h-10 text-primary" /> : imageUrl ? (
                            <img src={imageUrl} alt={productName} className="w-full h-full object-cover" />
                          ) : <ShoppingBag className="w-8 h-8 text-muted-foreground" />}
                        </div>
                        <div className="flex-1 min-w-0 flex flex-col justify-between">
                          {isCourierDelivery ? (
                            <div className="space-y-1">
                              <h4 className="font-medium text-sm text-foreground">Antar barang</h4>
                              <p className="text-xs text-muted-foreground truncate">{order.pickup_address || "Lokasi pickup"}</p>
                              <p className="text-xs text-muted-foreground truncate">→ {order.delivery_address || "Tujuan pengiriman"}</p>
                              <p className="text-xs text-muted-foreground">{order.package_type || "Paket"}{order.package_weight_kg ? ` • ${order.package_weight_kg} kg` : ""}</p>
                            </div>
                          ) : <div>
                            <h4 className="font-medium text-sm truncate text-foreground">{productName}</h4>
                            <p className="text-xs text-muted-foreground mt-0.5">
                              {itemCount > 1 ? `+${itemCount - 1} produk lainnya` : `${firstItem?.quantity || 1} barang`}
                            </p>
                          </div>}
                          <div className="flex items-end justify-between mt-2">
                            <div>
                              <p className="text-[11px] text-muted-foreground">{isCourierDelivery ? "Biaya Layanan" : "Total Belanja"}</p>
                              <p className="text-sm font-bold text-primary">{formatPrice(order.total)}</p>
                            </div>
                            <ChevronRight className="w-4 h-4 text-muted-foreground" />
                          </div>
                        </div>
                      </div>

                      {/* Contextual actions */}
                      <div className="px-4 py-3 border-t border-border/50 bg-muted/30 flex justify-between items-center gap-2">
                        {/* Contact seller (always visible for active orders) */}
                        {!isCourierDelivery && isActive && (order.merchant_id || order.merchants?.phone) && (
                          <Button
                            size="sm"
                            variant="ghost"
                            className="text-xs h-8 rounded-full px-3"
                            onClick={(e) => handleContactSeller(e, order)}
                          >
                            <MessageCircle className="w-3 h-3 mr-1" /> Hubungi Penjual
                          </Button>
                        )}
                        
                        <div className="flex gap-2 ml-auto">
                          {!isCourierDelivery && PENDING_STATUSES.includes(order.status) && (
                            <>
                              <Button
                                size="sm"
                                variant="ghost"
                                className="text-xs h-8 rounded-full px-3 text-destructive hover:text-destructive"
                                onClick={(e) => { e.stopPropagation(); setCancelOrderId(order.id); }}
                              >
                                <X className="w-3 h-3 mr-1" /> Batalkan
                              </Button>
                              {['NEW', 'PENDING_PAYMENT'].includes(order.status) && order.payment_method !== 'COD' && order.payment_status !== 'PAID' ? (
                                <Button
                                  size="sm"
                                  className="text-xs h-8 rounded-full px-4"
                                  onClick={(e) => { e.stopPropagation(); navigate(`/payment/${order.id}`); }}
                                >
                                  Bayar Sekarang
                                </Button>
                              ) : order.payment_method !== 'COD' && order.payment_status === 'PAID' ? (
                                <Button
                                  size="sm"
                                  variant="outline"
                                  className="text-xs h-8 rounded-full px-4"
                                  onClick={(e) => { e.stopPropagation(); navigate(`/orders?orderId=${order.id}`); }}
                                >
                                  <CheckCircle className="w-3 h-3 mr-1" /> Cek Status Pembayaran
                                </Button>
                              ) : (
                                <Badge variant="outline" className="text-xs h-8 rounded-full px-3 bg-orange-50 text-orange-700 border-orange-200">
                                  Menunggu Konfirmasi
                                </Badge>
                              )}
                            </>
                          )}
                          {!isCourierDelivery && order.payment_status === 'PAID' &&
                            !PENDING_STATUSES.includes(order.status) &&
                            !CANCELLED_STATUSES.includes(order.status) &&
                            order.status !== 'DONE' && (
                            <Button
                              size="sm"
                              variant="outline"
                              className="text-xs h-8 rounded-full px-4 border-emerald-300 text-emerald-700 hover:bg-emerald-50"
                              onClick={(e) => { e.stopPropagation(); navigate(`/orders?orderId=${order.id}`); }}
                            >
                              <CheckCircle className="w-3 h-3 mr-1" /> Cek Status Pesanan
                            </Button>
                          )}
                          {isCourierDelivery && isActive && (
                            <Button
                              size="sm"
                              variant="outline"
                              className="text-xs h-8 rounded-full px-4 border-primary/30 text-primary hover:bg-primary/5"
                              onClick={(e) => { e.stopPropagation(); navigate(`/orders/${order.id}/tracking`); }}
                            >
                              <MapPin className="w-3 h-3 mr-1" /> Lacak Kurir
                            </Button>
                          )}
                          {!isCourierDelivery && SHIPPING_STATUSES.includes(order.status) && (
                            <Button
                              size="sm"
                              variant="outline"
                              className="text-xs h-8 rounded-full px-4"
                              onClick={(e) => { e.stopPropagation(); navigate(`/orders/${order.id}/tracking`); }}
                            >
                              <MapPin className="w-3 h-3 mr-1" /> Lacak
                            </Button>
                          )}
                          {!isCourierDelivery && order.status === "DONE" && (
                            <>
                              {!order.has_review && (
                                <Button
                                  size="sm"
                                  variant="outline"
                                  className="text-xs h-8 rounded-full px-4 border-amber-300 text-amber-700 hover:bg-amber-50"
                                  onClick={(e) => { e.stopPropagation(); navigate(`/orders/${order.id}/review`); }}
                                >
                                  <Star className="w-3 h-3 mr-1 fill-amber-400 text-amber-400" /> Beri Rating
                                </Button>
                              )}
                              {!order.courier_rated && order.courier_id && (
                                <Button
                                  size="sm"
                                  variant="outline"
                                  className="text-xs h-8 rounded-full px-4 border-blue-300 text-blue-700 hover:bg-blue-50"
                                  onClick={(e) => {
                                    e.stopPropagation();
                                    setRatingOrder({
                                      id: order.id,
                                      orderNumber: order.id.slice(0, 8).toUpperCase(),
                                      courierId: order.courier_id!,
                                      courierName: order.courier_name || 'Kurir',
                                    });
                                  }}
                                >
                                  <Star className="w-3 h-3 mr-1" /> Nilai Kurir
                                </Button>
                              )}
                              <Button
                                size="sm"
                                variant="outline"
                                className="text-xs h-8 rounded-full px-4"
                                onClick={(e) => { e.stopPropagation(); handleReorder(order); }}
                              >
                                <RotateCcw className="w-3 h-3 mr-1" /> Pesan Lagi
                              </Button>
                              <Button
                                size="sm"
                                variant="outline"
                                className="text-xs h-8 rounded-full px-4 border-gray-200 text-gray-600 hover:bg-gray-50"
                                onClick={(e) => { e.stopPropagation(); navigate(`/orders/${order.id}/invoice`); }}
                              >
                                <FileText className="w-3 h-3 mr-1" /> Invoice
                              </Button>
                              <Button
                                size="sm"
                                variant="outline"
                                className="text-xs h-8 rounded-full px-4 border-red-200 text-red-600 hover:bg-red-50"
                                onClick={(e) => { e.stopPropagation(); navigate(`/orders/${order.id}/dispute`); }}
                              >
                                <AlertCircle className="w-3 h-3 mr-1" /> Komplain
                              </Button>
                            </>
                          )}
                          {!isCourierDelivery && CANCELLED_STATUSES.includes(order.status) && (
                            <Button
                              size="sm"
                              variant="outline"
                              className="text-xs h-8 rounded-full px-4"
                              onClick={(e) => { e.stopPropagation(); handleReorder(order); }}
                            >
                              <RotateCcw className="w-3 h-3 mr-1" /> Pesan Lagi
                            </Button>
                          )}
                        </div>
                      </div>
                    </CardContent>
                  </Card>
                );
              })
            ) : (
              <div className="flex flex-col items-center justify-center py-20 text-center">
                <div className="w-24 h-24 rounded-full bg-muted flex items-center justify-center mb-5">
                  <ShoppingBag className="w-12 h-12 text-muted-foreground/50" />
                </div>
                <h3 className="text-lg font-semibold text-foreground mb-1">Belum ada pesanan</h3>
                <p className="text-muted-foreground text-sm max-w-[220px] mb-6">
                  {activeTab === "all"
                    ? "Yuk mulai belanja dan temukan produk terbaik!"
                    : `Tidak ada pesanan dengan status "${TAB_FILTERS.find(t => t.value === activeTab)?.label || activeTab}"`}
                </p>
                <Button className="rounded-full px-6" onClick={() => navigate("/explore")}>
                  <ShoppingBag className="w-4 h-4 mr-2" /> Mulai Belanja
                </Button>
              </div>
            )}
          </div>
          {hasMoreOrders && activeTab === 'all' && (
            <div className="flex justify-center py-4">
              <Button variant="outline" className="rounded-full" onClick={() => void fetchNextOrderPage()} disabled={loadingMoreOrders}>
                {loadingMoreOrders ? 'Memuat pesanan lama...' : 'Muat pesanan lama'}
              </Button>
            </div>
          )}
        </Tabs>
      </div>
      {/* Order Detail Sheet - opened from notification */}
      <OrderDetailSheet
        orderId={selectedOrderId}
        open={isDetailSheetOpen}
        onOpenChange={(open) => {
          setIsDetailSheetOpen(open);
          if (!open) {
            setSelectedOrderId(null);
          }
        }}
      />
      {/* Chat - rendered directly without Dialog wrapper */}
      {chatOrder && (
        <OrderChat
          orderId={chatOrder.orderId}
          otherUserId={chatOrder.merchantUserId}
          otherUserName={chatOrder.merchantName}
          isOpen={!!chatOrder}
          onClose={() => setChatOrder(null)}
        />
      )}
      {/* Cancel Order Dialog */}
      <OrderCancelDialog
        open={!!cancelOrderId}
        onOpenChange={(open) => { if (!open) setCancelOrderId(null); }}
        orderId={cancelOrderId || ''}
        onCancelled={() => { setCancelOrderId(null); fetchOrders(); }}
      />
      {/* S4-03: Rating kurir dialog */}
      {ratingOrder && (
        <CourierRatingDialog
          open={!!ratingOrder}
          onClose={() => setRatingOrder(null)}
          orderId={ratingOrder.id}
          courierId={ratingOrder.courierId}
          courierName={ratingOrder.courierName}
          orderNumber={ratingOrder.orderNumber}
        />
      )}
      <BottomNav />
    </div>
  );
};

export default OrdersPage;

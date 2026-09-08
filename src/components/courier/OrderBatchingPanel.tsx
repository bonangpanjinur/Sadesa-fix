/**
 * Multi-order batching — gabung 2–3 order dalam 1 kurir
 * Menggunakan Supabase Edge Function agar identitas kurir dan klaim order
 * divalidasi di server, bukan dari browser.
 */
import { useState, useEffect } from 'react';
import { Package, MapPin, Clock, ChevronDown, ChevronUp, Layers, CheckCircle2, RefreshCw } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Checkbox } from '@/components/ui/checkbox';
import { toast } from 'sonner';
import { formatPrice } from '@/lib/utils';
import { supabase } from '@/integrations/supabase/client';

interface AvailableOrder {
  id: string;
  total: number;
  status: string;
  created_at: string;
  shipping_address: string | null;
  buyer_name: string | null;
  merchant_name: string | null;
  merchant_address: string | null;
}

interface OrderBatchingPanelProps {
  activeOrders: { id: string }[];
  onRefresh: () => void;
}

interface BatchResponse {
  orders?: AvailableOrder[];
  can_accept?: number;
  message?: string;
}

function getFunctionErrorMessage(error: { message?: string } | null, fallback: string) {
  const message = error?.message?.trim();
  if (!message) return fallback;
  if (/failed to send a request|function.*not found|404/i.test(message)) {
    return 'Layanan batching belum tersedia di server. Hubungi administrator.';
  }
  return message;
}

export function OrderBatchingPanel({ activeOrders, onRefresh }: OrderBatchingPanelProps) {
  const [availableOrders, setAvailableOrders] = useState<AvailableOrder[]>([]);
  const [canAccept, setCanAccept] = useState(0);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [loading, setLoading] = useState(false);
  const [accepting, setAccepting] = useState(false);
  const [expanded, setExpanded] = useState(false);

  useEffect(() => {
    if (expanded) fetchAvailableOrders();
  }, [expanded]);

  const fetchAvailableOrders = async () => {
    setLoading(true);
    try {
      const { data, error } = await supabase.functions.invoke<BatchResponse>('courier-batch-orders', {
        body: { action: 'available', limit: 12 },
      });
      if (error) throw new Error(getFunctionErrorMessage(error, 'Gagal memuat daftar pesanan'));
      setAvailableOrders(data?.orders || []);
      setCanAccept(data?.can_accept ?? 0);
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : 'Gagal memuat daftar pesanan');
    } finally {
      setLoading(false);
    }
  };

  const toggleSelect = (id: string) => {
    const next = new Set(selected);
    if (next.has(id)) {
      next.delete(id);
    } else if (next.size < Math.min(3, canAccept)) {
      next.add(id);
    } else {
      toast.warning(`Maksimal ${Math.min(3, canAccept)} pesanan yang bisa diterima`);
    }
    setSelected(next);
  };

  const acceptBatch = async () => {
    if (selected.size < 2) {
      toast.warning('Pilih minimal 2 pesanan untuk batching');
      return;
    }
    setAccepting(true);
    try {
      const { data, error } = await supabase.functions.invoke<BatchResponse>('courier-batch-orders', {
        body: { action: 'accept', order_ids: Array.from(selected) },
      });
      if (error) throw new Error(getFunctionErrorMessage(error, 'Gagal menerima batch'));

      toast.success(data?.message || `${selected.size} pesanan berhasil di-batch!`);
      setSelected(new Set());
      setExpanded(false);
      onRefresh();
    } catch (err: unknown) {
      toast.error('Gagal menerima batch: ' + (err instanceof Error ? err.message : 'Coba lagi'));
    } finally {
      setAccepting(false);
    }
  };

  const canBatch = activeOrders.length < 3;

  return (
    <Card>
      <CardHeader className="pb-2">
        <div className="flex items-center justify-between">
          <CardTitle className="text-sm flex items-center gap-2">
            <Layers className="h-4 w-4 text-primary" />
            Multi-Order Batching
            {activeOrders.length > 0 && (
              <Badge variant="secondary">{activeOrders.length} aktif</Badge>
            )}
          </CardTitle>
          <Button variant="ghost" size="sm" onClick={() => setExpanded(!expanded)}>
            {expanded ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
          </Button>
        </div>
        <p className="text-xs text-muted-foreground">
          Gabungkan 2–3 pesanan searah untuk efisiensi pengiriman
        </p>
      </CardHeader>

      {expanded && (
        <CardContent className="space-y-3">
          {!canBatch ? (
            <div className="text-center py-3 text-sm text-muted-foreground bg-muted rounded-lg">
              Selesaikan dulu sebagian pesanan aktif (maks 3 total)
            </div>
          ) : (
            <>
              <div className="flex items-center justify-between">
                <span className="text-xs text-muted-foreground">
                  Bisa terima {canAccept} pesanan lagi
                </span>
                <Button variant="ghost" size="sm" onClick={fetchAvailableOrders} disabled={loading}>
                  <RefreshCw className={`h-3.5 w-3.5 ${loading ? 'animate-spin' : ''}`} />
                </Button>
              </div>

              {loading ? (
                <div className="flex justify-center py-4">
                  <div className="animate-spin h-6 w-6 border-2 border-primary border-t-transparent rounded-full" />
                </div>
              ) : availableOrders.length === 0 ? (
                <p className="text-center text-sm text-muted-foreground py-3">
                  Tidak ada pesanan tersedia untuk di-batch
                </p>
              ) : (
                <div className="space-y-2">
                  {availableOrders.map((order) => (
                    <div
                      key={order.id}
                      className={`border rounded-lg p-3 cursor-pointer transition-colors ${
                        selected.has(order.id) ? 'border-primary bg-primary/5' : 'hover:bg-muted/50'
                      }`}
                      onClick={() => toggleSelect(order.id)}
                    >
                      <div className="flex items-start gap-3">
                        <Checkbox
                          checked={selected.has(order.id)}
                          onCheckedChange={() => toggleSelect(order.id)}
                          className="mt-0.5"
                        />
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center justify-between">
                            <span className="font-medium text-sm">#{order.id.slice(0, 8).toUpperCase()}</span>
                            <span className="text-xs font-medium text-primary">
                              {formatPrice(order.total)}
                            </span>
                          </div>
                          <div className="flex items-center gap-1 text-xs text-muted-foreground mt-0.5">
                            <Package className="h-3 w-3 flex-shrink-0" />
                            <span className="truncate">{order.merchant_name || '-'}</span>
                          </div>
                          <div className="flex items-center gap-1 text-xs text-muted-foreground">
                            <MapPin className="h-3 w-3 flex-shrink-0" />
                            <span className="truncate">{order.buyer_name || 'Pembeli'}</span>
                          </div>
                          <div className="flex items-center gap-1 text-xs text-muted-foreground">
                            <Clock className="h-3 w-3 flex-shrink-0" />
                            <span>
                              {new Date(order.created_at).toLocaleTimeString('id-ID', {
                                hour: '2-digit',
                                minute: '2-digit',
                              })}
                            </span>
                          </div>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              )}

              {selected.size >= 2 && (
                <Button className="w-full" onClick={acceptBatch} disabled={accepting}>
                  {accepting ? (
                    <div className="flex items-center gap-2">
                      <div className="animate-spin h-4 w-4 border-2 border-white border-t-transparent rounded-full" />
                      Menerima batch...
                    </div>
                  ) : (
                    <div className="flex items-center gap-2">
                      <CheckCircle2 className="h-4 w-4" />
                      Terima {selected.size} Pesanan Sekaligus
                    </div>
                  )}
                </Button>
              )}
            </>
          )}
        </CardContent>
      )}
    </Card>
  );
}

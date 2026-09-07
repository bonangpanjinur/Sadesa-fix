import { useCallback, useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { AlertTriangle, Package, ArrowUpRight } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { supabase } from '@/integrations/supabase/client';
import { MerchantCardError } from './MerchantDataState';

interface LowStockProduct {
  id: string;
  name: string;
  stock: number;
  min_stock_alert: number;
  image_url: string | null;
}

interface StockAlertsProps {
  merchantId: string;
}

export function StockAlerts({ merchantId }: StockAlertsProps) {
  const [products, setProducts] = useState<LowStockProduct[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const navigate = useNavigate();

  const fetchLowStockProducts = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const { data, error } = await supabase
        .from('products')
        .select('id, name, stock, min_stock_alert, image_url')
        .eq('merchant_id', merchantId)
        .eq('is_active', true);

      if (error) throw error;

      // Filter products where stock <= min_stock_alert
      const lowStock = (data || []).filter(p => p.stock <= (p.min_stock_alert || 5));
      setProducts(lowStock);
    } catch (fetchError) {
      setError(fetchError instanceof Error ? fetchError.message : 'Gagal memuat peringatan stok.');
    } finally {
      setLoading(false);
    }
  }, [merchantId]);

  useEffect(() => {
    fetchLowStockProducts();
  }, [fetchLowStockProducts]);

  if (loading) {
    return (
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <AlertTriangle className="h-5 w-5 text-warning" />
            Stok Menipis
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="animate-pulse space-y-3">
            {[1, 2].map(i => (
              <div key={i} className="h-16 bg-muted rounded" />
            ))}
          </div>
        </CardContent>
      </Card>
    );
  }

  if (error) {
    return <MerchantCardError message={error} onRetry={() => void fetchLowStockProducts()} />;
  }

  if (products.length === 0) {
    return (
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Package className="h-5 w-5 text-primary" />
            Stok Aman
          </CardTitle>
        </CardHeader>
        <CardContent>
          <p className="text-sm text-muted-foreground">
            Semua produk memiliki stok yang cukup.
          </p>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card className="border-warning/50">
      <CardHeader>
        <CardTitle className="flex items-center gap-2 text-warning">
          <AlertTriangle className="h-5 w-5" />
          Stok Menipis
          <Badge variant="destructive" className="ml-auto">
            {products.length} Produk
          </Badge>
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        {products.map((product) => (
          <div 
            key={product.id} 
            className="flex items-center gap-3 p-3 bg-muted/50 rounded-lg"
          >
            <div className="w-12 h-12 bg-muted rounded overflow-hidden flex-shrink-0">
              {product.image_url ? (
                <img 
                  src={product.image_url} 
                  alt={product.name}
                  className="w-full h-full object-cover"
                />
              ) : (
                <div className="w-full h-full flex items-center justify-center">
                  <Package className="h-6 w-6 text-muted-foreground" />
                </div>
              )}
            </div>
            
            <div className="flex-1 min-w-0">
              <p className="font-medium text-sm truncate">{product.name}</p>
              <p className="text-xs text-muted-foreground">
                Min: {product.min_stock_alert || 5} unit
              </p>
            </div>

            <Button
              size="sm"
              variant="outline"
              onClick={() => navigate('/merchant/stock')}
            >
              Kelola stok
              <ArrowUpRight className="ml-1.5 h-3.5 w-3.5" />
            </Button>
          </div>
        ))}
      </CardContent>
    </Card>
  );
}

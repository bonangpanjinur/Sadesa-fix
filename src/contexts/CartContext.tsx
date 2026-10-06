import React, { createContext, useContext, useState, useCallback, useEffect } from 'react';
import type { CartItem, CartTopping, Product } from '@/types';
import { toast } from '@/hooks/use-toast';
import { getMaxOrderQuantity, getProductUnavailableReason } from '@/lib/productAvailability';

interface CartContextType {
  items: CartItem[];
  selectedItemIds: string[];
  selectedItems: CartItem[];
  toggleItemSelection: (productId: string) => void;
  selectAllItems: () => void;
  clearItemSelection: () => void;
  addToCart: (product: Product, quantity?: number, toppings?: CartTopping[]) => void;
  removeFromCart: (productId: string) => void;
  updateQuantity: (productId: string, quantity: number) => void;
  syncProductStock: (stockByProductId: Record<string, number>) => void;
  clearCart: () => void;
  getCartTotal: () => number;
  getItemCount: () => number;
}

const CartContext = createContext<CartContextType | undefined>(undefined);
const CART_STORAGE_KEY = 'desawisata_cart';
const MAX_CART_QUANTITY = 1000;

function loadCartFromStorage(): CartItem[] {
  try {
    const stored = localStorage.getItem(CART_STORAGE_KEY);
    if (stored) {
      const parsed = JSON.parse(stored);
      if (Array.isArray(parsed)) {
        return parsed.filter((item): item is CartItem => Boolean(
          item && item.product && typeof item.product.id === 'string'
          && Number.isFinite(item.quantity) && item.quantity > 0,
        )).map(item => ({
          ...item,
          quantity: Math.min(MAX_CART_QUANTITY, Math.max(1, Math.trunc(item.quantity))),
        }));
      }
    }
  } catch (e) {
    console.warn('Failed to load cart from localStorage:', e);
  }
  return [];
}

export function CartProvider({ children }: { children: React.ReactNode }) {
  const [items, setItems] = useState<CartItem[]>(loadCartFromStorage);
  const [selectedItemIds, setSelectedItemIds] = useState<string[]>(() => items.map(item => item.product.id));

  useEffect(() => {
    try { localStorage.setItem(CART_STORAGE_KEY, JSON.stringify(items)); }
    catch (e) { console.warn('Failed to save cart to localStorage:', e); }
  }, [items]);

  useEffect(() => {
    setSelectedItemIds(current => current.filter(id => items.some(item => item.product.id === id)));
  }, [items]);

  const addToCart = useCallback((product: Product, quantity: number = 1, toppings: CartTopping[] = []) => {
    const reason = getProductUnavailableReason({ isActive: product.isActive, stock: product.stock, hasQuota: product.hasQuota, isMerchantOpen: product.isMerchantOpen });
    if (product.isAvailable === false || reason) {
      toast({ title: 'Tidak dapat menambahkan ke keranjang', description: reason || 'Produk tidak tersedia', variant: 'destructive' });
      return;
    }
    const normalizedToppings = toppings.filter(t => t.product.id !== product.id && t.quantity > 0).map(t => ({ ...t, quantity: Math.min(MAX_CART_QUANTITY, Math.max(1, Math.trunc(t.quantity))) }));
    const maxQuantity = getMaxOrderQuantity(product, normalizedToppings);
    if (maxQuantity <= 0) {
      toast({ title: 'Stok tidak mencukupi', description: 'Stok produk atau topping sudah habis.', variant: 'destructive' });
      return;
    }
    const safeQuantity = Math.min(maxQuantity, MAX_CART_QUANTITY, Math.max(1, Math.trunc(quantity) || 1));
    setItems(prev => {
      const toppingKey = normalizedToppings.map(t => `${t.product.id}:${t.quantity}`).sort().join('|');
      const existingItem = prev.find(item => item.product.id === product.id && (item.toppings || []).map(t => `${t.product.id}:${t.quantity}`).sort().join('|') === toppingKey);
      if (existingItem) {
        const nextQuantity = Math.min(maxQuantity, MAX_CART_QUANTITY, existingItem.quantity + safeQuantity);
        if (nextQuantity === existingItem.quantity) {
          toast({ title: 'Jumlah maksimal tercapai', description: `Stok ${product.name} hanya ${maxQuantity}.`, variant: 'destructive' });
          return prev;
        }
        return prev.map(item => item === existingItem ? { ...item, quantity: nextQuantity } : item);
      }
      setSelectedItemIds(current => current.includes(product.id) ? current : [...current, product.id]);
      return [...prev, { product, quantity: safeQuantity, toppings: normalizedToppings.length ? normalizedToppings : undefined }];
    });
  }, []);

  const removeFromCart = useCallback((productId: string) => {
    setItems(prev => prev.filter(item => item.product.id !== productId));
    setSelectedItemIds(prev => prev.filter(id => id !== productId));
  }, []);

  const updateQuantity = useCallback((productId: string, quantity: number) => {
    if (quantity <= 0) { removeFromCart(productId); return; }
    setItems(prev => prev.map(item => {
      if (item.product.id !== productId) return item;
      const maxQuantity = getMaxOrderQuantity(item.product, item.toppings);
      return { ...item, quantity: Math.min(maxQuantity || 1, MAX_CART_QUANTITY, Math.max(1, Math.trunc(quantity))) };
    }));
  }, [removeFromCart]);

  const syncProductStock = useCallback((stockByProductId: Record<string, number>) => {
    setItems(prev => {
      let changed = false;
      const nextItems = prev.map(item => {
        const productStock = stockByProductId[item.product.id];
        const nextProduct = Number.isFinite(productStock)
          ? { ...item.product, stock: Math.max(0, Math.trunc(productStock)) }
          : item.product;
        const nextToppings = item.toppings?.map(topping => {
          const toppingStock = stockByProductId[topping.product.id];
          return Number.isFinite(toppingStock)
            ? { ...topping, product: { ...topping.product, stock: Math.max(0, Math.trunc(toppingStock)) } }
            : topping;
        });
        const maxQuantity = getMaxOrderQuantity(nextProduct, nextToppings);
        const nextQuantity = maxQuantity > 0 ? Math.min(item.quantity, maxQuantity) : item.quantity;
        if (nextProduct.stock !== item.product.stock || nextQuantity !== item.quantity || nextToppings?.some((topping, index) => topping.product.stock !== item.toppings?.[index]?.product.stock)) {
          changed = true;
        }
        return { ...item, product: nextProduct, toppings: nextToppings, quantity: nextQuantity };
      });
      return changed ? nextItems : prev;
    });
  }, []);

  const clearCart = useCallback(() => { setItems([]); setSelectedItemIds([]); }, []);
  const toggleItemSelection = useCallback((productId: string) => {
    setSelectedItemIds(current => current.includes(productId) ? current.filter(id => id !== productId) : [...current, productId]);
  }, []);
  const selectAllItems = useCallback(() => setSelectedItemIds(items.map(item => item.product.id)), [items]);
  const clearItemSelection = useCallback(() => setSelectedItemIds([]), []);
  const selectedItems = items.filter(item => selectedItemIds.includes(item.product.id));
  const getCartTotal = useCallback(() => items.reduce((total, item) => total + (item.product.price + (item.toppings || []).reduce((sum, topping) => sum + topping.product.price * topping.quantity, 0)) * item.quantity, 0), [items]);
  const getItemCount = useCallback(() => items.reduce((count, item) => count + item.quantity, 0), [items]);

  return <CartContext.Provider value={{ items, selectedItemIds, selectedItems, toggleItemSelection, selectAllItems, clearItemSelection, addToCart, removeFromCart, updateQuantity, syncProductStock, clearCart, getCartTotal, getItemCount }}>{children}</CartContext.Provider>;
}

export function useCart() {
  const context = useContext(CartContext);
  if (!context) throw new Error('useCart must be used within a CartProvider');
  return context;
}

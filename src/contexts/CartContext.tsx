import React, { createContext, useContext, useState, useCallback, useEffect } from 'react';
import type { CartItem, CartTopping, Product } from '@/types';
import { toast } from '@/hooks/use-toast';
import { getCartStockDemand, getProductUnavailableReason } from '@/lib/productAvailability';
import { getCartItemsSubtotal } from '@/lib/cartPricing';
import { getCartItemKey } from '@/lib/cartItemIdentity';

interface CartContextType {
  items: CartItem[];
  selectedItemIds: string[];
  selectedItems: CartItem[];
  toggleItemSelection: (itemKey: string) => void;
  selectAllItems: () => void;
  clearItemSelection: () => void;
  addToCart: (product: Product, quantity?: number, toppings?: CartTopping[]) => void;
  removeFromCart: (productId: string, toppings?: CartTopping[]) => void;
  updateQuantity: (productId: string, quantity: number, toppings?: CartTopping[]) => void;
  syncProductStock: (stockByProductId: Record<string, number>) => void;
  clearCart: () => void;
  getCartTotal: () => number;
  getItemCount: () => number;
}

const CartContext = createContext<CartContextType | undefined>(undefined);
const CART_STORAGE_KEY = 'desawisata_cart';
const MAX_CART_QUANTITY = 1000;

function getToppingKey(toppings: CartTopping[] = []): string {
  return toppings.map(t => `${t.product.id}:${t.quantity}`).sort().join('|');
}

function getMaxQuantityAgainstOtherLines(product: Product, toppings: CartTopping[] | undefined, otherItems: CartItem[]): number {
  const demand = getCartStockDemand(otherItems);
  let maxQuantity = Math.max(0, Math.trunc(Number(product.stock) || 0) - (demand.get(product.id) || 0));
  for (const topping of toppings || []) {
    const perItem = Math.max(1, Math.trunc(Number(topping.quantity) || 1));
    const available = Math.max(0, Math.trunc(Number(topping.product.stock) || 0) - (demand.get(topping.product.id) || 0));
    maxQuantity = Math.min(maxQuantity, Math.floor(available / perItem));
  }
  return Math.max(0, maxQuantity);
}

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
  const [selectedItemIds, setSelectedItemIds] = useState<string[]>(() => items.map(getCartItemKey));

  useEffect(() => {
    try { localStorage.setItem(CART_STORAGE_KEY, JSON.stringify(items)); }
    catch (e) { console.warn('Failed to save cart to localStorage:', e); }
  }, [items]);

  useEffect(() => {
    setSelectedItemIds(current => current.filter(id => items.some(item => getCartItemKey(item) === id)));
  }, [items]);

  const addToCart = useCallback((product: Product, quantity: number = 1, toppings: CartTopping[] = []) => {
    const reason = getProductUnavailableReason({ isActive: product.isActive, stock: product.stock, hasQuota: product.hasQuota, isMerchantOpen: product.isMerchantOpen });
    if (product.isAvailable === false || reason) {
      toast({ title: 'Tidak dapat menambahkan ke keranjang', description: reason || 'Produk tidak tersedia', variant: 'destructive' });
      return;
    }
    const normalizedToppings = toppings.filter(t => t.product.id !== product.id && t.quantity > 0).map(t => ({ ...t, quantity: Math.min(MAX_CART_QUANTITY, Math.max(1, Math.trunc(t.quantity))) }));
    setItems(prev => {
      const toppingKey = getToppingKey(normalizedToppings);
      const existingItem = prev.find(item => item.product.id === product.id && getToppingKey(item.toppings) === toppingKey);
      const otherItems = existingItem ? prev.filter(item => item !== existingItem) : prev;
      const maxQuantity = getMaxQuantityAgainstOtherLines(product, normalizedToppings, otherItems);
      const requestedQuantity = Math.max(1, Math.trunc(quantity) || 1);
      if (existingItem) {
        const nextQuantity = Math.min(maxQuantity, MAX_CART_QUANTITY, existingItem.quantity + requestedQuantity);
        if (nextQuantity <= 0) return prev.filter(item => item !== existingItem);
        if (nextQuantity === existingItem.quantity) {
          toast({ title: 'Jumlah maksimal tercapai', description: `Stok ${product.name} hanya ${maxQuantity}.`, variant: 'destructive' });
          return prev;
        }
        return prev.map(item => item === existingItem ? { ...item, quantity: nextQuantity } : item);
      }
      const safeQuantity = Math.min(maxQuantity, MAX_CART_QUANTITY, requestedQuantity);
      if (safeQuantity <= 0) {
        toast({ title: 'Stok tidak mencukupi', description: 'Stok produk atau topping sudah habis.', variant: 'destructive' });
        return prev;
      }
      const nextItem = { product, quantity: safeQuantity, toppings: normalizedToppings.length ? normalizedToppings : undefined };
      const itemKey = getCartItemKey(nextItem);
      setSelectedItemIds(current => current.includes(itemKey) ? current : [...current, itemKey]);
      return [...prev, nextItem];
    });
  }, []);

  const removeFromCart = useCallback((productId: string, toppings?: CartTopping[]) => {
    setItems(prev => prev.filter(item => item.product.id !== productId || (toppings && getToppingKey(item.toppings) !== getToppingKey(toppings))));
    setSelectedItemIds(prev => prev.filter(id => !(
      id === productId || id.startsWith(`${productId}::`)
    )));
  }, []);

  const updateQuantity = useCallback((productId: string, quantity: number, toppings?: CartTopping[]) => {
    if (quantity <= 0) { removeFromCart(productId, toppings); return; }
    setItems(prev => prev.map(item => {
      if (item.product.id !== productId || (toppings && getToppingKey(item.toppings) !== getToppingKey(toppings))) return item;
      const otherItems = prev.filter(candidate => candidate !== item);
      const maxQuantity = getMaxQuantityAgainstOtherLines(item.product, item.toppings, otherItems);
      return { ...item, quantity: Math.min(maxQuantity, MAX_CART_QUANTITY, Math.max(1, Math.trunc(quantity))) };
    }).filter(item => item.quantity > 0));
  }, [removeFromCart]);

  const syncProductStock = useCallback((stockByProductId: Record<string, number>) => {
    setItems(prev => {
      let changed = false;
      const nextItems: CartItem[] = [];
      prev.forEach(item => {
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
        const maxQuantity = getMaxQuantityAgainstOtherLines(nextProduct, nextToppings, nextItems);
        // Keep one stale line visible when stock reaches zero so the cart can
        // explain why checkout is blocked; the minus/remove action can clear it.
        const nextQuantity = maxQuantity > 0 ? Math.min(item.quantity, maxQuantity) : 1;
        if (nextProduct.stock !== item.product.stock || nextQuantity !== item.quantity || nextToppings?.some((topping, index) => topping.product.stock !== item.toppings?.[index]?.product.stock)) {
          changed = true;
        }
        nextItems.push({ ...item, product: nextProduct, toppings: nextToppings, quantity: nextQuantity });
      });
      return changed ? nextItems : prev;
    });
  }, []);

  const clearCart = useCallback(() => { setItems([]); setSelectedItemIds([]); }, []);
  const toggleItemSelection = useCallback((itemKey: string) => {
    setSelectedItemIds(current => current.includes(itemKey) ? current.filter(id => id !== itemKey) : [...current, itemKey]);
  }, []);
  const selectAllItems = useCallback(() => setSelectedItemIds(items.map(getCartItemKey)), [items]);
  const clearItemSelection = useCallback(() => setSelectedItemIds([]), []);
  const selectedItems = items.filter(item => selectedItemIds.includes(getCartItemKey(item)));
  const getCartTotal = useCallback(() => getCartItemsSubtotal(items), [items]);
  const getItemCount = useCallback(() => items.reduce((count, item) => count + item.quantity, 0), [items]);

  return <CartContext.Provider value={{ items, selectedItemIds, selectedItems, toggleItemSelection, selectAllItems, clearItemSelection, addToCart, removeFromCart, updateQuantity, syncProductStock, clearCart, getCartTotal, getItemCount }}>{children}</CartContext.Provider>;
}

export function useCart() {
  const context = useContext(CartContext);
  if (!context) throw new Error('useCart must be used within a CartProvider');
  return context;
}

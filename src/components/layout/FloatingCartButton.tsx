import { Link } from 'react-router-dom';
import { ShoppingCart } from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';
import { useCart } from '@/contexts/CartContext';
import { formatPrice } from '@/lib/utils';

export function FloatingCartButton() {
  const { items, getItemCount, getCartTotal } = useCart();
  const itemCount = getItemCount();
  const subtotal = getCartTotal();

  if (itemCount === 0) return null;

  return (
    <AnimatePresence>
      <motion.div
        initial={{ scale: 0, opacity: 0 }}
        animate={{ scale: 1, opacity: 1 }}
        exit={{ scale: 0, opacity: 0 }}
        className="fixed bottom-20 right-4 z-50"
      >
        <Link
          to="/cart"
          className="flex items-center gap-3 rounded-2xl bg-primary px-4 py-3 text-primary-foreground shadow-[0_12px_28px_-10px_hsl(4_78%_47%_/_0.65)] transition-all hover:bg-brand-dark hover:scale-105"
        >
          <div className="relative">
            <ShoppingCart className="h-5 w-5" />
            <span className="absolute -right-2 -top-2 flex h-5 w-5 items-center justify-center rounded-full border-2 border-primary bg-accent text-[10px] font-extrabold text-accent-foreground">
              {itemCount > 9 ? '9+' : itemCount}
            </span>
          </div>
          <div className="border-l border-primary-foreground/30 pl-3">
            <p className="text-[10px] opacity-80">Total</p>
            <p className="font-bold text-sm">{formatPrice(subtotal)}</p>
          </div>
        </Link>
      </motion.div>
    </AnimatePresence>
  );
}

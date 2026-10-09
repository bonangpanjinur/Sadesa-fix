import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const cartPage = readFileSync(resolve(process.cwd(), 'src/pages/CartPage.tsx'), 'utf8');
const checkoutPage = readFileSync(resolve(process.cwd(), 'src/pages/CheckoutPage.tsx'), 'utf8');
const indexStyles = readFileSync(resolve(process.cwd(), 'src/index.css'), 'utf8');

describe('mobile commerce responsive contract', () => {
  it('keeps cart content scrollable above a mobile-safe sticky checkout summary', () => {
    expect(cartPage).toContain('mobile-shell flex min-h-[100dvh] flex-col');
    expect(cartPage).toContain('flex-1 overflow-y-auto p-4 pb-48');
    expect(cartPage).toContain('mobile-action-safe fixed bottom-0 left-0 right-0');
    expect(cartPage).toContain('max-w-[480px]');
    expect(cartPage).toContain('className="w-full shadow-brand font-bold"');
  });

  it('keeps checkout sections readable and the primary action reachable on narrow screens', () => {
    expect(checkoutPage).toContain('mobile-shell bg-secondary flex flex-col min-h-screen');
    expect(checkoutPage).toContain('sticky top-0 z-50');
    expect(checkoutPage).toContain('flex-1 overflow-y-auto p-4 pb-56');
    expect(checkoutPage).toContain('mobile-action-safe fixed bottom-0 left-0 right-0');
    expect(checkoutPage).toContain('max-w-[480px]');
    expect(checkoutPage).toContain('className="w-full shadow-brand font-bold transition-all"');
    expect(checkoutPage).toContain('className="flex justify-between items-center mb-1 text-xs sm:text-sm"');
    expect(checkoutPage).toContain('className="flex-1 min-w-0"');
  });

  it('defines safe-area padding for fixed mobile actions', () => {
    expect(indexStyles).toContain('.mobile-action-safe');
    expect(indexStyles).toContain('env(safe-area-inset-bottom)');
  });
});

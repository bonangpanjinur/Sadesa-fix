import { act, renderHook } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { usePOSPayment } from './usePOSPayment';

describe('usePOSPayment', () => {
  it('opens payment with the current total only when the cart is not empty', () => {
    const { result, rerender } = renderHook(({ total, count }) => usePOSPayment(total, count), {
      initialProps: { total: 25000, count: 2 },
    });
    let opened = false;
    act(() => { opened = result.current.openPayment(); });
    expect(opened).toBe(true);
    expect(result.current.paymentAmount).toBe('25000');
    expect(result.current.paymentDialog).toBe(true);
    rerender({ total: 25000, count: 0 });
    act(() => { opened = result.current.openPayment(); });
    expect(opened).toBe(false);
  });

  it('normalizes payment field changes and resets transient payment state', () => {
    const { result } = renderHook(() => usePOSPayment(10000, 1));
    act(() => {
      result.current.handlePaymentChange('isSplitPayment', true);
      result.current.handlePaymentChange('splitAmount1', '6000');
      result.current.handlePaymentChange('splitAmount2', '4000');
      result.current.handlePaymentChange('splitMethod2', 'qris');
    });
    expect(result.current.isSplitPayment).toBe(true);
    expect(result.current.splitAmount1).toBe('6000');
    expect(result.current.splitAmount2).toBe('4000');
    expect(result.current.splitMethod2).toBe('qris');
    act(() => result.current.resetPayment());
    expect(result.current.isSplitPayment).toBe(false);
    expect(result.current.splitMethod2).toBe('transfer');
    expect(result.current.splitAmount1).toBe('');
    expect(result.current.paymentDialog).toBe(false);
  });
});

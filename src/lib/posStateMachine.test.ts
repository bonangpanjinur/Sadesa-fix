import { describe, expect, it } from 'vitest';
import { assertTransition, canTransition, transition } from './posStateMachine';

describe('posStateMachine', () => {
  it('allows the normal KDS lifecycle', () => {
    expect(canTransition('kds', 'pending', 'confirmed')).toBe(true);
    const next = transition('kds', { status: 'preparing', id: 'order-1' }, 'ready');
    expect(next).toEqual({ status: 'ready', id: 'order-1' });
  });

  it('rejects skipping workflow states', () => {
    expect(canTransition('stock_transfer', 'draft', 'received')).toBe(false);
    expect(() => assertTransition('return', 'submitted', 'completed')).toThrow('Invalid return transition');
  });

  it('does not mutate the original entity', () => {
    const entity = { status: 'available', id: 'table-1' };
    const next = transition('table', entity, 'occupied');
    expect(entity.status).toBe('available');
    expect(next.status).toBe('occupied');
  });
});

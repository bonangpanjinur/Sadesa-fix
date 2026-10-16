import { afterEach, describe, expect, it, vi } from 'vitest';
import { createCoalescedTask } from './createCoalescedTask';

afterEach(() => {
  vi.useRealTimers();
});

describe('createCoalescedTask', () => {
  it('coalesces a burst of triggers into one task run', async () => {
    vi.useFakeTimers();
    const task = vi.fn();
    const refresh = createCoalescedTask(task, 100);

    refresh.trigger();
    refresh.trigger();
    refresh.trigger();
    await vi.advanceTimersByTimeAsync(100);

    expect(task).toHaveBeenCalledTimes(1);
    refresh.dispose();
  });

  it('schedules one follow-up when triggers arrive during an in-flight task', async () => {
    vi.useFakeTimers();
    let finishFirst!: () => void;
    const task = vi.fn()
      .mockImplementationOnce(() => new Promise<void>((resolve) => { finishFirst = resolve; }))
      .mockResolvedValue(undefined);
    const refresh = createCoalescedTask(task, 100);

    refresh.trigger();
    await vi.advanceTimersByTimeAsync(100);
    expect(task).toHaveBeenCalledTimes(1);

    refresh.trigger();
    refresh.trigger();
    finishFirst();
    await Promise.resolve();
    await vi.advanceTimersByTimeAsync(100);

    expect(task).toHaveBeenCalledTimes(2);
    refresh.dispose();
  });

  it('cancels pending work and ignores future triggers after disposal', async () => {
    vi.useFakeTimers();
    const task = vi.fn();
    const refresh = createCoalescedTask(task, 100);

    refresh.trigger();
    refresh.dispose();
    refresh.trigger();
    await vi.advanceTimersByTimeAsync(100);

    expect(task).not.toHaveBeenCalled();
  });
});

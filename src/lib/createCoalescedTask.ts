export interface CoalescedTask {
  runNow: () => void;
  trigger: () => void;
  dispose: () => void;
}

/**
 * Debounces bursts and serializes asynchronous refresh work. If an event arrives
 * while the task is running, exactly one follow-up run is scheduled after it
 * settles instead of starting another overlapping request.
 */
export function createCoalescedTask(task: () => Promise<unknown> | unknown, delayMs = 250): CoalescedTask {
  let timer: ReturnType<typeof setTimeout> | null = null;
  let inFlight = false;
  let dirty = false;
  let disposed = false;

  const schedule = () => {
    if (disposed || timer) return;
    timer = setTimeout(() => {
      timer = null;
      if (!dirty || disposed) return;
      dirty = false;
      void execute();
    }, delayMs);
  };

  const execute = async () => {
    if (disposed) return;
    if (inFlight) {
      dirty = true;
      return;
    }

    inFlight = true;
    try {
      await task();
    } finally {
      inFlight = false;
      if (dirty && !disposed) schedule();
    }
  };

  return {
    runNow: () => {
      if (disposed) return;
      if (timer) clearTimeout(timer);
      timer = null;
      dirty = false;
      void execute();
    },
    trigger: () => {
      if (disposed) return;
      dirty = true;
      if (!inFlight) {
        if (timer) clearTimeout(timer);
        timer = null;
        schedule();
      }
    },
    dispose: () => {
      disposed = true;
      dirty = false;
      if (timer) clearTimeout(timer);
      timer = null;
    },
  };
}

type PwaUpdateHandler = (reloadPage?: boolean) => Promise<void>;

let pwaUpdateHandler: PwaUpdateHandler | null = null;

export function setPwaUpdateHandler(handler: PwaUpdateHandler | null): void {
  pwaUpdateHandler = handler;
}

export async function requestPwaUpdate(): Promise<void> {
  if (!pwaUpdateHandler) {
    throw new Error('Handler pembaruan PWA belum siap. Muat ulang halaman lalu coba lagi.');
  }

  await pwaUpdateHandler(true);
}

export function isPendingServiceWorkerUpdate(
  workerState: ServiceWorkerState | undefined,
  isWaitingWorker: boolean,
  hasActiveController: boolean,
): boolean {
  return workerState === 'installed' && isWaitingWorker && hasActiveController;
}

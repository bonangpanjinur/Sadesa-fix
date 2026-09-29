export function isPendingServiceWorkerUpdate(
  workerState: ServiceWorkerState | undefined,
  isWaitingWorker: boolean,
  hasActiveController: boolean,
): boolean {
  return workerState === 'installed' && isWaitingWorker && hasActiveController;
}

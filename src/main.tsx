import { createRoot } from "react-dom/client";
import { registerSW } from 'virtual:pwa-register';
import App from './App.tsx';
import './index.css';
import { reportObservability } from './lib/observability';

const SERVICE_WORKER_UPDATE_INTERVAL_MS = 5 * 60 * 1000;

if (import.meta.env.PROD && "serviceWorker" in navigator) {
  let isReloadingForUpdate = false;
  let updateSW: ((reloadPage?: boolean) => Promise<void>) | null = null;

  const reloadForUpdate = () => {
    if (isReloadingForUpdate) return;
    isReloadingForUpdate = true;
    void updateSW?.(true).catch((error: unknown) => {
      isReloadingForUpdate = false;
      console.warn('Automatic application update failed:', error);
      reportObservability('application', 'service_worker_auto_update_failed', 'warn', {}, error);
    });
  };

  updateSW = registerSW({
    immediate: true,
    onNeedRefresh: reloadForUpdate,
    onRegisteredSW: (_swUrl, registration) => {
      if (!registration) return;

      const checkForUpdate = () => {
        if (document.visibilityState === 'visible') {
          void registration.update().catch((error: unknown) => {
            reportObservability('application', 'service_worker_update_check_failed', 'warn', {}, error);
          });
        }
      };

      // Check immediately, when the tab becomes active, and while it remains
      // open so deployed builds reach users without a manual hard refresh.
      checkForUpdate();
      const updateTimer = window.setInterval(checkForUpdate, SERVICE_WORKER_UPDATE_INTERVAL_MS);
      window.addEventListener('focus', checkForUpdate);
      window.addEventListener('online', checkForUpdate);
      document.addEventListener('visibilitychange', checkForUpdate);

      window.addEventListener('beforeunload', () => {
        window.clearInterval(updateTimer);
        window.removeEventListener('focus', checkForUpdate);
        window.removeEventListener('online', checkForUpdate);
        document.removeEventListener('visibilitychange', checkForUpdate);
      }, { once: true });
    },
    onRegisterError: (error) => {
      console.warn("Service worker registration failed:", error);
      reportObservability('application', 'service_worker_registration_failed', 'warn', {}, error);
    },
  });
}

createRoot(document.getElementById("root")!).render(<App />);

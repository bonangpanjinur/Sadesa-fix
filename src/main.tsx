import { createRoot } from "react-dom/client";
import { registerSW } from 'virtual:pwa-register';
import App from './App.tsx';
import './index.css';
import { reportObservability } from './lib/observability';
import { setPwaUpdateHandler } from './lib/pwaUpdate';

if (import.meta.env.PROD && "serviceWorker" in navigator) {
  // Registration is intentionally prompt-based. PWAProvider displays the
  // update prompt; the page must not reload merely because a new worker was
  // detected while the user is working.
  const updateServiceWorker = registerSW({
    immediate: true,
    onNeedRefresh: () => {
      reportObservability('application', 'service_worker_update_available', 'info');
    },
    onRegisterError: (error) => {
      console.warn("Service worker registration failed:", error);
      reportObservability('application', 'service_worker_registration_failed', 'warn', {}, error);
    },
  });
  setPwaUpdateHandler(updateServiceWorker);
}

createRoot(document.getElementById("root")!).render(<App />);

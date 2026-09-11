import { createRoot } from "react-dom/client";
import { registerSW } from 'virtual:pwa-register';
import App from './App.tsx';
import './index.css';
import { reportObservability } from './lib/observability';

if (import.meta.env.PROD && "serviceWorker" in navigator) {
  registerSW({
    immediate: true,
    onRegisteredSW: (_swUrl, registration) => {
      void registration?.update();
    },
    onRegisterError: (error) => {
      console.warn("Service worker registration failed:", error);
      reportObservability('application', 'service_worker_registration_failed', 'warn', {}, error);
    },
  });
}

createRoot(document.getElementById("root")!).render(<App />);

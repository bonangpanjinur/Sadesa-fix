import { createRoot } from "react-dom/client";
import { registerSW } from "virtual:pwa-register";
import App from "./App.tsx";
import "./index.css";

if (import.meta.env.PROD && "serviceWorker" in navigator) {
  registerSW({
    immediate: true,
    onRegisteredSW: (_swUrl, registration) => {
      void registration?.update();
    },
    onRegisterError: (error) => {
      console.warn("Service worker registration failed:", error);
    },
  });
}

createRoot(document.getElementById("root")!).render(<App />);

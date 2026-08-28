import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react-swc";
import path from "path";

export default defineConfig({
  plugins: [react()],
  test: {
    environment: "jsdom",
    globals: true,
    setupFiles: ["./src/test/setup.ts"],
    include: ["src/**/*.{test,spec}.{ts,tsx}"],
  },
  define: {
    // Synthetic public values keep unit tests deterministic without using production credentials.
    "import.meta.env.VITE_SUPABASE_URL": JSON.stringify("https://unit-test.supabase.local"),
    "import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY": JSON.stringify("unit-test-anon-key"),
  },
  resolve: {
    alias: { "@": path.resolve(__dirname, "./src") },
  },
});

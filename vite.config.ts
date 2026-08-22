import { defineConfig } from "vite";
import react from "@vitejs/plugin-react-swc";
import { VitePWA } from "vite-plugin-pwa";
import path from "path";

// https://vitejs.dev/config/
export default defineConfig(() => ({
  server: {
    host: "0.0.0.0",
    port: 8080,
    allowedHosts: process.env.VITE_ALLOWED_HOSTS?.split(',').map((host) => host.trim()).filter(Boolean) ?? [],
  },

  plugins: [
    react(),
    VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['favicon.ico', 'pwa-192x192.png', 'pwa-512x512.png', 'robots.txt'],
      manifest: {
        name: 'DesaMart',
        short_name: 'DesaMart',
        description: 'Marketplace UMKM & Desa Wisata Indonesia',
        theme_color: '#10b981',
        background_color: '#ffffff',
        display: 'standalone',
        start_url: '/',
        icons: [
          {
            src: 'pwa-192x192.png',
            sizes: '192x192',
            type: 'image/png',
            purpose: 'any maskable'
          },
          {
            src: 'pwa-512x512.png',
            sizes: '512x512',
            type: 'image/png',
            purpose: 'any maskable'
          }
        ]
      },
      workbox: {
        navigateFallbackDenylist: [/^\/~oauth/],
        maximumFileSizeToCacheInBytes: 5 * 1024 * 1024,
        globPatterns: ['**/*.{js,css,html,ico,png,svg,woff2}'],
        runtimeCaching: [
          {
            // Cache only public storefront images; never cache private documents,
            // payment proofs, courier documents, or chat attachments.
            urlPattern: /\/storage\/v1\/object\/public\/(product-images|tourism-images|profile-images|merchant-images|merchant-gallery|village-images)\//i,
            handler: 'CacheFirst',
            options: {
              cacheName: 'local-storage-cache',
              expiration: {
                maxEntries: 200,
                maxAgeSeconds: 60 * 60 * 24 * 30
              },
              cacheableResponse: {
                statuses: [0, 200]
              }
            }
          },
          {
            // Cache data wilayah dari edge function (jarang berubah)
            urlPattern: /\/functions\/v1\/wilayah-proxy.*/i,
            handler: 'CacheFirst',
            options: {
              cacheName: 'wilayah-cache',
              expiration: {
                maxEntries: 50,
                maxAgeSeconds: 60 * 60 * 24 * 7
              },
              cacheableResponse: {
                statuses: [0, 200]
              }
            }
          }
        ]
      }
    }),
  ],

  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
  build: {
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (id.includes('node_modules')) {
            if (id.includes('react') || id.includes('react-dom')) {
              return 'react-vendor';
            }
            if (id.includes('recharts')) {
              return 'recharts-vendor';
            }
            if (id.includes('@supabase')) {
              return 'supabase-vendor';
            }
            if (id.includes('leaflet')) {
              return 'map-vendor';
            }
            if (id.includes('framer-motion')) {
              return 'motion-vendor';
            }
            if (id.includes('jspdf')) {
              return 'pdf-vendor';
            }
            return 'vendor';
          }
          if (id.includes('workbox-window')) {
            return 'workbox';
          }
        },
      },
    },
  },
}));

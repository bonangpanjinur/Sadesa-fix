import { defineConfig } from "vite";
import react from "@vitejs/plugin-react-swc";
import { VitePWA } from "vite-plugin-pwa";
import path from "path";

// https://vitejs.dev/config/
export default defineConfig(() => ({
  server: {
    host: "0.0.0.0",
    port: 5000,
    // Replit serves the preview through a proxied host that is not known at
    // build time. Keep the optional env override for local hardening, but
    // allow the Replit proxy to reach Vite in the development workflow.
    allowedHosts: true,
  },

  plugins: [
    react(),
    VitePWA({
      strategies: 'injectManifest',
      srcDir: 'src',
      filename: 'sw.ts',
      // Do not force-reload active sessions when a deployment publishes a new
      // worker. The in-app UpdatePrompt lets the user choose the right moment.
      registerType: 'prompt',
      includeAssets: [
        'favicon.ico',
        'branding/sadesa-favicon.png',
        'branding/sadesa-icon-192.png',
        'branding/sadesa-icon-512.png',
        'robots.txt',
      ],
      manifest: {
        name: 'SaDesa',
        short_name: 'SaDesa',
        id: '/',
        lang: 'id',
        dir: 'ltr',
        description: 'Marketplace UMKM & Desa Wisata Indonesia',
        theme_color: '#10b981',
        background_color: '#ffffff',
        display: 'standalone',
        display_override: ['window-controls-overlay', 'tabbed', 'standalone', 'browser'],
        start_url: '/',
        scope: '/',
        orientation: 'portrait-primary',
        categories: ['shopping', 'business', 'lifestyle'],
        prefer_related_applications: false,
        launch_handler: {
          client_mode: 'navigate-existing',
        },
        share_target: {
          action: '/share-target',
          method: 'GET',
          enctype: 'application/x-www-form-urlencoded',
          params: {
            title: 'title',
            text: 'text',
            url: 'url',
          },
        },
        file_handlers: [
          {
            action: '/file-handler',
            accept: {
              'text/csv': ['.csv'],
              'application/json': ['.json'],
            },
            icons: [
              {
                src: 'branding/sadesa-icon-192.png',
                sizes: '192x192',
                type: 'image/png',
              },
            ],
          },
        ],
        protocol_handlers: [
          {
            protocol: 'web+sadesa',
            url: '/protocol-handler?url=%s',
          },
        ],
        shortcuts: [
          {
            name: 'Belanja Produk Desa',
            short_name: 'Belanja',
            description: 'Jelajahi produk UMKM desa',
            url: '/shops',
            icons: [{ src: 'branding/sadesa-icon-192.png', sizes: '192x192', type: 'image/png' }],
          },
          {
            name: 'Pesanan Saya',
            short_name: 'Pesanan',
            description: 'Lihat status pesanan Anda',
            url: '/orders',
            icons: [{ src: 'branding/sadesa-icon-192.png', sizes: '192x192', type: 'image/png' }],
          },
          {
            name: 'Akun Saya',
            short_name: 'Akun',
            description: 'Buka profil dan pengaturan akun',
            url: '/account',
            icons: [{ src: 'branding/sadesa-icon-192.png', sizes: '192x192', type: 'image/png' }],
          },
        ],
        edge_side_panel: { preferred_width: 480 },
        tab_strip: {
          home_tab: {
            scope: '/',
            icons: [{ src: 'branding/sadesa-icon-192.png', sizes: '192x192' }]
          }
        },
        note_taking: { new_note_url: '/?new_note=1' },
        widgets: [{
          name: 'Ringkasan SaDesa',
          short_name: 'SaDesa',
          description: 'Ringkasan cepat aktivitas marketplace SaDesa',
          tag: 'sadesa-summary',
          template: 'sadesa-summary',
          ms_ac_template: 'widgets/sadesa-summary-template.json',
          data: 'widgets/sadesa-summary-data.json',
          type: 'application/json',
          screenshots: [{ src: 'widgets/sadesa-widget-preview.png', sizes: '480x270', label: 'Widget ringkasan SaDesa' }],
          icons: [{ src: 'branding/sadesa-icon-192.png', sizes: '192x192' }],
          auth: false,
          update: 86400
        }],
        screenshots: [
          {
            src: 'screenshots/sadesa-home-narrow.jpg',
            sizes: '480x720',
            type: 'image/jpeg',
            form_factor: 'narrow',
            label: 'Beranda SaDesa di perangkat mobile',
          },
          {
            src: 'screenshots/sadesa-home-wide.jpg',
            sizes: '1280x720',
            type: 'image/jpeg',
            form_factor: 'wide',
            label: 'Beranda SaDesa di layar desktop',
          },
        ],
        icons: [
          {
            src: 'branding/sadesa-icon-192.png',
            sizes: '192x192',
            type: 'image/png',
            purpose: 'any maskable'
          },
          {
            src: 'branding/sadesa-icon-512.png',
            sizes: '512x512',
            type: 'image/png',
            purpose: 'any maskable'
          }
        ]
      },
      // This project uses injectManifest, so precache/runtime options must be
      // configured here (the `workbox` block is only used by generateSW).
      injectManifest: {
        maximumFileSizeToCacheInBytes: 5 * 1024 * 1024,
        // Precache only the app shell. The previous `**/*.js` pattern also
        // downloaded every admin/merchant/POS route on first visit, producing
        // a 346-entry / ~6.3 MB install. Lazy route chunks, images, and other
        // non-critical scripts are cached on demand below.
        globPatterns: [
          '**/*.{css,html,ico,svg,woff2}',
          'assets/index-*.js',
          'assets/react-vendor-*.js',
          'assets/data-router-vendor-*.js',
          'assets/supabase-vendor-*.js',
          'assets/ui-vendor-*.js',
          'assets/utility-vendor-*.js',
        ],
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
            if (id.includes('leaflet') || id.includes('react-leaflet')) {
              return 'map-vendor';
            }
            if (id.includes('node_modules/react/') || id.includes('node_modules/react-dom/')) {
              return 'react-vendor';
            }
            if (id.includes('@supabase')) {
              return 'supabase-vendor';
            }
            if (id.includes('@tanstack') || id.includes('react-router')) {
              return 'data-router-vendor';
            }
            if (id.includes('@radix-ui') || id.includes('cmdk') || id.includes('vaul')) {
              return 'ui-vendor';
            }
            if (id.includes('recharts')) {
              return 'recharts-vendor';
            }
            if (id.includes('framer-motion')) {
              return 'motion-vendor';
            }
            if (id.includes('jspdf') || id.includes('jspdf-autotable')) {
              return 'pdf-vendor';
            }
            if (id.includes('date-fns') || id.includes('react-day-picker')) {
              return 'date-vendor';
            }
            if (id.includes('react-hook-form') || id.includes('zod')) {
              return 'form-vendor';
            }
            if (id.includes('lucide-react') || id.includes('sonner')) {
              return 'utility-vendor';
            }
            // Let Rollup place uncategorized dependencies with their importing route
            // instead of recreating a monolithic shared vendor chunk.
            return undefined;
          }
          if (id.includes('workbox-window')) {
            return 'workbox';
          }
        },
      },
    },
  },
}));

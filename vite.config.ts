import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import { VitePWA } from 'vite-plugin-pwa'
import { viteSingleFile } from 'vite-plugin-singlefile'

// LM_SINGLEFILE=1 builds a fully self-contained index.html (fonts, images and
// code inlined) used for shareable previews. The normal build keeps the PWA.
const singleFile = process.env.LM_SINGLEFILE === '1'

// https://vite.dev/config/
export default defineConfig({
  plugins: singleFile
    ? [react(), tailwindcss(), viteSingleFile()]
    : [
        react(),
        tailwindcss(),
        VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['icons/apple-touch-icon.png'],
      workbox: {
        globPatterns: ['**/*.{js,css,html,svg,png,woff2}'],
        maximumFileSizeToCacheInBytes: 4 * 1024 * 1024,
      },
      manifest: {
        name: 'LensMood — AI aesthetic camera',
        short_name: 'LensMood',
        description:
          'Upload a photo, choose a camera mood, and recreate the lighting, grain, color and vibe of iconic camera styles.',
        theme_color: '#f1e8d6',
        background_color: '#f1e8d6',
        display: 'standalone',
        orientation: 'portrait',
        start_url: '/home',
        icons: [
          { src: '/icons/icon-192.png', sizes: '192x192', type: 'image/png' },
          { src: '/icons/icon-512.png', sizes: '512x512', type: 'image/png' },
          {
            src: '/icons/icon-maskable-512.png',
            sizes: '512x512',
            type: 'image/png',
            purpose: 'maskable',
              },
            ],
          },
        }),
      ],
})

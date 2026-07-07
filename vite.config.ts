import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import { VitePWA } from 'vite-plugin-pwa'
import { viteSingleFile } from 'vite-plugin-singlefile'

// LM_SINGLEFILE=1 builds a fully self-contained index.html (fonts, images and
// code inlined) used for shareable previews. The normal build keeps the PWA.
const singleFile = process.env.LM_SINGLEFILE === '1'

// Content-Security-Policy for the normal (PWA / iOS shell) build — enforces
// "photos never leave the device" at the platform level, so a future
// dependency regression can't silently phone home. The single-file preview
// inlines all scripts, which a strict CSP forbids, so it is skipped there.
const CSP = [
  "default-src 'self'",
  "script-src 'self' 'wasm-unsafe-eval'", // mediapipe wasm
  "style-src 'self' 'unsafe-inline'", // framer-motion inline styles + splash
  "img-src 'self' data: blob:",
  "media-src 'self' data: blob:",
  "font-src 'self' data:",
  "connect-src 'self' data: blob:",
  "worker-src 'self' blob:",
  "object-src 'none'",
  "base-uri 'self'",
].join('; ')

const cspPlugin = () => ({
  name: 'lm-csp',
  transformIndexHtml(html: string) {
    return html.replace(
      '<meta charset="UTF-8" />',
      `<meta charset="UTF-8" />\n    <meta http-equiv="Content-Security-Policy" content="${CSP}" />`,
    )
  },
})

// https://vite.dev/config/
export default defineConfig({
  plugins: singleFile
    ? [react(), tailwindcss(), viteSingleFile()]
    : [
        react(),
        tailwindcss(),
        cspPlugin(),
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
        theme_color: '#eef2f5',
        background_color: '#eef2f5',
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

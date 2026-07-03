# LensMood — the AI aesthetic camera

> Turn any photo into a cinematic camera shot.

LensMood is an AI aesthetic camera and lighting simulator. Upload a photo, choose a camera
mood — Disposable, iPhone Flash, 90s Camcorder, Leica Street, GQ Editorial, A24 Still,
Film Noir, Y2K Digicam, Polaroid — and LensMood recreates the lighting, grain, color and
vibe of that camera, right in the browser.

**The hook:** *see what your photo would look like shot on a $7,000 camera.*

## Running it

```bash
npm install
npm run dev      # local dev server
npm run build    # production build → dist/
npm run preview  # serve the production build
```

## What's inside

| Area | Notes |
| --- | --- |
| **Frontend** | React 19 + TypeScript + Vite, Tailwind CSS 4, Framer Motion, React Router |
| **Design system** | White editorial base, violet accent, Fraunces (display serif) + Inter (UI), pill buttons, 24px+ radii, film-grain UI overlay |
| **Filter engine** | `src/lib/engine.ts` — a real canvas pipeline (color pass → smoothing → halation → warmth → tint → flash → faded blacks → vignette → grain → scanlines/timestamp → Polaroid frame → watermark). Previews and exports run through the same code, so WYSIWYG. |
| **Camera styles** | `src/lib/styles.ts` — 9 styles, each a parameter recipe + character flags. Adding a style is adding one object. |
| **Monetization** | Free tier: 5 transformations/month + watermark (tracked in `localStorage`). Creator/Pro/Studio plans with simulated checkout; paid plans export watermark-free, Pro+ in HD. |
| **Virality** | Auto-generated captions per style, share links, Web Share API export to TikTok/Reels, trending/featured badges, weekly featured mood. |

### Swapping in a real AI backend

The "generation" step is intentionally isolated: `Studio.tsx → beginGeneration()` runs the
local engine after a staged progress sequence. To plug in a server-side model, replace the
`renderStyled(...)` call with an API request that returns an image, and keep the slider
re-render path pointed at either the local engine (fast client-side fine-tuning) or the API.

Photos never leave the browser in the current build — a genuine privacy feature worth
keeping in marketing copy even after a backend exists.

### Structure

```
src/
  lib/        styles.ts (style recipes) · engine.ts (canvas pipeline) · store.tsx (app state) · captions.ts
  components/ Nav · Footer · UploadArea · StyleCarousel · AdjustmentPanel ·
              BeforeAfterSlider · ExportPanel · AuthModal · Modal · Logo
  pages/      LandingPage · Studio · PricingPage · Dashboard
  assets/     sample "photos" (hand-built SVG art, safe to replace with real photography)
```

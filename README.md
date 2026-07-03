# LensMood — the AI aesthetic camera

> Turn any photo into a cinematic camera shot.

LensMood is an AI aesthetic camera and lighting simulator. Upload photos or a short clip,
choose a camera mood — Disposable, iPhone Flash, 90s Camcorder, Leica Street, GQ Editorial,
A24 Still, Film Noir, Y2K Digicam, Polaroid — and LensMood recreates the lighting, grain,
color and vibe of that camera, right on the device.

**The hook:** *see what your photo would look like shot on a $7,000 camera.*

## Run the web app

```bash
npm install
npm run dev      # local dev server
npm run build    # production build → dist/
npm run preview  # serve the production build
```

The build is a full **PWA** — open it in Safari on an iPhone, hit *Share → Add to Home
Screen*, and it installs with the LensMood icon, splash-free standalone chrome, and offline
asset caching.

## Run the iOS app (Capacitor)

The repo ships a native iOS shell in `ios/` (Capacitor 8, Swift Package Manager — no
CocoaPods needed). On a Mac with Xcode:

```bash
npm install
npm run build
npx cap sync ios     # copies dist/ into the native shell + wires plugins
npx cap open ios     # opens Xcode — pick your team, then Run on a device/simulator
```

**No Mac? Ship to TestFlight from GitHub Actions instead** — the repo includes a
one-button cloud build pipeline. See [docs/TESTFLIGHT.md](docs/TESTFLIGHT.md) for the
full walkthrough (both the Mac path and the no-Mac path).

Native integrations already wired up in `src/lib/native.ts`:

- **Camera** — "Take a photo" uses the real iOS camera (falls back to `<input capture>` on web)
- **Share sheet** — exports write to the app cache and open the system share sheet
  (Save Image/Video, AirDrop, TikTok, Instagram…)
- **Haptics** — impact feedback on shutter, generation, and export
- **Status bar + splash** — styled to match the app (violet splash, light status bar)
- Permission strings for camera/photo library/microphone are set in `ios/App/App/Info.plist`

## What's inside

| Area | Notes |
| --- | --- |
| **Frontend** | React 19 + TypeScript + Vite, Tailwind CSS 4, Framer Motion, React Router, vite-plugin-pwa |
| **Design system** | White editorial base, violet accent, Fraunces (display serif) + Inter (UI), pill buttons, 24px+ radii, film-grain UI overlay |
| **Filter engine** | `src/lib/engine.ts` — a real canvas pipeline (color pass → smoothing → halation → warmth → tint → flash → faded blacks → vignette → grain → scanlines/timestamp → Polaroid frame → watermark). Previews and exports run through the same code, so WYSIWYG. |
| **Video engine** | `src/lib/video.ts` — plays the clip hidden, re-shoots every frame through the engine onto a canvas (grain animates per-frame), records with MediaRecorder (mp4 on Safari/Chrome, webm fallback), keeps source audio when the platform allows. 30s / 120 MB caps. |
| **Camera styles** | `src/lib/styles.ts` — 9 styles, each a parameter recipe + character flags. Adding a style is adding one object. |
| **Monetization** | Free: 5 transformations/month + watermark. Creator $7 (unlimited, no watermark), Pro $15 (HD, video, batch), Studio $29 — simulated checkout, plan-gated features are real (video upsell, HD exports, watermarks). |
| **Virality** | Auto captions per style, **working style links** (`/studio?style=…&p=…` re-applies the exact look), Web Share export to TikTok/Reels, trending/featured badges, weekly featured mood. |

### Feature map

- Upload: drag & drop, file picker (multi — up to 6 photos become a switchable roll),
  paste-from-clipboard, native camera capture, 3 built-in sample shots
- Studio: live style carousel with previews on *your* media, 7 fine-tune sliders,
  5 quick presets, Original/LensMood/Compare views, draggable before/after slider
- Video: live styled playback (tap to pause), frame-accurate export with progress,
  Pro plan gating with upsell
- Export: save/share via the right mechanism per platform, captions, style links
- Dashboard: history with thumbnails, saved presets (re-appliable), favorites, credit meter

### Swapping in a real AI backend

The "generation" step is isolated in `Studio.tsx → beginGeneration()`. To plug in a
server-side model, replace the `renderStyled(...)` call with an API request that returns an
image, and keep the slider re-render path on the local engine for instant fine-tuning.
Media never leaves the device in the current build — a genuine privacy feature worth keeping
in the marketing copy even after a backend exists.

### Structure

```
src/
  lib/        styles.ts (recipes) · engine.ts (canvas pipeline) · video.ts (clip renderer)
              native.ts (Capacitor bridge) · store.tsx (app state) · captions.ts
  components/ Nav · Footer · UploadArea · StyleCarousel · AdjustmentPanel · VideoPreview ·
              BeforeAfterSlider · ExportPanel · AuthModal · Modal · Logo
  pages/      LandingPage · Studio · PricingPage · Dashboard
  assets/     sample "photos" (hand-built SVG art, safe to replace with real photography)
ios/          Capacitor iOS shell (open with Xcode via `npx cap open ios`)
```

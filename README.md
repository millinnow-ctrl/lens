# LensMood — the AI aesthetic camera (iOS)

> Turn any photo into a cinematic camera shot.

LensMood is a native **iOS** app. Pick a photo or a short clip, choose a camera
mood — Disposable, iPhone Flash, 90s Camcorder, Leica Street, GQ Editorial, A24
Still, Film Noir, Y2K Digicam, Polaroid and more — and LensMood recreates the
lighting, grain, color and vibe of that camera, entirely on the device.

**The hook:** *see what your photo would look like shot on a $7,000 camera.*

This is an **iOS-native-only** app built with **Expo (React Native) + Skia**.
The whole app lives in [`lensmood-native/`](lensmood-native/). (There is no web
build — the old Vite/Capacitor web app was removed to keep a single, clear
target.)

## Run it

```bash
cd lensmood-native
npm install
npx expo start            # scan the QR with Expo Go, or press i for a simulator
```

For the full native modules (Skia render, camera, IAP), use a dev build:

```bash
npm i -g eas-cli
eas login
eas init                  # links the Expo project (writes extra.eas.projectId)
eas build --profile development --platform ios
```

## Ship to TestFlight

```bash
eas build --platform ios --profile production --auto-submit
```

Or push a `v*` tag / run the **TestFlight** GitHub Action, which does the same on
Expo's cloud (needs an `EXPO_TOKEN` repo secret). See
[docs/TESTFLIGHT.md](docs/TESTFLIGHT.md).

## What's inside

| Area | Notes |
| --- | --- |
| **Stack** | Expo Router, React Native, `@shopify/react-native-skia`, Reanimated, expo-camera, expo-video, react-native-purchases (IAP) |
| **Render engine** | `lensmood-native/src/engine/engine.ts` — a Skia pipeline (color → smoothing → halation → relight → tone curves → grain → optics → frame). Previews and exports run through the same code, so WYSIWYG. |
| **Camera styles** | `lensmood-native/src/engine/styles.ts` — each stock is a parameter recipe + character flags. |
| **Recognition** | `lensmood-native/src/engine/focal.ts` — on-device subject/face finder that drives metering, relight and depth (no network, no per-use cost). |
| **Print Room** | `lensmood-native/app/print.tsx` + `src/print/` — develop a shot as a real instant photo and photograph it on a surface (bird's-eye template). |
| **Screens** | `lensmood-native/app/` — `index` (home), `camera`, `develop`, `gallery`, `account`, `paywall`, `print`. |

### Structure

```
lensmood-native/
  app/          expo-router screens (index, camera, develop, gallery, account, paywall, print)
  src/
    engine/     styles.ts (recipes) · engine.ts (Skia pipeline) · focal.ts (subject finder) · types.ts
    print/      scenes.ts · compose.ts (Print Room composite)
    components/ dock, sliders, developing print, shared UI
    store/      app state (history, credits, entitlements)
  assets/       icons, splash, scene plates, sample shots
  app.json      Expo config (bundle id app.lensmood.native)
  eas.json      EAS build/submit profiles
```

Media never leaves the device — a genuine privacy feature worth keeping in the
marketing copy.

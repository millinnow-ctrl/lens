# LensMood (native)

Native React Native (Expo + TypeScript + expo-router + @shopify/react-native-skia)
reimplementation of LensMood. Reimplements the HTML-Canvas develop pipeline on
GPU-backed Skia. The web app (Vite/React-DOM/Capacitor) is untouched.

## Run (Mac only — nobody compiles iOS in CI)

```bash
cd lensmood-native
npm install
npx expo install --fix   # reconcile any patch drift to the SDK 54 lockfile
npx expo run:ios         # builds the dev client + launches the simulator
# note: react-native-skia is a native module — plain Expo Go will NOT work;
# use `expo run:ios` (or a custom dev client / EAS build) instead
```

Skia 2.x requires the New Architecture (`newArchEnabled: true`, already set).

## Milestone 1 scope

Pick photo → choose style → develop (Skia) → before/after → export.

- **Ocean theme** — `src/theme/colors.ts` + `typography.ts` (ported from the
  web `@theme`).
- **18 camera styles** — `src/engine/styles.ts` (data), unchanged from web.
- **Adaptive lens meter** — `src/engine/scene.ts` (Skia pixel readback).
- **Develop engine** — `src/engine/engine.ts` (Skia offscreen surface port of
  the Canvas 2D pipeline). Returns `DevelopResult` (a cached JPEG file URI).
- **Flow** — `app/index.tsx` → `app/styles.tsx` → `app/develop.tsx` →
  `app/result.tsx`.

## Architecture

```
lensmood-native/
  app/                      # expo-router (file-based routes, headers hidden)
    _layout.tsx             # Stack root · ocean theme · gesture + safe-area
    index.tsx               # Home — pick photo / shoot (Agent: screens)
    styles.tsx              # 18-style chooser grid (Agent: screens)
    develop.tsx             # develop progress → runs the engine (Agent: screens)
    result.tsx              # before/after compare + export (Agent: screens)
  src/
    engine/
      types.ts              # SHARED types — everything imports this
      styles.ts             # 18 styles + presets (Agent: engine)
      scene.ts              # scene analysis on a Skia thumbnail (Agent: engine)
      engine.ts             # Skia develop pipeline (Agent: engine)
      focal.ts              # Focal helper (M1: no-op stub, no face model)
    theme/
      colors.ts             # OCEAN palette tokens
      typography.ts         # font + weight tokens
    components/
      Logo.tsx              # vector mark, ported to react-native-svg (Agent: ui)
    state/
      session.ts            # picked photo + chosen style (M1: in-memory) (Agent: screens)
  assets/                   # icon.png · splash-icon.png · adaptive-icon.png
```

### Import convention

All cross-module imports go through the `@/*` alias → `./src/*`
(configured in `tsconfig.json`, resolved by Metro):

```ts
import { CameraStyle, StyleParams, DevelopResult } from '@/engine/types'
import { CAMERA_STYLES, getStyle } from '@/engine/styles'
import { renderStyled } from '@/engine/engine'
import { colors } from '@/theme/colors'
import { Logo } from '@/components/Logo'
```

Routes in `app/` import from `@/…`; nothing in `src/` imports from `app/`.
`src/engine/types.ts` stays dependency-free so `styles.ts` and `scene.ts`
never pull in Skia.

## Deferred — OUT of scope for M1 (do not implement yet)

- StoreKit / RevenueCat subscriptions & paywall (all 18 styles unlocked in M1)
- Video capture / develop (the engine's `animateGrain` path is stubbed)
- The 3D mood carousel
- Deep-link recipes (`encodeParams`/`decodeParams` ported but unrouted)
- Dashboard / history sync (develops are ephemeral in M1)
- On-device face detection (MediaPipe BlazeFace) — `focal.ts` returns `null`;
  the engine's focal-gated passes (DOF, face metering) simply stay off.

## Version pins (verified July 2026)

Targets **Expo SDK 54** (RN 0.81 / React 19.1) — the most documented pairing
with **@shopify/react-native-skia 2.2.3** (Skia's Expo-locked pin for SDK 54).
New Architecture is on. SDK 56 (RN 0.85) is a clean future upgrade; run
`npx expo install expo@^56 --fix` when ready.

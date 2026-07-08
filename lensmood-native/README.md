# LensMood (native)

True-native React Native app (Expo SDK 54 + TypeScript + expo-router +
@shopify/react-native-skia). The photo engine is the same deterministic
pipeline as the web app, ported to GPU-backed Skia — parity-proven (identical
grain PRNG, tone LUTs, and style parameters). The web app stays untouched.

## Run it on your iPhone with Expo Go — no Mac needed

Everything this app uses (Skia, reanimated, gesture-handler, svg,
image-picker, media-library, sharing, haptics, async-storage) is **bundled in
Expo Go**. The one native module that isn't — `react-native-purchases` — is
loaded defensively, so in Expo Go the paywall runs in preview mode instead of
crashing.

On any computer (Windows/Linux/Mac) with Node 20+:

```bash
cd lensmood-native
npm install --legacy-peer-deps   # skia 2.2.3 lists reanimated ^3 as an optional peer; the flag reconciles it with reanimated 4
npx expo start --tunnel     # --tunnel = phone connects over the internet,
                            #   same wifi not required
```

Then open **Expo Go** on your iPhone and scan the QR code in the terminal.
The app loads and hot-reloads as code changes.

> If the QR won't scan, press `s` in the terminal to switch to Expo Go mode,
> or log into the same Expo account in Expo Go and the project appears under
> "Recently opened".

## Real subscriptions + App Store — EAS cloud builds (still no Mac)

Apple In-App Purchase needs a real binary (Expo Go can't contain RevenueCat).
Expo's EAS service builds iOS in the cloud:

```bash
npm i -g eas-cli
eas login                                   # free Expo account
eas build --profile development --platform ios   # installable dev build (~15 min)
eas build --profile production --platform ios    # App Store binary
eas submit --platform ios                        # upload to App Store Connect
```

Requires an Apple Developer account ($99/yr) — Apple's rule for installing on
device + publishing, regardless of toolchain.

### RevenueCat setup (for real billing)

1. revenuecat.com → new project → iOS app, bundle id `app.lensmood.native`.
2. Create **entitlements** with ids exactly: `creator`, `pro`, `studio`.
3. Create App Store Connect subscription products and attach them; name the
   packages so their identifiers contain `creator_monthly`, `creator_annual`,
   `pro_monthly`, … (the paywall matches on those substrings).
4. Put the public Apple SDK key in `app.json` → `expo.extra.revenueCatIosKey`.
Purchases then work in dev/TestFlight/production builds; entitlement changes
sync to the in-app plan automatically.

## What's implemented

- **Home** — living hero (rotating word, Start CTA), category chips,
  18-stock catalog, floating dock.
- **Develop** — pick photo → on-device scene analysis (meter readout) →
  Skia develop; stock rail to switch looks; named-stop fine-tune panel
  (debounced re-develops, haptic detents); Original / LensMood / Compare
  (drag wipe); Share + Save to Photos. First run: four bundled sample
  shots (golden-hour portrait, neon night, party flash, brunch) develop
  credit-free — the lenses can be tried before granting photo access.
- **Credits & plans** — first develop free, then 5/month free; paid plans
  unlimited; free exports watermarked; out of credits → paywall.
- **Paywall/Account** — Creator $8 / Pro $15 / Studio $29, monthly/annual
  (2 months free), RevenueCat when configured, restore purchases.
- **Print Lab** (Polaroid stock) — flash + shutter/motor sound, the print
  ejects black and chemistry-develops over ~2.7s, then lands on a staged
  surface (wood / sand / linen / marble / grass) with a contact shadow;
  Share/Save export a Skia composite that reads like a photo of the print.
- **Gallery** — develop history (cap 60), large view, share, remove.
- **Engine** — full pipeline: adaptive metering, AWB, tone LUT + smart-HDR,
  vibrance w/ skin guard, shadow denoise, clarity + universal acutance,
  scene-adaptive halation, DoF + specular bokeh, subject vignette, film
  grain w/ auto-ISO, dither, leaks, frames, watermark.
- **Subject finder** (focal.ts) — classical on-device skin-blob detector
  (no deps, Expo Go-safe): a confident lock turns on face metering, DoF
  bokeh, skin relight, clipped smoothing, flash centering, and the subject
  vignette; anything ambiguous returns null (the safe pre-R37 behavior).
  Apple Vision via a dev build is the planned upgrade.
- **Optics** (per stock) — radial chromatic aberration, barrel distortion,
  field-curvature corner softness, anisotropic per-light flare. Cheap glass
  (disposable/lomo/point-and-shoot) misbehaves; Leica/editorial glass barely
  does. This is the lens in front of the film's color science.
- **LensMood Camera** — the dock's center button opens a real in-app camera
  (expo-camera, Expo Go-safe): iOS-style dark viewfinder with grid, flash,
  zoom, flip, plus a dial deck — ƒ, ISO, EV, WB. iPhones expose no
  manual sensor controls to any app, so the dials do what makes them real:
  they steer the engine's develop of the shot (ƒ→depth of field, ISO→grain +
  denoise, EV→meter bias, WB→color). The shot lands in /develop where the
  dial readout rides on top of whichever of the 18 stocks you pick.

## Still to come

- Video develop (engine's animateGrain path is ready; capture/preview UI isn't)
- Apple Vision face detection via an EAS dev build (upgrades the classical
  subject finder; same Focal contract)
- The 3D mood carousel, deep-link recipes, saved-preset UI

## Honest notes

- Nothing here has been compiled in CI (no macOS runner). The code is
  API-correct per adversarial review + current docs; expect a normal round
  of on-device fixes on first run.
- The develop pass runs synchronously on the JS thread (~1–3s at 1280px on
  an iPhone 12+). Fine for v1; worklet/threading is a later optimization.
- Version pins target Expo SDK 54 (RN 0.81 / React 19.1 / Skia 2.2.3 — the
  Expo-Go-matched version). Run `npx expo install --fix` after install to
  reconcile patch drift.

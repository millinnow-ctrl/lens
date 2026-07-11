# How to test LensMood — accurate paths

This corrects two earlier over-broad claims. Verified against the actual
dependency list and source in `lensmood-native/`.

## What runs in standard Expo Go

React Native Skia **is** bundled in Expo Go (SDK 54), so the film engine runs.
Confirmed working in Expo Go:

- Home, the 18-lens case, navigation
- **Develop** — all 18 looks render through the real Skia engine
- **Print Room** — the bird's-eye Polaroid composite
- **Camcorder live preview** — a clip plays back through the VHS look
  (grade, grain, timecode) on the GPU
- Camera, photo picking, video playback, gallery, sharing
- Reanimated animations, gestures, SVG

## What needs a custom development build (not the framework — specific modules)

Three things use native code that Expo Go does not contain. Each is written to
**degrade gracefully** — the app does not crash in Expo Go; only these specific
features are inert:

| Feature | Module | Behavior in Expo Go |
| --- | --- | --- |
| Save a camcorder tape to a video file | `modules/vhs-export` (Swift/AVFoundation) | Preview still plays; the Save button shows "needs the full build" (`vhsExportAvailable === false`) |
| On-device Apple Vision face/subject detection | `modules/lensmood-vision` (Swift/Vision) | Silently falls back to the built-in heuristic subject finder (`visionAvailable === false`) — develops still work |
| Real in-app purchases | `react-native-purchases` (RevenueCat) | Runs in mock/Preview mode; the paywall explains it needs a real build (`purchasesAvailable() === false`) |

So: **the whole app is explorable in Expo Go**; a custom **development build**
(`eas build --profile development`) is only required to test tape *export*, real
Vision, and real purchases.

## Apple testing matrix (accurate)

| Path | Apple account | Mac needed? | What it gives you |
| --- | --- | --- | --- |
| **Expo Go** | none | no | Everything above except the 3 native features |
| **Custom dev build via Xcode + free provisioning** | free Apple ID | **yes (Mac + Xcode)** | Full app incl. Vision + tape export, installed on your own device. 7-day signing, re-sign weekly. IAP still won't complete without the paid program. |
| **Custom dev build via EAS internal distribution** | **paid ($99)** | no | Full app to your device over the air (ad-hoc provisioning requires the paid program) |
| **TestFlight** | **paid ($99)** | no | Beta distribution to yourself/testers, 90-day builds |
| **In-app purchase testing (StoreKit sandbox)** | **paid ($99)** | no | Requires App Store Connect, which requires the paid program |
| **App Store release** | **paid ($99)** | no | Public launch |

### What this means for *your* setup (Windows, iPhone, no Mac)

- **Expo Go**: works today, free — the main way to see the app now.
- **Free Xcode direct-install**: not available to you, because Xcode is macOS-only.
- **Full features on your iPhone** (tape export / Vision / purchases): needs a
  custom dev build, and from Windows that means EAS, which needs the **paid $99**
  account (ad-hoc/TestFlight). If you had a Mac, the free Apple ID path would work.
- The **$99 is required anyway** for App Store launch and for testing purchases.

## SwiftUI app (`LensMoodApp/`)

Separate track. Compiles on the SwiftUI CI (cloud Mac, unsigned) on every push.
To run on a device it follows the same Apple matrix above once it's far enough
along.

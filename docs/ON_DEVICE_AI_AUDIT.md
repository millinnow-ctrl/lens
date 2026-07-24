# LensMood — On-Device Image Pipeline Technical Audit (R60)

Scope: `LensMoodApp/` (the shipping SwiftUI product). Every claim is grounded in
code; `lensmood-native/` (frozen RN reference) and `reference/` (Node golden
toolchain) are out of scope. This is Deliverable #1 of the on-device-AI mandate
and the baseline the R60 architecture builds on.

## 1. Stack
- **SwiftUI-first**, minimal UIKit (only `UIImage`/`UIGraphicsImageRenderer`/
  haptics + two `UIViewRepresentable` bridges: `CameraPreviewView`, pickers).
- **iOS 16.0** target, Swift 5.9, iPhone-only, portrait-only (`project.yml`).
- Built with **XcodeGen**; CI = GitHub Actions `swiftui-ci.yml` on `macos-15`
  (`xcodegen` → `xcodebuild build`/test). Simulator only — **no real-device
  perf signal in CI**.

## 2. Navigation / IA
- One `TabView`, 5 tags (`AppTab`): Cameras (Home), Capture, Library, Print,
  Tape. Native tab bar hidden; custom floating `OceanDock` via
  `safeAreaInset`. Account is a sheet. `DevelopView` pushed in a stack.

## 3. FilmEngine (`Sources/Engine/FilmEngine.swift`)
- **Single shared instance** `FilmEngine.shared`; **one `CIContext`** (sRGB
  working+output, `cacheIntermediates: true`, `useSoftwareRenderer: false` →
  **GPU/Metal-backed** via Core Image's Metal backend; no hand-written `.metal`).
- Render ladder (in order): decode+orient → scene analysis (96px thumb) →
  optional Vision subject/face/mask → optional Lanczos downscale → reference
  geometry (barrel/CA warp) → **color core (branch on `engineClass`)** → acutance
  + corner softness → face protection → mono pass → bloom → vignette+grain →
  capture-look physical pass → mono invariant → instant-frame composite →
  rasterize to `CGImage`→`UIImage`. Custom CIKernels compiled once in `init`.

## 4. Core Image / Metal / LUTs
- Pure **Core Image** (CIFilters + custom CIKernels); GPU via CI's Metal backend.
- **LUTLoader**: 33³ cubes, Float32 RGBA, mmap'd + `NSLock`-cached `Data`,
  applied via `CIColorCube`.
- **10 `.staticLUT`** (leica-street, gq-editorial, a24-still, film-noir,
  polaroid, super-8, kodachrome, pastel-cinema, tokyo-neon, tintype) +
  **8 `.adaptive`** (disposable, iphone-flash, camcorder-90s, y2k-digicam, lomo,
  security-cam, point-shoot, photobooth).

## 5. Preview vs export — THE key finding
- **Same engine, same code path.** The only difference is `maxPixelSize`:
  preview caps at **2048**, export at **4096** (comment: 4096 keeps peak memory
  under jetsam on 2–3 GB devices). There is **no proxy/tile/low-res preview
  pipeline** and the preview render is **not reused** at export — the full
  pipeline runs a second time on save. Every lens switch re-develops the whole
  image. → This is the dominant latency/UX bottleneck (R60-5 target).

## 6. Resolutions per stage
- Decode: full-res `UIImage` (no decode-time downsample).
- Downsample: only inside `FilmEngine.scaled` (Lanczos) when `maxPixelSize` set.
- Scene analysis: ≤96px thumb. Golden tests: 560px. Library persist: ≤2048 JPEG.
- Net: preview ≤2048px, export ≤4096px longest edge.

## 7. CIContext
- **Exactly one** constructed (in `FilmEngine.init`), shared into `SceneAnalyzer`.
  Production uses the singleton. Tests instantiate `FilmEngine()` directly (fresh
  context each) — the class does not *enforce* reuse (a footgun).

## 8. Caching
- **No `NSCache`, no `autoreleasepool` anywhere.** Only caches: `LUTLoader` cube
  `Data` + CI's internal intermediates. **No render/preview/mask cache** — Vision
  masks and the per-pixel Float32 reference-grain buffer are recomputed every
  develop.

## 9. Concurrency & cancellation
- Develop/save on `DispatchQueue.global(.userInitiated)` → hop to main.
- **Stale-render handling is result-discard, not cancellation**: a UUID token is
  compared on completion and a stale result is dropped, but the in-flight CI
  render still runs to completion. Rapid lens switches queue N full renders. No
  `actor`, no `Task` cancellation, no serialized render queue.

## 10. Memory / buffers
- `UIGraphicsImageRenderer` for strength blend, library downscale, tests.
- **No `autoreleasepool`** around renders; **no device-tier memory sizing** —
  fixed 2048/4096 magic caps identical across all hardware. Reference-grain
  allocates a full-res `[Float32]` (w·h·4) CPU buffer per render for LUT stocks.

## 11. Parity / golden tests (`Tests/FilmEngineTests.swift`)
- **MAE gate** (0–255) with a per-camera `maeRegressionCeiling` dict
  (regression-only). Only kodachrome meets the ≤2.0 target; others carry higher
  CI-measured ceilings. Golden fixtures at `Tests/Fixtures/golden-<id>.png`,
  rendered at 560px. Also: determinism, catalog counts, adaptive distinctness,
  and copy-hygiene (bans "AI"/brand terms in source).

## 12. Vision / ML
- **Apple Vision only**: `VNDetectFaceRectanglesRequest` (always) +
  `VNGeneratePersonSegmentationRequest` (opt-in). Feeds face protection + DoF/
  relight. **Zero Core ML** — no `.mlmodel`/`.mlpackage` ships. Confirmed.

## 13. StoreKit
- **StoreKit 2**, `@MainActor`. `EVERYTHING_FREE_FOR_NOW`: `isPro=true`, gates
  nothing; `refreshEntitlements` computes ownership but discards it.

## 14. Analytics
- Enum event taxonomy, snake_case, **non-identifying properties only**. Default
  sink is **no-op** (DEBUG print). No backend, no networking, no content.

## 15. Networking
- **None today.** Only `URL(string:)` values are paywall Terms/Privacy `Link`s,
  never fetched. (This changes under the new mandate: a LensMood-owned model/
  content-delivery seam is added — but still no third-party per-image inference.)

## 16. Security / privacy
- **No hardcoded secrets.** `PrivacyInfo.xcprivacy` present: no tracking, no
  collection, on-device. Photos: add-only usage string.

## 17. Top weaknesses for on-device-AI evolution
1. **Single full-pipeline render path — no proxy previews.** Every interaction
   re-develops the whole image; preview≠reused at export. (R60-5)
2. **No render/mask caching** — Vision + grain recomputed each develop. (R60-4/5)
3. **No true cancellation** — result-discard only; rapid switches run N full
   renders. (R60-5)
4. **No device tiering / adaptive memory budget** — hardcoded 2048/4096 caps,
   no `autoreleasepool`. (R60-2)
5. **Parity aspirational + heavyweight harness** — one 560px fixture, fresh
   `CIContext` per test; MAE-only. (R60-6)

## How R60 responds
| Weakness | R60 batch |
|---|---|
| Single render path, no proxy | R60-5 progressive previews + caching |
| No mask cache | R60-4 SegmentationService (precompute once/photo) |
| No cancellation | R60-5 (structured concurrency + cancel on switch) |
| No device tiers | R60-2 DeviceCapabilityProfile |
| MAE-only, one fixture | R60-6 SSIM/histogram/skin-delta + diverse fixtures |
| No model delivery | R60-3 ModelRegistry/Download/Verify/Install/Storage |
| No learned layer | R60-8 hero-Lens POC + RefinementService (fallback-safe) |
| Loose schema (3 split types) | R60-1 unified `Lens` schema ✅ (this batch) |

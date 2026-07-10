# FilmEngine — the Swift port of the LensMood film engine

The reference implementation is `lensmood-native/src/engine/engine.ts` (and its
byte-parity web twin, recoverable at git `88753c3:src/lib/engine.ts`). That
engine is the ground truth: 18 stocks, scene-adaptive metering, relight,
optics, grain. The Swift engine must match it visually, verified by fixtures.

## Architecture (Stage 2)

1. **Per-stock color core → 3D LUTs.** Every stock's pure color math (tone
   curves, color matrix, split tone, saturation, DMax floor) is baked to a
   33³ LUT by running the reference engine in Node
   (`reference/` harness). LUTs ship as app resources and apply via
   `CIColorCube`. This gives bit-faithful color with zero re-implementation
   drift — the same pattern already proven by the camcorder exporter
   (`lensmood-native/modules/vhs-export`).

2. **Spatial passes → Metal / Core Image kernels.** What a LUT can't encode:
   - grain (hash-based, per-stock size/amp/chroma)
   - halation / bloom around highlights
   - optics: chromatic aberration, barrel distortion, corner softness, vignette
   - relight (subject-aware key/fill from the Vision mask)
   - frames (Polaroid card), timestamps (Y2K), scanlines (security cam)
   Each is one small CIKernel (Metal Shading Language), parameterized per
   stock from a generated `StockRecipes.swift`.

3. **Recognition → Vision framework, direct.** `VNDetectFaceRectanglesRequest`
   + `VNGeneratePersonSegmentationRequest`, no bridge — the Swift module in
   `lensmood-native/modules/lensmood-vision` is the porting reference.

4. **Scene metering.** `analyzeScene` (histogram key/warmth/lights) ports 1:1
   from `scene.ts` — pure math over a downscaled thumb, unit-testable.

## Verification

- Fixtures: `reference/` renders sample photos through the reference engine
  (already used for the in-chat previews). XCTests render the same photos
  through FilmEngine and assert per-channel mean/percentile deltas within
  tolerance. Runs on the macOS CI (no signing, no device needed).
- The camcorder video path reuses `VhsExporter` (LUT + grain + flicker +
  timecode over AVFoundation) — that Swift is already written.

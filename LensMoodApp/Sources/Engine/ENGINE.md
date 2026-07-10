# FilmEngine — the Swift port of the LensMood film engine

Ground truth: `lensmood-native/src/engine/engine.ts` (recoverable web twin at git
`50e885d^:src/lib/engine.ts`), preserved on the `react-native-reference-complete`
branch. The Swift engine must match it visually, verified by fixtures.

## Stage 2a measured finding (this is real, from `reference/lutbake.cjs`)

We baked each stock's per-pixel color core to a 33³ LUT and measured how well a
static LUT reproduces the reference color response on real photos (Node, no Mac).
Result — the 18 stocks split cleanly into two engine classes:

**Class A — static color (LUT-sufficient), 10 stocks.** A single `CIColorCube`
LUT reproduces the color core with < 8/255 mean error (mostly < 5):
kodachrome (3.3), a24-still (3.8), film-noir (4.7), pastel-cinema (1.9),
tokyo-neon (4.1), leica-street (5.0), polaroid (6.1), tintype (6.5),
super-8 (7.0), gq-editorial (7.7).
→ Their LUTs are baked and shipped in `Resources/luts/*.lut` (float32 RGBA,
r-fastest, ready for `CIColorCube`). Color port = load LUT, done. Zero drift.

**Class B — image-adaptive color, 8 stocks.** A static LUT does NOT reproduce
these (12–72/255 error) because their color transform depends on the whole
image — auto-exposure / AGC / auto-white-balance / adaptive tone:
security-cam (72), camcorder-90s (68), lomo (22), iphone-flash (20),
photobooth (16), y2k-digicam (16), point-shoot (15), disposable (13).
→ These need a **parameterized** path: compute the per-image statistic first
(the ported scene meter), then apply the transform with that parameter — not a
frozen cube. This is exactly why the app's looks are "smart," and it's the real
engineering in Stage 2a. Their spatial effects (chroma-bleed, interlace, grain,
edge-fringe) become CIKernels on top.

## Architecture

1. **Class A color:** `CIColorCube` + the baked `.lut`. Verified zero-drift.
2. **Class B color:** port `scene.ts` metering → a scalar/vector, feed a
   parameterized Core Image graph (exposure/gain/awb) per stock.
3. **Spatial passes (all stocks):** grain, halation, optics (CA/barrel/corner/
   vignette), relight, frames — small CIKernels (Metal Shading Language only
   where a stock CIFilter can't express it; several are plain `CIColorKernel`).
4. **Recognition:** Vision directly (`VNDetectFaceRectangles` +
   `VNGeneratePersonSegmentation`) — port of `modules/lensmood-vision`.
5. **Video:** reuse `modules/vhs-export` Swift (already written).

## Verification

- `reference/` renders the reference engine headless (@napi-rs/canvas) to
  produce golden fixtures. XCTests render the same inputs through FilmEngine and
  assert per-channel mean + perceptual deltas within tolerance, on the macOS CI.
- A stock is "done" only when it passes the fixture test **and** owner visual
  sign-off — never merely because it compiles.

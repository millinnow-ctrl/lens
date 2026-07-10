/**
 * The camcorder tape look — ONE fixed, deterministic grade (no AI, no params).
 * `vhsGrade` is the source of truth: the live preview shader (VHS_SKSL) mirrors
 * its math line for line, and `buildVhsLut` bakes it into a CIColorCube LUT so
 * the native exporter writes exactly what the preview showed.
 *
 * The recipe is the camcorder-90s stock's fixed color core: slight desaturation,
 * the tape color matrix, smoky lifted blacks, and a teal-shadow / cream-highlight
 * split tone. Grain, chroma bleed, vignette and the counting timecode are
 * applied outside the LUT (shader live, CIFilters on export).
 */

/** grade one RGB pixel, all channels 0..1 — the single source of truth */
export function vhsGrade(r: number, g: number, b: number): [number, number, number] {
  // 1 — tape never held full saturation
  const l = 0.299 * r + 0.587 * g + 0.114 * b
  r = l + (r - l) * 0.85
  g = l + (g - l) * 0.85
  b = l + (b - l) * 0.85
  // 2 — the camcorder color matrix (muted red, cross-fed green, dull blue)
  const mr = 0.92 * r + 0.1 * g - 0.02 * b
  const mg = 0.03 * r + 1.0 * g - 0.03 * b
  const mb = 0.02 * r + 0.1 * g + 0.88 * b
  // 3 — smoky lifted blacks, gently compressed range
  let or_ = 0.045 + mr * 0.93
  let og = 0.045 + mg * 0.93
  let ob = 0.045 + mb * 0.93
  // 4 — split tone, luminance-preserving: teal cast in shadows, cream in highlights
  const lm = 0.299 * or_ + 0.587 * og + 0.114 * ob
  const sw = (1 - lm) * 0.55
  const hw = lm * 0.5
  or_ += -0.065 * sw + 0.045 * hw
  og += 0.033 * sw + -0.026 * hw
  ob += 0.002 * sw + 0.017 * hw
  const clamp = (v: number) => (v < 0 ? 0 : v > 1 ? 1 : v)
  return [clamp(or_), clamp(og), clamp(ob)]
}

/**
 * Bake the grade into a CIColorCube table (RGBA float32, blue-major order per
 * Apple's spec), base64-encoded for the bridge. 33³ is Core Image's sweet spot.
 */
export function buildVhsLut(dim = 33): { data: string; dim: number } {
  const floats = new Float32Array(dim * dim * dim * 4)
  let i = 0
  for (let bi = 0; bi < dim; bi++) {
    for (let gi = 0; gi < dim; gi++) {
      for (let ri = 0; ri < dim; ri++) {
        const [r, g, b] = vhsGrade(ri / (dim - 1), gi / (dim - 1), bi / (dim - 1))
        floats[i++] = r
        floats[i++] = g
        floats[i++] = b
        floats[i++] = 1
      }
    }
  }
  return { data: base64FromBytes(new Uint8Array(floats.buffer)), dim }
}

/** minimal base64 (no Buffer in React Native) */
function base64FromBytes(bytes: Uint8Array): string {
  const ABC = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  let out = ''
  for (let i = 0; i < bytes.length; i += 3) {
    const b0 = bytes[i]
    const b1 = i + 1 < bytes.length ? bytes[i + 1] : 0
    const b2 = i + 2 < bytes.length ? bytes[i + 2] : 0
    out += ABC[b0 >> 2]
    out += ABC[((b0 & 3) << 4) | (b1 >> 4)]
    out += i + 1 < bytes.length ? ABC[((b1 & 15) << 2) | (b2 >> 6)] : '='
    out += i + 2 < bytes.length ? ABC[b2 & 63] : '='
  }
  return out
}

/**
 * The live-preview shader: video frame → chroma bleed → the SAME grade as
 * vhsGrade above → tape grain → vignette. Runs per-pixel on the GPU while the
 * clip plays; `t` is playback seconds (drives grain refresh at ~30Hz).
 */
export const VHS_SKSL = `
uniform shader video;
uniform float t;
uniform float2 res;

half3 grade(half3 c) {
  half l = dot(c, half3(0.299, 0.587, 0.114));
  c = mix(half3(l), c, half(0.85));
  half3 m;
  m.r = 0.92 * c.r + 0.10 * c.g - 0.02 * c.b;
  m.g = 0.03 * c.r + 1.00 * c.g - 0.03 * c.b;
  m.b = 0.02 * c.r + 0.10 * c.g + 0.88 * c.b;
  m = half3(0.045) + m * 0.93;
  half lm = dot(m, half3(0.299, 0.587, 0.114));
  half sw = (1.0 - lm) * 0.55;
  half hw = lm * 0.5;
  m += half3(-0.065, 0.033, 0.002) * sw;
  m += half3(0.045, -0.026, 0.017) * hw;
  return clamp(m, 0.0, 1.0);
}

half4 main(float2 xy) {
  half4 c = video.eval(xy);
  // chroma bleed: red smears a couple of pixels right, like composite video
  c.r = video.eval(xy + float2(2.2, 0.0)).r;
  half3 m = grade(c.rgb);
  // heavy tape grain, refreshed slowly (~12x/sec) so the noise crawls like
  // worn tape instead of shimmering like digital noise
  float2 cell = floor(xy / 2.0) + floor(t * 12.0) * 7.31;
  float n = fract(sin(dot(cell, float2(12.9898, 78.233))) * 43758.5453);
  m += (half(n) - 0.5) * 0.10;
  // slow AGC flicker — the deck hunting for exposure, a lazy breathing pump
  m *= half(1.0 + 0.035 * sin(t * 2.4) * (0.6 + 0.4 * sin(t * 0.7)));
  // gentle tube vignette
  float2 uv = xy / res - 0.5;
  m *= 1.0 - dot(uv, uv) * 0.5;
  return half4(clamp(m, 0.0, 1.0), 1.0);
}
`

import CoreImage
import CoreGraphics
import Foundation
import UIKit

/**
 * Scene — the light meter behind the lens (SwiftUI port).
 *
 * One tiny deterministic analysis pass per image (a <=96px downscale) that
 * tells the engine what a real camera's electronics would know about the
 * scene: how bright it is, what color the light is, where the actual light
 * sources sit, and how bright the subject's face is.
 *
 * VERBATIM port of the frozen reference `lensmood-native/src/engine/scene.ts`
 * (owner ruling #2: port the current meter exactly; Scene V2 only after
 * parity). Every pass, constant, and guard matches the reference line for
 * line — diff this file against scene.ts side by side. The only intentional
 * differences are the pixel source (a CoreGraphics downscale instead of a
 * Skia offscreen surface; RGBA / row-major top-down layout is identical) and
 * the throwing Swift call surface the app already uses.
 */

enum SceneAnalysisError: LocalizedError {
  case unreadableImage
  case renderFailed

  var errorDescription: String? {
    switch self {
    case .unreadableImage: return "The photograph could not be decoded."
    case .renderFailed: return "The photograph could not be analyzed."
    }
  }
}

/// the meter's one-word reading of a scene — shown in the studio viewfinder
/// so the person can see the lens thinking. Rule-based, from the profile.
func sceneLabel(_ p: SceneProfile) -> String {
  if !p.analyzed { return "READING" }
  if p.key < 0.1 { return "NIGHT" }
  if let faceLum = p.faceLum, p.key - faceLum > 0.15 { return "BACKLIT" }
  if p.key < 0.26 { return "LOW LIGHT" }
  // cast direction only — the meter can't know tungsten from golden hour,
  // so it says what it actually measured and never guesses wrong
  if p.illum[2] > 1.18 { return "WARM LIGHT" }
  if p.illum[0] > 1.18 { return "COOL LIGHT" }
  if p.sat < 0.1 { return "MUTED" }
  if p.p99 - p.p01 < 0.45 { return "FLAT" }
  return "DAYLIGHT"
}

/// the meter's decisions, spelled out — the lens showing its work.
func sceneNotes(_ p: SceneProfile) -> [String] {
  if !p.analyzed { return [] }
  var notes: [String] = []
  if p.faceLum != nil { notes.append("metered for the face") }
  if p.key < 0.1 {
    notes.append("exposure recovered, ISO pushed")
  } else if p.key < 0.26 {
    notes.append("low light — exposure lifted")
  }
  if let faceLum = p.faceLum, p.key - faceLum > 0.15 { notes.append("backlight — shadows opened") }
  if p.illum[2] > 1.12 || p.illum[0] > 1.12 { notes.append("color cast neutralized") }
  if p.sat < 0.14 { notes.append("muted scene — color recovered") }
  if !p.lights.isEmpty {
    notes.append("\(p.lights.count) light source\(p.lights.count > 1 ? "s" : "") mapped")
  }
  if p.p99 - p.p01 > 0.85 { notes.append("high contrast — highlights guarded") }
  return notes
}

private let THUMB = 96
private let LUMA_R = 0.299
private let LUMA_G = 0.587
private let LUMA_B = 0.114

final class SceneAnalyzer {
  private let context: CIContext

  init(context: CIContext) {
    self.context = context
  }

  /// Analyze a scene. Pure and synchronous — closed-form math on a <=96px
  /// thumb. `focal` mirrors the reference's optional face reading (pass 3);
  /// existing callers pass none, matching the headless fixture harness.
  func analyze(_ image: CIImage, focal: Focal? = nil) throws -> SceneProfile {
    let source = image.orientedForDisplay
    guard !source.extent.isEmpty else { throw SceneAnalysisError.unreadableImage }
    let profile = try analyzeScene(source, focal: focal)
    // a not-yet-decoded frame reads as pure black — don't let it lock the
    // exposure; return neutral now and analyze again next call
    if profile.key < 0.004 && profile.p99 < 0.02 { return .neutral }
    return profile
  }

  /// downscale the source into a THUMB-sized RGBA8 buffer and pull the bytes
  /// back — sRGB, 8-bit, premultiplied-last, top-down row-major. Photographs
  /// are opaque so premultiplication is a no-op and the buffer layout matches
  /// the reference's straight-alpha `getImageData` / `readPixels` exactly.
  ///
  /// The resample is a hand-rolled 4-tap bilinear at destination pixel
  /// centers (s = (d + 0.5) * S/D - 0.5, edge-clamped) — the same sampling
  /// the reference's Skia `drawImage` performs at the canvas default filter
  /// quality. CoreGraphics' own scaler was measured to area-average a 12x
  /// downscale, erasing exactly the noise, speculars, and small light blobs
  /// the meter exists to read (CI parity run 151: p99 low by 0.17 on night,
  /// saturation 0.32 vs 0.51 on the noisy fixture). Doing the arithmetic
  /// ourselves removes the platform resampler from the equation entirely.
  private func thumbPixels(_ source: CIImage, w: Int, h: Int) throws -> [UInt8] {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
      throw SceneAnalysisError.renderFailed
    }
    guard let cgSource = context.createCGImage(
      source,
      from: source.extent,
      format: .RGBA8,
      colorSpace: colorSpace
    ) else {
      throw SceneAnalysisError.renderFailed
    }
    let sw = cgSource.width
    let sh = cgSource.height
    guard sw > 0, sh > 0 else { throw SceneAnalysisError.renderFailed }

    // decode at native size, 1:1 — no resampling happens in this draw
    var src = [UInt8](repeating: 0, count: sw * sh * 4)
    let decoded = src.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) -> Bool in
      guard let cg = CGContext(
        data: buffer.baseAddress,
        width: sw,
        height: sh,
        bitsPerComponent: 8,
        bytesPerRow: sw * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ) else { return false }
      cg.interpolationQuality = .none
      cg.draw(cgSource, in: CGRect(x: 0, y: 0, width: sw, height: sh))
      return true
    }
    guard decoded else { throw SceneAnalysisError.renderFailed }

    var px = [UInt8](repeating: 0, count: w * h * 4)
    let xRatio = Double(sw) / Double(w)
    let yRatio = Double(sh) / Double(h)
    for dy in 0..<h {
      let sy = (Double(dy) + 0.5) * yRatio - 0.5
      let y0 = min(max(Int(sy.rounded(.down)), 0), sh - 1)
      let y1 = min(y0 + 1, sh - 1)
      let fy = min(max(sy - Double(y0), 0), 1)
      for dx in 0..<w {
        let sx = (Double(dx) + 0.5) * xRatio - 0.5
        let x0 = min(max(Int(sx.rounded(.down)), 0), sw - 1)
        let x1 = min(x0 + 1, sw - 1)
        let fx = min(max(sx - Double(x0), 0), 1)
        let i00 = (y0 * sw + x0) * 4
        let i10 = (y0 * sw + x1) * 4
        let i01 = (y1 * sw + x0) * 4
        let i11 = (y1 * sw + x1) * 4
        let out = (dy * w + dx) * 4
        for c in 0..<4 {
          let top = Double(src[i00 + c]) + (Double(src[i10 + c]) - Double(src[i00 + c])) * fx
          let bottom = Double(src[i01 + c]) + (Double(src[i11 + c]) - Double(src[i01 + c])) * fx
          px[out + c] = UInt8(min(255, max(0, (top + (bottom - top) * fy).rounded())))
        }
      }
    }
    return px
  }

  // swiftlint:disable:next function_body_length
  private func analyzeScene(_ source: CIImage, focal: Focal?) throws -> SceneProfile {
    let sw = Double(source.extent.width)
    let sh = Double(source.extent.height)
    guard sw > 0, sh > 0 else { throw SceneAnalysisError.unreadableImage }

    let scale = Double(THUMB) / max(sw, sh)
    let w = max(2, Int((sw * scale).rounded()))
    let h = max(2, Int((sh * scale).rounded()))
    let px = try thumbPixels(source, w: w, h: h)
    let n = w * h

    /* ---- pass 1: luminance stats + shades-of-gray illuminant (p = 6) ---- */
    var hist = [UInt32](repeating: 0, count: 64)
    var logSum = 0.0
    var er = 0.0
    var eg = 0.0
    var eb = 0.0
    var mid = 0
    var satSum = 0.0
    var satCnt = 0
    // Float32, exactly like the reference's Float32Array — the blob pass
    // compares these stored values against a Double threshold below
    var lum = [Float](repeating: 0, count: n)
    for i in 0..<n {
      let r = Double(px[i * 4]) / 255
      let g = Double(px[i * 4 + 1]) / 255
      let b = Double(px[i * 4 + 2]) / 255
      let L = LUMA_R * r + LUMA_G * g + LUMA_B * b
      lum[i] = Float(L)
      logSum += log(max(L, 0.001))
      hist[min(63, Int(L * 64))] += 1
      // saturation census — near-black pixels excluded (their hue is noise)
      let mx = r > g ? (r > b ? r : b) : (g > b ? g : b)
      if mx > 0.06 {
        let mn = r < g ? (r < b ? r : b) : (g < b ? g : b)
        satSum += (mx - mn) / mx
        satCnt += 1
      }
      if L > 0.04 && L < 0.96 {
        // Minkowski p=6 — between gray-world and white-patch; clipped pixels
        // excluded so a blown sky doesn't read as "blue light"
        let r6 = r * r * r
        let g6 = g * g * g
        let b6 = b * b * b
        er += r6 * r6
        eg += g6 * g6
        eb += b6 * b6
        mid += 1
      }
    }
    let key = exp(logSum / Double(n))

    func pct(_ q: Double) -> Double {
      let target = q * Double(n)
      var acc = 0.0
      for bin in 0..<64 {
        acc += Double(hist[bin])
        if acc >= target { return (Double(bin) + 0.5) / 64 }
      }
      return 1
    }
    let p01 = pct(0.01)
    let p50 = pct(0.5)
    let p99 = pct(0.99)

    var illum: [Double] = [1, 1, 1]
    if Double(mid) > Double(n) * 0.05 {
      let mr = pow(er / Double(mid), 1.0 / 6.0)
      let mg = pow(eg / Double(mid), 1.0 / 6.0)
      let mb = pow(eb / Double(mid), 1.0 / 6.0)
      if mr > 0.001 && mg > 0.001 && mb > 0.001 {
        var gr = mg / mr
        var gb = mg / mb
        // luma-preserving: WB must never change exposure (that's the meter's job)
        let lumaGain = LUMA_R * gr + LUMA_G + LUMA_B * gb
        gr /= lumaGain
        gb /= lumaGain
        illum = [gr, 1 / lumaGain, gb]
      }
    }

    /* ---- pass 2: light sources — connected blobs above the specular knee ---- */
    let T = max(0.9, 0.98 * p99)
    var bright = 0
    for i in 0..<n where Double(lum[i]) >= T { bright += 1 }
    var lights: [LightSource] = []
    // >20% of the frame above threshold = ambient brightness (sky, wall), not sources
    if bright > 0 && Double(bright) < Double(n) * 0.2 {
      var label = [Int32](repeating: -1, count: n)
      struct Blob {
        var mass = 0.0
        var sx = 0.0
        var sy = 0.0
        var count = 0
        var peak = 0.0
      }
      var blobs: [Blob] = []
      var stack: [Int] = []
      for i in 0..<n {
        if Double(lum[i]) < T || label[i] != -1 { continue }
        let id = Int32(blobs.count)
        var blob = Blob()
        stack.removeAll(keepingCapacity: true)
        stack.append(i)
        label[i] = id
        while let j = stack.popLast() {
          let jx = j % w
          let jy = j / w
          let Lj = Double(lum[j])
          blob.mass += Lj - T
          if Lj > blob.peak { blob.peak = Lj }
          blob.sx += Double(jx)
          blob.sy += Double(jy)
          blob.count += 1
          if jx > 0, label[j - 1] == -1, Double(lum[j - 1]) >= T { label[j - 1] = id; stack.append(j - 1) }
          if jx < w - 1, label[j + 1] == -1, Double(lum[j + 1]) >= T { label[j + 1] = id; stack.append(j + 1) }
          if jy > 0, label[j - w] == -1, Double(lum[j - w]) >= T { label[j - w] = id; stack.append(j - w) }
          if jy < h - 1, label[j + w] == -1, Double(lum[j + w]) >= T { label[j + w] = id; stack.append(j + w) }
        }
        blobs.append(blob)
      }
      struct Kept {
        var x: Double
        var y: Double
        var rPx: Double
        var peak: Double
        // tint accumulators — filled by the annulus pass below
        var tr = 0.0
        var tg = 0.0
        var tb = 0.0
        var tn = 0
      }
      var kept: [Kept] = blobs.enumerated()
        .filter { $0.element.count >= 2 }
        // the reference leans on Array.sort stability for equal masses;
        // Swift's sort is not guaranteed stable, so ties keep scan order
        .sorted {
          $0.element.mass == $1.element.mass
            ? $0.offset < $1.offset
            : $0.element.mass > $1.element.mass
        }
        .prefix(5)
        .map { entry in
          Kept(
            x: entry.element.sx / Double(entry.element.count),
            y: entry.element.sy / Double(entry.element.count),
            rPx: (Double(entry.element.count) / .pi).squareRoot(),
            peak: entry.element.peak
          )
        }
      /* the light's color lives in the glow ring AROUND the clipped core (the
         core itself reads pure white) — one cheap pass over the near-bright
         band, attributed to the closest blob within reach */
      if !kept.isEmpty {
        let lo = T * 0.6
        for i in 0..<n {
          let L = Double(lum[i])
          if L < lo || L >= T { continue }
          let x = i % w
          let y = i / w
          for k in kept.indices {
            let dx = Double(x) - kept[k].x
            let dy = Double(y) - kept[k].y
            let reach = (kept[k].rPx + 2) * 2.5
            if dx * dx + dy * dy <= reach * reach {
              kept[k].tr += Double(px[i * 4])
              kept[k].tg += Double(px[i * 4 + 1])
              kept[k].tb += Double(px[i * 4 + 2])
              kept[k].tn += 1
              break
            }
          }
        }
      }
      lights = kept.map { k in
        LightSource(
          x: k.x / Double(w),
          y: k.y / Double(h),
          r: k.rPx / Double(max(w, h)),
          intensity: min(1, (k.peak - T) / max(0.02, 1 - T)),
          tint: k.tn > 3
            ? [k.tr / Double(k.tn) / 255, k.tg / Double(k.tn) / 255, k.tb / Double(k.tn) / 255]
            : [1, 0.72, 0.45] // warm default
        )
      }
    }

    /* ---- pass 2b (R63, Swift-only addition): chroma lights ----
       Saturated colored emitters (blue/red neon) whose LUMA never crosses the
       specular knee — pass 2 is blind to them (a blazing pure-blue sign has
       luma ≈ 0.11·B). Same flood-fill structure, thresholded on peak channel
       energy + saturation. Additive `auxLights` field: the reference meter's
       `lights` stays verbatim for the scene-meter parity suite. */
    var auxLights: [LightSource] = []
    do {
      var peak = [Double](repeating: 0, count: n)
      var sat = [Double](repeating: 0, count: n)
      for i in 0..<n {
        let r = Double(px[i * 4]) / 255
        let g = Double(px[i * 4 + 1]) / 255
        let b = Double(px[i * 4 + 2]) / 255
        let mx = max(r, max(g, b))
        let mn = min(r, min(g, b))
        peak[i] = mx
        sat[i] = mx > 1e-4 ? (mx - mn) / mx : 0
      }
      let luT = max(0.9, 0.98 * p99) // pass-2 knee: exclude what it already caught
      var hot = [Bool](repeating: false, count: n)
      var hotCount = 0
      for i in 0..<n where peak[i] >= 0.72 && sat[i] > 0.35 && Double(lum[i]) < luT {
        hot[i] = true
        hotCount += 1
      }
      // ambient guard: a saturated dusk sky is color, not a light source
      if hotCount > 0, Double(hotCount) < Double(n) * 0.12 {
        struct CBlob { var mass = 0.0; var sx = 0.0; var sy = 0.0; var count = 0
                       var pk = 0.0; var tr = 0.0; var tg = 0.0; var tb = 0.0 }
        var label = [Int32](repeating: -1, count: n)
        var blobs: [CBlob] = []
        var stack: [Int] = []
        for i in 0..<n {
          if !hot[i] || label[i] != -1 { continue }
          let id = Int32(blobs.count)
          var blob = CBlob()
          stack.removeAll(keepingCapacity: true)
          stack.append(i)
          label[i] = id
          while let j = stack.popLast() {
            let jx = j % w
            let jy = j / w
            blob.mass += peak[j] - 0.72
            if peak[j] > blob.pk { blob.pk = peak[j] }
            blob.sx += Double(jx); blob.sy += Double(jy); blob.count += 1
            blob.tr += Double(px[j * 4]); blob.tg += Double(px[j * 4 + 1]); blob.tb += Double(px[j * 4 + 2])
            if jx > 0, label[j - 1] == -1, hot[j - 1] { label[j - 1] = id; stack.append(j - 1) }
            if jx < w - 1, label[j + 1] == -1, hot[j + 1] { label[j + 1] = id; stack.append(j + 1) }
            if jy > 0, label[j - w] == -1, hot[j - w] { label[j - w] = id; stack.append(j - w) }
            if jy < h - 1, label[j + w] == -1, hot[j + w] { label[j + w] = id; stack.append(j + w) }
          }
          blobs.append(blob)
        }
        auxLights = blobs
          .filter { $0.count >= 2 }
          .sorted { $0.mass > $1.mass }
          .prefix(5)
          .compactMap { blob in
            let bx = blob.sx / Double(blob.count)
            let by = blob.sy / Double(blob.count)
            // skip anything pass 2 already owns (within 3 thumb px)
            for known in lights {
              let dx = bx - known.x * Double(w)
              let dy = by - known.y * Double(h)
              if dx * dx + dy * dy < 9 { return nil }
            }
            let cnt = Double(blob.count)
            var tint = [blob.tr / cnt / 255, blob.tg / cnt / 255, blob.tb / cnt / 255]
            let m = tint.max() ?? 1
            if m > 1e-4 { tint = tint.map { $0 / m } } // the emitter IS the color
            return LightSource(
              x: bx / Double(w),
              y: by / Double(h),
              r: (cnt / .pi).squareRoot() / Double(max(w, h)),
              intensity: min(1, (blob.pk - 0.72) / 0.28),
              tint: tint
            )
          }
      }
    }

    /* ---- pass 3: face luminance under the focal ellipse ---- */
    var faceLum: Double? = nil
    if let focal {
      let cx = focal.x * Double(w)
      let cy = focal.y * Double(h)
      let rr = max(2, focal.r * Double(max(w, h)))
      var sum = 0.0
      var cnt = 0
      let x0 = max(0, Int(floor(cx - rr)))
      let x1 = min(w - 1, Int(ceil(cx + rr)))
      let y0 = max(0, Int(floor(cy - rr)))
      let y1 = min(h - 1, Int(ceil(cy + rr)))
      // stride(through:) mirrors the reference's `for (y = y0; y <= y1; ...)`
      // — an empty range is a no-op instead of a crash
      for y in stride(from: y0, through: y1, by: 1) {
        for x in stride(from: x0, through: x1, by: 1) {
          let dx = (Double(x) - cx) / rr
          let dy = (Double(y) - cy) / (rr * 1.25) // faces are taller than wide
          if dx * dx + dy * dy <= 1 {
            sum += Double(lum[y * w + x])
            cnt += 1
          }
        }
      }
      if cnt > 4 { faceLum = sum / Double(cnt) }
    }

    let legacy = legacyStats(px: px, n: n)
    return SceneProfile(
      analyzed: true,
      key: key,
      p01: p01,
      p50: p50,
      p99: p99,
      illum: illum,
      sat: Double(satCnt) > Double(n) * 0.05 ? satSum / Double(satCnt) : 0.35,
      lights: lights,
      auxLights: auxLights,
      faceLum: faceLum,
      meanLuminance: legacy.meanLuminance,
      medianLuminance: legacy.medianLuminance,
      shadowFraction: legacy.shadowFraction,
      highlightFraction: legacy.highlightFraction,
      dynamicRange: legacy.dynamicRange,
      averageRed: legacy.averageRed,
      averageGreen: legacy.averageGreen,
      averageBlue: legacy.averageBlue,
      saturation: legacy.saturation,
      warmth: legacy.warmth,
      isLowKey: legacy.isLowKey,
      isHighKey: legacy.isHighKey,
      isBacklit: legacy.isBacklit
    )
  }

  // MARK: - Legacy aggregates
  // Pre-port Swift statistics (Rec.709 luma, 256-bin histogram), kept ONLY so
  // FilmEngine's existing adaptive paths keep working until they are rewired
  // to the ported meter. Not part of the reference scene meter.

  private struct LegacyStats {
    let meanLuminance: Double
    let medianLuminance: Double
    let shadowFraction: Double
    let highlightFraction: Double
    let dynamicRange: Double
    let averageRed: Double
    let averageGreen: Double
    let averageBlue: Double
    let saturation: Double
    let warmth: Double
    let isLowKey: Bool
    let isHighKey: Bool
    let isBacklit: Bool
  }

  private func legacyStats(px: [UInt8], n: Int) -> LegacyStats {
    var histogram = [Int](repeating: 0, count: 256)
    var sumLuminance = 0.0
    var sumRed = 0.0
    var sumGreen = 0.0
    var sumBlue = 0.0
    var sumSaturation = 0.0
    var shadowCount = 0
    var highlightCount = 0
    let count = max(1, n)

    for i in 0..<n {
      let red = Double(px[i * 4]) / 255
      let green = Double(px[i * 4 + 1]) / 255
      let blue = Double(px[i * 4 + 2]) / 255
      let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
      let bin = min(255, max(0, Int((luminance * 255).rounded())))
      histogram[bin] += 1
      sumLuminance += luminance
      sumRed += red
      sumGreen += green
      sumBlue += blue
      let maximum = max(red, max(green, blue))
      let minimum = min(red, min(green, blue))
      sumSaturation += maximum == 0 ? 0 : (maximum - minimum) / maximum
      if luminance < 0.12 { shadowCount += 1 }
      if luminance > 0.92 { highlightCount += 1 }
    }

    let p01 = legacyPercentile(0.01, histogram: histogram, count: count)
    let median = legacyPercentile(0.50, histogram: histogram, count: count)
    let p99 = legacyPercentile(0.99, histogram: histogram, count: count)
    let mean = sumLuminance / Double(count)
    let averageRed = sumRed / Double(count)
    let averageGreen = sumGreen / Double(count)
    let averageBlue = sumBlue / Double(count)
    let warmth = (averageRed - averageBlue).clamped(to: -0.35...0.35)

    return LegacyStats(
      meanLuminance: mean,
      medianLuminance: median,
      shadowFraction: Double(shadowCount) / Double(count),
      highlightFraction: Double(highlightCount) / Double(count),
      dynamicRange: max(0, p99 - p01),
      averageRed: averageRed,
      averageGreen: averageGreen,
      averageBlue: averageBlue,
      saturation: sumSaturation / Double(count),
      warmth: warmth,
      isLowKey: median < 0.30,
      isHighKey: median > 0.68,
      isBacklit: mean > 0.48 && Double(shadowCount) / Double(count) > 0.30
    )
  }

  private func legacyPercentile(_ value: Double, histogram: [Int], count: Int) -> Double {
    let target = Int((Double(count - 1) * value).rounded())
    var cumulative = 0
    for (index, amount) in histogram.enumerated() {
      cumulative += amount
      if cumulative > target { return Double(index) / 255 }
    }
    return 1
  }
}

private extension Double {
  func clamped(to range: ClosedRange<Double>) -> Double {
    min(range.upperBound, max(range.lowerBound, self))
  }
}

extension CIImage {
  var orientedForDisplay: CIImage {
    let origin = extent.origin
    return transformed(by: CGAffineTransform(translationX: -origin.x, y: -origin.y))
  }
}

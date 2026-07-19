import CoreGraphics
import UIKit

/// Perceptual & distribution metrics for the expanded evaluation harness
/// (R60-6). The audit noted the parity gate is MAE-only; MAE alone misses
/// structure, tonal distribution, and clipping. These are test-target utilities
/// (not shipped in the app) that future golden tests and the hero-Lens
/// evaluation score against, alongside the existing MAE ceiling.
///
/// All operate on RGBA8 rasterizations so results are deterministic and
/// device-independent.
enum ImageMetrics {

  struct Raster {
    let px: [UInt8]   // RGBA8, row-major
    let w: Int
    let h: Int
    var count: Int { w * h }
  }

  static func raster(_ image: UIImage) -> Raster? {
    guard let cg = image.cgImage else { return nil }
    return raster(cg)
  }

  static func raster(_ cg: CGImage) -> Raster? {
    let w = cg.width, h = cg.height
    guard w > 0, h > 0 else { return nil }
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
      data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
      space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    return Raster(px: buf, w: w, h: h)
  }

  // MARK: Luma

  /// Rec.601 luma, 0…255.
  private static func luma(_ px: [UInt8], _ i: Int) -> Double {
    let r = Double(px[i]), g = Double(px[i + 1]), b = Double(px[i + 2])
    return 0.299 * r + 0.587 * g + 0.114 * b
  }

  // MARK: MAE (parity with the existing gate)

  /// Mean absolute per-channel RGB error, 0…255. Requires equal dimensions.
  static func meanAbsoluteError(_ a: Raster, _ b: Raster) -> Double? {
    guard a.w == b.w, a.h == b.h else { return nil }
    var sum = 0.0
    var n = 0
    for i in stride(from: 0, to: a.px.count, by: 4) {
      sum += abs(Double(a.px[i]) - Double(b.px[i]))
      sum += abs(Double(a.px[i + 1]) - Double(b.px[i + 1]))
      sum += abs(Double(a.px[i + 2]) - Double(b.px[i + 2]))
      n += 3
    }
    return n > 0 ? sum / Double(n) : 0
  }

  // MARK: Global SSIM (luma)

  /// Single-window SSIM on luma, 1.0 = identical. A global approximation of the
  /// windowed metric — enough to catch structural drift a golden test cares
  /// about, without a full Gaussian pyramid.
  static func ssim(_ a: Raster, _ b: Raster) -> Double? {
    guard a.w == b.w, a.h == b.h, a.count > 0 else { return nil }
    var muA = 0.0, muB = 0.0
    for i in stride(from: 0, to: a.px.count, by: 4) { muA += luma(a.px, i); muB += luma(b.px, i) }
    let n = Double(a.count)
    muA /= n; muB /= n
    var varA = 0.0, varB = 0.0, cov = 0.0
    for i in stride(from: 0, to: a.px.count, by: 4) {
      let da = luma(a.px, i) - muA
      let db = luma(b.px, i) - muB
      varA += da * da; varB += db * db; cov += da * db
    }
    varA /= n; varB /= n; cov /= n
    let L = 255.0
    let c1 = pow(0.01 * L, 2), c2 = pow(0.03 * L, 2)
    let num = (2 * muA * muB + c1) * (2 * cov + c2)
    let den = (muA * muA + muB * muB + c1) * (varA + varB + c2)
    return den == 0 ? 1 : num / den
  }

  // MARK: Histogram distance (luma)

  /// Total-variation distance between normalized luma histograms, 0…1.
  /// 0 = identical tonal distribution.
  static func histogramDistance(_ a: Raster, _ b: Raster, bins: Int = 32) -> Double {
    let ha = lumaHistogram(a, bins: bins)
    let hb = lumaHistogram(b, bins: bins)
    var d = 0.0
    for i in 0..<bins { d += abs(ha[i] - hb[i]) }
    return d / 2.0
  }

  private static func lumaHistogram(_ r: Raster, bins: Int) -> [Double] {
    var h = [Double](repeating: 0, count: bins)
    guard r.count > 0 else { return h }
    for i in stride(from: 0, to: r.px.count, by: 4) {
      let bin = min(bins - 1, Int(luma(r.px, i) / 256.0 * Double(bins)))
      h[bin] += 1
    }
    let total = Double(r.count)
    for i in 0..<bins { h[i] /= total }
    return h
  }

  // MARK: Clipping

  /// Fraction of pixels whose luma ≥ threshold (blown highlights), 0…1.
  static func highlightClipRate(_ r: Raster, threshold: Double = 250) -> Double {
    guard r.count > 0 else { return 0 }
    var c = 0
    for i in stride(from: 0, to: r.px.count, by: 4) where luma(r.px, i) >= threshold { c += 1 }
    return Double(c) / Double(r.count)
  }

  /// Fraction of pixels whose luma ≥ threshold inside a normalized,
  /// top-left-origin rect (blown highlights within a crop, e.g. a face box).
  static func highlightClipRate(_ r: Raster, in rect: CGRect, threshold: Double = 250) -> Double {
    let x0 = max(0, Int(Double(rect.minX) * Double(r.w)))
    let x1 = min(r.w, Int(Double(rect.maxX) * Double(r.w)))
    let y0 = max(0, Int(Double(rect.minY) * Double(r.h)))
    let y1 = min(r.h, Int(Double(rect.maxY) * Double(r.h)))
    guard x1 > x0, y1 > y0 else { return 0 }
    var c = 0, n = 0
    for y in y0..<y1 {
      for x in x0..<x1 {
        if luma(r.px, (y * r.w + x) * 4) >= threshold { c += 1 }
        n += 1
      }
    }
    return n > 0 ? Double(c) / Double(n) : 0
  }

  /// Fraction of pixels whose luma ≤ threshold (crushed shadows), 0…1.
  static func shadowClipRate(_ r: Raster, threshold: Double = 5) -> Double {
    guard r.count > 0 else { return 0 }
    var c = 0
    for i in stride(from: 0, to: r.px.count, by: 4) where luma(r.px, i) <= threshold { c += 1 }
    return Double(c) / Double(r.count)
  }

  // MARK: Region mean colour (skin-tone delta support)

  /// Mean RGB (0…255) inside a normalized, top-left-origin rect.
  static func meanColor(_ r: Raster, in rect: CGRect) -> (r: Double, g: Double, b: Double)? {
    guard r.count > 0 else { return nil }
    let x0 = max(0, Int(Double(rect.minX) * Double(r.w)))
    let x1 = min(r.w, Int(Double(rect.maxX) * Double(r.w)))
    let y0 = max(0, Int(Double(rect.minY) * Double(r.h)))
    let y1 = min(r.h, Int(Double(rect.maxY) * Double(r.h)))
    guard x1 > x0, y1 > y0 else { return nil }
    var sr = 0.0, sg = 0.0, sb = 0.0, n = 0.0
    for y in y0..<y1 {
      for x in x0..<x1 {
        let i = (y * r.w + x) * 4
        sr += Double(r.px[i]); sg += Double(r.px[i + 1]); sb += Double(r.px[i + 2]); n += 1
      }
    }
    return (sr / n, sg / n, sb / n)
  }

  /// Euclidean RGB distance between two mean colours (skin-tone delta).
  static func colorDelta(_ a: (r: Double, g: Double, b: Double), _ b: (r: Double, g: Double, b: Double)) -> Double {
    sqrt(pow(a.r - b.r, 2) + pow(a.g - b.g, 2) + pow(a.b - b.b, 2))
  }
}

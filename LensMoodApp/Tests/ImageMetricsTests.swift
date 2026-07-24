import CoreGraphics
import UIKit
import XCTest
@testable import LensMood

/// Validates the R60-6 evaluation metrics on synthetic images so the harness
/// itself is trustworthy before golden tests depend on it.
final class ImageMetricsTests: XCTestCase {

  private func solid(_ color: UIColor, _ side: Int = 32) -> UIImage {
    UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
      color.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
    }
  }

  /// Half black / half white — a known 50/50 tonal split.
  private func halfSplit(_ side: Int = 32) -> UIImage {
    UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
      UIColor.black.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: side, height: side / 2))
      UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: side / 2, width: side, height: side / 2))
    }
  }

  func testIdenticalImages() throws {
    let a = try XCTUnwrap(ImageMetrics.raster(solid(.gray)))
    let b = try XCTUnwrap(ImageMetrics.raster(solid(.gray)))
    XCTAssertEqual(ImageMetrics.meanAbsoluteError(a, b) ?? -1, 0, accuracy: 0.001)
    XCTAssertEqual(ImageMetrics.ssim(a, b) ?? 0, 1.0, accuracy: 0.001)
    XCTAssertEqual(ImageMetrics.histogramDistance(a, b), 0, accuracy: 0.001)
  }

  func testDifferentSolidsDivergeButStayStructured() throws {
    let mid = try XCTUnwrap(ImageMetrics.raster(solid(UIColor(white: 0.5, alpha: 1))))
    let bright = try XCTUnwrap(ImageMetrics.raster(solid(UIColor(white: 0.6, alpha: 1))))
    let mae = try XCTUnwrap(ImageMetrics.meanAbsoluteError(mid, bright))
    XCTAssertGreaterThan(mae, 10, "≈0.1*255 luminance shift")
    // Both flat ⇒ zero variance ⇒ SSIM luminance term dominates; still high.
    let s = try XCTUnwrap(ImageMetrics.ssim(mid, bright))
    XCTAssertGreaterThan(s, 0.8)
    // Tonal distribution moved to a different bin.
    XCTAssertGreaterThan(ImageMetrics.histogramDistance(mid, bright), 0.5)
  }

  func testClipRates() throws {
    let white = try XCTUnwrap(ImageMetrics.raster(solid(.white)))
    let black = try XCTUnwrap(ImageMetrics.raster(solid(.black)))
    XCTAssertEqual(ImageMetrics.highlightClipRate(white), 1.0, accuracy: 0.001)
    XCTAssertEqual(ImageMetrics.shadowClipRate(white), 0.0, accuracy: 0.001)
    XCTAssertEqual(ImageMetrics.shadowClipRate(black), 1.0, accuracy: 0.001)
    XCTAssertEqual(ImageMetrics.highlightClipRate(black), 0.0, accuracy: 0.001)
  }

  func testHalfSplitHistogramAndClip() throws {
    let r = try XCTUnwrap(ImageMetrics.raster(halfSplit()))
    // Roughly half blown, half crushed.
    XCTAssertEqual(ImageMetrics.highlightClipRate(r), 0.5, accuracy: 0.05)
    XCTAssertEqual(ImageMetrics.shadowClipRate(r), 0.5, accuracy: 0.05)
  }

  func testRegionMeanColorAndDelta() throws {
    let r = try XCTUnwrap(ImageMetrics.raster(solid(UIColor(red: 0.8, green: 0.4, blue: 0.2, alpha: 1))))
    let mean = try XCTUnwrap(ImageMetrics.meanColor(r, in: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)))
    XCTAssertEqual(mean.r, 204, accuracy: 2)
    XCTAssertEqual(mean.g, 102, accuracy: 2)
    XCTAssertEqual(mean.b, 51, accuracy: 2)
    let delta = ImageMetrics.colorDelta(mean, (r: 204, g: 102, b: 51))
    XCTAssertEqual(delta, 0, accuracy: 1)
  }
}

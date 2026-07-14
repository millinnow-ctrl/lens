import CoreGraphics
import UIKit
import XCTest
@testable import LensMood

/// On-device performance harness (Deliverable #6).
///
/// IMPORTANT: in CI this runs on the **simulator**, whose timings and memory are
/// NOT representative of iPhone hardware (no Apple Neural Engine, different GPU/
/// thermal behaviour). The value here is the *instrument*: it compiles, exercises
/// the real `FilmEngine.develop` at preview and export sizes, and logs measured
/// wall-clock + `phys_footprint`. Run it from Xcode on a real device (or read the
/// Xcode Core ML / metrics perf report) to fill the by-device benchmark table.
///
/// `measure {}` is used without committed baselines, so it records timings but
/// never fails the build on timing variance. Iteration counts are kept low to
/// bound CI wall-clock.
final class PerformanceBenchmarks: XCTestCase {

  private func gradientImage(_ side: Int) -> UIImage {
    let size = CGSize(width: side, height: side)
    return UIGraphicsImageRenderer(size: size).image { ctx in
      let cs = CGColorSpaceCreateDeviceRGB()
      let colors = [UIColor(red: 0.05, green: 0.1, blue: 0.2, alpha: 1).cgColor,
                    UIColor(red: 0.95, green: 0.8, blue: 0.6, alpha: 1).cgColor] as CFArray
      if let g = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1]) {
        ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
      }
      // A few blocks to give tone/edges something to work on.
      UIColor(white: 0.5, alpha: 1).setFill()
      ctx.fill(CGRect(x: side / 4, y: side / 4, width: side / 3, height: side / 3))
    }
  }

  private func lowIterationOptions() -> XCTMeasureOptions {
    let opts = XCTMeasureOptions()
    opts.iterationCount = 3
    return opts
  }

  func testPreviewRenderLUTStock() throws {
    let image = gradientImage(1024)
    let recipe = CameraRecipe.recipe(for: "kodachrome")
    let engine = FilmEngine()
    // Warm once (first render compiles kernels / uploads LUT).
    _ = try? engine.develop(image, with: recipe, maxPixelSize: 1024).image

    let before = MemoryProbe.footprintMB()
    measure(metrics: [XCTClockMetric()], options: lowIterationOptions()) {
      _ = try? engine.develop(image, with: recipe, maxPixelSize: 1024).image
    }
    let after = MemoryProbe.footprintMB()
    XCTAssertGreaterThan(MemoryProbe.footprintBytes(), 0, "footprint probe should return a value")
    print(String(format: "[bench] kodachrome preview@1024 footprint %.1f→%.1f MB", before, after))
  }

  func testExportRenderAdaptiveStock() throws {
    let image = gradientImage(1536)
    let recipe = CameraRecipe.recipe(for: "disposable")
    let engine = FilmEngine()
    _ = try? engine.develop(image, with: recipe, maxPixelSize: 2048).image

    let before = MemoryProbe.footprintMB()
    let ms = Stopwatch.millis {
      _ = try? engine.develop(image, with: recipe, maxPixelSize: 2048).image
    }
    let after = MemoryProbe.footprintMB()
    print(String(format: "[bench] disposable export@2048 %.0f ms, footprint %.1f→%.1f MB", ms, before, after))
    XCTAssertGreaterThan(ms, 0)
  }

  func testFootprintProbeIsSane() {
    // Between 1 MB and 4 GB — a smoke test that the Mach query is wired right.
    let mb = MemoryProbe.footprintMB()
    XCTAssertGreaterThan(mb, 1)
    XCTAssertLessThan(mb, 4096)
  }
}

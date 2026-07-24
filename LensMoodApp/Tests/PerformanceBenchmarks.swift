import CoreGraphics
import Foundation
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

  /// Timestamps the real stage boundaries `FilmEngine.read` reports through
  /// `onPhase`, so each stage's cost is measured rather than guessed. A class
  /// (not a captured `var`) because the callback is `@Sendable` and arrives on
  /// the read's own thread.
  private final class PhaseClock: @unchecked Sendable {
    private let lock = NSLock()
    private var stamps: [(ReadPhase, CFAbsoluteTime)] = []

    func mark(_ phase: ReadPhase) {
      let now = CFAbsoluteTimeGetCurrent()
      lock.lock()
      stamps.append((phase, now))
      lock.unlock()
    }

    /// Each stage's wall-clock span: from its own mark to the next stage's
    /// mark (or, for the last stage, to the end of the read).
    func durations(readEnd: CFAbsoluteTime) -> (metering: Double, findingSubject: Double, tracingLight: Double) {
      lock.lock()
      let marks = stamps
      lock.unlock()
      func span(_ phase: ReadPhase) -> Double {
        guard let index = marks.firstIndex(where: { $0.0 == phase }) else { return 0 }
        let end = index + 1 < marks.count ? marks[index + 1].1 : readEnd
        return (end - marks[index].1) * 1000
      }
      return (span(.metering), span(.findingSubject), span(.tracingLight))
    }
  }

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

  /// R89-C — **the number**. How long does a develop actually take?
  ///
  /// `Analytics.developFinished(ms:)` has always logged it and nothing has
  /// ever surfaced it, so no one in this repo could say. This times the whole
  /// shipping shape of one develop — the three real `read` stages separately
  /// (via the `onPhase` seam, which is what the ceremony panel reports), then
  /// both rungs of the resolution ladder — and prints it, so every CI run
  /// records a develop duration in its log.
  ///
  /// Asserts only that the clock moved: per this file's standing discipline,
  /// simulator timings are NOT device timings and must never gate the build.
  func testDevelopDurationDiagnostic() throws {
    // same source as testExportRenderAdaptiveStock, so this adds no new peak:
    // the renderer's backing store is the simulator's screen scale, so both
    // ladder rungs below are genuine DOWNSCALES of it, never upscales
    let image = gradientImage(1536)
    let engine = FilmEngine()
    let recipe = CameraRecipe.recipe(for: "kodachrome")
    // warm once — the first render of a process compiles kernels and uploads
    // the LUT, which belongs to launch, not to a develop
    _ = try? engine.develop(image, with: recipe, maxPixelSize: 512).image

    let marks = PhaseClock()
    let readStart = CFAbsoluteTimeGetCurrent()
    let reading = try engine.read(image) { marks.mark($0) }
    let readMS = (CFAbsoluteTimeGetCurrent() - readStart) * 1000

    let rungEdge = DevelopLadder.firstRung
    let rungMS = Stopwatch.millis {
      _ = try? engine.develop(image, with: recipe, maxPixelSize: CGFloat(rungEdge),
                              seed: 7, reading: reading).image
    }
    let fullEdge = 2048
    let fullMS = Stopwatch.millis {
      _ = try? engine.develop(image, with: recipe, maxPixelSize: CGFloat(fullEdge),
                              seed: 7, reading: reading).image
    }

    let stages = marks.durations(readEnd: readStart + readMS / 1000)
    print(String(
      format: "[DIAG] develop duration (kodachrome, 1536 pt gradient) — read %.0f ms "
        + "[meter %.0f · subject %.0f · masks %.0f], ladder rung@%ld %.0f ms, "
        + "full@%ld %.0f ms · TOTAL %.0f ms",
      readMS, stages.metering, stages.findingSubject, stages.tracingLight,
      rungEdge, rungMS, fullEdge, fullMS, readMS + rungMS + fullMS
    ))
    print("[DIAG] simulator timings are NOT iPhone timings — see this file's header")
    XCTAssertGreaterThan(readMS + rungMS + fullMS, 0)
  }

  func testFootprintProbeIsSane() {
    // Between 1 MB and 4 GB — a smoke test that the Mach query is wired right.
    let mb = MemoryProbe.footprintMB()
    XCTAssertGreaterThan(mb, 1)
    XCTAssertLessThan(mb, 4096)
  }
}

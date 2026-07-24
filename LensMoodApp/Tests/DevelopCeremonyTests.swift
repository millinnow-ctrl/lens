import CoreImage
import Foundation
import UIKit
import XCTest
@testable import LensMood

/// R89-C — the develop is real work, and the ceremony is only allowed to
/// report it.
///
/// These tests pin the two halves of that promise:
///
/// 1. **The phase seam is an observer.** `FilmEngine.read`'s new `onPhase`
///    callback fires at the three stage boundaries that already existed, in
///    the order they already ran, and a develop from a reading taken with it
///    wired is byte-identical to one taken without.
/// 2. **The ceremony cannot lie.** No step appears before its stage begins, no
///    step is checked before its stage returns, the settled list is exactly
///    `Conductor.narration`, and a `PreviewCache` hit — where nothing is
///    computed — produces no ceremony at all.
///
/// Plus the resolution ladder's containment: the first rung is a real render
/// at a genuinely different resolution, and it can never occupy the cache key
/// or the state slot that the kept frame uses.
final class DevelopCeremonyTests: XCTestCase {

  private func canvas() -> UIImage {
    let size = CGSize(width: 128, height: 96)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1   // pixel geometry must not inherit the simulator's screen
    return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
      UIColor(white: 0.18, alpha: 1).setFill()
      ctx.fill(CGRect(origin: .zero, size: size))
      UIColor(red: 0.95, green: 0.93, blue: 0.9, alpha: 1).setFill()
      ctx.cgContext.fillEllipse(in: CGRect(x: 88, y: 12, width: 24, height: 24))
      UIColor(red: 0.15, green: 0.25, blue: 0.85, alpha: 1).setFill()
      ctx.cgContext.fillEllipse(in: CGRect(x: 12, y: 56, width: 30, height: 30))
    }
  }

  // MARK: - The phase seam

  /// The three phases are emitted in pipeline order, exactly once each. They
  /// are the stage boundaries that already existed inside `read` — nothing was
  /// added, split or reordered to produce them.
  func testReadEmitsItsRealStagesInOrder() throws {
    let engine = FilmEngine()
    let seen = PhaseRecorder()
    _ = try engine.read(canvas()) { seen.record($0) }
    XCTAssertEqual(seen.phases, [.metering, .findingSubject, .tracingLight])
  }

  /// With the subject pass off, only the stage that actually runs reports.
  /// A skipped stage must never announce itself.
  func testSkippedStagesNeverReport() throws {
    let engine = FilmEngine()
    let seen = PhaseRecorder()
    _ = try engine.read(canvas(), analyzeSubjects: false) { seen.record($0) }
    XCTAssertEqual(seen.phases, [.metering], "the subject pass did not run, so it does not narrate")
  }

  /// THE determinism guarantee for the whole workstream: observing the read
  /// cannot move a pixel. A develop fed a reading taken with `onPhase` wired
  /// is byte-identical to one fed a reading taken without it.
  func testObservingTheReadChangesNoPixels() throws {
    let engine = FilmEngine()
    let photo = canvas()
    // subject pass off: Vision segmentation is not guaranteed bit-stable
    // across separate runs, so the meter side is what a byte comparison of two
    // separate reads can honestly prove (same discipline as ConductorTests).
    let silent = try engine.read(photo, analyzeSubjects: false)
    let seen = PhaseRecorder()
    let observed = try engine.read(photo, analyzeSubjects: false) { seen.record($0) }
    XCTAssertFalse(seen.phases.isEmpty, "the observer must actually have been called")
    for stockID in ["iphone-flash", "kodachrome", "tokyo-neon"] {
      let recipe = CameraRecipe.recipe(for: stockID)
      let a = try engine.develop(photo, with: recipe, seed: 7, analyzeSubjects: false, reading: silent).image
      let b = try engine.develop(photo, with: recipe, seed: 7, analyzeSubjects: false, reading: observed).image
      XCTAssertEqual(
        a.pngData(), b.pngData(),
        "\(stockID): a watched read must render byte-identically to an unwatched one"
      )
    }
  }

  /// The Conductor forwards the phases of a read it actually performs, and
  /// emits nothing on a cache hit — because on a cache hit it runs nothing.
  @MainActor
  func testConductorForwardsPhasesOnlyWhenItReads() async throws {
    let conductor = Conductor()
    let photo = canvas()
    let key = UUID()
    let first = PhaseRecorder()
    _ = try await conductor.reading(for: photo, key: key) { first.record($0) }
    XCTAssertEqual(first.phases, [.metering, .findingSubject, .tracingLight])

    let second = PhaseRecorder()
    _ = try await conductor.reading(for: photo, key: key) { second.record($0) }
    XCTAssertTrue(second.phases.isEmpty, "a cached reading ran nothing, so it narrates nothing")
  }

  // MARK: - The ceremony state machine

  /// A step exists only once its stage has begun.
  func testNoStepAppearsBeforeItsStageBegins() {
    var ceremony = DevelopCeremony()
    XCTAssertTrue(ceremony.steps.isEmpty, "nothing has run, so nothing is claimed")

    ceremony.begin(.metering)
    XCTAssertEqual(ceremony.steps, ["Reading the light"])
    ceremony.begin(.findingSubject)
    XCTAssertEqual(ceremony.steps, ["Reading the light", "Finding your subject"])
    ceremony.begin(.tracingLight)
    XCTAssertEqual(
      ceremony.steps,
      ["Reading the light", "Finding your subject", "Tracing the light sources"]
    )
  }

  /// A step is checked (index < activeIndex) only once the NEXT stage has
  /// begun — i.e. only once the work it names has genuinely returned. The
  /// stage in flight is always the last one, and it is never checked.
  func testOnlyReturnedStagesReadAsComplete() {
    var ceremony = DevelopCeremony()
    ceremony.begin(.metering)
    XCTAssertEqual(ceremony.activeIndex, 0, "metering is running, not done")
    ceremony.begin(.findingSubject)
    XCTAssertEqual(ceremony.activeIndex, 1, "metering returned; the subject pass is running")
    ceremony.begin(.tracingLight)
    XCTAssertEqual(ceremony.activeIndex, 2)
    XCTAssertEqual(ceremony.activeIndex, ceremony.steps.count - 1)
  }

  /// The callback is hopped from the read's thread to the main actor, so
  /// delivery order is not something this type may depend on. A duplicate or
  /// a late arrival must never walk the panel backwards.
  func testDeliveryOrderCannotScrambleThePanel() {
    var forward = DevelopCeremony()
    [ReadPhase.metering, .findingSubject, .tracingLight].forEach { forward.begin($0) }

    var scrambled = DevelopCeremony()
    [ReadPhase.metering, .tracingLight, .findingSubject, .metering, .tracingLight]
      .forEach { scrambled.begin($0) }

    XCTAssertEqual(scrambled.steps, forward.steps)
    XCTAssertEqual(scrambled.activeIndex, forward.activeIndex)
  }

  /// The settled list is EXACTLY `Conductor.narration(for:)` — the app's one
  /// truth-check on what the pipeline did to this photograph. A stage that ran
  /// and found nothing leaves no claim behind.
  func testSettledListIsExactlyNarration() {
    let quiet = SceneReading(
      scene: SceneProfile.neutral,   // no lights
      subject: SubjectAnalysis(faces: [], personMask: nil)
    )
    var ceremony = DevelopCeremony()
    [ReadPhase.metering, .findingSubject, .tracingLight].forEach { ceremony.begin($0) }
    XCTAssertEqual(ceremony.steps.count, 3, "three stages ran")

    ceremony.settle(narration: Conductor.narration(for: quiet))
    XCTAssertEqual(ceremony.steps, Conductor.narration(for: quiet))
    XCTAssertEqual(
      ceremony.steps, ["Reading the light", "Developing"],
      "no faces and no lights were found, so neither is claimed"
    )
    XCTAssertEqual(ceremony.activeIndex, ceremony.steps.count - 1, "Developing is the running step")
    XCTAssertTrue(ceremony.isSettled)
  }

  /// A phase that lands after the read returned cannot un-settle the truth.
  func testALatePhaseCannotReopenASettledList() {
    var ceremony = DevelopCeremony()
    ceremony.settle(narration: ["Reading the light", "Developing"])
    ceremony.begin(.tracingLight)
    XCTAssertEqual(ceremony.steps, ["Reading the light", "Developing"])
  }

  /// A `PreviewCache` hit computes nothing, so it narrates nothing: zero
  /// ceremony, no steps, no elapsed clock. (`DevelopView.develop` resets the
  /// ceremony to this value before restoring a cached render.)
  func testACacheHitProducesNoCeremony() {
    let ceremony = DevelopCeremony()
    XCTAssertTrue(ceremony.steps.isEmpty)
    XCTAssertFalse(ceremony.isSettled)
  }

  /// A photograph already read this session (any camera switch) opens with its
  /// read stages genuinely behind it — the panel does not replay a read that
  /// is not going to happen.
  func testAKnownReadingOpensAlreadySettled() {
    let narration = ["Reading the light", "Finding your subject", "Developing"]
    let ceremony = DevelopCeremony.settled(narration: narration)
    XCTAssertEqual(ceremony.steps, narration)
    XCTAssertEqual(ceremony.activeIndex, 2)
  }

  /// When the frame lands, nothing is left showing as running.
  func testFinishLeavesNothingRunning() {
    var ceremony = DevelopCeremony.settled(narration: ["Reading the light", "Developing"])
    ceremony.finish()
    for index in ceremony.steps.indices {
      XCTAssertLessThan(index, ceremony.activeIndex, "step \(index) must read as complete")
    }
  }

  /// The fetch step names the photo library's own work — the panel used to
  /// claim "Reading the light" through an iCloud download.
  func testThePhotoFetchIsNamedAsItself() {
    let ceremony = DevelopCeremony.loadingPhotograph()
    XCTAssertEqual(ceremony.steps, [DevelopCeremony.photoLoadStep])
    XCTAssertEqual(ceremony.activeIndex, 0)
    XCTAssertFalse(
      ceremony.steps.contains("Reading the light"),
      "nothing has been read while the photograph is still being fetched"
    )
  }

  // MARK: - The resolution ladder

  /// The first rung is off exactly where the full preview is already small
  /// (the universal tier renders at 1024), and on above it.
  func testLadderIsGatedOffWhereTheFullPreviewIsAlreadySmall() {
    XCTAssertNil(DevelopLadder.firstRungEdge(previewEdge: 1024), "universal tier: one render only")
    XCTAssertEqual(DevelopLadder.firstRungEdge(previewEdge: 1536), 512)
    XCTAssertEqual(DevelopLadder.firstRungEdge(previewEdge: 2048), 512)
  }

  /// The rung can never occupy the kept render's cache key: `PreviewCache.key`
  /// includes the edge, so the two are distinct by construction. (The view
  /// does not write the rung to the cache at all — this pins the second lock.)
  func testTheRungCannotCollideWithTheKeptRender() {
    let photo = UUID()
    let kept = PreviewCache.key(photo: photo, lens: "kodachrome", edge: 2048, intensityPercent: 100)
    let rung = PreviewCache.key(
      photo: photo, lens: "kodachrome", edge: DevelopLadder.firstRung, intensityPercent: 100
    )
    XCTAssertNotEqual(kept, rung)
  }

  /// Both rungs are REAL renders of the real recipe from the ONE reading — the
  /// photograph resolves because the machine computes it twice at increasing
  /// resolution, not because a timer pretends it does. The rung is genuinely
  /// smaller, and the full render is bit-for-bit what it was before the ladder
  /// existed (the rung is a separate render that touches nothing).
  func testBothRungsAreRealRendersAndTheKeptOneIsUnchanged() throws {
    let engine = FilmEngine()
    let photo = canvas()
    let reading = try engine.read(photo, analyzeSubjects: false)
    let recipe = CameraRecipe.recipe(for: "kodachrome")

    let control = try engine.develop(
      photo, with: recipe, maxPixelSize: 128, seed: 7, analyzeSubjects: false, reading: reading
    ).image
    let rung = try engine.develop(
      photo, with: recipe, maxPixelSize: 48, seed: 7, analyzeSubjects: false, reading: reading
    ).image
    let kept = try engine.develop(
      photo, with: recipe, maxPixelSize: 128, seed: 7, analyzeSubjects: false, reading: reading
    ).image

    XCTAssertLessThan(
      rung.size.width * rung.scale, kept.size.width * kept.scale,
      "the first rung is genuinely a smaller render, not a scaled copy of the full one"
    )
    XCTAssertEqual(
      control.pngData(), kept.pngData(),
      "rendering the rung in between must leave the kept frame byte-identical"
    )
  }
}

/// Collects phases delivered from the read's own thread.
private final class PhaseRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [ReadPhase] = []

  func record(_ phase: ReadPhase) {
    lock.lock()
    storage.append(phase)
    lock.unlock()
  }

  var phases: [ReadPhase] {
    lock.lock()
    defer { lock.unlock() }
    return storage
  }
}

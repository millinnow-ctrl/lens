import CoreImage
import XCTest
@testable import LensMood

/// Pins the Layer-3 seam's honest contract: shipping lenses are deterministic-
/// only, the coordinator gates a hypothetical model correctly by device, and the
/// refinement path is a guaranteed pass-through (never degrades the base image)
/// until a real model is installed.
final class RefinementServiceTests: XCTestCase {

  private func tmp() -> URL {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("lm-refine-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
  }

  private func profile(gb: Double, os: Int = 17) -> DeviceCapabilityProfile {
    DeviceCapabilityProfile(
      physicalMemoryBytes: UInt64(gb * 1024 * 1024 * 1024),
      processorCount: 6, osMajor: os, hasNeuralEngine: true,
      thermalState: .nominal, lowPowerMode: false
    )
  }

  private let model = RefinementModelDescriptor(
    modelID: "polaroid.refiner", version: 1, displayName: "Polaroid Finish",
    downloadBytes: 40_000_000, installedBytes: 60_000_000,
    minDeviceTier: .enhanced, minOSMajor: 17,
    computeUnits: .cpuAndNeuralEngine, defaultStrength: 0.25,
    sha256: "abc", hasDeterministicFallback: true
  )

  private func lens(withRefinement refinement: RefinementModelDescriptor?) -> Lens {
    Lens(
      id: "polaroid", version: 1, collection: .instant, defaultIntensity: 0.9,
      previewLatency: .fast, exportLatency: .moderate, requiredMasks: .portrait,
      pipeline: .deterministic(subjectAware: true), refinement: refinement,
      minDeviceTier: .universal, memoryClass: .universal, isPremium: false,
      entitlement: nil, analyticsID: "lens_polaroid", evalScore: nil,
      fallbackLensID: "polaroid", rollbackVersion: nil
    )
  }

  func testAllShippingLensesAreDeterministicOnly() async {
    let coord = InferenceCoordinator(registry: ModelRegistry(directoryOverride: tmp()))
    let cap = profile(gb: 8)
    for l in Lens.all {
      let a = await coord.availability(for: l, capability: cap)
      XCTAssertEqual(a, .deterministicOnly, "\(l.id) should be deterministic-only today")
    }
  }

  func testNeedsDownloadOnCapableDevice() async {
    let coord = InferenceCoordinator(registry: ModelRegistry(directoryOverride: tmp()))
    let a = await coord.availability(for: lens(withRefinement: model), capability: profile(gb: 8))
    XCTAssertEqual(a, .needsDownload(model))
  }

  func testUnsupportedOnWeakDevice() async {
    let coord = InferenceCoordinator(registry: ModelRegistry(directoryOverride: tmp()))
    // 3 GB ⇒ universal tier, below the model's .enhanced floor.
    let a = await coord.availability(for: lens(withRefinement: model), capability: profile(gb: 3))
    XCTAssertEqual(a, .unsupportedDevice)
  }

  func testRefineIsIdentityForDeterministicLens() async {
    let coord = InferenceCoordinator(registry: ModelRegistry(directoryOverride: tmp()))
    let img = CIImage(color: CIColor.red).cropped(to: CGRect(x: 0, y: 0, width: 10, height: 10))
    let out = await coord.refineIfAvailable(
      img, lens: lens(withRefinement: nil), masks: .empty(), capability: profile(gb: 8)
    )
    XCTAssertEqual(out.extent, img.extent, "deterministic lens ⇒ image passes through unchanged")
  }

  func testFallbackRefinerReturnsInput() async throws {
    let img = CIImage(color: CIColor.green).cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
    let out = try await DeterministicFallbackRefiner().refine(
      img, lens: lens(withRefinement: nil), masks: .empty(), strength: 0.5
    )
    XCTAssertEqual(out.extent, img.extent)
  }
}

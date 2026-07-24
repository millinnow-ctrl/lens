import XCTest
@testable import LensMood

/// Pins the capability tiering, thermal/Low-Power back-off, memory budgets, and
/// the "never expose a model the device can't run" guarantee.
final class DeviceCapabilityTests: XCTestCase {

  private func profile(
    gb: Double,
    os: Int = 17,
    thermal: ThermalState = .nominal,
    lowPower: Bool = false,
    ane: Bool = true
  ) -> DeviceCapabilityProfile {
    DeviceCapabilityProfile(
      physicalMemoryBytes: UInt64(gb * 1024 * 1024 * 1024),
      processorCount: 6,
      osMajor: os,
      hasNeuralEngine: ane,
      thermalState: thermal,
      lowPowerMode: lowPower
    )
  }

  func testHardwareTierByMemory() {
    XCTAssertEqual(profile(gb: 3).hardwareTier, .universal)
    XCTAssertEqual(profile(gb: 4).hardwareTier, .enhanced)
    XCTAssertEqual(profile(gb: 5.9).hardwareTier, .enhanced)
    XCTAssertEqual(profile(gb: 6).hardwareTier, .highEnd)
    XCTAssertEqual(profile(gb: 8).hardwareTier, .highEnd)
  }

  func testThermalAndLowPowerBackoff() {
    XCTAssertEqual(profile(gb: 8, thermal: .serious).effectiveTier, .enhanced)
    XCTAssertEqual(profile(gb: 8, thermal: .critical).effectiveTier, .universal)
    XCTAssertEqual(profile(gb: 8, lowPower: true).effectiveTier, .enhanced)
    XCTAssertEqual(profile(gb: 4, lowPower: true, ane: true).effectiveTier, .universal)
    // Nominal/fair never demote.
    XCTAssertEqual(profile(gb: 8, thermal: .fair).effectiveTier, .highEnd)
  }

  func testMemoryBudgets() {
    let p = profile(gb: 8)
    XCTAssertEqual(p.memoryBudget(for: .universal), 500 * 1024 * 1024)
    XCTAssertEqual(p.memoryBudget(for: .enhanced), 1200 * 1024 * 1024)
    XCTAssertEqual(p.memoryBudget(for: .highEnd), 1800 * 1024 * 1024)
  }

  func testEdgeCapsScaleWithEffectiveTier() {
    XCTAssertEqual(profile(gb: 3).previewMaxEdge, 1024)
    XCTAssertEqual(profile(gb: 3).exportMaxEdge, 3072)
    XCTAssertEqual(profile(gb: 8).previewMaxEdge, 2048)
    XCTAssertEqual(profile(gb: 8).exportMaxEdge, 4096)
    // A hot high-end device is treated as universal for sizing.
    XCTAssertEqual(profile(gb: 8, thermal: .critical).exportMaxEdge, 3072)
  }

  func testCanRunGatesOnTierAndOS() {
    let model = RefinementModelDescriptor(
      modelID: "test.refiner", version: 1, displayName: "Test",
      downloadBytes: 40_000_000, installedBytes: 60_000_000,
      minDeviceTier: .enhanced, minOSMajor: 17,
      computeUnits: .cpuAndNeuralEngine, defaultStrength: 0.3,
      sha256: "deadbeef", hasDeterministicFallback: true
    )
    XCTAssertTrue(profile(gb: 8).canRun(model))
    XCTAssertFalse(profile(gb: 3).canRun(model), "universal device below min tier")
    XCTAssertFalse(profile(gb: 8, os: 16).canRun(model), "OS below min")
    XCTAssertFalse(profile(gb: 8, thermal: .critical).canRun(model), "thermal demote drops below min tier")
  }

  func testAvailableRefinementIsNilForDeterministicLenses() {
    // Every shipping lens is deterministic-only today ⇒ nil regardless of device.
    let p = profile(gb: 8)
    for lens in Lens.all {
      XCTAssertNil(p.availableRefinement(for: lens))
    }
  }
}

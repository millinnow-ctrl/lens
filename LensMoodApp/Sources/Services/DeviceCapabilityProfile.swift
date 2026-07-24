import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// A centralized, testable read of the device's rendering budget.
///
/// The rest of the app asks for a *tier*, a *memory budget*, or "can this lens's
/// learned model run right now" — never a device-name string. This kills the
/// scattered `UIDevice`/magic-number checks the audit flagged (hardcoded 2048/
/// 4096 caps in the views) and gives the model-delivery + refinement layers one
/// honest place to gate on hardware, OS, thermal state, and Low Power Mode.
struct DeviceCapabilityProfile: Equatable {
  let physicalMemoryBytes: UInt64
  let processorCount: Int
  /// iOS major version (e.g. 17).
  let osMajor: Int
  /// Best-effort: true on real A11+ hardware (all iOS-16 devices ship an ANE),
  /// false on the simulator. Refined by real Core ML compute-unit probing later.
  let hasNeuralEngine: Bool
  let thermalState: ThermalState
  let lowPowerMode: Bool

  private static let gb: UInt64 = 1024 * 1024 * 1024

  /// The static hardware tier from installed RAM (ignores transient state).
  /// <4 GB ⇒ universal · 4–5.99 GB ⇒ enhanced · ≥6 GB ⇒ high-end.
  var hardwareTier: DeviceTier {
    switch physicalMemoryBytes {
    case ..<(4 * Self.gb): return .universal
    case ..<(6 * Self.gb): return .enhanced
    default: return .highEnd
    }
  }

  /// The tier to actually use *right now*. Backs off under thermal pressure or
  /// Low Power Mode so we never expose a feature that will then jetsam.
  var effectiveTier: DeviceTier {
    var tier = hardwareTier
    if lowPowerMode { tier = tier.demoted() }
    switch thermalState {
    case .serious: tier = tier.demoted()
    case .critical: tier = .universal
    case .nominal, .fair: break
    }
    return tier
  }

  /// Peak working-set budget (bytes) for a render path at the given class
  /// (research targets: universal <500 MB, enhanced <1.2 GB, high-end <1.8 GB).
  func memoryBudget(for memoryClass: MemoryTier) -> UInt64 {
    switch memoryClass {
    case .universal: return 500 * 1024 * 1024
    case .enhanced: return 1200 * 1024 * 1024
    case .highEnd: return 1800 * 1024 * 1024
    }
  }

  /// Longest-edge cap for the preview proxy at the effective tier. Replaces the
  /// view-level magic numbers; smaller on constrained/hot devices.
  var previewMaxEdge: Int {
    switch effectiveTier {
    case .universal: return 1024
    case .enhanced: return 1536
    case .highEnd: return 2048
    }
  }

  /// Longest-edge cap for full-resolution export at the effective tier.
  var exportMaxEdge: Int {
    switch effectiveTier {
    case .universal: return 3072
    case .enhanced, .highEnd: return 4096
    }
  }

  /// Whether a specific downloadable model may run under current conditions.
  func canRun(_ model: RefinementModelDescriptor) -> Bool {
    effectiveTier >= model.minDeviceTier && osMajor >= model.minOSMajor
  }

  /// The refinement a lens should actually use right now — its descriptor if the
  /// device can run it, otherwise `nil` (caller falls back to the deterministic
  /// Layer-1/2 result). Never returns something that would fail at inference.
  func availableRefinement(for lens: Lens) -> RefinementModelDescriptor? {
    guard let model = lens.refinement, canRun(model) else { return nil }
    return model
  }
}

/// Thermal pressure, mirrored from `ProcessInfo.ThermalState` so this type stays
/// Foundation-light and unit-testable without a device.
enum ThermalState: Int, Codable, Comparable, Equatable {
  case nominal, fair, serious, critical
  static func < (lhs: ThermalState, rhs: ThermalState) -> Bool { lhs.rawValue < rhs.rawValue }
}

extension DeviceTier {
  /// One tier lower, floored at `.universal`.
  func demoted() -> DeviceTier {
    switch self {
    case .highEnd: return .enhanced
    case .enhanced: return .universal
    case .universal: return .universal
    }
  }
}

// MARK: - Provider (injectable)

/// Supplies the current capability profile. Injectable so tests and previews can
/// drive synthetic hardware/thermal states.
protocol DeviceCapabilityProviding {
  func current() -> DeviceCapabilityProfile
}

/// Live provider reading `ProcessInfo`/`UIDevice`. The single production source.
struct LiveDeviceCapabilityProvider: DeviceCapabilityProviding {
  func current() -> DeviceCapabilityProfile {
    let info = ProcessInfo.processInfo
    let osMajor = info.operatingSystemVersion.majorVersion

    let thermal: ThermalState
    switch info.thermalState {
    case .nominal: thermal = .nominal
    case .fair: thermal = .fair
    case .serious: thermal = .serious
    case .critical: thermal = .critical
    @unknown default: thermal = .nominal
    }

    #if targetEnvironment(simulator)
    let ane = false
    #else
    let ane = true // every iOS-16-capable device ships an Apple Neural Engine
    #endif

    return DeviceCapabilityProfile(
      physicalMemoryBytes: info.physicalMemory,
      processorCount: info.processorCount,
      osMajor: osMajor,
      hasNeuralEngine: ane,
      thermalState: thermal,
      lowPowerMode: info.isLowPowerModeEnabled
    )
  }
}

enum DeviceCapability {
  /// Shared provider; swap in tests for a synthetic device.
  static var provider: DeviceCapabilityProviding = LiveDeviceCapabilityProvider()
  static var current: DeviceCapabilityProfile { provider.current() }
}

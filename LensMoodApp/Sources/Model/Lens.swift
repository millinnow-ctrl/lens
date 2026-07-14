import Foundation

/// The unified, versioned **Lens** definition — the single source of truth that
/// the UI, rendering engine, model-delivery system, analytics, tests, and
/// monetization all read from.
///
/// It deliberately does **not** duplicate existing data. Three per-id
/// representations already exist and stay authoritative:
///   • `Stock`            — UI card metadata (name, tagline, EXIF, gradient, icon)
///   • `CameraRecipe`     — numeric engine behaviour (LUT, matrices, grain, optics)
///   • `StyleDefinition`  — the prose contract (palette, tone, guard-rails)
/// `Lens` *composes* those by shared `id` and layers on the delivery / device /
/// model / monetization metadata that the on-device-AI architecture needs.
///
/// A Lens name must map to concrete photographic behaviour — never a marketing
/// label alone — which is why `recipe` and `definition` are always reachable
/// from here. New systems should request a `Lens`, not a raw recipe.
struct Lens: Identifiable, Equatable {
  /// Stable engine id — matches `Stock.id` / `CameraRecipe.id` / `StyleDefinition.id`.
  let id: String
  /// Recipe/behaviour version. Bump when the deterministic look changes so
  /// delivered recipe updates and rollbacks are addressable.
  let version: Int

  // MARK: Composed authoritative sources (by id — no duplication)
  var stock: Stock { Stock.find(id) }
  var recipe: CameraRecipe { CameraRecipe.recipe(for: id) }
  var definition: StyleDefinition { StyleDefinition.forStock(id: id) }

  var name: String { stock.name }

  // MARK: Taxonomy & UX
  let collection: LensCollection
  /// Where the intensity slider starts (0…1).
  let defaultIntensity: Double
  /// Coarse, honest design-intent latency class — NOT a measured number.
  /// Real millis come from the on-device benchmark harness (R60-7).
  let previewLatency: LatencyClass
  let exportLatency: LatencyClass

  // MARK: Subject-aware requirements
  /// Which reusable masks this lens's subject-aware passes need precomputed
  /// once per photo (person/skin/sky/face/text).
  let requiredMasks: MaskRequirement

  // MARK: Two render paths
  let pipeline: LensPipeline

  // MARK: Layer-3 learned refinement (optional, downloadable)
  /// `nil` ⇒ deterministic-only lens (Layers 1–2). When present, the refinement
  /// is optional, device-gated, and always paired with a deterministic fallback.
  let refinement: RefinementModelDescriptor?

  // MARK: Capability gating
  /// Minimum device tier required to expose this lens's *advanced* (learned)
  /// path. The deterministic path runs on `.universal` regardless.
  let minDeviceTier: DeviceTier
  /// Which peak-memory budget bucket the export path targets.
  let memoryClass: MemoryTier

  // MARK: Monetization
  let isPremium: Bool
  /// Entitlement id required when `isPremium` (e.g. "premium"). `nil` while free.
  let entitlement: String?

  // MARK: Ops
  /// Non-identifying analytics slug (snake_case). Never carries image content.
  let analyticsID: String
  /// Populated by the evaluation harness (R60-6); `nil` until measured. A score
  /// must never be fabricated — absence means "not yet evaluated".
  let evalScore: Double?
  /// Deterministic fallback lens id if this lens's model is unavailable or the
  /// device can't run it. Usually itself (its own Layer-1 recipe).
  let fallbackLensID: String
  /// Previous known-good recipe version to roll back to if a delivered update
  /// is deactivated. `nil` when there is no prior version.
  let rollbackVersion: Int?

  /// True when the lens produces a result with no network dependency once the
  /// app is installed (all deterministic lenses; learned lenses once their
  /// model is downloaded).
  var runsFullyOnDevice: Bool { true }
}

// MARK: - Supporting types

/// Human-facing groupings for the Lens browser (replaces an endless flat list).
enum LensCollection: String, Codable, CaseIterable, Equatable {
  case film, cinema, instant, editorial, night, street
  case blackAndWhite = "black_and_white"
  case historical, experimental

  var title: String {
    switch self {
    case .film: return "Film"
    case .cinema: return "Cinema"
    case .instant: return "Instant"
    case .editorial: return "Editorial"
    case .night: return "Night"
    case .street: return "Street"
    case .blackAndWhite: return "Black & White"
    case .historical: return "Historical"
    case .experimental: return "Experimental"
    }
  }
}

/// Coarse design-intent latency, not a measurement. Ordered from cheapest.
enum LatencyClass: String, Codable, Comparable, Equatable {
  case instant, fast, moderate, heavy

  private var order: Int {
    switch self {
    case .instant: return 0
    case .fast: return 1
    case .moderate: return 2
    case .heavy: return 3
    }
  }
  static func < (lhs: LatencyClass, rhs: LatencyClass) -> Bool { lhs.order < rhs.order }
}

/// Runtime hardware/capability tiers. `.universal` runs everywhere; higher tiers
/// unlock learned refinement only where real-device testing proves them stable.
enum DeviceTier: String, Codable, Comparable, Equatable {
  case universal, enhanced, highEnd = "high_end"

  private var order: Int {
    switch self {
    case .universal: return 0
    case .enhanced: return 1
    case .highEnd: return 2
    }
  }
  static func < (lhs: DeviceTier, rhs: DeviceTier) -> Bool { lhs.order < rhs.order }
}

/// Peak working-set budget bucket for a render path (targets to validate on
/// device, per the research: universal <500MB, enhanced <1.2GB, high-end <1.8GB).
enum MemoryTier: String, Codable, Equatable {
  case universal, enhanced, highEnd = "high_end"
}

/// Reusable per-photo analysis masks a lens may require. OptionSet so a lens can
/// declare several; the SegmentationService computes each at most once per photo.
struct MaskRequirement: OptionSet, Codable, Equatable {
  let rawValue: Int
  static let person = MaskRequirement(rawValue: 1 << 0)
  static let skin   = MaskRequirement(rawValue: 1 << 1)
  static let sky    = MaskRequirement(rawValue: 1 << 2)
  static let face   = MaskRequirement(rawValue: 1 << 3)
  static let text   = MaskRequirement(rawValue: 1 << 4)

  static let none: MaskRequirement = []
  /// The common portrait set: cut the person, find the face, protect skin.
  static let portrait: MaskRequirement = [.person, .face, .skin]
}

/// A single stage in a render path. Preview favours the cheap early stages;
/// export may run the full ladder. Labels here also drive honest progress copy
/// (never fabricated steps).
enum PipelineStage: String, Codable, Equatable {
  case proxy          // downsampled working image
  case deterministic  // Core Image / Metal look (Layer 1)
  case subjectAware   // mask-driven local corrections (Layer 2)
  case fullRes        // full-resolution render for export
  case refinement     // optional learned img2img pass (Layer 3)
}

/// The two render paths every lens supports. Export should look like a
/// higher-quality version of the preview, not a different interpretation.
struct LensPipeline: Codable, Equatable {
  let preview: [PipelineStage]
  let export: [PipelineStage]
}

/// Descriptor for an optional downloadable Core ML refinement model (Layer 3).
/// Carries everything the model-delivery system (R60-3) needs to fetch, verify,
/// install, size-account, gate, and roll back — without the app hard-coding a
/// generated Core ML class name anywhere.
struct RefinementModelDescriptor: Codable, Equatable {
  /// Stable model id (independent of the lens id; models may be shared).
  let modelID: String
  let version: Int
  let displayName: String
  /// Bytes to download over the network (compressed .mlpackage/asset).
  let downloadBytes: Int64
  /// Bytes occupied once compiled/installed on disk.
  let installedBytes: Int64
  /// Minimum device tier that may run this model.
  let minDeviceTier: DeviceTier
  /// Minimum iOS major version.
  let minOSMajor: Int
  /// Preferred Core ML compute units.
  let computeUnits: ComputeUnitsPreference
  /// Default blend strength of the learned pass over the deterministic result.
  let defaultStrength: Double
  /// Expected SHA-256 of the delivered asset for integrity verification.
  let sha256: String
  /// Always true for this product: if the model can't run, the deterministic
  /// Layer-1/2 result is shown instead — never a failure or a blank.
  let hasDeterministicFallback: Bool
}

/// Which Core ML compute units to request. Kept as our own enum so no UI or
/// engine code depends on `MLComputeUnits` directly.
enum ComputeUnitsPreference: String, Codable, Equatable {
  case all                    // CPU + GPU + Neural Engine
  case cpuAndNeuralEngine     // skip GPU
  case cpuAndGPU              // skip ANE
  case cpuOnly                // fallback
}

// MARK: - Convenience builders

extension LensPipeline {
  /// Standard deterministic-only paths. Preview is proxy→look (+subject-aware
  /// when the lens uses masks); export adds a full-resolution pass.
  static func deterministic(subjectAware: Bool) -> LensPipeline {
    let previewCore: [PipelineStage] = subjectAware ? [.proxy, .deterministic, .subjectAware]
                                                    : [.proxy, .deterministic]
    let exportCore: [PipelineStage] = subjectAware ? [.deterministic, .subjectAware, .fullRes]
                                                   : [.deterministic, .fullRes]
    return LensPipeline(preview: previewCore, export: exportCore)
  }

  /// Adds a learned refinement stage to the export path only (preview stays
  /// deterministic for speed and identity-safety).
  func addingExportRefinement() -> LensPipeline {
    LensPipeline(preview: preview, export: export + [.refinement])
  }
}

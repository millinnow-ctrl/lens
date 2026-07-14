import CoreImage

/// Layer-3 learned-refinement seam (R60-8).
///
/// This is the drop-in point for an optional, downloadable Core ML img2img
/// refiner (the Polaroid hero experiment is first — see
/// `docs/HERO_LENS_SELECTION.md`). It is deliberately **fallback-first**: the
/// default refiner is the identity, so with no model installed the deterministic
/// Layer-1/2 result stands untouched. Nothing in the UI or engine references a
/// generated Core ML class — they ask the coordinator for a *capability*.
///
/// Honest state today: every lens has `refinement == nil`, so availability is
/// always `.deterministicOnly` and `refineIfAvailable` is a pass-through. The
/// wiring exists so a validated model can be switched on per-lens without
/// touching callers.

/// What refinement a lens can offer on this device right now — what the editor's
/// "Premium Finish / Refine Details" affordance reads.
enum RefinementAvailability: Equatable {
  /// Lens has no learned model — deterministic look is the finished result.
  case deterministicOnly
  /// Model installed and runnable now.
  case ready(RefinementModelDescriptor)
  /// Model exists and the device can run it, but it must be downloaded first.
  case needsDownload(RefinementModelDescriptor)
  /// Installed but a newer version is published.
  case updateAvailable(RefinementModelDescriptor)
  /// Model exists but this device/OS/thermal state can't run it → fall back.
  case unsupportedDevice
}

/// Applies a learned refinement over a deterministic result. Implementations are
/// swapped in (a real Core ML refiner) without changing callers.
protocol LearnedRefining {
  func refine(_ image: CIImage, lens: Lens, masks: PhotoMasks, strength: Double) async throws -> CIImage
}

/// Default refiner: identity. No model ⇒ the deterministic image is returned
/// unchanged. Guarantees Layer 3 can never *degrade* the base result.
struct DeterministicFallbackRefiner: LearnedRefining {
  func refine(_ image: CIImage, lens: Lens, masks: PhotoMasks, strength: Double) async throws -> CIImage {
    image
  }
}

/// Coordinates device capability + model installation + the active refiner into
/// one honest answer: can this lens refine right now, and if so, do it — else
/// return the deterministic image unchanged.
actor InferenceCoordinator {
  static let shared = InferenceCoordinator()

  private let registry: ModelRegistry
  private var refiner: LearnedRefining

  init(registry: ModelRegistry = .shared, refiner: LearnedRefining = DeterministicFallbackRefiner()) {
    self.registry = registry
    self.refiner = refiner
  }

  /// Install the real learned refiner once a validated model ships.
  func setRefiner(_ new: LearnedRefining) { refiner = new }

  /// Resolve what refinement `lens` can offer under `capability`.
  func availability(for lens: Lens, capability: DeviceCapabilityProfile) async -> RefinementAvailability {
    guard let model = lens.refinement else { return .deterministicOnly }
    guard capability.canRun(model) else { return .unsupportedDevice }
    switch await registry.status(for: model) {
    case .installed:
      return .ready(model)
    case let .updateAvailable(_, latest) where latest > 0:
      return .updateAvailable(model)
    default:
      return .needsDownload(model)
    }
  }

  /// Apply refinement only when it's `.ready`; otherwise return the deterministic
  /// image untouched. Any refiner error also falls back — Layer 3 is never
  /// allowed to break or degrade the export.
  func refineIfAvailable(
    _ image: CIImage,
    lens: Lens,
    masks: PhotoMasks,
    capability: DeviceCapabilityProfile
  ) async -> CIImage {
    guard case let .ready(model) = await availability(for: lens, capability: capability) else {
      return image
    }
    do {
      return try await refiner.refine(image, lens: lens, masks: masks, strength: model.defaultStrength)
    } catch {
      return image
    }
  }
}

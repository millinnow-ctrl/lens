import Foundation

/// The canonical catalog of LensMood's 18 lenses, expressed in the unified
/// `Lens` schema. Ids/order mirror `Stock.all` and `CameraRecipe.all` exactly
/// (asserted in `LensCatalogTests`), so this stays the single browse/gate/
/// deliver/monetize source of truth without duplicating look data.
///
/// Every lens here is currently **deterministic-only** (Layers 1–2): no
/// downloadable model, `.universal` device tier, free. That is the honest state
/// today — the schema is ready for learned refinement, delivery, tiers, and
/// premium packs to be switched on per-lens as they are actually built and
/// validated on device (R60-8 onward).
extension Lens {
  static let all: [Lens] = [
    det("disposable",    .film,          intensity: 0.95, masks: .portrait,                       preview: .fast,    export: .moderate),
    det("iphone-flash",  .night,         intensity: 1.00, masks: .portrait,                       preview: .fast,    export: .moderate),
    det("camcorder-90s", .cinema,        intensity: 0.90, masks: .none,                           preview: .fast,    export: .moderate),
    det("leica-street",  .street,        intensity: 0.90, masks: [.person, .face, .skin, .sky],   preview: .instant, export: .fast),
    det("gq-editorial",  .editorial,     intensity: 1.00, masks: .portrait,                       preview: .instant, export: .fast),
    det("a24-still",     .cinema,        intensity: 0.90, masks: [.person, .face, .skin, .sky],   preview: .fast,    export: .moderate),
    det("film-noir",     .blackAndWhite, intensity: 0.95, masks: .portrait,                       preview: .fast,    export: .moderate),
    det("y2k-digicam",   .experimental,  intensity: 1.00, masks: .portrait,                       preview: .fast,    export: .moderate),
    det("polaroid",      .instant,       intensity: 0.90, masks: [.person, .face, .skin, .sky],   preview: .fast,    export: .moderate),
    det("super-8",       .cinema,        intensity: 0.90, masks: .sky,                             preview: .moderate, export: .moderate),
    det("lomo",          .experimental,  intensity: 0.90, masks: .sky,                             preview: .fast,    export: .moderate),
    det("kodachrome",    .film,          intensity: 0.90, masks: [.person, .face, .skin, .sky],   preview: .instant, export: .fast),
    det("security-cam",  .experimental,  intensity: 0.85, masks: .none,                           preview: .fast,    export: .moderate),
    det("point-shoot",   .film,          intensity: 1.00, masks: .portrait,                       preview: .fast,    export: .fast),
    det("pastel-cinema", .cinema,        intensity: 0.90, masks: [.person, .face, .skin, .sky],   preview: .fast,    export: .moderate),
    det("tokyo-neon",    .night,         intensity: 0.95, masks: .portrait,                       preview: .moderate, export: .moderate),
    det("photobooth",    .blackAndWhite, intensity: 1.00, masks: .portrait,                       preview: .fast,    export: .moderate),
    det("tintype",       .historical,    intensity: 0.85, masks: .portrait,                       preview: .moderate, export: .moderate),
  ]

  static func find(_ id: String) -> Lens {
    all.first { $0.id == id } ?? all[0]
  }

  /// Lenses in a given collection, in catalog order.
  static func inCollection(_ collection: LensCollection) -> [Lens] {
    all.filter { $0.collection == collection }
  }

  /// Collections that actually contain at least one lens, in canonical order.
  static var populatedCollections: [LensCollection] {
    LensCollection.allCases.filter { !inCollection($0).isEmpty }
  }

  // MARK: - Builder

  /// Deterministic-only lens builder — fills the delivery/model/monetization
  /// boilerplate that is uniform today (no model, universal tier, free) so each
  /// catalog row states only what differs.
  private static func det(
    _ id: String,
    _ collection: LensCollection,
    intensity: Double,
    masks: MaskRequirement,
    preview: LatencyClass,
    export: LatencyClass
  ) -> Lens {
    Lens(
      id: id,
      version: 1,
      collection: collection,
      defaultIntensity: intensity,
      previewLatency: preview,
      exportLatency: export,
      requiredMasks: masks,
      pipeline: .deterministic(subjectAware: masks != .none),
      refinement: nil,
      minDeviceTier: .universal,
      memoryClass: .universal,
      isPremium: false,
      entitlement: nil,
      analyticsID: "lens_" + id.replacingOccurrences(of: "-", with: "_"),
      evalScore: nil,
      fallbackLensID: id,
      rollbackVersion: nil
    )
  }
}

import UIKit

/// One ranked entry of the "For this photo" read: how much a camera will love
/// the loaded photograph, with the honest reason when one exists.
struct LookMatch: Identifiable, Equatable {
  let stockID: String
  /// 0…1 affinity — derived from the same physics gates the engine runs, so a
  /// promoted look genuinely engages on this photograph
  let score: Double
  /// short reason shown for top matches — stated only when the underlying
  /// scene signal was actually measured, never as filler
  let reason: String?

  var id: String { stockID }
}

/// The Conductor (Master Prompt §II) — the one subsystem that owns the
/// intelligence pipeline. A photograph goes in; the Conductor runs the scene
/// meter and the subject pass exactly once (cached per photo, cancellable),
/// ranks which looks will love this photograph for the film rail, and hands
/// the cached reading to the render engine so switching cameras never
/// re-reads the same photo. Views ask the Conductor, not the parts — no
/// servers, and no model logic in views.
@MainActor
final class Conductor: ObservableObject {
  static let shared = Conductor()

  private var readings: [UUID: SceneReading] = [:]
  private var inFlight: [UUID: Task<SceneReading, Error>] = [:]
  /// insertion order for the small LRU cap — a reading retains a full-res
  /// person mask, so the cache must stay tiny
  private var order: [UUID] = []
  private let capacity = 4

  // stored properties all have defaults; nonisolated so the static shared
  // instance can be created outside the main actor
  nonisolated init() {}

  /// The finished reading for a photo key, when one is already computed.
  /// Never blocks — callers that can proceed without it (the first develop
  /// of a fresh import) simply pass nil to the engine, which reads for
  /// itself with identical results.
  func cachedReading(for key: UUID) -> SceneReading? {
    readings[key]
  }

  /// Read the photograph once, off the main thread. Concurrent callers for
  /// the same key share a single in-flight task.
  func reading(for photo: UIImage, key: UUID) async throws -> SceneReading {
    if let finished = readings[key] { return finished }
    if let running = inFlight[key] { return try await running.value }
    let task = Task.detached(priority: .userInitiated) {
      try FilmEngine.shared.read(photo)
    }
    inFlight[key] = task
    do {
      let reading = try await task.value
      // Store only while this call's task is still the registered one — a
      // forget() that raced this read must win, or the forgotten reading
      // (with its full-res mask) would be re-inserted and retained forever.
      if inFlight[key] == task {
        inFlight[key] = nil
        store(reading, key: key)
      }
      return reading
    } catch {
      if inFlight[key] == task { inFlight[key] = nil }
      throw error
    }
  }

  private func store(_ reading: SceneReading, key: UUID) {
    readings[key] = reading
    order.removeAll { $0 == key }
    order.append(key)
    while order.count > capacity, let oldest = order.first {
      order.removeFirst()
      readings[oldest] = nil
    }
  }

  /// Drop a photograph's read (photo replaced) and cancel any in-flight
  /// work for it.
  func forget(key: UUID) {
    readings[key] = nil
    order.removeAll { $0 == key }
    inFlight[key]?.cancel()
    inFlight[key] = nil
  }

  /// Rank every camera against the measured scene — the "For this photo"
  /// order for the film rail. Pure and deterministic: the same photograph
  /// always ranks the rail identically, and every adjustment mirrors a real
  /// engine behavior (a look is promoted only when its physics passes will
  /// actually engage, and demoted when they would refuse).
  nonisolated static func rank(scene: SceneProfile, faces: [FaceProfile]) -> [LookMatch] {
    func unit(_ value: Double) -> Double { min(1, max(0, value)) }
    let darkness = unit((0.35 - scene.key) / 0.35)
    let daylight = unit((scene.key - 0.42) / 0.30)
    let keyLight = scene.lights.first ?? scene.auxLights.first
    // mirrors the source-bloom pass's honest refusal gate: emissive sources
    // only count in scenes dark enough to read as emitting
    let emissive = scene.key < 0.35 && keyLight != nil
    let hasFaces = !faces.isEmpty
    let colorRichness = unit((scene.sat - 0.18) / 0.35)
    let range = unit(scene.dynamicRange)
    let warmthPositive = unit(scene.warmth / 0.18)

    var matches: [LookMatch] = []
    for recipe in CameraRecipe.all {
      var score = 0.5
      var reasons: [String] = []

      if recipe.flashPhysics > 0.001 {
        if darkness > 0.15, hasFaces {
          // flash physics shapes falloff around a real subject — its best case
          score += 0.32 * recipe.flashPhysics
          reasons.append("The flash has a subject to find")
        } else if darkness > 0.15 {
          score += 0.10 * recipe.flashPhysics
        } else {
          score -= 0.06
        }
      }
      if recipe.sourceBloom > 0.001 {
        if emissive {
          score += 0.42
          reasons.append("Found light sources to bloom")
        } else {
          // the pass refuses without emissive sources — demote honestly
          score -= 0.34
        }
      }
      if recipe.keyShadow > 0.001 {
        if let keyLight {
          score += 0.30 + 0.10 * keyLight.intensity
          reasons.append("A key light to carve shadows from")
        } else {
          score += 0.10 * range
        }
      }
      if recipe.gainDrivenGrain {
        score += 0.20 * darkness
      }
      if recipe.nightReciprocity > 0.001 {
        // slow film starves in the dark — the engine renders that honestly,
        // so the rail should not lead with it at night
        score -= 0.30 * darkness
        score += 0.18 * daylight * (0.5 + 0.5 * warmthPositive)
        if daylight > 0.30 { reasons.append("Slow film loves this much light") }
      }
      if recipe.ccdClip > 0.001 {
        score += 0.06 * daylight
      }
      if recipe.monochrome {
        score += 0.14 * range
        score -= 0.08 * colorRichness
      }
      if recipe.protectsFaces, hasFaces {
        score += 0.08
      }
      if recipe.saturation >= 1.08 {
        score += 0.16 * colorRichness
      }
      if recipe.preservesWarmCast {
        score += 0.08 * warmthPositive
      }
      if recipe.engineClass == .staticLUT, !recipe.monochrome, recipe.sourceBloom < 0.001 {
        // the emulsion stocks are daylight characters
        score += 0.10 * daylight
      }

      matches.append(LookMatch(stockID: recipe.id, score: unit(score), reason: reasons.first))
    }
    // stable order: score descending, catalog order breaking ties
    return matches.enumerated().sorted {
      $0.element.score == $1.element.score
        ? $0.offset < $1.offset
        : $0.element.score > $1.element.score
    }.map(\.element)
  }

  /// The develop ceremony's narration — only steps the pipeline truly runs
  /// on this photograph (Master Prompt §IV.3: never invented steps).
  nonisolated static func narration(for reading: SceneReading) -> [String] {
    var lines = ["Reading the light"]
    if !reading.subject.faces.isEmpty {
      lines.append(reading.subject.faces.count == 1 ? "Finding your subject" : "Finding your subjects")
    }
    if !(reading.scene.lights.isEmpty && reading.scene.auxLights.isEmpty) {
      lines.append("Tracing the light sources")
    }
    lines.append("Developing")
    return lines
  }
}

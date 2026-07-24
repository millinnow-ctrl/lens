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
  /// recency order for the small LRU cap — a reading retains the person
  /// matte plus the masked-light rasters (~1–3 MB), so the cache stays tiny
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
  ///
  /// `onPhase` (optional, default nil) observes the read's real stage
  /// boundaries — see `ReadPhase`. It fires ONLY when this call actually runs
  /// a read: a cached reading and a shared in-flight task both return without
  /// emitting a phase, because on those paths this caller ran nothing. It is
  /// delivered on the read's own thread; a UI caller hops it to the main actor
  /// itself (`ReadPhase` is order-independent by design, so the hop cannot
  /// scramble the picture).
  func reading(
    for photo: UIImage, key: UUID,
    onPhase: (@Sendable (ReadPhase) -> Void)? = nil
  ) async throws -> SceneReading {
    if let finished = readings[key] {
      // true LRU: a hit refreshes recency, so the ACTIVE photo's reading is
      // never the one evicted (a re-read would re-run the subject pass,
      // which is not guaranteed bit-stable)
      order.removeAll { $0 == key }
      order.append(key)
      return finished
    }
    if let running = inFlight[key] { return try await running.value }
    let task = Task.detached(priority: .userInitiated) {
      try FilmEngine.shared.read(photo, onPhase: onPhase)
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

  /// Seed the cache with a reading recovered from disk (a persisted reading
  /// for a photograph about to be re-developed), so the develop replays that
  /// exact reading instead of a drifted re-read. It never overrides a live
  /// reading: an already-cached reading is the one the active session is using,
  /// and an in-flight read will store its own result — adopting must not race
  /// or clobber either. When neither exists, the persisted reading enters the
  /// normal LRU exactly as a fresh read would (evictable at the cap).
  func adopt(_ reading: SceneReading, key: UUID) {
    guard readings[key] == nil, inFlight[key] == nil else { return }
    store(reading, key: key)
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

  /// The first develop must be a develop, never an ask: top-ranked camera
  /// the user can open today. Falls back to the catalog's first camera.
  nonisolated static func firstDevelopStockID(
    ranked: [String], isUnlocked: (String) -> Bool
  ) -> String {
    ranked.first(where: isUnlocked) ?? Stock.all[0].id
  }

  /// Rank every camera against the measured scene — the "For this photo"
  /// order for the film rail. Pure and deterministic: the same photograph
  /// always ranks the rail identically, and every adjustment mirrors a real
  /// engine behavior (a look is promoted only when its physics passes will
  /// actually engage, and demoted when they would refuse).
  nonisolated static func rank(scene: SceneProfile, faces: [FaceProfile]) -> [LookMatch] {
    func unit(_ value: Double) -> Double { min(1, max(0, value)) }
    let darkness = unit((0.35 - scene.key) / 0.35)
    // brightness uses the mean too: the log-average key underrates scenes
    // with deep shadow pockets, which left the mid-key band unranked (seen
    // in the day-fixture evidence review)
    let daylight = unit((max(scene.key, scene.meanLuminance) - 0.34) / 0.30)
    let keyLight = scene.lights.first ?? scene.auxLights.first
    // THE engine's own refusal gate — a look is promoted for bloom only when
    // the bloom pass would truly find emitters (white daylight speculars are
    // refused, exactly as in the render)
    let emitters = FilmEngine.emissiveLights(in: scene)
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
        if let best = emitters.max(by: { $0.intensity < $1.intensity }) {
          // graded by how "neon" the scene really is: deep dark, strongly
          // colored emitters = the look's best case; a bright window in a
          // dim room still promotes, but doesn't pin the top of the rail
          let mx = best.tint.max() ?? 0
          let mn = best.tint.min() ?? 0
          let tintSat = mx > 1e-4 ? (mx - mn) / mx : 0
          score += 0.42 * (0.35 + 0.65 * darkness) * (0.5 + 0.5 * tintSat)
          reasons.append("Found light sources to bloom")
        } else {
          // the pass refuses without emissive sources — demote honestly
          score -= 0.34
        }
      }
      if recipe.keyShadow > 0.001 {
        // The noir key-shadow pass (applyKeyShadow) carves the frame away from
        // the detected key with a per-pixel gain weighted by (1 − luma): it
        // sculpts real chiaroscuro only where a dark fill sits below the key. A
        // bright, evenly-lit daylight frame leaves that (1 − luma) carve budget
        // near zero, so the pass runs but sculpts no shadow even when the meter
        // found a bright spot to key from — the flat scenes that used to take
        // film-noir to the top of every rail with a claim it never earned.
        // Mirror the render math (the (1 − luma) budget IS the scene's dark
        // fill, exactly as ccdClip mirrors the bright-scene grade-down): gate
        // the chiaroscuro claim and its promotion on the measured key-to-fill
        // ratio — a real key over a dark fill — never on mere light presence.
        let keyToFill = (keyLight?.intensity ?? 0) * darkness
        if let keyLight, keyToFill > 0.10 {
          score += (0.12 + 0.22 * range) * (0.6 + 0.4 * keyLight.intensity)
          reasons.append("A key light to carve shadows from")
        } else {
          // a detected light with no dark fill to carve (or no light at all) —
          // a small contrast-based nudge, never the chiaroscuro claim
          score += 0.10 * range
        }
      }
      if recipe.gainDrivenGrain {
        score += 0.20 * darkness
      }
      // R66 masked-light promotions — small and structural, mirroring the new
      // passes' own gates: rim needs a subject to trace AND a metered source
      // behind it (its best case is a backlit subject); skin protection needs
      // people in the photograph. Sky coverage is not measured by the scene
      // meter, so no sky promotion is invented here.
      if recipe.rimLight > 0.001, hasFaces, keyLight != nil {
        if scene.isBacklit {
          score += 0.12 * recipe.rimLight
          reasons.append("Backlight to trace a rim from")
        } else {
          score += 0.05 * recipe.rimLight
        }
      }
      if recipe.skinProtect > 0.001, hasFaces {
        score += 0.05 * recipe.skinProtect
      }
      if recipe.nightReciprocity > 0.001 {
        // slow film starves in the dark — the engine renders that honestly,
        // so the rail should not lead with it at night
        score -= 0.30 * darkness
        score += 0.18 * daylight * (0.5 + 0.5 * warmthPositive)
        if daylight > 0.30 { reasons.append("Slow film loves this much light") }
      }
      if recipe.ccdClip > 0.001 {
        // R81 rank honesty: the CCD "glossy clip" is a dark-scene character —
        // the engine now grades it DOWN on bright, well-exposed frames (it
        // bleached them), so the rail must not promote it on daylight. Mirror
        // the render: promote where the gloss actually engages (dark scenes).
        score += 0.06 * darkness
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

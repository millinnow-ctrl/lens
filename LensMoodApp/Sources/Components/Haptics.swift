import UIKit

/// Prepared haptics.
///
/// Every call site in the app used to allocate a generator and fire it in the
/// same breath:
///
///     UIImpactFeedbackGenerator(style: .light).impactOccurred()
///
/// A feedback generator asks the Taptic Engine to warm up when it is
/// *prepared*. A generator allocated and fired in one expression has never
/// been prepared, so the engine is cold: the first haptic of a session arrives
/// noticeably late, or is dropped outright. UIKit's own guidance is to hold
/// the generator, `prepare()` it shortly before the event becomes likely, and
/// reuse it — an instrument's controls should answer the finger immediately,
/// every time, including the first time.
///
/// This holds one generator per flavour for the app's lifetime and re-prepares
/// it right after each fire, so the *next* tap is warm too. Feedback
/// generators are UIKit objects that must be used from the main thread, hence
/// `@MainActor` — which every call site (SwiftUI button actions, and AppModel,
/// itself `@MainActor`) already satisfies.
///
/// Honest caveat: none of this is visible to CI. It is provable by
/// compilation and by hand on a device — never by a screenshot.
///
/// Threading: feedback generators are UIKit objects and must be used from the
/// main thread. This type is deliberately *not* `@MainActor`-isolated —
/// several call sites are plain synchronous helpers on SwiftUI view structs
/// and `DispatchQueue.main` closures, which are nonisolated contexts that
/// could not call an isolated member at all. Every one of them already ran on
/// the main thread when it allocated its generator inline, so the threading
/// here is exactly what shipped; only the lifetime of the generator changes.
enum Haptics {

  // MARK: - Generators, allocated once and kept warm

  private static let lightImpact = UIImpactFeedbackGenerator(style: .light)
  private static let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
  private static let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
  private static let rigidImpact = UIImpactFeedbackGenerator(style: .rigid)
  private static let softImpact = UIImpactFeedbackGenerator(style: .soft)
  private static let selectionGenerator = UISelectionFeedbackGenerator()
  private static let notificationGenerator = UINotificationFeedbackGenerator()

  private static func generator(
    for style: UIImpactFeedbackGenerator.FeedbackStyle
  ) -> UIImpactFeedbackGenerator {
    switch style {
    case .light: return lightImpact
    case .medium: return mediumImpact
    case .heavy: return heavyImpact
    case .rigid: return rigidImpact
    case .soft: return softImpact
    @unknown default: return mediumImpact
    }
  }

  // MARK: - Warming

  /// Warm the engine for an impact that is about to become possible. Call
  /// this when the screen that can produce it appears, or when a gesture
  /// begins — not at the moment of the tap, which is already too late.
  static func prepare(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
    generator(for: style).prepare()
  }

  /// Warm selection and success feedback — the two flavours nearly every
  /// screen can produce.
  static func prepare() {
    selectionGenerator.prepare()
    notificationGenerator.prepare()
  }

  // MARK: - Firing

  static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
    let generator = generator(for: style)
    generator.impactOccurred()
    // stay warm: in this app a second tap is usually seconds away
    generator.prepare()
  }

  static func selectionChanged() {
    selectionGenerator.selectionChanged()
    selectionGenerator.prepare()
  }

  static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
    notificationGenerator.notificationOccurred(type)
    notificationGenerator.prepare()
  }
}
